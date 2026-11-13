import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hisab/core/books.dart';
import 'package:hisab/core/db.dart';
import 'package:hisab/core/money.dart';
import 'package:hisab/core/imei_smart.dart';
import 'package:hisab/core/smart.dart';
import 'package:hisab/print/invoice_pdf.dart' show amountInWords;
import 'package:hisab/screens/sales_book.dart' show matchSale, matchDoc;

Future<void> freshDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: AppDb.schemaVersion, onConfigure: AppDb.configure, onCreate: AppDb.create, singleInstance: false));
  AppDb.useDatabase(db);
}

Future<void> expectBalanced() async {
  final tb = await Books.trialBalance();
  final dr = tb.fold<int>(0, (a, r) => a + asInt(r['dr']));
  final cr = tb.fold<int>(0, (a, r) => a + asInt(r['cr']));
  expect(dr, cr, reason: 'trial balance must balance');
  final bs = await Books.balanceSheet(ymd(DateTime.now()));
  expect(bs.totalAssets, bs.totalLiabilities + bs.totalEquity, reason: 'balance sheet must balance');
}

void main() {
  setUp(freshDb);

  test('money parsing and Indian formatting', () {
    expect(Money.parse('1,234.5'), 123450);
    expect(Money.parse('0.07'), 7);
    expect(Money.inr(123456789), '12,34,567.89');
    expect(Money.inr(10000000), '1,00,000');
    expect(Money.percent(10000, 1800), 1800);
  });

  test('purchase → sale → receipt keeps books balanced', () async {
    final s = await Books.saveParty('supplier', {'name': 'Distributor'});
    final c = await Books.saveParty('customer', {'name': 'Rahul'});
    final p = await Books.saveProduct({'name': 'iPhone', 'gst_bp': 1800, 'price': 3000000});
    final money = await Books.moneyAccounts();
    final cash = asInt(money.first['id']);

    await Books.createPurchase(items: [ItemIn(p, 2, 2500000)], supplierId: s, paid: 1000000, accountId: cash);
    expect(await Books.partyBalance('supplier', s), 5900000 - 1000000);

    await Books.createSale(items: [ItemIn(p, 1, 3000000, 'IMEI1')], customerId: c, paid: 500000, accountId: cash);
    expect(await Books.partyBalance('customer', c), 3540000 - 500000);

    await Books.createPayment(kind: 'receipt', partyId: c, amount: 1000000, accountId: cash);
    expect(await Books.partyBalance('customer', c), 2040000);

    final prod = (await Books.query('SELECT stock, cost FROM products WHERE id = ?', [p])).first;
    expect(asInt(prod['stock']), 1);
    expect(asInt(prod['cost']), 2500000);

    final pl = await Books.profitLoss(null, ymd(DateTime.now()));
    expect(pl.revenue, 3000000);
    expect(pl.cogs, 2500000);
    expect(pl.netProfit, 500000);
    expect(await Books.balanceByCode('1000'), -1000000 + 500000 + 1000000);
    await expectBalanced();
  });

  test('cannot oversell stock or leave walk-in unpaid', () async {
    final p = await Books.saveProduct({'name': 'Mouse', 'gst_bp': 0, 'price': 50000}, openingQty: 1, openingCost: 30000);
    await expectLater(Books.createSale(items: [ItemIn(p, 2, 50000)]), throwsA(isA<AccountingError>()));
    await expectLater(Books.createSale(items: [ItemIn(p, 1, 50000)], paid: 0), throwsA(isA<AccountingError>()));
    await Books.createSale(items: [ItemIn(p, 1, 50000)]);
    await expectBalanced();
  });

  test('a document cannot be posted twice', () async {
    final db = await AppDb.instance;
    final cash = await Books.accountId(db, '1000');
    final sales = await Books.accountId(db, '4000');
    await Books.post(db, 'manual', 1, ymd(DateTime.now()), 'x', [JL(cash, 100, 0), JL(sales, 0, 100)]);
    await expectLater(Books.post(db, 'manual', 1, ymd(DateTime.now()), 'x', [JL(cash, 100, 0), JL(sales, 0, 100)]),
        throwsA(isA<AccountingError>()));
    await expectLater(Books.post(db, 'manual', 2, ymd(DateTime.now()), 'x', [JL(cash, 100, 0), JL(sales, 0, 90)]),
        throwsA(isA<AccountingError>()));
  });

  test('dashboard analytics: series add up to period totals', () async {
    await Books.loadDemo();
    final now = DateTime.now();
    for (final from in [DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, 1), DateTime(now.year, 1, 1)]) {
      final a = await Books.analytics(from, now);
      expect(a.series.fold<int>(0, (s, p) => s + p.sales), a.cur.sales);
      expect(a.series.fold<int>(0, (s, p) => s + p.purchases), a.cur.purchases);
    }
    final year = await Books.analytics(DateTime(now.year - 1, now.month, now.day), now);
    expect(year.granularity, 'month');
  });

  test('smart assist reads product names', () async {
    final a = Smart.analyse('iPhone 15 Pro 8GB 256GB Natural Titanium');
    expect(a.category, 'Mobile');
    expect(a.brand, 'Apple');
    expect(a.hsn, '8517');
    expect(a.ram, '8GB');
    expect(a.storage, '256GB');
    expect(a.color, 'Natural Titanium');
    final b = Smart.analyse('HP Victus 15 16GB 512GB SSD');
    expect(b.category, 'Laptop');
    expect(b.brand, 'HP');
    expect(b.storage, '512GB SSD');
    expect(Smart.analyse('Apple 20W USB-C Charger').category, 'Accessories');
    expect(Smart.analyse('Redmi Note 13 8/128 Blue').variant, '8GB • 128GB • Blue');
    expect(Smart.suggestPrice(4200000, 'Mobile'), 4539900);
    expect(await Smart.nextSku('Mobile', 'Apple'), 'GX-MOB-APP-0001');
  });

  test('due ageing settles the oldest bills first', () async {
    final c = await Books.saveParty('customer', {'name': 'Ageing Test'});
    final p = await Books.saveProduct({'name': 'Cable', 'gst_bp': 0, 'price': 10000}, openingQty: 10, openingCost: 5000);
    final cash = asInt((await Books.moneyAccounts()).first['id']);
    final now = DateTime.now();
    String ago(int d) => ymd(now.subtract(Duration(days: d)));
    await Books.createSale(items: [ItemIn(p, 1, 10000)], customerId: c, paid: 0, accountId: cash, date: ago(75)); // ₹100
    await Books.createSale(items: [ItemIn(p, 1, 10000)], customerId: c, paid: 0, accountId: cash, date: ago(40)); // ₹100
    await Books.createSale(items: [ItemIn(p, 1, 10000)], customerId: c, paid: 0, accountId: cash, date: ago(5)); // ₹100
    await Books.createPayment(kind: 'receipt', partyId: c, amount: 15000, accountId: cash); // ₹150 clears oldest + half
    final a = (await Books.ageing('customer'))[c]!;
    expect(a.buckets, [10000, 5000, 0, 0]);
    expect(a.total, await Books.partyBalance('customer', c));
    expect(a.oldestDays, 40);
    final stats = await Books.partyStats('customer', c);
    expect(stats.docs, 3);
    expect(stats.business, 30000);
    expect(stats.paymentsTotal, 15000);
  });

  test('split payment posts each account and keeps books balanced', () async {
    final c = await Books.saveParty('customer', {'name': 'Split Test'});
    final p = await Books.saveProduct({'name': 'Phone', 'gst_bp': 0, 'price': 1000000}, openingQty: 2, openingCost: 800000);
    final acc = await Books.moneyAccounts();
    final cash = asInt(acc[0]['id']), bank = asInt(acc[1]['id']);
    final id = await Books.createSale(
      items: [ItemIn(p, 1, 1000000)],
      customerId: c,
      splits: [MapEntry(cash, 400000), MapEntry(bank, 500000)],
    );
    expect(await Books.balance(cash, 'asset'), 400000);
    expect(await Books.balance(bank, 'asset'), 500000);
    expect(await Books.partyBalance('customer', c), 100000);
    final sp = await Books.query('SELECT account_id, amount FROM sale_payments WHERE sale_id = ? ORDER BY amount', [id]);
    expect(sp.map((r) => asInt(r['amount'])).toList(), [400000, 500000]);
    await expectBalanced();
  });

  test('expense insights: totals, recurring rent and spikes', () async {
    final heads = await Books.accounts(kind: 'expense');
    final rent = asInt(heads.first['id']);
    final cash = asInt((await Books.moneyAccounts()).first['id']);
    final now = DateTime.now();
    for (var m = 1; m <= 3; m++) {
      await Books.createExpense(headId: rent, amount: 1200000, accountId: cash, date: ymd(DateTime(now.year, now.month - m, 5)));
    }
    await Books.createExpense(headId: asInt(heads.last['id']), amount: 30000, accountId: cash, date: ymd(now));
    final x = await Books.expenseInsights(DateTime(now.year, now.month, 1), now);
    expect(x.total, 30000);
    expect(x.recurring.single.name, heads.first['name']);
    expect(x.recurring.single.typical, 1200000);
    expect(x.recurring.single.day, 5);
    expect(x.recurring.single.paidThisMonth, isFalse);
    expect(x.months.length, 6);
  });

  test('khata: cash given / got, goods on credit, due dates and feed', () async {
    final c = await Books.saveParty('customer', {'name': 'Khata Test', 'phone': '9800000099', 'aadhaar': '123412341234'});
    final p = await Books.saveProduct({'name': 'Charger', 'gst_bp': 0, 'price': 50000}, openingQty: 5, openingCost: 30000);
    final cash = asInt((await Books.moneyAccounts()).first['id']);
    await Books.createSale(items: [ItemIn(p, 2, 50000)], customerId: c, paid: 20000, accountId: cash); // ₹800 on credit
    await Books.createLend(kind: 'gave', partyType: 'customer', partyId: c, amount: 300000, accountId: cash, reason: 'Cash loan');
    await Books.createLend(kind: 'got', partyType: 'customer', partyId: c, amount: 100000, accountId: cash, reason: 'Loan returned');
    expect(await Books.partyBalance('customer', c), 80000 + 300000 - 100000);

    final split = await Books.creditSplit('customer', c);
    expect(split.goods, 80000);
    expect(split.cashGave, 300000);
    expect(split.cashGot, 100000);

    final t = await Books.khataTotals();
    expect(t.youGet, 280000);
    expect(t.cashLent, 300000);

    final feed = await Books.khataFeed();
    expect(feed.map((e) => e['kind']).toSet(), containsAll(['goods', 'cash_gave', 'cash_got']));
    expect(feed.firstWhere((e) => e['kind'] == 'goods')['reason'], 'Charger ×2');

    final due = await Books.addDue('customer', c, 280000, ymd(DateTime.now().add(const Duration(days: 7))), 'After salary');
    expect((await Books.dues()).single['party'], 'Khata Test');
    await Books.setDueStatus(due, 'paid');
    expect(await Books.dues(), isEmpty);
    expect((await Books.dues(partyType: 'customer', partyId: c, openOnly: false)).single['status'], 'paid');
    expect((await Books.boughtBy(c)).single['qty'], 2);
    await expectBalanced();
  });

  test('credit card: spends fall due after bill days, payments settle oldest first', () async {
    final acc = await Books.moneyAccounts();
    final bank = asInt(acc[1]['id']);
    final card = await Books.saveMoneyAccount(
        {'name': 'Test Credit', 'card_type': 'credit', 'credit_limit': 1000000, 'bill_days': 40}, opening: 0);
    final rec = (await Books.query('SELECT * FROM accounts WHERE id = ?', [card])).single;
    expect(rec['type'], 'liability');
    expect((await Books.moneyAccounts()).any((a) => asInt(a['id']) == card), isFalse);
    expect((await Books.moneyAccounts(withCards: true)).any((a) => asInt(a['id']) == card), isTrue);
    final heads = await Books.accounts(kind: 'expense');
    final now = DateTime.now();
    String ago(int d) => ymd(now.subtract(Duration(days: d)));
    await Books.createExpense(headId: asInt(heads[0]['id']), amount: 300000, accountId: card, date: ago(30));
    await Books.createExpense(headId: asInt(heads[0]['id']), amount: 200000, accountId: card, date: ago(10));
    var st = await Books.cardStatus(rec);
    expect(st.outstanding, 500000);
    expect(st.available, 500000);
    expect(st.dues.first.key, ymd(DateTime.parse(ago(30)).add(const Duration(days: 40))));
    expect(st.dues.first.value, 300000);
    await Books.createTransfer(fromId: bank, toId: card, amount: 350000);
    st = await Books.cardStatus(rec);
    expect(st.outstanding, 150000);
    expect(st.dues.length, 1);
    expect(st.next!.value, 150000);
    expect(st.next!.key, ymd(DateTime.parse(ago(10)).add(const Duration(days: 40))));
    final debit = await Books.saveMoneyAccount({'name': 'My Debit', 'card_type': 'debit', 'acc_no': '1234'}, opening: 100000);
    expect(await Books.balance(debit, 'asset'), 100000);
    await expectBalanced();
  });

  test('sales book search: mobile, IMEI, amount, address', () async {
    final c = await Books.saveParty('customer', {'name': 'Rahul Das', 'phone': '98300 12345', 'address': 'Salt Lake, Kolkata'});
    final p = await Books.saveProduct({'name': 'iPhone 15', 'gst_bp': 0, 'price': 7000000}, openingQty: 2, openingCost: 6000000);
    await Books.createSale(items: [ItemIn(p, 1, 7000000, '356789104455667')], customerId: c, paid: 7000000, accountId: asInt((await Books.moneyAccounts())[0]['id']));
    final rows = await Books.salesBook();
    expect(rows.single['serials'], '356789104455667');
    expect(rows.single['accounts'], 'Cash in Hand');
    expect(matchSale(rows.single, '9830012345')?.$1, 'Mobile');
    expect(matchSale(rows.single, '4455667')?.$1, 'IMEI / Serial');
    expect(matchSale(rows.single, '70000')?.$1, 'Amount');
    expect(matchSale(rows.single, 'salt lake')?.$1, 'Address');
    expect(matchSale(rows.single, 'iphone')?.$1, 'Product');
    expect(matchSale(rows.single, 'samsung'), isNull);
  });

  test('purchases book and stock supplied by a supplier', () async {
    final sup = await Books.saveParty('supplier', {'name': 'Kolkata Mobile Dist', 'phone': '033 2222 1111', 'gstin': '19ABCDE1234F1Z5'});
    final p = await Books.saveProduct({'name': 'Redmi Note 13', 'gst_bp': 0, 'price': 1500000});
    final bank = asInt((await Books.moneyAccounts())[1]['id']);
    await Books.createPurchase(
        items: [ItemIn(p, 2, 1200000, '861234500012345')], supplierId: sup, paid: 1000000, accountId: bank, billNo: 'KMD/77');
    final rows = await Books.purchasesBook();
    expect(rows.single['supplier'], 'Kolkata Mobile Dist');
    expect(asInt(rows.single['qty']), 2);
    expect(matchDoc(rows.single, 'kmd/77', party: 'supplier', accounts: 'account')?.$1, 'Bill no.');
    expect(matchDoc(rows.single, '00012345', party: 'supplier', accounts: 'account')?.$1, 'IMEI / Serial');
    expect(matchDoc(rows.single, 'kolkata', party: 'supplier', accounts: 'account')?.$1, 'Supplier');
    expect(matchDoc(rows.single, '19abcde', party: 'supplier', accounts: 'account')?.$1, 'GSTIN');
    final supplied = await Books.suppliedBy(sup);
    expect(supplied.single['bill_no'], 'KMD/77');
    expect(asInt(supplied.single['qty']), 2);
  });

  test('sale return: refund less than value, the rest is profit, stock comes back', () async {
    final c = await Books.saveParty('customer', {'name': 'Return Test'});
    final p = await Books.saveProduct({'name': 'Phone X', 'gst_bp': 0, 'price': 1000000}, openingQty: 2, openingCost: 800000);
    final acc = await Books.moneyAccounts();
    final cash = asInt(acc[0]['id']);
    final sale = await Books.createSale(items: [ItemIn(p, 1, 1000000)], customerId: c, paid: 1000000, accountId: cash);
    final before = await Books.profitLoss(ymd(DateTime.now()), ymd(DateTime.now()));
    final lines = await Books.returnable(sale);
    expect(lines.single.left, 1);
    expect(lines.single.unitValue, 1000000);
    await Books.createSaleReturn(saleId: sale, qty: {asInt(lines.single.item['id']): 1}, refund: 900000, accountId: cash);
    expect(await Books.balance(cash, 'asset'), 100000);
    expect(asInt((await Books.query('SELECT stock FROM products WHERE id = ?', [p])).first['stock']), 2);
    final after = await Books.profitLoss(ymd(DateTime.now()), ymd(DateTime.now()));
    // sale profit 2,000 is reversed; the 1,000 kept stays as profit
    expect(after.netProfit, before.netProfit - 200000 + 100000);
    expect((await Books.returnable(sale)).single.left, 0);
    expect(() => Books.createSaleReturn(saleId: sale, qty: {asInt(lines.single.item['id']): 1}, refund: 0, accountId: cash),
        throwsA(isA<AccountingError>()));
    expect((await Books.saleReturns()).single['deduction'], 100000);
    await expectBalanced();
  });

  test('sale return adjusted against customer due', () async {
    final c = await Books.saveParty('customer', {'name': 'Due Return'});
    final p = await Books.saveProduct({'name': 'Earbuds', 'gst_bp': 1800, 'price': 200000}, openingQty: 3, openingCost: 100000);
    final sale = await Books.createSale(items: [ItemIn(p, 2, 200000)], customerId: c, paid: 0);
    expect(await Books.partyBalance('customer', c), 472000);
    final l = (await Books.returnable(sale)).single;
    await Books.createSaleReturn(saleId: sale, qty: {asInt(l.item['id']): 1}, refund: 236000, restock: false);
    expect(await Books.partyBalance('customer', c), 236000);
    expect(asInt((await Books.query('SELECT stock FROM products WHERE id = ?', [p])).first['stock']), 1);
    await expectBalanced();
  });

  test('amount in words (Indian system)', () {
    expect(amountInWords(2000000), 'TWENTY THOUSAND RUPEES ONLY');
    expect(amountInWords(12345678950), 'TWELVE CRORE THIRTY FOUR LAKH FIFTY SIX THOUSAND SEVEN HUNDRED EIGHTY NINE RUPEES AND FIFTY PAISE ONLY');
    expect(amountInWords(10100), 'ONE HUNDRED ONE RUPEES ONLY');
  });

  test('edit sale: items, payment and stock are replaced in place', () async {
    final c = await Books.saveParty('customer', {'name': 'Edit Me'});
    final a = await Books.saveProduct({'name': 'Phone A', 'gst_bp': 0, 'price': 1000000}, openingQty: 3, openingCost: 800000);
    final b = await Books.saveProduct({'name': 'Phone B', 'gst_bp': 0, 'price': 500000}, openingQty: 3, openingCost: 400000);
    final cash = asInt((await Books.moneyAccounts())[0]['id']);
    final id = await Books.createSale(items: [ItemIn(a, 2, 1000000, 'IMEI1', 'OPP-7')], customerId: c, paid: 1000000, accountId: cash);
    final number = (await Books.query('SELECT number FROM sales WHERE id = ?', [id])).first['number'];
    expect((await Books.query('SELECT opp_id FROM sale_items WHERE sale_id = ?', [id])).first['opp_id'], 'OPP-7');
    await Books.updateSale(id, items: [ItemIn(b, 1, 500000)], customerId: c, paid: 500000, accountId: cash);
    final pa = (await Books.query('SELECT stock FROM products WHERE id = ?', [a])).first;
    final pb = (await Books.query('SELECT stock FROM products WHERE id = ?', [b])).first;
    expect(asInt(pa['stock']), 3);
    expect(asInt(pb['stock']), 2);
    final s = (await Books.query('SELECT * FROM sales WHERE id = ?', [id])).first;
    expect(s['number'], number);
    expect(asInt(s['total']), 500000);
    expect(await Books.partyBalance('customer', c), 0);
    expect(await Books.balance(cash, 'asset'), 500000);
    expect(asInt((await Books.query("SELECT COUNT(*) AS n FROM journal_entries WHERE source_type = 'sale' AND source_id = ?", [id])).first['n']), 1);
    await expectBalanced();
  });

  test('edit purchase replaces stock; refuses when units are already sold', () async {
    final sup = await Books.saveParty('supplier', {'name': 'Edit Supplier'});
    final p = await Books.saveProduct({'name': 'Cable', 'gst_bp': 0, 'price': 30000});
    final pid = await Books.createPurchase(items: [ItemIn(p, 10, 10000)], supplierId: sup);
    await Books.createPurchase(items: [ItemIn(p, 4, 12000)], supplierId: sup, editId: pid);
    expect(asInt((await Books.query('SELECT stock FROM products WHERE id = ?', [p])).first['stock']), 4);
    expect(await Books.partyBalance('supplier', sup), 48000);
    await Books.createSale(items: [ItemIn(p, 3, 30000)]);
    expect(() => Books.createPurchase(items: [ItemIn(p, 1, 12000)], supplierId: sup, editId: pid), throwsA(isA<AccountingError>()));
    await expectBalanced();
  });

  test('EMI: schedule, shop collections post receipts, plan closes when paid', () async {
    expect(ymd(addMonths(DateTime(2026, 1, 31), 1)), '2026-02-28');
    final c = await Books.saveParty('customer', {'name': 'EMI Buyer'});
    final p = await Books.saveProduct({'name': 'Vivo Y28', 'gst_bp': 0, 'price': 1500000}, openingQty: 1, openingCost: 1200000);
    final cash = asInt((await Books.moneyAccounts())[0]['id']);
    final sale = await Books.createSale(items: [ItemIn(p, 1, 1500000, '861111222233334')], customerId: c, paid: 300000, accountId: cash);
    final plan = await Books.createEmiPlan(
        customerId: c, kind: 'shop', emi: 400000, months: 3, startDate: '2026-12-05', saleId: sale, price: 1500000, downPayment: 300000);
    final inst = await Books.emiInstallments(plan);
    expect(inst.map((r) => r['due_date']).toList(), ['2026-12-05', '2027-01-05', '2027-02-05']);
    var row = (await Books.emiPlans()).single;
    expect(row['next_due'], '2026-12-05');
    expect(asInt(row['paid_n']), 0);
    for (final r in inst) {
      await Books.payEmi(asInt(r['id']), amount: 400000, accountId: cash);
    }
    row = (await Books.emiPlans()).single;
    expect(row['status'], 'closed');
    expect(asInt(row['paid_sum']), 1200000);
    expect(await Books.partyBalance('customer', c), 0);
    expect(() => Books.deleteEmiPlan(plan), throwsA(isA<AccountingError>()));
    final f = await Books.createEmiPlan(customerId: c, kind: 'finance', financer: 'Bajaj Finserv', emi: 250000, months: 6, startDate: '2026-12-10');
    final fi = (await Books.emiInstallments(f)).first;
    await Books.payEmi(asInt(fi['id']), amount: 250000);
    expect(await Books.partyBalance('customer', c), 0); // finance plans never touch the books
    await expectBalanced();
  });

  test('IMEI history: purchase, sale, return and warranty', () async {
    final sup = await Books.saveParty('supplier', {'name': 'IMEI Supplier'});
    final c = await Books.saveParty('customer', {'name': 'IMEI Customer', 'phone': '9000000000'});
    final p = await Books.saveProduct({'name': 'Redmi 13C', 'gst_bp': 0, 'price': 900000, 'warranty_months': 12});
    await Books.createPurchase(items: [ItemIn(p, 1, 800000, '865432100001111')], supplierId: sup, billNo: 'B-77');
    final sale = await Books.createSale(items: [ItemIn(p, 1, 900000, '865432100001111')], customerId: c, paid: 900000);
    var r = (await Books.imeiLookup('00001111')).single;
    expect(r.status, 'sold');
    expect(r.purchase!['party'], 'IMEI Supplier');
    expect(r.sale!['party'], 'IMEI Customer');
    expect(r.warrantyMonths, 12);
    expect(r.warrantyDaysLeft, greaterThan(300));
    final line = (await Books.returnable(sale)).single;
    await Books.createSaleReturn(saleId: sale, qty: {asInt(line.item['id']): 1}, refund: 900000, accountId: asInt((await Books.moneyAccounts())[0]['id']));
    r = (await Books.imeiLookup('865432100001111')).single;
    expect(r.status, 'returned');
    expect(await Books.imeiLookup('99999999'), isEmpty);
  });

  test('delete sale, purchase, return and parties keeps the books right', () async {
    final sup = await Books.saveParty('supplier', {'name': 'Del Supplier'});
    final c = await Books.saveParty('customer', {'name': 'Del Customer'}, opening: 50000);
    final p = await Books.saveProduct({'name': 'Del Phone', 'gst_bp': 0, 'price': 1000000});
    final cash = asInt((await Books.moneyAccounts())[0]['id']);
    final pur = await Books.createPurchase(items: [ItemIn(p, 3, 800000)], supplierId: sup, paid: 800000, accountId: cash);
    final sale = await Books.createSale(items: [ItemIn(p, 1, 1000000)], customerId: c, paid: 400000, accountId: cash);
    Future<int> st() async => asInt((await Books.query('SELECT stock FROM products WHERE id = ?', [p])).first['stock']);
    expect(await st(), 2);
    // party with bills cannot be deleted
    expect(await Books.partyLinks('customer', c), isNotEmpty);
    expect(() => Books.deleteParty('customer', c), throwsA(isA<AccountingError>()));
    // a sale with a return must lose the return first
    final line = (await Books.returnable(sale)).single;
    final ret = await Books.createSaleReturn(saleId: sale, qty: {asInt(line.item['id']): 1}, refund: 900000, accountId: cash);
    expect(await st(), 3);
    expect(() => Books.deleteSale(sale), throwsA(isA<AccountingError>()));
    await Books.deleteSaleReturn(ret);
    expect(await st(), 2);
    await Books.deleteSale(sale);
    expect(await st(), 3);
    expect(await Books.partyBalance('customer', c), 50000);
    // purchase can be deleted once nothing from it is sold
    await Books.deletePurchase(pur);
    expect(await st(), 0);
    expect(await Books.balance(cash, 'asset'), 0);
    expect(await Books.partyBalance('supplier', sup), 0);
    await Books.deleteParty('customer', c);
    await Books.deleteParty('supplier', sup);
    expect(await Books.query('SELECT * FROM customers WHERE id = ?', [c]), isEmpty);
    await expectBalanced();
  });

  test('Smart IMEI: check digit, model from TAC, duplicates', () async {
    expect(SmartImei.luhn('490154203237518'), isTrue);
    expect(SmartImei.luhn('490154203237519'), isFalse);
    final sup = await Books.saveParty('supplier', {'name': 'TAC Supplier'});
    final p = await Books.saveProduct({'name': 'Vivo Y28 8/128', 'gst_bp': 0, 'price': 1500000});
    await Books.createPurchase(items: [ItemIn(p, 1, 1200000, '490154203237518')], supplierId: sup);
    // exact device bought earlier
    var m = await SmartImei.match('490154203237518');
    expect(m.how, 'exact');
    expect(asInt(m.product!['id']), p);
    expect(m.warning(), isNull);
    expect(m.warning(selling: false), contains('Already purchased'));
    // another unit of the same model (same first 8 digits)
    m = await SmartImei.match('490154209999991');
    expect(m.how, 'tac');
    expect(asInt(m.product!['id']), p);
    // once sold, selling it again is flagged
    await Books.createSale(items: [ItemIn(p, 1, 1500000, '490154203237518')]);
    m = await SmartImei.match('490154203237518');
    expect(m.warning(), contains('Already sold'));
    // unknown model
    m = await SmartImei.match('111111111111116');
    expect(m.product, isNull);
  });

  test('demo data loads and balances', () async {
    await Books.loadDemo();
    await expectBalanced();
    final d = await Books.dashboard();
    expect(d.months.length, 6);
  });
}
