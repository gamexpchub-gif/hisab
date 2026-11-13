import 'books.dart';
import 'money.dart';

/// What the app knows about a scanned IMEI / serial.
class ImeiMatch {
  final String code;
  final bool isImei; // 15 digits
  final bool valid; // check digit OK (always true for non-IMEI serials)
  final Rec? product; // the product this device is
  final String how; // exact | tac | none
  final int tacSeen; // devices of this model seen before
  final Rec? soldOn; // open sale that already has this IMEI
  final Rec? boughtOn; // purchase that brought this IMEI in
  const ImeiMatch(this.code,
      {this.isImei = false, this.valid = true, this.product, this.how = 'none', this.tacSeen = 0, this.soldOn, this.boughtOn});

  String get tac => isImei ? code.substring(0, 8) : '';

  /// Warning line to show, or null when all is well.
  String? warning({bool selling = true}) {
    if (isImei && !valid) return 'IMEI check digit is wrong — please re-check the number';
    if (selling && soldOn != null) return 'Already sold on ${soldOn!['number']} (${prettyDate('${soldOn!['date']}')})';
    if (!selling && boughtOn != null) return 'Already purchased on ${boughtOn!['number']} (${prettyDate('${boughtOn!['date']}')})';
    return null;
  }
}

/// Smart IMEI — validates IMEIs (Luhn check digit), recognises the model from
/// its TAC (first 8 digits) using the shop's own purchases and sales, and
/// spots duplicates. Works offline and gets better with every device.
class SmartImei {
  static String clean(String s) => s.replaceAll(RegExp(r'[\s\-/]'), '').trim();

  static bool looksLikeImei(String s) => RegExp(r'^\d{15}$').hasMatch(clean(s));

  /// Luhn check used by IMEIs.
  static bool luhn(String s) {
    final d = clean(s);
    if (!RegExp(r'^\d{15}$').hasMatch(d)) return false;
    var sum = 0;
    for (var i = 0; i < 15; i++) {
      var n = d.codeUnitAt(14 - i) - 48;
      if (i.isOdd) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
    }
    return sum % 10 == 0;
  }

  static Future<ImeiMatch> match(String raw) async {
    final code = clean(raw);
    final isImei = looksLikeImei(code);
    final valid = !isImei || luhn(code);
    // exact device: bought into stock earlier
    final bought = await Books.query(
        'SELECT i.product_id, b.id AS doc_id, b.number, b.date FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id '
        'WHERE i.serial = ? ORDER BY b.date DESC, b.id DESC LIMIT 1',
        [code]);
    // already sold (and not returned)
    final sold = await Books.query(
        'SELECT i.product_id, s.id AS doc_id, s.number, s.date FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'WHERE i.serial = ? AND NOT EXISTS (SELECT 1 FROM sale_return_items r WHERE r.sale_item_id = i.id) '
        'ORDER BY s.date DESC, s.id DESC LIMIT 1',
        [code]);
    Rec? product;
    var how = 'none';
    var seen = 0;
    final exactId = bought.isNotEmpty ? asInt(bought.first['product_id']) : sold.isNotEmpty ? asInt(sold.first['product_id']) : null;
    if (exactId != null) {
      product = await _product(exactId);
      how = product == null ? 'none' : 'exact';
    }
    if (product == null && isImei) {
      // same model = same TAC (first 8 digits); pick the product seen most
      final tac = '${code.substring(0, 8)}%';
      final r = await Books.query(
          'SELECT product_id, COUNT(*) AS n, MAX(at) AS last FROM ('
          'SELECT i.product_id, b.date AS at FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id WHERE i.serial LIKE ? '
          'UNION ALL '
          'SELECT i.product_id, s.date AS at FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE i.serial LIKE ?'
          ') GROUP BY product_id ORDER BY n DESC, last DESC LIMIT 1',
          [tac, tac]);
      if (r.isNotEmpty) {
        product = await _product(asInt(r.first['product_id']));
        if (product != null) {
          how = 'tac';
          seen = asInt(r.first['n']);
        }
      }
    }
    return ImeiMatch(code,
        isImei: isImei,
        valid: valid,
        product: product,
        how: how,
        tacSeen: seen,
        soldOn: sold.isEmpty ? null : sold.first,
        boughtOn: bought.isEmpty ? null : bought.first);
  }

  static Future<Rec?> _product(int id) async {
    final r = await Books.query(
        'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id WHERE p.id = ?', [id]);
    return r.isEmpty ? null : r.first;
  }
}
