/// Smart Assist — an offline rule engine that reads a product name and
/// suggests category, brand, HSN, GST, variant and a selling price.
/// Everything runs on the phone; nothing is sent anywhere.
library;

import 'books.dart';
import 'money.dart';

class SmartGuess {
  final String? category, brand, hsn, ram, storage, color;
  final int? gstBp;
  final double confidence; // 0..1, how much of the name was recognised
  const SmartGuess({
    this.category,
    this.brand,
    this.hsn,
    this.gstBp,
    this.ram,
    this.storage,
    this.color,
    this.confidence = 0,
  });

  bool get isEmpty => category == null && brand == null && hsn == null && ram == null && storage == null && color == null;

  String get variant => [
        if (ram != null && storage != null) '$ram • $storage' else ...[if (ram != null) ram!, if (storage != null) storage!],
        if (color != null) color!,
      ].join(' • ');
}

class _Rule {
  final String category, hsn;
  final int gstBp;
  final List<String> words;
  const _Rule(this.category, this.hsn, this.gstBp, this.words);
}

class Smart {
  // Ordered: the first rule with a matching word wins (accessories before
  // devices, so "iPhone charger" is an accessory, not a phone).
  static const _rules = [
    _Rule('Accessories', '8504', 1800, ['charger', 'adapter', 'power adapter', 'adaptor']),
    _Rule('Accessories', '8507', 1800, ['power bank', 'powerbank', 'battery']),
    _Rule('Accessories', '8544', 1800, ['cable', 'type-c cable', 'lightning', 'hdmi', 'usb cable', 'otg']),
    _Rule('Accessories', '8518', 1800, ['airpods', 'buds', 'earbuds', 'earphone', 'earphones', 'headphone', 'headphones', 'headset', 'neckband', 'speaker', 'airdopes', 'soundbar']),
    _Rule('Accessories', '3926', 1800, ['cover', 'case', 'back cover', 'pouch', 'skin']),
    _Rule('Accessories', '7007', 1800, ['tempered', 'screen guard', 'screen protector', 'glass']),
    _Rule('Accessories', '8471', 1800, ['mouse', 'keyboard', 'webcam', 'router', 'usb hub', 'cooling pad']),
    _Rule('Accessories', '8517', 1800, ['smartwatch', 'smart watch', 'watch', 'band']),
    _Rule('Tablet', '8471', 1800, ['ipad', 'tablet', ' tab ', 'galaxy tab', 'pad ']),
    _Rule('Laptop', '8471', 1800, ['macbook', 'laptop', 'notebook', 'thinkpad', 'ideapad', 'yoga', 'vivobook', 'zenbook', 'rog', 'tuf', 'inspiron', 'vostro', 'latitude', 'xps', 'pavilion', 'victus', 'omen', 'envy', 'elitebook', 'probook', 'aspire', 'nitro', 'predator', 'swift', 'legion', 'chromebook', 'surface']),
    _Rule('Desktop / PC', '8471', 1800, ['desktop', 'imac', 'mac mini', 'cpu', 'pc ', 'gaming pc', 'all in one', 'aio', 'monitor', 'workstation']),
    _Rule('Mobile', '8517', 1800, ['iphone', 'galaxy', 'redmi', 'poco', 'pixel', 'oneplus', 'nord', 'vivo', 'oppo', 'realme', 'narzo', 'iqoo', 'motorola', 'moto', 'nokia', 'infinix', 'tecno', 'itel', 'lava', 'nothing phone', 'mobile', 'smartphone', 'phone']),
    _Rule('Accessories', '8523', 1800, ['pendrive', 'pen drive', 'ssd', 'hdd', 'hard disk', 'ram stick', 'memory card', 'sd card']),
  ];

  static const _brands = {
    'Apple': ['iphone', 'macbook', 'airpods', 'ipad', 'imac', 'mac mini', 'apple', 'magsafe', 'lightning'],
    'Samsung': ['samsung', 'galaxy'],
    'Xiaomi': ['xiaomi', 'redmi', 'poco', ' mi '],
    'OnePlus': ['oneplus', 'nord'],
    'Google': ['pixel', 'google'],
    'Vivo': ['vivo', 'iqoo'],
    'Oppo': ['oppo'],
    'Realme': ['realme', 'narzo'],
    'Motorola': ['motorola', 'moto'],
    'Nokia': ['nokia'],
    'Nothing': ['nothing'],
    'Infinix': ['infinix'],
    'Tecno': ['tecno'],
    'HP': ['hp ', 'victus', 'omen', 'pavilion', 'envy', 'elitebook', 'probook'],
    'Dell': ['dell', 'inspiron', 'vostro', 'latitude', 'xps', 'alienware'],
    'Lenovo': ['lenovo', 'thinkpad', 'ideapad', 'legion', 'yoga'],
    'Asus': ['asus', 'vivobook', 'zenbook', 'rog', 'tuf'],
    'Acer': ['acer', 'aspire', 'nitro', 'predator', 'swift'],
    'MSI': ['msi'],
    'Microsoft': ['surface', 'microsoft'],
    'boAt': ['boat', 'airdopes', 'rockerz'],
    'JBL': ['jbl'],
    'Sony': ['sony'],
    'Logitech': ['logitech'],
    'Noise': ['noise'],
    'Mivi': ['mivi'],
    'Portronics': ['portronics'],
    'Ambrane': ['ambrane'],
    'SanDisk': ['sandisk'],
    'Seagate': ['seagate'],
    'WD': ['western digital', ' wd '],
    'Kingston': ['kingston'],
    'TP-Link': ['tp-link', 'tplink'],
  };

