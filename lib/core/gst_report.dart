import 'dart:convert';

import 'books.dart';
import 'gst.dart';
import 'money.dart';
import 'xlsx.dart';

/// Taxable value and tax split by head (IGST for inter-state, CGST + SGST
/// inside the state).
class GstRateRow {
  final int rateBp;
  int taxable = 0, tax = 0, igst = 0, qty = 0;
  GstRateRow(this.rateBp);
  int get local => tax - igst;
  int get cgst => local ~/ 2;
  int get sgst => local - local ~/ 2;
  String get rate => '${(rateBp / 100).toStringAsFixed(rateBp % 100 == 0 ? 0 : 1)}%';
  num get rt => rateBp % 100 == 0 ? rateBp ~/ 100 : rateBp / 100;

  void add(int taxableValue, int t, {required bool inter, int q = 0}) {
    taxable += taxableValue;
    tax += t;
    if (inter) igst += t;
    qty += q;
  }
}

class HsnRow {
  final String hsn, name;
  final int rateBp;
  final bool b2b; // to registered customers (GSTR-1 table 12 is split B2B / B2C)
  int qty = 0, taxable = 0, tax = 0, igst = 0;
  HsnRow(this.hsn, this.name, this.rateBp, {this.b2b = false});
  int get cgst => (tax - igst) ~/ 2;
  int get sgst => (tax - igst) - (tax - igst) ~/ 2;
}

/// One B2B invoice (or credit note) with its rate-wise lines.
class GstDoc {
  final String number, date, party, gstin, pos;
  final String? against; // credit note: the original invoice
  int value = 0;
  final Map<int, GstRateRow> rates = {};
  GstDoc(this.number, this.date, this.party, this.gstin, this.pos, {this.against});
  int get taxable => rates.values.fold(0, (a, r) => a + r.taxable);
  int get tax => rates.values.fold(0, (a, r) => a + r.tax);
  int get igst => rates.values.fold(0, (a, r) => a + r.igst);
}

/// GST returns for a period, from the books:
///  · GSTR-1  — B2B invoices, B2C (small) by state and rate, credit notes to
///    registered (CDNR) and unregistered customers, HSN summary (B2B / B2C),
///    documents issued; JSON for the GST portal's offline tool
///  · GSTR-3B — outward supplies, input tax credit and tax payable per head
///    (IGST / CGST / SGST) after setting off the credit
///  · GSTR-2  — purchase register (ITC), supplier-wise
/// Supplies to a customer registered in another state are inter-state
/// (IGST); every other sale is inside the shop's state (CGST + SGST).
class GstReport {
  final String from, to;
  final Map<String, String> settings;
  final List<GstDoc> b2bDocs = [];
  final Map<String, GstRateRow> b2cs = {}; // "pos|rate" → net of unregistered credit notes
  final Map<int, GstRateRow> outward = {}; // all sales by rate (before credit notes)
  final Map<int, GstRateRow> inward = {}; // purchases (ITC) by rate
  final Map<int, GstRateRow> creditByRate = {};
  final Map<String, HsnRow> hsn = {};
  final List<GstDoc> cdnr = []; // credit notes to registered customers
  final List<GstDoc> purchaseDocs = []; // GSTR-2
  final List<Rec> creditNotes = []; // every sale return
  int discount = 0, invoices = 0;
  String firstInvoice = '', lastInvoice = '', firstCn = '', lastCn = '';
  int nilRated = 0; // 0% GST sales (3.1(c))
  int itcBlocked = 0; // purchases from suppliers without a GSTIN (no ITC)
  GstReport(this.from, this.to, this.settings);

  String get shopState => Gst.shopState(settings);
  String get gstin => (settings['gstin'] ?? '').trim().toUpperCase();

  // ---------------------------------------------------------- old names
  List<Rec> get b2b => [
        for (final d in b2bDocs)
          {'number': d.number, 'date': d.date, 'customer': d.party, 'gstin': d.gstin, 'taxable': d.taxable, 'tax': d.tax, 'total': d.value}
      ];
  Map<int, GstRateRow> get b2c {
    final m = <int, GstRateRow>{};
    for (final r in b2cs.values) {
      (m[r.rateBp] ??= GstRateRow(r.rateBp)).add(r.taxable, r.tax, inter: false, q: r.qty);
    }
    return m;
  }

