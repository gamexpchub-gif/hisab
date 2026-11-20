import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/quick.dart';

Map<String, Object?> p(int id, String name, {String? brand, String? variant, String? cat, int stock = 1, String? sku}) =>
    {'id': id, 'name': name, 'brand': brand, 'variant': variant, 'category': cat, 'stock': stock, 'sku': sku, 'price': 100000};

void main() {
  final products = [
    p(1, 'Vivo T3', brand: 'Vivo', variant: '8GB • 128GB • Blue', cat: 'Mobile'),
    p(2, 'Vivo T3', brand: 'Vivo', variant: '8GB • 256GB • Black', cat: 'Mobile'),
    p(3, 'Redmi Note 13', brand: 'Xiaomi', variant: '6GB • 128GB', cat: 'Mobile'),
    p(4, 'iPhone 15', brand: 'Apple', variant: '128GB', cat: 'Mobile'),
    p(5, 'Back Cover', cat: 'Accessories'),
    p(6, 'Charger 33W', brand: 'Generic', cat: 'Accessories', sku: 'CHG33'),
  ];
  final customers = [
    {'id': 1, 'name': 'Rahim Sheikh'},
    {'id': 2, 'name': 'Ankit Das'},
  ];

  test('smart search: variants, typos, joined words, SKU', () {
    expect(SmartSearch.rank(products, 'vivo 8 128 blue').first['id'], 1);
    expect(SmartSearch.rank(products, 'vivo 256').first['id'], 2);
    expect(SmartSearch.rank(products, 'redmi note13').first['id'], 3);
    expect(SmartSearch.rank(products, 'iphne 15').first['id'], 4);
    expect(SmartSearch.rank(products, 'chg33').first['id'], 6);
    expect(SmartSearch.rank(products, 'samsung'), isEmpty);
    expect(SmartSearch.rank(products, 'cover').first['id'], 5);
  });

  test('voice bill: Banglish sentence', () {
    final o = VoiceBill.parse('Vivo T3 ekta 18 hajar Rahim cash', products, customers);
    expect(o.lines.length, 1);
    expect(o.lines.first.product['name'], 'Vivo T3');
    expect(o.lines.first.qty, 1);
    expect(o.lines.first.rate, 1800000);
    expect(o.customer?['id'], 1);
    expect(o.pay, 'cash');
  });

  test('voice bill: several items, model numbers, due', () {
    final o = VoiceBill.parse('iPhone 15 one piece 65,000 and 2 ta back cover 299 Ankit baki', products, customers);
    expect(o.lines.length, 2);
    expect(o.lines[0].product['id'], 4);
    expect(o.lines[0].rate, 6500000);
    expect(o.lines[1].product['id'], 5);
    expect(o.lines[1].qty, 2);
    expect(o.lines[1].rate, 29900);
    expect(o.customer?['id'], 2);
    expect(o.pay, 'due');
  });

  test('voice bill: Bengali digits and lakh', () {
    expect(VoiceBill.normalise('১৮ হাজার'), contains('18'));
    expect(VoiceBill.normalise('1.5 lakh'), '150000');
    expect(VoiceBill.normalise('18 hajar 500'), '18500');
  });

  test('bill scan: phone numbers split by spaces are not IMEIs', () {
    // 98300 11111 98300 2222x: try every last digit — none may be read as an IMEI
    for (var d = 0; d < 10; d++) {
      expect(BillScan.imeis('Ph: 98300 11111 98300 2222$d'), isEmpty);
    }
    expect(BillScan.imeis('IMEI 3512 3456 0000 010'), ['351234560000010']);
  });

  test('bill scan: lines, quantities, rates and IMEIs', () async {
    const text = 'ABC MOBILE DISTRIBUTORS\nInvoice No: INV-2291\n'
        'Vivo T3 8/128 Blue  2  16500.00  33000.00\n'
        'IMEI: 351234560000010, 351234560007775\n'
        'Back Cover 10 50 500\n';
    final r = await BillScan.parse(text, products);
    expect(r.billNo, 'INV-2291');
    expect(r.imeis, ['351234560000010', '351234560007775']);
    expect(r.lines.length, 2);
    expect(r.lines[0].product['name'], 'Vivo T3');
    expect(r.lines[0].qty, 2);
    expect(r.lines[0].rate, 1650000);
    expect(r.lines[0].serials.length, 2);
    expect(r.lines[1].product['id'], 5);
    expect(r.lines[1].qty, 10);
    expect(r.lines[1].rate, 5000);
  });
}
