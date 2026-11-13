import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'books.dart';
import 'gst_report.dart';
import 'money.dart';
import 'native_files.dart';
import 'xlsx.dart';

/// Excel exports of the books: registers, stock, parties, day book, GST.
class ExportBook {
  static const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static const kinds = <(String, String)>[
    ('all', 'Full business workbook'),
    ('sales', 'Sales register'),
    ('purchases', 'Purchase register'),
    ('stock', 'Stock & valuation'),
    ('parties', 'Customers & suppliers'),
    ('expenses', 'Expenses'),
    ('daybook', 'Day book (journal)'),
    ('gst', 'GST — GSTR-1 & GSTR-3B'),
  ];

  static Future<Sheet> sales(String from, String to) async {
    final s = Sheet('Sales', ['Invoice', 'Date', 'Customer', 'Phone', 'Items', 'IMEI / Serial', 'Subtotal', 'Discount', 'GST', 'Total', 'Paid', 'Due', 'Paid in'],
        widths: [13, 12, 24, 14, 36, 22, 14, 12, 12, 14, 14, 14, 16]);
    var sub = 0, dis = 0, tax = 0, tot = 0, paid = 0;
    for (final r in (await Books.salesBook()).reversed) {
      final d = '${r['date']}';
      if (d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
      final t = asInt(r['total']), pd = asInt(r['paid']);
      sub += asInt(r['subtotal']);
      dis += asInt(r['discount']);
      tax += asInt(r['tax']);
      tot += t;
      paid += pd;
      s.add([r['number'], d, r['customer'] ?? 'Walk-in', r['phone'] ?? '', r['items'] ?? '', r['serials'] ?? '', Money2(asInt(r['subtotal'])),
        Money2(asInt(r['discount'])), Money2(asInt(r['tax'])), Money2(t), Money2(pd), Money2(t - pd), r['accounts'] ?? '']);
    }
    s.add(['TOTAL', '', '', '', '', '', Money2(sub), Money2(dis), Money2(tax), Money2(tot), Money2(paid), Money2(tot - paid), ''], bold: true);
    return s;
  }

  static Future<Sheet> saleItems(String from, String to) async {
    final s = Sheet('Sale items', ['Invoice', 'Date', 'Product', 'IMEI / Serial', 'Qty', 'Rate', 'GST %', 'Amount', 'GST', 'Cost', 'Profit'],
        widths: [13, 12, 30, 20, 7, 14, 8, 14, 12, 14, 14]);
    var amt = 0, tax = 0, cost = 0;
    for (final r in await Books.query(
        'SELECT i.*, s.number, s.date FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE s.date >= ? AND s.date <= ? ORDER BY s.date, s.id',
        [from, to])) {
      final a = asInt(r['amount']), c = asInt(r['unit_cost']) * asInt(r['qty']);
      amt += a;
      tax += asInt(r['tax']);
      cost += c;
      s.add([r['number'], r['date'], r['name'], r['serial'] ?? '', asInt(r['qty']), Money2(asInt(r['rate'])), '${asInt(r['gst_bp']) ~/ 100}%',
        Money2(a), Money2(asInt(r['tax'])), Money2(c), Money2(a - c)]);
    }
    s.add(['TOTAL', '', '', '', '', '', '', Money2(amt), Money2(tax), Money2(cost), Money2(amt - cost)], bold: true);
    return s;
  }

  static Future<Sheet> purchases(String from, String to) async {
    final s = Sheet('Purchases', ['Number', 'Bill no', 'Date', 'Supplier', 'GSTIN', 'Items', 'IMEI / Serial', 'Subtotal', 'GST', 'Total', 'Paid', 'Payable'],
        widths: [13, 12, 12, 24, 18, 36, 22, 14, 12, 14, 14, 14]);
    var sub = 0, tax = 0, tot = 0, paid = 0;
    for (final r in (await Books.purchasesBook()).reversed) {
      final d = '${r['date']}';
      if (d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
      final t = asInt(r['total']), pd = asInt(r['paid']);
      sub += asInt(r['subtotal']);
      tax += asInt(r['tax']);
      tot += t;
      paid += pd;
      s.add([r['number'], r['bill_no'] ?? '', d, r['supplier'], r['gstin'] ?? '', r['items'] ?? '', r['serials'] ?? '', Money2(asInt(r['subtotal'])),
        Money2(asInt(r['tax'])), Money2(t), Money2(pd), Money2(t - pd)]);
    }
    s.add(['TOTAL', '', '', '', '', '', '', Money2(sub), Money2(tax), Money2(tot), Money2(paid), Money2(tot - paid)], bold: true);
    return s;
  }

  static Future<Sheet> stock() async {
    final s = Sheet('Stock', ['Product', 'Variant', 'Brand', 'Category', 'SKU', 'HSN', 'GST %', 'Stock', 'Cost', 'Price', 'MRP', 'Stock value', 'Status'],
        widths: [30, 18, 14, 16, 14, 10, 8, 8, 14, 14, 14, 16, 12]);
    var value = 0, units = 0;
    for (final r in await Books.query(
        'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id ORDER BY p.name')) {
      final st = asInt(r['stock']), v = st > 0 ? st * asInt(r['cost']) : 0;
      value += v;
      units += st > 0 ? st : 0;
      s.add([r['name'], r['variant'] ?? '', r['brand'] ?? '', r['category'] ?? '', r['sku'] ?? '', r['hsn'] ?? '', '${asInt(r['gst_bp']) ~/ 100}%', st,
        Money2(asInt(r['cost'])), Money2(asInt(r['price'])), Money2(asInt(r['mrp'])), Money2(v),
        st <= 0 ? 'Out of stock' : st <= asInt(r['low_stock']) ? 'Low' : 'OK']);
    }
    s.add(['TOTAL', '', '', '', '', '', '', units, '', '', '', Money2(value), ''], bold: true);
    return s;
  }

  static Future<Sheet> parties(String type) async {
    final bal = await Books.partyBalances(type);
    final isC = type == 'customer';
    final s = Sheet(isC ? 'Customers' : 'Suppliers', ['Name', 'Phone', 'Alt phone', 'Address', 'GSTIN', isC ? 'Receivable (due)' : 'Payable', 'Credit limit'],
        widths: [26, 14, 14, 36, 18, 18, 14]);
    var total = 0;
    for (final r in await Books.query('SELECT * FROM ${isC ? 'customers' : 'suppliers'} ORDER BY name')) {
      final b = bal[asInt(r['id'])] ?? 0;
      total += b;
      s.add([r['name'], r['phone'] ?? '', r['alt_phone'] ?? '', r['address'] ?? '', r['gstin'] ?? '', Money2(b), Money2(asInt(r['credit_limit']))]);
    }
    s.add(['TOTAL', '', '', '', '', Money2(total), ''], bold: true);
    return s;
  }

  static Future<Sheet> expenses(String from, String to) async {
    final s = Sheet('Expenses', ['Number', 'Date', 'Category', 'Paid from', 'Note', 'Amount'], widths: [13, 12, 22, 18, 36, 14]);
    var total = 0;
    for (final r in await Books.query(
        'SELECT e.*, h.name AS head, a.name AS account FROM expenses e JOIN accounts h ON h.id = e.head_id '
        'JOIN accounts a ON a.id = e.account_id WHERE e.date >= ? AND e.date <= ? ORDER BY e.date, e.id',
        [from, to])) {
      total += asInt(r['amount']);
      s.add([r['number'], r['date'], r['head'], r['account'], r['note'] ?? '', Money2(asInt(r['amount']))]);
    }
    s.add(['TOTAL', '', '', '', '', Money2(total)], bold: true);
    return s;
  }

  static Future<Sheet> dayBook(String from, String to) async {
    final s = Sheet('Day book', ['Date', 'Ref', 'Narration', 'Account', 'Party', 'Debit', 'Credit'], widths: [12, 14, 40, 24, 22, 14, 14]);
    var dr = 0, cr = 0;
    for (final r in await Books.query(
        'SELECT e.date, e.ref, e.narration, a.name AS account, l.debit, l.credit, l.party_type, '
        "CASE l.party_type WHEN 'customer' THEN (SELECT name FROM customers WHERE id = l.party_id) "
        "WHEN 'supplier' THEN (SELECT name FROM suppliers WHERE id = l.party_id) END AS party "
        'FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id '
        'WHERE e.date >= ? AND e.date <= ? ORDER BY e.date, e.id, l.id',
        [from, to])) {
      dr += asInt(r['debit']);
      cr += asInt(r['credit']);
      s.add([r['date'], r['ref'], r['narration'] ?? '', r['account'], r['party'] ?? '',
        asInt(r['debit']) == 0 ? null : Money2(asInt(r['debit'])), asInt(r['credit']) == 0 ? null : Money2(asInt(r['credit']))]);
    }
    s.add(['TOTAL', '', '', '', '', Money2(dr), Money2(cr)], bold: true);
    return s;
  }

  static Future<List<Sheet>> sheets(String kind, String from, String to) async => switch (kind) {
        'sales' => [await sales(from, to), await saleItems(from, to)],
        'purchases' => [await purchases(from, to)],
        'stock' => [await stock()],
        'parties' => [await parties('customer'), await parties('supplier')],
        'expenses' => [await expenses(from, to)],
        'daybook' => [await dayBook(from, to)],
        'gst' => (await GstReport.load(from, to)).sheets(),
        _ => [
            await sales(from, to),
            await saleItems(from, to),
            await purchases(from, to),
            await expenses(from, to),
            await stock(),
            await parties('customer'),
            await parties('supplier'),
            await dayBook(from, to),
            ...(await GstReport.load(from, to)).sheets(),
          ],
      };

  static Future<Uint8List> build(String kind, String from, String to) async =>
      Xlsx.build(await sheets(kind, from, to), title: 'GameX Hisab · $kind · $from to $to');

  /// Writes the workbook and opens the share sheet (WhatsApp, Drive, email…).
  static Future<File> share(String kind, String from, String to) async {
    final bytes = await build(kind, from, to);
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final label = kinds.firstWhere((k) => k.$1 == kind, orElse: () => kinds.first).$2.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final f = File(p.join(dir.path, 'GameX-$label-${from}_to_$to.xlsx'));
    await f.writeAsBytes(bytes, flush: true);
    await NativeFiles.share(f, mime: xlsxMime, subject: 'GameX Hisab — $label', text: '$label · ${prettyDate(from)} – ${prettyDate(to)}');
    return f;
  }
}