  // ---------------------------------------------------------- totals
  int get outTaxable => outward.values.fold(0, (a, r) => a + r.taxable);
  int get outTax => outward.values.fold(0, (a, r) => a + r.tax);
  int get creditTaxable => creditByRate.values.fold(0, (a, r) => a + r.taxable);
  int get creditTax => creditByRate.values.fold(0, (a, r) => a + r.tax);
  int get netOutTax => outTax - creditTax;
  int get itcTaxable => inward.values.fold(0, (a, r) => a + r.taxable);
  int get itc => inward.values.fold(0, (a, r) => a + r.tax);
  int get payable => netOutTax - itc;

  int _sum(Map<int, GstRateRow> m, int Function(GstRateRow) f) => m.values.fold(0, (a, r) => a + f(r));
  (int, int, int) get outHeads => (
        _sum(outward, (r) => r.igst) - _sum(creditByRate, (r) => r.igst),
        _sum(outward, (r) => r.cgst) - _sum(creditByRate, (r) => r.cgst),
        _sum(outward, (r) => r.sgst) - _sum(creditByRate, (r) => r.sgst),
      );
  (int, int, int) get itcHeads => (_sum(inward, (r) => r.igst), _sum(inward, (r) => r.cgst), _sum(inward, (r) => r.sgst));

  /// GSTR-3B table 6.1: tax paid through ITC and in cash, per head.
  /// Set-off order: IGST credit → IGST, CGST, SGST; CGST credit → CGST,
  /// IGST; SGST credit → SGST, IGST. Returns cash payable and credit left.
  ({(int, int, int) cash, (int, int, int) left}) get setOff {
    var (oi, oc, os) = outHeads;
    var (ci, cc, cs) = itcHeads;
    oi = oi < 0 ? 0 : oi;
    oc = oc < 0 ? 0 : oc;
    os = os < 0 ? 0 : os;
    int use(int need, int have) => need < have ? need : have;
    var u = use(oi, ci);
    oi -= u;
    ci -= u;
    u = use(oc, ci);
    oc -= u;
    ci -= u;
    u = use(os, ci);
    os -= u;
    ci -= u;
    u = use(oc, cc);
    oc -= u;
    cc -= u;
    u = use(oi, cc);
    oi -= u;
    cc -= u;
    u = use(os, cs);
    os -= u;
    cs -= u;
    u = use(oi, cs);
    oi -= u;
    cs -= u;
    return (cash: (oi, oc, os), left: (ci, cc, cs));
  }

  int get cashPayable {
    final c = setOff.cash;
    return c.$1 + c.$2 + c.$3;
  }

