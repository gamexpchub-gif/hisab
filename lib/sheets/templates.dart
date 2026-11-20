import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import 'workbook.dart';

/// A ready-made workbook in the gallery.
class SheetTemplate {
  final String id, name, desc, category;
  final int color;
  final IconData icon;
  final Future<Workbook> Function() build;
  const SheetTemplate(this.id, this.name, this.desc, this.category, this.color, this.icon, this.build);
}

const sheetCategories = <(String, int, IconData)>[
  ('Live data', 0xFF16A36A, Icons.sync_rounded),
  ('Business', 0xFF5B2EE0, Icons.storefront_rounded),
  ('Finance', 0xFF2F6BFF, Icons.account_balance_wallet_rounded),
  ('Shop tools', 0xFFF08A24, Icons.handyman_rounded),
  ('Personal', 0xFFD81E4A, Icons.person_rounded),
];

// ---------------------------------------------------------------- helpers
const _head = 0xFF0F1240, _headText = 0xFFFFFFFF, _band = 0xFFF4F1FF, _total = 0xFFE9FBF2;

GridSheet _table(String name, List<String> header, List<List<String>> rows,
    {Map<int, String> fmt = const {}, Map<int, double> widths = const {}, List<String>? totals, int headFill = _head}) {
  final s = GridSheet(name, rows: rows.length + 30, cols: header.length + 2);
  for (var c = 0; c < header.length; c++) {
    s.put(0, c, header[c]);
    s.style(0, c)
      ..bold = true
      ..fill = headFill
      ..color = _headText
      ..align = 'center';
  }
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      s.put(r + 1, c, rows[r][c]);
      if (fmt[c] != null) s.style(r + 1, c).fmt = fmt[c]!;
      if (r.isOdd) s.style(r + 1, c).fill = _band;
    }
  }
  if (totals != null) {
    final tr = rows.length + 1;
    for (var c = 0; c < totals.length; c++) {
      if (totals[c].isEmpty) continue;
      s.put(tr, c, totals[c]);
      s.style(tr, c)
        ..bold = true
        ..fill = _total
        ..fmt = fmt[c] ?? 'auto';
    }
  }
  widths.forEach((c, w) => s.widths[c] = w);
  return s;
}

String _sum(int col, int first, int last) => last < first ? '0' : '=SUM(${_c(col)}${first + 1}:${_c(col)}${last + 1})';
String _c(int col) => String.fromCharCode(65 + col);
String _rs(int paise) => (paise / 100).toStringAsFixed(2);

Workbook _wb(String name, String cat, int color, List<GridSheet> sheets) =>
    Workbook(Workbook.newId(), name, category: cat, color: color, sheets: sheets);

// ---------------------------------------------------------------- live data
Future<Workbook> _liveSales() async {
  final rows = <List<String>>[];
  for (final r in (await Books.salesBook()).take(500)) {
    final n = rows.length + 2;
    rows.add(['${r['number']}', '${r['date']}', '${r['customer'] ?? 'Walk-in'}', '${r['items'] ?? ''}', _rs(asInt(r['total'])), _rs(asInt(r['paid'])), '=E$n-F$n']);
  }
  final last = rows.length;
  return _wb('Sales register', 'Live data', 0xFF5B2EE0, [
    _table('Sales', ['Invoice', 'Date', 'Customer', 'Items', 'Total', 'Paid', 'Due'], rows,
        fmt: {4: 'inr', 5: 'inr', 6: 'inr'}, widths: {0: 100, 1: 96, 2: 140, 3: 200, 4: 110, 5: 110, 6: 110},
        totals: ['TOTAL', '', '=COUNTA(A2:A${last + 1})&" bills"', '', _sum(4, 1, last), _sum(5, 1, last), _sum(6, 1, last)]),
  ]);
}

