import 'books.dart';
import 'money.dart';
import 'xlsx.dart';

/// One GST rate line: taxable value and tax (split CGST / SGST for
/// intra-state supplies).
class GstRateRow {
  final int rateBp;
  int taxable = 0, tax = 0, qty = 0;
  GstRateRow(this.rateBp);
  int get cgst => tax ~/ 2;
  int get sgst => tax - tax ~/ 2;
  String get rate => '${(rateBp / 100).toStringAsFixed(rateBp % 100 == 0 ? 0 : 1)}%';
}

class HsnRow {
  final String hsn, name;
  final int rateBp;
  int qty = 0, taxable = 0, tax = 0;
  HsnRow(this.hsn, this.name, this.rateBp);
}

/// GST returns for a period, computed from the bills:
/// GSTR-1 (B2B invoices, B2C by rate, HSN summary, credit notes) and
/// GSTR-3B (outward tax, input tax credit, net payable).
/// All supplies are treated as intra-state (CGST + SGST).
class GstReport {
  final String from, to;
  final List<Rec> b2b = []; // invoices to registered customers (with GSTIN)
  final Map<int, GstRateRow> b2c = {}; // by rate
  final Map<int, GstRateRow> outward = {}; // all sales by rate
  final Map<int, GstRateRow> inward = {}; // purchases (ITC) by rate
  final Map<String, HsnRow> hsn = {};
  final List<Rec> creditNotes = []; // sale returns
  int creditTaxable = 0, creditTax = 0;
  int discount = 0, invoices = 0;
  GstReport(this.from, this.to);

  int get outTaxable => outward.values.fold(0, (a, r) => a + r.taxable);
  int get outTax => outward.values.fold(0, (a, r) => a + r.tax);
  int get itcTaxable => inward.values.fold(0, (a, r) => a + r.taxable);
  int get itc => inward.values.fold(0, (a, r) => a + r.tax);
  int get netOutTax => outTax - creditTax;
  int get payable => netOutTax - itc;

  static Future<GstReport> load(String from, String to) async {
    final r = GstReport(from, to);
    final lines = await Books.query(
        'SELECT i.*, s.number, s.date, s.customer_id, s.total AS bill_total, s.discount AS bill_discount, '
        'c.name AS customer, c.gstin, p.hsn FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'LEFT JOIN customers c ON c.id = s.customer_id LEFT JOIN products p ON p.id = i.product_id '
        'WHERE s.date >= ? AND s.date <= ? ORDER BY s.date, s.id',
        [from, to]);
    final b2bBills = <int, Map<String, Object?>>{};
    for (final l in lines) {
      final bp = asInt(l['gst_bp']), amt = asInt(l['amount']), tax = asInt(l['tax']), q = asInt(l['qty']);
      (r.outward[bp] ??= GstRateRow(bp))
        ..taxable += amt
        ..tax += tax
        ..qty += q;
      final gstin = '${l['gstin'] ?? ''}'.trim();
      if (gstin.isNotEmpty) {
        final b = b2bBills[asInt(l['sale_id'])] ??= {
          'number': l['number'],
          'date': l['date'],
          'customer': l['customer'],
          'gstin': gstin,
          'total': asInt(l['bill_total']),
          'taxable': 0,
          'tax': 0,
          'rates': <String>{},
        };
        b['taxable'] = asInt(b['taxable']) + amt;
        b['tax'] = asInt(b['tax']) + tax;
        (b['rates'] as Set<String>).add(GstRateRow(bp).rate);
      } else {
        (r.b2c[bp] ??= GstRateRow(bp))
          ..taxable += amt
          ..tax += tax
          ..qty += q;
      }
      final code = '${l['hsn'] ?? ''}'.trim().isEmpty ? '—' : '${l['hsn']}'.trim();
      (r.hsn['$code|$bp'] ??= HsnRow(code, '${l['name']}', bp))
        ..qty += q
        ..taxable += amt
        ..tax += tax;
    }
    r.b2b.addAll(b2bBills.values.map((m) => <String, Object?>{...m, 'rates': (m['rates'] as Set<String>).join(', ')}));
    final bills = await Books.query(
        'SELECT COUNT(*) AS n, COALESCE(SUM(discount),0) AS d FROM sales WHERE date >= ? AND date <= ?', [from, to]);
    r.invoices = asInt(bills.first['n']);
    r.discount = asInt(bills.first['d']);

    for (final p in await Books.query(
        'SELECT i.gst_bp, SUM(i.amount) AS amt, SUM(i.tax) AS tax, SUM(i.qty) AS q FROM purchase_items i '
        'JOIN purchases p ON p.id = i.purchase_id WHERE p.date >= ? AND p.date <= ? GROUP BY i.gst_bp',
        [from, to])) {
      final bp = asInt(p['gst_bp']);
      (r.inward[bp] ??= GstRateRow(bp))
        ..taxable += asInt(p['amt'])
        ..tax += asInt(p['tax'])
        ..qty += asInt(p['q']);
    }

    for (final c in await Books.query(
        'SELECT r.number, r.date, s.number AS invoice, c.name AS customer, c.gstin, '
        'SUM(i.value) AS taxable, SUM(i.tax) AS tax FROM sale_returns r JOIN sale_return_items i ON i.return_id = r.id '
        'JOIN sales s ON s.id = r.sale_id LEFT JOIN customers c ON c.id = r.customer_id '
        'WHERE r.date >= ? AND r.date <= ? GROUP BY r.id ORDER BY r.date',
        [from, to])) {
      r.creditNotes.add(c);
      r.creditTaxable += asInt(c['taxable']);
      r.creditTax += asInt(c['tax']);
    }
    return r;
  }