  static Future<GstReport> load(String from, String to) async {
    final r = GstReport(from, to, await Books.settings());
    final shop = r.shopState;

    // ------------------------------------------------ sales
    final lines = await Books.query(
        'SELECT i.*, s.number, s.date, s.subtotal AS bill_subtotal, s.discount AS bill_discount, s.total AS bill_total, '
        'c.name AS customer, c.gstin, p.hsn FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'LEFT JOIN customers c ON c.id = s.customer_id LEFT JOIN products p ON p.id = i.product_id '
        'WHERE s.date >= ? AND s.date <= ? ORDER BY s.date, s.id',
        [from, to]);
    final docs = <int, GstDoc>{};
    for (final l in lines) {
      final bp = asInt(l['gst_bp']), amt = asInt(l['amount']), tax = asInt(l['tax']), q = asInt(l['qty']);
      // the bill discount lowers each line's taxable value
      final taxable = amt - Gst.share(asInt(l['bill_discount']), amt, asInt(l['bill_subtotal']));
      final gstin = '${l['gstin'] ?? ''}'.trim().toUpperCase();
      final registered = Gst.stateOf(gstin) != null && gstin.length == 15;
      final pos = registered ? Gst.stateOf(gstin)! : shop;
      final inter = pos != shop;
      (r.outward[bp] ??= GstRateRow(bp)).add(taxable, tax, inter: inter, q: q);
      if (bp == 0) r.nilRated += taxable;
      if (registered) {
        final d = docs[asInt(l['sale_id'])] ??= (GstDoc('${l['number']}', '${l['date']}', '${l['customer']}', gstin, pos)..value = asInt(l['bill_total']));
        (d.rates[bp] ??= GstRateRow(bp)).add(taxable, tax, inter: inter, q: q);
      } else if (bp > 0) {
        (r.b2cs['$pos|$bp'] ??= GstRateRow(bp)).add(taxable, tax, inter: inter, q: q);
      }
      final code = '${l['hsn'] ?? ''}'.trim().isEmpty ? '—' : '${l['hsn']}'.trim();
      final h = r.hsn['$code|$bp|$registered'] ??= HsnRow(code, '${l['name']}', bp, b2b: registered);
      h
        ..qty += q
        ..taxable += taxable
        ..tax += tax
        ..igst += inter ? tax : 0;
    }
    r.b2bDocs.addAll(docs.values);
    final bills = await Books.query(
        'SELECT COUNT(*) AS n, COALESCE(SUM(discount),0) AS d, MIN(number) AS a, MAX(number) AS b FROM sales WHERE date >= ? AND date <= ?', [from, to]);
    r.invoices = asInt(bills.first['n']);
    r.discount = asInt(bills.first['d']);
    r.firstInvoice = '${bills.first['a'] ?? ''}';
    r.lastInvoice = '${bills.first['b'] ?? ''}';

    // ------------------------------------------------ credit notes (sale returns)
    final cnLines = await Books.query(
        'SELECT r.id AS rid, r.number, r.date, s.number AS invoice, s.date AS invoice_date, c.name AS customer, c.gstin, '
        'i.value, i.tax, i.qty, si.gst_bp, p.hsn, i.name FROM sale_returns r JOIN sale_return_items i ON i.return_id = r.id '
        'JOIN sale_items si ON si.id = i.sale_item_id JOIN sales s ON s.id = r.sale_id '
        'LEFT JOIN customers c ON c.id = r.customer_id LEFT JOIN products p ON p.id = i.product_id '
        'WHERE r.date >= ? AND r.date <= ? ORDER BY r.date, r.id',
        [from, to]);
    final notes = <int, GstDoc>{};
    final cnRows = <int, Rec>{};
    for (final l in cnLines) {
      final bp = asInt(l['gst_bp']), val = asInt(l['value']), tax = asInt(l['tax']), q = asInt(l['qty']);
      final gstin = '${l['gstin'] ?? ''}'.trim().toUpperCase();
      final registered = Gst.stateOf(gstin) != null && gstin.length == 15;
      final pos = registered ? Gst.stateOf(gstin)! : shop;
      final inter = pos != shop;
      (r.creditByRate[bp] ??= GstRateRow(bp)).add(val, tax, inter: inter, q: q);
      final row = cnRows[asInt(l['rid'])] ??= {
        'number': l['number'],
        'date': l['date'],
        'invoice': l['invoice'],
        'customer': l['customer'],
        'gstin': gstin,
        'taxable': 0,
        'tax': 0,
      };
      row['taxable'] = asInt(row['taxable']) + val;
      row['tax'] = asInt(row['tax']) + tax;
      if (registered) {
        final d = notes[asInt(l['rid'])] ??= GstDoc('${l['number']}', '${l['date']}', '${l['customer']}', gstin, pos, against: '${l['invoice']}');
        (d.rates[bp] ??= GstRateRow(bp)).add(val, tax, inter: inter, q: q);
        d.value += val + tax;
      } else if (bp > 0) {
        // unregistered: B2C small is reported net of returns
        (r.b2cs['$pos|$bp'] ??= GstRateRow(bp)).add(-val, -tax, inter: inter, q: -q);
      }
      final code = '${l['hsn'] ?? ''}'.trim().isEmpty ? '—' : '${l['hsn']}'.trim();
      final h = r.hsn['$code|$bp|$registered'] ??= HsnRow(code, '${l['name']}', bp, b2b: registered);
      h
        ..qty -= q
        ..taxable -= val
        ..tax -= tax
        ..igst -= inter ? tax : 0;
    }
    r.cdnr.addAll(notes.values);
    r.creditNotes.addAll(cnRows.values);
    if (cnRows.isNotEmpty) {
      final ns = cnRows.values.map((e) => '${e['number']}').toList()..sort();
      r.firstCn = ns.first;
      r.lastCn = ns.last;
    }

    // ------------------------------------------------ purchases (ITC)
    final pl = await Books.query(
        'SELECT i.gst_bp, i.amount, i.tax, i.qty, p.id AS pid, p.number, p.bill_no, p.date, p.total, s.name AS supplier, s.gstin '
        'FROM purchase_items i JOIN purchases p ON p.id = i.purchase_id JOIN suppliers s ON s.id = p.supplier_id '
        'WHERE p.date >= ? AND p.date <= ? ORDER BY p.date, p.id',
        [from, to]);
    final pdocs = <int, GstDoc>{};
    for (final l in pl) {
      final bp = asInt(l['gst_bp']), amt = asInt(l['amount']), tax = asInt(l['tax']), q = asInt(l['qty']);
      final gstin = '${l['gstin'] ?? ''}'.trim().toUpperCase();
      final registered = Gst.stateOf(gstin) != null && gstin.length == 15;
      if (!registered) {
        r.itcBlocked += tax; // no ITC without the supplier's GSTIN
        continue;
      }
      final inter = Gst.stateOf(gstin)! != shop;
      (r.inward[bp] ??= GstRateRow(bp)).add(amt, tax, inter: inter, q: q);
      final bill = '${l['bill_no'] ?? ''}'.trim().isEmpty ? '${l['number']}' : '${l['bill_no']}';
      final d = pdocs[asInt(l['pid'])] ??= (GstDoc(bill, '${l['date']}', '${l['supplier']}', gstin, shop)..value = asInt(l['total']));
      (d.rates[bp] ??= GstRateRow(bp)).add(amt, tax, inter: inter, q: q);
    }
    r.purchaseDocs.addAll(pdocs.values);
    return r;
  }