Future<Workbook> _livePurchases() async {
  final rows = <List<String>>[];
  for (final r in (await Books.purchasesBook()).take(500)) {
    final n = rows.length + 2;
    rows.add(['${r['number']}', '${r['bill_no'] ?? ''}', '${r['date']}', '${r['supplier']}', _rs(asInt(r['total'])), _rs(asInt(r['paid'])), '=E$n-F$n']);
  }
  final last = rows.length;
  return _wb('Purchase register', 'Live data', 0xFFF08A24, [
    _table('Purchases', ['Number', 'Bill no', 'Date', 'Supplier', 'Total', 'Paid', 'Payable'], rows,
        fmt: {4: 'inr', 5: 'inr', 6: 'inr'}, widths: {0: 100, 1: 90, 2: 96, 3: 150, 4: 110, 5: 110, 6: 110},
        totals: ['TOTAL', '', '', '', _sum(4, 1, last), _sum(5, 1, last), _sum(6, 1, last)]),
  ]);
}

Future<Workbook> _liveStock() async {
  final rows = <List<String>>[];
  for (final r in await Books.query('SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id ORDER BY p.name')) {
    final n = rows.length + 2;
    rows.add(['${r['name']}', '${r['category'] ?? ''}', '${r['stock']}', _rs(asInt(r['cost'])), _rs(asInt(r['price'])), '=C$n*D$n', '=IF(E$n=0,0,(E$n-D$n)/E$n)']);
  }
  final last = rows.length;
  return _wb('Stock & valuation', 'Live data', 0xFF2F6BFF, [
    _table('Stock', ['Product', 'Category', 'Stock', 'Cost', 'Price', 'Stock value', 'Margin'], rows,
        fmt: {2: 'int', 3: 'inr', 4: 'inr', 5: 'inr', 6: 'pct'}, widths: {0: 170, 1: 110, 5: 120},
        totals: ['TOTAL', '', '=SUM(C2:C${last + 1})', '', '', _sum(5, 1, last), '=IFERROR(AVERAGE(G2:G${last + 1}),0)']),
  ]);
}

Future<Workbook> _liveDues() async {
  final bal = await Books.partyBalances('customer');
  final rows = <List<String>>[];
  for (final c in await Books.query('SELECT id, name, phone FROM customers ORDER BY name')) {
    final b = bal[asInt(c['id'])] ?? 0;
    if (b <= 0) continue;
    rows.add(['${c['name']}', '${c['phone'] ?? ''}', _rs(b)]);
  }
  rows.sort((a, b) => double.parse(b[2]).compareTo(double.parse(a[2])));
  final last = rows.length;
  return _wb('Customer dues', 'Live data', 0xFFD81E4A, [
    _table('Dues', ['Customer', 'Phone', 'Due'], rows,
        fmt: {2: 'inr'}, widths: {0: 170, 1: 120, 2: 120}, totals: ['TOTAL', '=COUNTA(A2:A${last + 1})&" customers"', _sum(2, 1, last)]),
  ]);
}

Future<Workbook> _liveExpenses() async {
  final rows = <List<String>>[];
  for (final r in await Books.query(
      'SELECT e.date, h.name AS head, e.note, e.amount FROM expenses e JOIN accounts h ON h.id = e.head_id ORDER BY e.date DESC LIMIT 500')) {
    rows.add(['${r['date']}', '${r['head']}', '${r['note'] ?? ''}', _rs(asInt(r['amount']))]);
  }
  final last = rows.length;
  final s = _table('Expenses', ['Date', 'Category', 'Note', 'Amount'], rows,
      fmt: {3: 'inr'}, widths: {0: 96, 1: 140, 2: 180, 3: 110}, totals: ['TOTAL', '', '', _sum(3, 1, last)]);
  // a category summary beside it with SUMIF
  final cats = {for (final r in rows) r[1]}.toList()..sort();
  s.put(0, 5, 'Category');
  s.put(0, 6, 'Spent');
  for (final c in [5, 6]) {
    s.style(0, c)
      ..bold = true
      ..fill = _head
      ..color = _headText;
  }
  for (var i = 0; i < cats.length; i++) {
    s.put(i + 1, 5, cats[i]);
    s.put(i + 1, 6, '=SUMIF(B2:B${last + 1},F${i + 2},D2:D${last + 1})');
    s.style(i + 1, 6).fmt = 'inr';
  }
  s.widths[5] = 140;
  s.widths[6] = 110;
  return _wb('Expense report', 'Live data', 0xFFDC4545, [s]);
}

