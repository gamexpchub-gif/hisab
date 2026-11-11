import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hisab/core/books.dart';
import 'package:hisab/core/db.dart';
import 'package:hisab/core/money.dart';
import 'package:hisab/core/smart.dart';

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

  test('demo data loads and balances', () async {
    await Books.loadDemo();
    await expectBalanced();
    final d = await Books.dashboard();
    expect(d.months.length, 6);
  });
}
