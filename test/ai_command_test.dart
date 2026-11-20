import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/ai_command.dart';

Map<String, Object?> p(int id, String name, {String? brand, String? variant, int stock = 3}) =>
    {'id': id, 'name': name, 'brand': brand, 'variant': variant, 'stock': stock, 'price': 1000000, 'gst_bp': 0};

void main() {
  final products = [
    p(1, 'Vivo T3', brand: 'Vivo', variant: '8GB • 128GB'),
    p(2, 'iPhone 15', brand: 'Apple'),
    p(3, 'Back Cover'),
    p(4, 'Tempered Glass'),
  ];
  final customers = [
    {'id': 1, 'name': 'Rahim Sheikh', 'phone': '98300 11111'},
    {'id': 2, 'name': 'Ankit Das', 'phone': '9830022222'},
  ];

  test('new customer + bill in one sentence', () {
    final c = AiCommands.parse('Karim Uddin 9830099999 ke Vivo T3 ekta 18 hajar cash', products, customers) as BillCommand;
    expect(c.customer, isNull);
    expect(c.newName, 'Karim Uddin');
    expect(c.newPhone, '9830099999');
    expect(c.lines.single.product['id'], 1);
    expect(c.lines.single.qty, 1);
    expect(c.lines.single.rate, 1800000);
    expect(c.pay, 'cash');
  });

  test('existing customer by phone or by name, several items, due', () {
    var c = AiCommands.parse('+91 98300-11111 iphone 15 65000 and 2 ta back cover 299 baki', products, customers) as BillCommand;
    expect(c.customer?['id'], 1);
    expect(c.lines.length, 2);
    expect(c.lines[0].rate, 6500000);
    expect(c.lines[1].qty, 2);
    expect(c.lines[1].rate, 29900);
    expect(c.pay, 'due');
    c = AiCommands.parse('Ankit Das tempered glass 199 upi', products, customers) as BillCommand;
    expect(c.customer?['id'], 2);
    expect(c.lines.single.product['id'], 4);
    expect(c.pay, 'upi');
  });

  test('advance on a bill', () {
    final c = AiCommands.parse('Rahim Sheikh vivo t3 18000 advance 5000', products, customers) as BillCommand;
    expect(c.lines.single.rate, 1800000);
    expect(c.paidNow, 500000);
  });

  test('money received and new customer commands', () {
    final r = AiCommands.parse('Rahim Sheikh 5000 joma', products, customers) as ReceiptCommand;
    expect(r.customer?['id'], 1);
    expect(r.amount, 500000);
    final n = AiCommands.parse('new customer Bablu Roy 9830077777', products, customers) as CustomerCommand;
    expect(n.name, 'Bablu Roy');
    expect(n.phone, '9830077777');
  });

  test('questions are not commands', () {
    expect(AiCommands.parse('gato mash-e Vivo-te koto labh?', products, customers), isNull);
    expect(AiCommands.parse('best seller this month', products, customers), isNull);
  });
}