// ---------------------------------------------------------------- business
Future<Workbook> _invoice() async {
  final s = GridSheet('Invoice', rows: 40, cols: 6);
  s.put(0, 0, 'TAX INVOICE');
  s.style(0, 0)
    ..bold = true
    ..color = 0xFF5B2EE0;
  s.put(1, 0, 'Bill to:');
  s.put(1, 3, 'Date:');
  s.put(1, 4, '=TODAY()');
  s.style(1, 4).fmt = 'date';
  final head = ['Item', 'Qty', 'Rate', 'GST %', 'Amount'];
  for (var c = 0; c < head.length; c++) {
    s.put(3, c, head[c]);
    s.style(3, c)
      ..bold = true
      ..fill = _head
      ..color = _headText;
  }
  final items = [['Mobile cover', '2', '199', '18'], ['Tempered glass', '1', '149', '18'], ['Charger 20W', '1', '899', '18']];
  for (var i = 0; i < 8; i++) {
    final r = 4 + i, n = r + 1;
    if (i < items.length) {
      for (var c = 0; c < 4; c++) {
        s.put(r, c, items[i][c]);
      }
    }
    s.put(r, 4, '=IF(B$n="","",B$n*C$n)');
    s.style(r, 2).fmt = 'inr';
    s.style(r, 4).fmt = 'inr';
  }
  final rows = [('Subtotal', ''), ('GST 18%', ''), ('Grand total', '')];
  for (var i = 0; i < rows.length; i++) {
    s.put(13 + i, 3, rows[i].$1);
    s.style(13 + i, 3).bold = true;
    s.style(13 + i, 4)
      ..fmt = 'inr'
      ..bold = i == 2
      ..fill = i == 2 ? _total : null;
  }
  s.put(13, 4, '=SUM(E5:E12)');
  s.put(14, 4, '=SUM(E5:E12)*18%');
  s.put(15, 4, '=E14+E15');
  s.widths[0] = 160;
  return _wb('Invoice', 'Business', 0xFF5B2EE0, [s]);
}

Future<Workbook> _priceList() async {
  final rows = <List<String>>[];
  for (final r in await Books.query('SELECT name, variant, price, mrp FROM products ORDER BY name LIMIT 300')) {
    final n = rows.length + 2;
    rows.add(['${r['name']}', '${r['variant'] ?? ''}', _rs(asInt(r['mrp'])), _rs(asInt(r['price'])), '=IF(C$n=0,0,(C$n-D$n)/C$n)']);
  }
  if (rows.isEmpty) rows.add(['Product', '', '1000', '899', '=IF(C2=0,0,(C2-D2)/C2)']);
  return _wb('Price list', 'Business', 0xFF8B5CF6, [
    _table('Price list', ['Product', 'Variant', 'MRP', 'Our price', 'Discount'], rows, fmt: {2: 'inr', 3: 'inr', 4: 'pct'}, widths: {0: 170, 1: 130}),
  ]);
}

Future<Workbook> _customerList() async => _wb('Customer list', 'Business', 0xFF0D9488, [
      _table('Customers', ['Name', 'Phone', 'Address', 'GSTIN', 'Note'], [
        for (final c in await Books.query('SELECT name, phone, address, gstin FROM customers ORDER BY name LIMIT 500'))
          ['${c['name']}', '${c['phone'] ?? ''}', '${c['address'] ?? ''}', '${c['gstin'] ?? ''}', ''],
      ], widths: {0: 160, 1: 120, 2: 200, 3: 150}),
    ]);

Future<Workbook> _cashBook() async {
  final rows = [
    for (var i = 0; i < 15; i++) [i == 0 ? '=TODAY()' : '', i == 0 ? 'Opening balance' : '', i == 0 ? '5000' : '', '', i == 0 ? '=C2-D2' : '=E${i + 1}+C${i + 2}-D${i + 2}'],
  ];
  return _wb('Daily cash book', 'Business', 0xFF16A36A, [
    _table('Cash book', ['Date', 'Particulars', 'Cash in', 'Cash out', 'Balance'], rows,
        fmt: {0: 'date', 2: 'inr', 3: 'inr', 4: 'inr'}, widths: {1: 180}, totals: ['TOTAL', '', '=SUM(C2:C16)', '=SUM(D2:D16)', '=C17-D17']),
  ]);
}