  List<GstRateRow> sorted(Map<int, GstRateRow> m) => m.values.toList()..sort((a, b) => a.rateBp.compareTo(b.rateBp));

  /// GSTR-1 / GSTR-3B workbook for the CA.
  List<Sheet> sheets() {
    final s3b = Sheet('GSTR-3B', ['Particulars', 'Taxable value', 'CGST', 'SGST', 'Total tax'], widths: [42, 18, 16, 16, 18]);
    void line(String n, int taxable, int tax, {bool bold = false}) =>
        s3b.add([n, Money2(taxable), Money2(tax ~/ 2), Money2(tax - tax ~/ 2), Money2(tax)], bold: bold);
    line('3.1(a) Outward taxable supplies', outTaxable, outTax);
    line('Less: credit notes (sale returns)', -creditTaxable, -creditTax);
    line('Net outward tax', outTaxable - creditTaxable, netOutTax, bold: true);
    line('4(A) Input tax credit — purchases', itcTaxable, itc);
    line(payable >= 0 ? 'GST payable' : 'ITC carried forward', 0, payable.abs(), bold: true);
    s3b.add(['Period', '${prettyDate(from)} – ${prettyDate(to)}']);
    s3b.add(['Invoices', invoices]);
    s3b.add(['Bill discounts given (not deducted above)', Money2(discount)]);

    final b2bS = Sheet('B2B', ['Invoice', 'Date', 'Customer', 'GSTIN', 'Rate', 'Taxable value', 'CGST', 'SGST', 'Invoice value'],
        widths: [14, 12, 26, 18, 10, 16, 14, 14, 16]);
    for (final b in b2b) {
      final t = asInt(b['tax']);
      b2bS.add([b['number'], b['date'], b['customer'], b['gstin'], b['rates'], Money2(asInt(b['taxable'])), Money2(t ~/ 2), Money2(t - t ~/ 2), Money2(asInt(b['total']))]);
    }

    final b2cS = Sheet('B2C small', ['Rate', 'Qty', 'Taxable value', 'CGST', 'SGST', 'Total tax'], widths: [10, 10, 18, 16, 16, 16]);
    for (final x in sorted(b2c)) {
      b2cS.add([x.rate, x.qty, Money2(x.taxable), Money2(x.cgst), Money2(x.sgst), Money2(x.tax)]);
    }

    final hsnS = Sheet('HSN', ['HSN', 'Description', 'Rate', 'Qty', 'Taxable value', 'CGST', 'SGST', 'Total value'],
        widths: [12, 30, 10, 10, 16, 14, 14, 16]);
    final hs = hsn.values.toList()..sort((a, b) => a.hsn.compareTo(b.hsn));
    for (final h in hs) {
      hsnS.add([h.hsn, h.name, GstRateRow(h.rateBp).rate, h.qty, Money2(h.taxable), Money2(h.tax ~/ 2), Money2(h.tax - h.tax ~/ 2), Money2(h.taxable + h.tax)]);
    }

    final cn = Sheet('Credit notes', ['Return', 'Date', 'Against invoice', 'Customer', 'GSTIN', 'Taxable value', 'Tax'],
        widths: [14, 12, 16, 26, 18, 16, 14]);
    for (final c in creditNotes) {
      cn.add([c['number'], c['date'], c['invoice'], c['customer'] ?? 'Walk-in', c['gstin'] ?? '', Money2(asInt(c['taxable'])), Money2(asInt(c['tax']))]);
    }

    final itcS = Sheet('ITC purchases', ['Rate', 'Qty', 'Taxable value', 'CGST', 'SGST', 'Total ITC'], widths: [10, 10, 18, 16, 16, 16]);
    for (final x in sorted(inward)) {
      itcS.add([x.rate, x.qty, Money2(x.taxable), Money2(x.cgst), Money2(x.sgst), Money2(x.tax)]);
    }
    return [s3b, b2bS, b2cS, hsnS, cn, itcS];
  }
}
