import '../cloud/cloud.dart';
import 'books.dart';
import 'money.dart';
import 'plan.dart';
import 'smart.dart';
import 'tac_db.dart';

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
  final String? suggestName, suggestBrand; // model name when no product matches yet
  final String? suggestCategory, suggestRam, suggestStorage;
  const ImeiMatch(this.code,
      {this.isImei = false,
      this.valid = true,
      this.product,
      this.how = 'none',
      this.tacSeen = 0,
      this.soldOn,
      this.boughtOn,
      this.suggestName,
      this.suggestBrand,
      this.suggestCategory,
      this.suggestRam,
      this.suggestStorage});

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
    // bought back after it was sold (exchange): in stock again, not "sold"
    var soldRows = sold;
    if (sold.isNotEmpty && bought.isNotEmpty) {
      final nb = asInt((await Books.query('SELECT COUNT(*) AS c FROM purchase_items WHERE serial = ?', [code])).first['c']);
      final ns = asInt((await Books.query(
              'SELECT COUNT(*) AS c FROM sale_items i WHERE i.serial = ? AND NOT EXISTS (SELECT 1 FROM sale_return_items r WHERE r.sale_item_id = i.id)',
              [code]))
          .first['c']);
      if (nb > ns) soldRows = const [];
    }
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
    String? sName, sBrand, sCat, sRam, sStorage;
    if (product == null && isImei) {
      // models taught to the app (Add Product with a scanned IMEI)
      final t = await Books.query('SELECT * FROM imei_models WHERE tac = ?', [code.substring(0, 8)]);
      if (t.isNotEmpty) {
        final pid = t.first['product_id'];
        if (pid != null) product = await _product(asInt(pid));
        if (product != null) {
          how = 'learned';
        } else {
          final full = '${t.first['name'] ?? ''}';
          final g = Smart.analyse(full);
          sName = full.isEmpty ? null : modelName(full);
          sBrand = t.first['brand'] as String? ?? g.brand;
          sCat = g.category;
          sRam = g.ram;
          sStorage = g.storage;
        }
      }
    }
    if (product == null && sName == null && isImei) {
      // Hisab AI community list: models named by other shops
      final c = await Accounts.tacGet(code.substring(0, 8)).timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (c != null) {
        sName = c.model;
        sBrand = c.brand;
        sCat = c.category;
        sRam = c.ram;
        sStorage = c.storage;
        how = 'community';
        try {
          // cached on the phone with RAM / storage in the name (read back by Smart.analyse)
          final full = [c.model, if (c.ram != null) c.ram!, if (c.storage != null) c.storage!].join(' ');
          await Books.execute(
              'INSERT OR IGNORE INTO imei_models (tac, product_id, name, brand, source, updated_at) VALUES (?, NULL, ?, ?, ?, ?)',
              [code.substring(0, 8), full, sBrand, 'community', DateTime.now().toIso8601String()]);
        } catch (_) {}
      }
    }
    if (product == null && sName == null && isImei && Sub.can('smart_imei')) {
      // public TAC database (online, cached on the phone)
      final m = await TacDb.lookup(code).timeout(const Duration(seconds: 25), onTimeout: () => null);
      if (m != null) {
        sName = m.name;
        sBrand = m.brand;
        how = 'tacdb';
      }
    }
    return ImeiMatch(code,
        isImei: isImei,
        valid: valid,
        product: product,
        how: how,
        tacSeen: seen,
        soldOn: soldRows.isEmpty ? null : soldRows.first,
        boughtOn: bought.isEmpty ? null : bought.first,
        suggestName: sName,
        suggestBrand: sBrand,
        suggestCategory: sCat,
        suggestRam: sRam,
        suggestStorage: sStorage);
  }

  /// Remembers that IMEIs starting with this TAC are [productId].
  static Future<void> learn(String imei,
      {int? productId, String? name, String? brand, String? category, String? ram, String? storage}) async {
    final c = clean(imei);
    if (!looksLikeImei(c)) return;
    await Books.execute(
        'INSERT OR REPLACE INTO imei_models (tac, product_id, name, brand, source, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [c.substring(0, 8), productId, name, brand, 'shop', DateTime.now().toIso8601String()]);
    // teach every Hisab AI shop this model
    if ((name ?? '').trim().length >= 2) {
      final g = Smart.analyse(name!);
      String? n(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
      Accounts.tacPut(
              c.substring(0, 8),
              TacInfo(modelName(name), n(brand) ?? g.brand, n(category) ?? g.category ?? 'Mobile', n(ram) ?? g.ram,
                  n(storage) ?? g.storage))
          .catchError((_) => false);
    }
  }

  /// The model part of a product name: drops colour, storage (8/128, 128GB)
  /// and condition words so one name fits every phone with that TAC.
  static String modelName(String name) {
    var s = ' ${name.trim()} ';
    s = s.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
    s = s.replaceAll(RegExp(r'\b\d{1,2}\s*(gb)?\s*[/+|]\s*\d{2,4}\s*(gb|tb)?\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\b\d{1,4}\s*(gb|tb)\b(\s*(ram|rom|storage))?', caseSensitive: false), ' ');
    const words = 'black|white|blue|red|green|gold|silver|grey|gray|purple|pink|yellow|orange|violet|midnight|starlight|graphite|titanium|natural|desert|mint|cream|lavender|bronze|navy|teal|new|used|refurbished|box|pack';
    s = s.replaceAll(RegExp('\\b($words)\\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[\s,\-/|]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length >= 2 ? s : name.trim();
  }

  /// Shares the models in this shop's past purchases and sales (phones with a
  /// valid IMEI) with the community list — once per store. Returns how many.
  static Future<int> shareHistory() async {
    if (Cloud.user == null) return 0;
    final st = await Books.settings();
    if (st['tac_shared'] == '1') return 0;
    final rows = await Books.query(
        'SELECT substr(x.serial, 1, 8) AS tac, p.name, p.brand, p.variant, c.name AS category, COUNT(*) AS n FROM ('
        'SELECT serial, product_id FROM purchase_items WHERE length(serial) = 15 '
        'UNION ALL SELECT serial, product_id FROM sale_items WHERE length(serial) = 15'
        ') x JOIN products p ON p.id = x.product_id LEFT JOIN categories c ON c.id = p.category_id '
        'GROUP BY tac, p.id ORDER BY tac, n DESC');
    final best = <String, Rec>{};
    for (final r in rows) {
      best.putIfAbsent('${r['tac']}', () => r);
    }
    var n = 0;
    for (final e in best.entries.take(300)) {
      if (!RegExp(r'^\d{8}$').hasMatch(e.key)) continue;
      final name = '${e.value['name'] ?? ''}';
      await Books.execute(
          'INSERT OR IGNORE INTO imei_models (tac, product_id, name, brand, source, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [e.key, null, name, e.value['brand'], 'history', DateTime.now().toIso8601String()]);
      final g = Smart.analyse('$name ${e.value['variant'] ?? ''}');
      final brand = '${e.value['brand'] ?? ''}'.trim();
      final cat = '${e.value['category'] ?? ''}'.trim();
      if (await Accounts.tacPut(e.key,
          TacInfo(modelName(name), brand.isEmpty ? g.brand : brand, cat.isEmpty ? g.category ?? 'Mobile' : cat, g.ram, g.storage))) {
        n++;
      }
    }
    // only when the list really reached the cloud (otherwise try again next time)
    if (n > 0 || best.isEmpty) await Books.setSetting('tac_shared', '1');
    return n;
  }

  /// IMEIs / serials of [productId] bought and still in stock (not sold, or
  /// sold and returned), oldest purchase first.
  static Future<List<String>> inStock(int productId) async {
    // a serial is in stock when it was bought more often than it was sold
    // (and not returned) — a phone sold and later bought back (exchange)
    // counts again — and its latest purchase is this product
    final r = await Books.query(
        'SELECT TRIM(i.serial) AS serial, MIN(b.date) AS d, MIN(i.id) AS first FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id '
        "WHERE i.product_id = ? AND TRIM(COALESCE(i.serial, '')) <> '' GROUP BY TRIM(i.serial) ORDER BY d, first",
        [productId]);
    final out = <String>[];
    for (final x in r) {
      final sn = '${x['serial']}';
      final c = (await Books.query(
              'SELECT (SELECT COUNT(*) FROM purchase_items WHERE TRIM(serial) = ?) AS bought, '
              '(SELECT COUNT(*) FROM sale_items s WHERE TRIM(s.serial) = ? AND NOT EXISTS (SELECT 1 FROM sale_return_items r WHERE r.sale_item_id = s.id)) AS sold, '
              '(SELECT i.product_id FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id WHERE TRIM(i.serial) = ? ORDER BY b.date DESC, i.id DESC LIMIT 1) AS latest',
              [sn, sn, sn]))
          .first;
      if (asInt(c['bought']) > asInt(c['sold']) && asInt(c['latest']) == productId) out.add(sn);
    }
    return out;
  }

  static Future<Rec?> _product(int id) async {
    final r = await Books.query(
        'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id WHERE p.id = ?', [id]);
    return r.isEmpty ? null : r.first;
  }
}