// ---------------------------------------------------------------- finance
Future<Workbook> _budget() async => _wb('Monthly budget', 'Finance', 0xFF2F6BFF, [
      _table('Budget', ['Head', 'Budget', 'Actual', 'Difference', 'Used'], [
        for (final (i, h) in ['Shop rent', 'Salary', 'Electricity', 'Internet', 'Transport', 'Marketing', 'Repairs', 'Food & tea', 'Other'].indexed)
          [h, ['15000', '20000', '3000', '1000', '2000', '2500', '1500', '1500', '1000'][i], '', '=B${i + 2}-C${i + 2}', '=IF(B${i + 2}=0,0,C${i + 2}/B${i + 2})'],
      ], fmt: {1: 'inr', 2: 'inr', 3: 'inr', 4: 'pct'}, widths: {0: 150}, totals: ['TOTAL', '=SUM(B2:B10)', '=SUM(C2:C10)', '=B11-C11', '=IF(B11=0,0,C11/B11)']),
    ]);

Future<Workbook> _emi() async {
  final s = GridSheet('EMI', rows: 80, cols: 8);
  final inputs = [('Loan amount', '300000', 'inr'), ('Interest % per year', '11', 'auto'), ('Months', '24', 'int'), ('Monthly EMI', '=EMI(B1,B2,B3)', 'inr'), ('Total interest', '=B4*B3-B1', 'inr'), ('Total payment', '=B4*B3', 'inr')];
  for (var i = 0; i < inputs.length; i++) {
    s.put(i, 0, inputs[i].$1);
    s.style(i, 0).bold = true;
    s.put(i, 1, inputs[i].$2);
    s.style(i, 1)
      ..fmt = inputs[i].$3
      ..fill = i < 3 ? 0xFFFFF8EB : _total
      ..bold = i >= 3;
  }
  final head = ['#', 'Opening', 'EMI', 'Interest', 'Principal', 'Closing'];
  for (var c = 0; c < head.length; c++) {
    s.put(7, c, head[c]);
    s.style(7, c)
      ..bold = true
      ..fill = _head
      ..color = _headText;
  }
  for (var i = 0; i < 60; i++) {
    final r = 8 + i, n = r + 1;
    s.put(r, 0, '=IF(${i + 1}>\$B\$3,"",${i + 1})');
    s.put(r, 1, i == 0 ? '=B1' : '=IF(A$n="","",F${n - 1})');
    s.put(r, 2, '=IF(A$n="","",\$B\$4)');
    s.put(r, 3, '=IF(A$n="","",B$n*\$B\$2/1200)');
    s.put(r, 4, '=IF(A$n="","",C$n-D$n)');
    s.put(r, 5, '=IF(A$n="","",B$n-E$n)');
    for (var c = 1; c <= 5; c++) {
      s.style(r, c).fmt = 'inr';
    }
  }
  s.frozenRows = 0;
  s.widths[0] = 150;
  return _wb('Loan EMI calculator', 'Finance', 0xFF0F1240, [s]);
}

Future<Workbook> _gstCalc() async => _wb('GST calculator', 'Finance', 0xFFDB2777, [
      _table('GST', ['Item', 'Price (excl.)', 'GST %', 'GST', 'CGST', 'SGST', 'Total'], [
        for (var i = 0; i < 10; i++)
          [i == 0 ? 'Laptop' : '', i == 0 ? '45000' : '', '18', '=B${i + 2}*C${i + 2}/100', '=D${i + 2}/2', '=D${i + 2}/2', '=B${i + 2}+D${i + 2}'],
      ], fmt: {1: 'inr', 3: 'inr', 4: 'inr', 5: 'inr', 6: 'inr'}, widths: {0: 140},
          totals: ['TOTAL', '=SUM(B2:B11)', '', '=SUM(D2:D11)', '=SUM(E2:E11)', '=SUM(F2:F11)', '=SUM(G2:G11)']),
    ]);