  static const _colors = [
    'Deep Purple', 'Space Black', 'Space Grey', 'Space Gray', 'Midnight', 'Starlight', 'Natural Titanium', 'Blue Titanium',
    'Black', 'White', 'Blue', 'Purple', 'Gold', 'Silver', 'Green', 'Red', 'Pink', 'Yellow', 'Grey', 'Gray', 'Graphite',
    'Titanium', 'Cream', 'Lavender', 'Mint', 'Orange', 'Bronze',
  ];

  /// Typical retail margin by category, used for the price suggestion.
  static const margins = {'Mobile': 8, 'Laptop': 10, 'Tablet': 10, 'Desktop / PC': 12, 'Accessories': 40};

  static SmartGuess analyse(String rawName) {
    final name = ' ${rawName.toLowerCase().replaceAll(RegExp(r'[()\[\],|]'), ' ')} ';
    if (name.trim().length < 2) return const SmartGuess();
    var hits = 0;

    _Rule? rule;
    for (final r in _rules) {
      if (r.words.any(name.contains)) {
        rule = r;
        hits++;
        break;
      }
    }
    String? brand;
    for (final e in _brands.entries) {
      if (e.value.any((w) => name.contains(w))) {
        brand = e.key;
        hits++;
        break;
      }
    }

    // memory: "8gb 256gb", "8/256", "16gb ram 1tb ssd"
    String? ram, storage;
    final slash = RegExp(r'\b(\d{1,2})\s*/\s*(\d{2,4})\s*(gb)?\b').firstMatch(name);
    if (slash != null) {
      ram = '${slash.group(1)}GB';
      storage = '${slash.group(2)}GB';
    } else {
      final sizes = RegExp(r'\b(\d{1,4})\s*(gb|tb)\b').allMatches(name).map((m) {
        final n = int.parse(m.group(1)!);
        return (n, m.group(2)!, m.end);
      }).toList();
      for (final s in sizes) {
        final gb = s.$2 == 'tb' ? s.$1 * 1024 : s.$1;
        final label = '${s.$1}${s.$2.toUpperCase()}';
        final tail = name.substring(s.$3, (s.$3 + 5).clamp(0, name.length));
        final isSsd = tail.contains('ssd') || tail.contains('hdd');
        if (gb <= 32 && ram == null && !isSsd) {
          ram = label;
        } else if (storage == null) {
          storage = isSsd ? '$label ${tail.contains('hdd') ? 'HDD' : 'SSD'}' : label;
        }
      }
    }
    if (ram != null || storage != null) hits++;

    String? color;
    for (final c in _colors) {
      if (name.contains(' ${c.toLowerCase()} ') || name.contains(' ${c.toLowerCase()}')) {
        color = c == 'Gray' ? 'Grey' : c;
        hits++;
        break;
      }
    }
    return SmartGuess(
      category: rule?.category,
      brand: brand,
      hsn: rule?.hsn,
      gstBp: rule?.gstBp,
      ram: ram,
      storage: storage,
      color: color,
      confidence: (hits / 4).clamp(0, 1).toDouble(),
    );
  }

  /// Suggested selling price for a cost price (paise), rounded to a "99" price.
  static int suggestPrice(int cost, String? category) {
    if (cost <= 0) return 0;
    final m = margins[category] ?? 15;
    final raw = cost * (100 + m) ~/ 100;
    final rupees = raw ~/ 100;
    final rounded = rupees < 1000 ? ((rupees + 9) ~/ 10) * 10 - 1 : ((rupees + 99) ~/ 100) * 100 - 1;
    return rounded * 100;
  }

  /// Unique SKU like GX-MOB-APL-0012.
  static Future<String> nextSku(String? category, String? brand) async {
    String code(String? s, String fallback) {
      final c = (s ?? '').toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
      return c.isEmpty ? fallback : (c.length >= 3 ? c.substring(0, 3) : c.padRight(3, 'X'));
    }

    final prefix = 'GX-${code(category, 'GEN')}-${code(brand, 'GEN')}';
    final rows = await Books.query('SELECT sku FROM products WHERE sku LIKE ?', ['$prefix-%']);
    var n = rows.length + 1;
    final used = {for (final r in rows) r['sku']};
    while (used.contains('$prefix-${n.toString().padLeft(4, '0')}')) {
      n++;
    }
    return '$prefix-${n.toString().padLeft(4, '0')}';
  }

  /// Product already using this barcode / SKU, if any.
  static Future<Rec?> findBySku(String sku, {int? exceptId}) async {
    if (sku.trim().isEmpty) return null;
    final r = await Books.query('SELECT * FROM products WHERE sku = ? AND id != ?', [sku.trim(), exceptId ?? -1]);
    return r.isEmpty ? null : r.first;
  }

  /// "₹12,499" style helper for suggestions.
  static String rs(int paise) => Money.rs(paise);
}