  List<GstRateRow> sorted(Map<int, GstRateRow> m) => m.values.toList()..sort((a, b) => a.rateBp.compareTo(b.rateBp));

  // ================================================================ Excel
  /// GSTR-1 / GSTR-3B / GSTR-2 workbook for the CA.
  List<Sheet> sheets() {
    final (oi, oc, os) = outHeads;
    final (ci, cc, cs) = itcHeads;
    final so = setOff;
    final s3b = Sheet('GSTR-3B', ['Table', 'Particulars', 'Taxable value', 'IGST', 'CGST', 'SGST', 'Total tax'], widths: [8, 44, 18, 14, 14, 14, 16]);
    s3b.add([
      '3.1(a)',
      'Outward taxable supplies (net of credit notes)',
      Money2(outTaxable - creditTaxable - nilRated),
      Money2(oi),
      Money2(oc),
      Money2(os),
      Money2(netOutTax)
    ]);
    s3b.add(['3.1(c)', 'Nil rated / exempted', Money2(nilRated), Money2(0), Money2(0), Money2(0), Money2(0)]);
    s3b.add(['4(A)(5)', 'ITC — all other (purchases with GSTIN)', Money2(itcTaxable), Money2(ci), Money2(cc), Money2(cs), Money2(itc)]);
    if (itcBlocked > 0) s3b.add(['', 'GST on purchases without supplier GSTIN (no ITC)', '', '', '', '', Money2(itcBlocked)]);
    s3b.add(['6.1', 'Tax payable in cash (after ITC set-off)', '', Money2(so.cash.$1), Money2(so.cash.$2), Money2(so.cash.$3), Money2(cashPayable)],
        bold: true);
    s3b.add(['', 'ITC carried forward', '', Money2(so.left.$1), Money2(so.left.$2), Money2(so.left.$3), Money2(so.left.$1 + so.left.$2 + so.left.$3)]);
    s3b.add(['', 'Period', '${prettyDate(from)} – ${prettyDate(to)}']);
    s3b.add(['', 'GSTIN', gstin.isEmpty ? '(set your GSTIN in Settings)' : gstin]);

    final head = [
      'GSTIN of recipient',
      'Receiver name',
      'Invoice number',
      'Invoice date',
      'Invoice value',
      'Place of supply',
      'Reverse charge',
      'Invoice type',
      'Rate',
      'Taxable value',
      'IGST',
      'CGST',
      'SGST',
      'Cess'
    ];
    final b2bS = Sheet('GSTR-1 B2B', head, widths: [18, 24, 14, 12, 14, 22, 8, 12, 8, 16, 12, 12, 12, 8]);
    for (final d in b2bDocs) {
      for (final x in sorted(d.rates)) {
        b2bS.add([
          d.gstin,
          d.party,
          d.number,
          _dmy(d.date),
          Money2(d.value),
          Gst.stateName(d.pos),
          'N',
          'Regular B2B',
          x.rate,
          Money2(x.taxable),
          Money2(x.igst),
          Money2(x.cgst),
          Money2(x.sgst),
          Money2(0)
        ]);
      }
    }

    final b2cS =
        Sheet('GSTR-1 B2CS', ['Type', 'Place of supply', 'Rate', 'Taxable value', 'IGST', 'CGST', 'SGST', 'Cess'], widths: [10, 24, 8, 16, 12, 12, 12, 8]);
    for (final e in (b2cs.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
      final x = e.value;
      if (x.taxable == 0 && x.tax == 0) continue;
      b2cS.add(['OE', Gst.stateName(e.key.split('|').first), x.rate, Money2(x.taxable), Money2(x.igst), Money2(x.cgst), Money2(x.sgst), Money2(0)]);
    }

    final cdnS = Sheet('GSTR-1 CDNR', [
      'GSTIN of recipient',
      'Receiver name',
      'Note number',
      'Note date',
      'Against invoice',
      'Note type',
      'Place of supply',
      'Note value',
      'Rate',
      'Taxable value',
      'IGST',
      'CGST',
      'SGST'
    ], widths: [
      18,
      24,
      14,
      12,
      14,
      8,
      22,
      14,
      8,
      16,
      12,
      12,
      12
    ]);
    for (final d in cdnr) {
      for (final x in sorted(d.rates)) {
        cdnS.add([
          d.gstin,
          d.party,
          d.number,
          _dmy(d.date),
          d.against ?? '',
          'C',
          Gst.stateName(d.pos),
          Money2(d.value),
          x.rate,
          Money2(x.taxable),
          Money2(x.igst),
          Money2(x.cgst),
          Money2(x.sgst)
        ]);
      }
    }

    Sheet hsnSheet(String name, bool b2b) {
      final s = Sheet(name, ['HSN', 'Description', 'UQC', 'Total quantity', 'Total value', 'Rate', 'Taxable value', 'IGST', 'CGST', 'SGST', 'Cess'],
          widths: [12, 30, 8, 10, 16, 8, 16, 12, 12, 12, 8]);
      final hs = hsn.values.where((h) => h.b2b == b2b).toList()..sort((a, b) => a.hsn.compareTo(b.hsn));
      for (final h in hs) {
        s.add([
          h.hsn,
          h.name,
          'NOS',
          h.qty,
          Money2(h.taxable + h.tax),
          GstRateRow(h.rateBp).rate,
          Money2(h.taxable),
          Money2(h.igst),
          Money2(h.cgst),
          Money2(h.sgst),
          Money2(0)
        ]);
      }
      return s;
    }

    final docS =
        Sheet('GSTR-1 Docs', ['Nature of document', 'Sr. no. from', 'Sr. no. to', 'Total number', 'Cancelled', 'Net issued'], widths: [36, 16, 16, 12, 10, 10]);
    if (invoices > 0) docS.add(['Invoices for outward supply', firstInvoice, lastInvoice, invoices, 0, invoices]);
    if (creditNotes.isNotEmpty) docS.add(['Credit note', firstCn, lastCn, creditNotes.length, 0, creditNotes.length]);

    final g2 = Sheet(
        'GSTR-2 Purchases', ['Supplier GSTIN', 'Supplier', 'Bill number', 'Bill date', 'Bill value', 'Rate', 'Taxable value', 'IGST', 'CGST', 'SGST', 'ITC'],
        widths: [18, 24, 14, 12, 14, 8, 16, 12, 12, 12, 12]);
    for (final d in purchaseDocs) {
      for (final x in sorted(d.rates)) {
        g2.add([
          d.gstin,
          d.party,
          d.number,
          _dmy(d.date),
          Money2(d.value),
          x.rate,
          Money2(x.taxable),
          Money2(x.igst),
          Money2(x.cgst),
          Money2(x.sgst),
          Money2(x.tax)
        ]);
      }
    }
    return [s3b, b2bS, b2cS, cdnS, hsnSheet('GSTR-1 HSN B2B', true), hsnSheet('GSTR-1 HSN B2C', false), docS, g2];
  }

  static String _dmy(String ymdDate) {
    final p = ymdDate.split('-');
    return p.length == 3 ? '${p[2]}-${p[1]}-${p[0]}' : ymdDate;
  }

  static num _r(int paise) => paise / 100;

  // ================================================================ JSON
  /// GSTR-1 in the GST portal's JSON layout (import it in the GST offline
  /// tool, check, then upload). Use one calendar month as the period.
  String gstr1Json() {
    final fp = '${to.substring(5, 7)}${to.substring(0, 4)}';
    Map<String, Object> det(GstRateRow x) => {
          'txval': _r(x.taxable),
          'rt': x.rt,
          'iamt': _r(x.igst),
          'camt': _r(x.cgst),
          'samt': _r(x.sgst),
          'csamt': 0,
        };
    final byCtin = <String, List<GstDoc>>{};
    for (final d in b2bDocs) {
      (byCtin[d.gstin] ??= []).add(d);
    }
    final notesBy = <String, List<GstDoc>>{};
    for (final d in cdnr) {
      (notesBy[d.gstin] ??= []).add(d);
    }
    List<Map<String, Object>> hsnData(bool b2b) {
      final hs = hsn.values.where((h) => h.b2b == b2b && h.hsn != '—').toList()..sort((a, b) => a.hsn.compareTo(b.hsn));
      var n = 0;
      return [
        for (final h in hs)
          {
            'num': ++n,
            'hsn_sc': h.hsn,
            'desc': h.name.length > 30 ? h.name.substring(0, 30) : h.name,
            'uqc': 'NOS',
            'qty': h.qty,
            'rt': GstRateRow(h.rateBp).rt,
            'txval': _r(h.taxable),
            'iamt': _r(h.igst),
            'camt': _r(h.cgst),
            'samt': _r(h.sgst),
            'csamt': 0,
          }
      ];
    }

    final out = <String, Object>{
      'gstin': gstin,
      'fp': fp,
      'version': 'GST3.2',
      'hash': 'hash',
      if (byCtin.isNotEmpty)
        'b2b': [
          for (final e in byCtin.entries)
            {
              'ctin': e.key,
              'inv': [
                for (final d in e.value)
                  {
                    'inum': d.number,
                    'idt': _dmy(d.date),
                    'val': _r(d.value),
                    'pos': d.pos,
                    'rchrg': 'N',
                    'inv_typ': 'R',
                    'itms': [
                      for (final (i, x) in sorted(d.rates).indexed) {'num': i + 1, 'itm_det': det(x)}
                    ],
                  }
              ],
            }
        ],
      if (b2cs.values.any((x) => x.taxable != 0))
        'b2cs': [
          for (final e in b2cs.entries)
            if (e.value.taxable != 0)
              {
                'sply_ty': e.key.split('|').first == shopState ? 'INTRA' : 'INTER',
                'pos': e.key.split('|').first,
                'typ': 'OE',
                ...det(e.value),
              }
        ],
      if (notesBy.isNotEmpty)
        'cdnr': [
          for (final e in notesBy.entries)
            {
              'ctin': e.key,
              'nt': [
                for (final d in e.value)
                  {
                    'ntty': 'C',
                    'nt_num': d.number,
                    'nt_dt': _dmy(d.date),
                    'pos': d.pos,
                    'rchrg': 'N',
                    'inv_typ': 'R',
                    'val': _r(d.value),
                    'itms': [
                      for (final (i, x) in sorted(d.rates).indexed) {'num': i + 1, 'itm_det': det(x)}
                    ],
                  }
              ],
            }
        ],
      'hsn': {'hsn_b2b': hsnData(true), 'hsn_b2c': hsnData(false)},
      if (invoices > 0)
        'doc_issue': {
          'doc_det': [
            {
              'doc_num': 1,
              'docs': [
                {'num': 1, 'from': firstInvoice, 'to': lastInvoice, 'totnum': invoices, 'cancel': 0, 'net_issue': invoices}
              ],
            },
            if (creditNotes.isNotEmpty)
              {
                'doc_num': 5,
                'docs': [
                  {'num': 1, 'from': firstCn, 'to': lastCn, 'totnum': creditNotes.length, 'cancel': 0, 'net_issue': creditNotes.length}
                ],
              },
          ],
        },
    };
    return const JsonEncoder.withIndent(' ').convert(out);
  }
}