Future<Workbook> _profit() async => _wb('Profit calculator', 'Finance', 0xFF16A36A, [
      _table('Profit', ['Product', 'Cost', 'Sell', 'Qty', 'Profit', 'Margin'], [
        for (var i = 0; i < 12; i++)
          [i == 0 ? 'iPhone 15' : '', i == 0 ? '62000' : '', i == 0 ? '69900' : '', i == 0 ? '3' : '', '=(C${i + 2}-B${i + 2})*D${i + 2}', '=IF(C${i + 2}=0,0,(C${i + 2}-B${i + 2})/C${i + 2})'],
      ], fmt: {1: 'inr', 2: 'inr', 3: 'int', 4: 'inr', 5: 'pct'}, widths: {0: 150}, totals: ['TOTAL', '', '', '=SUM(D2:D13)', '=SUM(E2:E13)', '=IFERROR(AVERAGE(F2:F13),0)']),
    ]);

// ---------------------------------------------------------------- shop tools
Future<Workbook> _stockCount() async {
  final rows = <List<String>>[];
  for (final r in await Books.query('SELECT name, stock FROM products ORDER BY name LIMIT 500')) {
    final n = rows.length + 2;
    rows.add(['${r['name']}', '${r['stock']}', '', '=IF(C$n="","",C$n-B$n)']);
  }
  return _wb('Stock count', 'Shop tools', 0xFFF08A24, [
    _table('Count', ['Product', 'In books', 'Counted', 'Difference'], rows, fmt: {1: 'int', 2: 'int', 3: 'int'}, widths: {0: 180}),
  ]);
}

Future<Workbook> _orderList() async => _wb('Purchase order', 'Shop tools', 0xFFE08A00, [
      _table('Order', ['Item', 'Qty', 'Rate', 'Amount', 'Supplier'], [
        for (var i = 0; i < 15; i++) ['', '', '', '=IF(B${i + 2}="","",B${i + 2}*C${i + 2})', ''],
      ], fmt: {2: 'inr', 3: 'inr'}, widths: {0: 170, 4: 140}, totals: ['TOTAL', '=SUM(B2:B16)', '', '=SUM(D2:D16)', '']),
    ]);

Future<Workbook> _repairs() async => _wb('Repair jobs', 'Shop tools', 0xFF64748B, [
      _table('Jobs', ['Date', 'Customer', 'Phone', 'Device', 'Problem', 'Charge', 'Status'], [
        for (var i = 0; i < 15; i++) ['', '', '', '', '', '', i == 0 ? 'Pending' : ''],
      ], fmt: {0: 'date', 5: 'inr'}, widths: {1: 130, 3: 130, 4: 160},
          totals: ['', '', '', '', 'Pending:', '=COUNTIF(G2:G16,"Pending")', '']),
    ]);

Future<Workbook> _attendance() async {
  final head = ['Staff', for (var d = 1; d <= 31; d++) '$d', 'Present'];
  final s = _table('Attendance', head, [
    for (var i = 0; i < 6; i++) [i == 0 ? 'Staff 1' : '', for (var d = 0; d < 31; d++) '', '=COUNTIF(B${i + 2}:AF${i + 2},"P")'],
  ], widths: {0: 120});
  for (var c = 1; c <= 31; c++) {
    s.widths[c] = 36;
  }
  s.frozenCols = 1;
  return _wb('Staff attendance', 'Shop tools', 0xFF0D9488, [s]);
}

// ---------------------------------------------------------------- personal
Future<Workbook> _todo() async => _wb('To-do list', 'Personal', 0xFFD81E4A, [
      _table('To-do', ['Task', 'Due', 'Done', 'Note'], [
        for (var i = 0; i < 15; i++) ['', '', i == 0 ? 'FALSE' : '', ''],
      ], fmt: {1: 'date'}, widths: {0: 200, 3: 160}, totals: ['Done:', '', '=COUNTIF(C2:C16,TRUE)', '']),
    ]);

Future<Workbook> _savings() async => _wb('Savings goal', 'Personal', 0xFF8B5CF6, [
      _table('Savings', ['Month', 'Saved', 'Total', 'Goal left'], [
        for (final (i, m) in ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].indexed)
          [m, '', i == 0 ? '=B2' : '=C${i + 1}+B${i + 2}', '=\$F\$2-C${i + 2}'],
      ], fmt: {1: 'inr', 2: 'inr', 3: 'inr'})
        ..put(0, 5, 'Goal')
        ..put(1, 5, '100000'),
    ]);

Future<Workbook> blankWorkbook([String name = 'Untitled sheet']) async => Workbook(Workbook.newId(), name);

final sheetTemplates = <SheetTemplate>[
  SheetTemplate('live_sales', 'Sales register', 'Every bill from your books, with totals', 'Live data', 0xFF5B2EE0, Icons.point_of_sale_rounded, _liveSales),
  SheetTemplate('live_purchases', 'Purchase register', 'Supplier bills and payables', 'Live data', 0xFFF08A24, Icons.shopping_bag_rounded, _livePurchases),
  SheetTemplate('live_stock', 'Stock & valuation', 'Stock, cost, price, value, margin', 'Live data', 0xFF2F6BFF, Icons.inventory_2_rounded, _liveStock),
  SheetTemplate('live_dues', 'Customer dues', 'Who owes you, biggest first', 'Live data', 0xFFD81E4A, Icons.schedule_rounded, _liveDues),
  SheetTemplate('live_expenses', 'Expense report', 'Expenses with a category summary', 'Live data', 0xFFDC4545, Icons.sell_rounded, _liveExpenses),
  SheetTemplate('invoice', 'Invoice', 'Quick bill with GST and totals', 'Business', 0xFF5B2EE0, Icons.receipt_long_rounded, _invoice),
  SheetTemplate('price_list', 'Price list', 'MRP, your price and discount', 'Business', 0xFF8B5CF6, Icons.local_offer_rounded, _priceList),
  SheetTemplate('customers', 'Customer list', 'Names, phones, addresses', 'Business', 0xFF0D9488, Icons.groups_rounded, _customerList),
  SheetTemplate('cash_book', 'Daily cash book', 'Cash in, out and running balance', 'Business', 0xFF16A36A, Icons.menu_book_rounded, _cashBook),
  SheetTemplate('budget', 'Monthly budget', 'Budget vs actual for every head', 'Finance', 0xFF2F6BFF, Icons.pie_chart_rounded, _budget),
  SheetTemplate('emi', 'Loan EMI calculator', 'EMI and full repayment schedule', 'Finance', 0xFF0F1240, Icons.calculate_rounded, _emi),
  SheetTemplate('gst', 'GST calculator', 'GST, CGST, SGST for any price', 'Finance', 0xFFDB2777, Icons.request_quote_rounded, _gstCalc),
  SheetTemplate('profit', 'Profit calculator', 'Profit and margin per product', 'Finance', 0xFF16A36A, Icons.trending_up_rounded, _profit),
  SheetTemplate('stock_count', 'Stock count', 'Physical count vs books', 'Shop tools', 0xFFF08A24, Icons.fact_check_rounded, _stockCount),
  SheetTemplate('order', 'Purchase order', 'What to buy, from whom', 'Shop tools', 0xFFE08A00, Icons.local_shipping_rounded, _orderList),
  SheetTemplate('repairs', 'Repair jobs', 'Service jobs and status', 'Shop tools', 0xFF64748B, Icons.build_rounded, _repairs),
  SheetTemplate('attendance', 'Staff attendance', 'Mark P / A for the month', 'Shop tools', 0xFF0D9488, Icons.event_available_rounded, _attendance),
  SheetTemplate('todo', 'To-do list', 'Tasks, due dates, done', 'Personal', 0xFFD81E4A, Icons.checklist_rounded, _todo),
  SheetTemplate('savings', 'Savings goal', 'Monthly saving towards a goal', 'Personal', 0xFF8B5CF6, Icons.savings_rounded, _savings),
];

/// Money format for a cell value in sheets (₹1,23,456.00).
String sheetInr(double v) => '₹${Money.inr((v * 100).round(), decimals: true)}';
