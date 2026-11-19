/// Quick work — the engines behind smart search, voice billing and the
/// purchase-bill photo scan. Pure Dart, offline, unit-tested.
library;

import 'books.dart';
import 'imei_smart.dart';

// ============================================================================
// Smart search
// ============================================================================

/// Product search that understands how a shop types: "vivo 8 128 blue",
/// "redmi note13", "iphne 15" (typos), SKU and IMEI-style codes.
class SmartSearch {
  static const _units = {'gb', 'tb', 'ram', 'rom', 'pcs', 'pc', 'piece', 'pieces'};

  /// Lower-case words; "8/128", "8gb+128gb", "note13" become separate words.
  static List<String> words(String s) {
    var t = s.toLowerCase();
    t = t.replaceAllMapped(RegExp(r'(\d)\s*(gb|tb)\b'), (m) => '${m[1]} ');
    t = t.replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}');
    return t
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty && !_units.contains(w))
        .toList();
  }

  /// Edit distance (with swaps), stopping early above [max].
  static int distance(String a, String b, {int max = 2}) {
    if ((a.length - b.length).abs() > max) return max + 1;
    final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      var best = max + 1;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].reduce((x, y) => x < y ? x : y);
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          v = v < d[i - 2][j - 2] + 1 ? v : d[i - 2][j - 2] + 1;
        }
        d[i][j] = v;
        if (v < best) best = v;
      }
      if (best > max) return max + 1;
    }
    return d[a.length][b.length];
  }

  /// How well one typed word matches one product word (0 = no match).
  static double wordScore(String q, String w) {
    if (q == w) return 1;
    final isNum = RegExp(r'^\d+$').hasMatch(q);
    if (isNum) return 0; // numbers must match exactly (8 ≠ 128)
    if (w.startsWith(q)) return q.length >= 2 ? 0.85 : 0.5;
    if (q.length >= 4) {
      final allowed = q.length >= 7 ? 2 : 1;
      final dist = distance(q, w.length > q.length + 2 ? w.substring(0, q.length + 1) : w, max: allowed);
      if (dist <= allowed) return 0.7 - 0.1 * dist;
    }
    if (q.length >= 3 && w.contains(q)) return 0.5;
    return 0;
  }

  /// Text a product is searched by.
  static String haystack(Rec p) =>
      [p['name'], p['brand'], p['variant'], p['category'], p['sku']].where((v) => v != null && '$v'.isNotEmpty).join(' ');

  /// 0..1 — every typed word has to be found somewhere for a good score.
  static double score(String query, Rec p) {
    final q = words(query);
    if (q.isEmpty) return 0;
    final sku = '${p['sku'] ?? ''}'.toLowerCase();
    final raw = query.trim().toLowerCase();
    if (sku.isNotEmpty && sku == raw) return 2;
    final hay = words(haystack(p));
    if (hay.isEmpty) return 0;
    var total = 0.0;
    for (final w in q) {
      var best = 0.0;
      for (final h in hay) {
        final s = wordScore(w, h);
        if (s > best) best = s;
        if (best == 1) break;
      }
      if (best == 0) return 0; // a word that is nowhere = not this product
      total += best;
    }
    var s = total / q.length;
    // the name itself starting with the query ranks first
    final name = '${p['name'] ?? ''}'.toLowerCase();
    if (name.startsWith(raw)) s += 0.15;
    if (asInt(p['stock']) > 0) s += 0.02;
    return s;
  }

  /// Best matches first.
  static List<Rec> rank(Iterable<Rec> products, String query, {int limit = 8}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final scored = <(double, Rec)>[];
    for (final p in products) {
      final s = score(q, p);
      if (s > 0.45) scored.add((s, p));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final x in scored.take(limit)) x.$2];
  }
}

// ============================================================================
// Voice billing
// ============================================================================

class VoiceLine {
  final Rec product;
  final int qty;
  final int? rate; // paise per unit, as spoken (incl. GST); null = list price
  const VoiceLine(this.product, this.qty, this.rate);
}

class VoiceOrder {
  final List<VoiceLine> lines;
  final Rec? customer;
  final String? pay; // cash | upi | card | due
  final List<String> unknown; // parts that matched no product
  const VoiceOrder(this.lines, this.customer, this.pay, this.unknown);
  bool get isEmpty => lines.isEmpty;
}

/// Turns a spoken sentence into a bill:
/// "Vivo T3 ekta 18 hajar Rahim cash", "2 cover 299 and 1 charger 499 upi",
/// "iphone 15 one piece 65000 customer Ankit baki".
class VoiceBill {
  static const _qtyWords = {
    'one': 1, 'ek': 1, 'ekta': 1, 'ekti': 1, 'single': 1, 'a': 1, 'ak': 1, 'akta': 1,
    'two': 2, 'dui': 2, 'duita': 2, 'duto': 2, 'do': 2, 'dho': 2,
    'three': 3, 'tin': 3, 'tinta': 3, 'teen': 3,
    'four': 4, 'char': 4, 'charta': 4, 'chaar': 4,
    'five': 5, 'panch': 5, 'pach': 5, 'pachta': 5, 'paanch': 5,
    'six': 6, 'choy': 6, 'chhoy': 6, 'chhe': 6,
    'seven': 7, 'saat': 7, 'sat': 7,
    'eight': 8, 'aat': 8, 'aath': 8,
    'nine': 9, 'noy': 9, 'nau': 9,
    'ten': 10, 'dosh': 10, 'das': 10,
  };
  static const _pay = {
    'cash': 'cash', 'nagad': 'cash', 'nogod': 'cash', 'naqad': 'cash',
    'upi': 'upi', 'gpay': 'upi', 'phonepe': 'upi', 'paytm': 'upi', 'online': 'upi', 'google': 'upi',
    'card': 'card', 'debit': 'card', 'credit card': 'card',
    'baki': 'due', 'bakee': 'due', 'due': 'due', 'udhar': 'due', 'udhaar': 'due', 'credit': 'due', 'khata': 'due',
  };
  static const _filler = {
    'ta', 'ti', 'to', 'te', 'pcs', 'piece', 'pieces', 'unit', 'units', 'qty', 'quantity', 'nos', 'no',
    'rupees', 'rupee', 'rs', 'taka', 'tk', 'inr', 'price', 'rate', 'dam', 'at', 'for', 'er', 'ke', 'customer',
    'name', 'naam', 'diye', 'dilam', 'bill', 'koro', 'kore', 'sell', 'sale', 'becho', 'bikri', 'payment', 'pay', 'in', 'by',
  };

  /// Bengali / Devanagari digits → ASCII; "18 hajar" → 18000; "1.5 lakh" → 150000.
  static String normalise(String s) {
    var t = s.toLowerCase();
    const bn = '০১২৩৪৫৬৭৮৯', hi = '०१२३४५६७८९';
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(bn[i], '$i').replaceAll(hi[i], '$i');
    }
    t = t.replaceAll('₹', ' ');
    for (var k = 0; k < 3; k++) {
      t = t.replaceAllMapped(RegExp(r'(\d),(\d{2,3})(?!\d)'), (m) => '${m[1]}${m[2]}');
    }
    num mult(String w) => switch (w) {
          'k' || 'hajar' || 'hazar' || 'hazaar' || 'thousand' || 'hajaar' || 'haja' => 1000,
          'lakh' || 'lac' || 'lakhs' || 'lacs' => 100000,
          'sho' || 'hundred' || 'sau' || 'so' => 100,
          _ => 0,
        };
    t = t.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*(k|hajar|hazar|hazaar|hajaar|haja|thousand|lakh|lakhs|lac|lacs|sho|hundred|sau)\b'), (m) {
      final v = double.parse(m.group(1)!) * mult(m.group(2)!);
      return ' ${v.round()} ';
    });
    // "18 hajar 500" was made "18000 500" → join
    t = t.replaceAllMapped(RegExp(r'\b(\d+000)\s+(\d{1,3})\b(?!\s*(?:ta|ti|pcs|piece))'), (m) => '${int.parse(m.group(1)!) + int.parse(m.group(2)!)}');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static VoiceOrder parse(String spoken, List<Rec> products, List<Rec> customers) {
    var text = normalise(spoken);
    // payment
    String? pay;
    for (final e in _pay.entries) {
      if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(text)) {
        pay = e.value;
        text = text.replaceAll(RegExp('\\b${RegExp.escape(e.key)}\\b'), ' ');
        break;
      }
    }
    // customer: the best customer name found in the sentence
    Rec? customer;
    var bestC = 0.0;
    final said = SmartSearch.words(text);
    for (final c in customers) {
      final name = SmartSearch.words('${c['name'] ?? ''}');
      if (name.isEmpty) continue;
      var hit = 0.0;
      for (final n in name) {
        var b = 0.0;
        for (final w in said) {
          if (RegExp(r'^\d+$').hasMatch(w)) continue;
          final s = n == w ? 1.0 : (n.length >= 4 && SmartSearch.distance(n, w, max: 1) <= 1 ? 0.8 : 0.0);
          if (s > b) b = s;
        }
        hit += b;
      }
      // the first name alone is enough ("Rahim" for "Rahim Sheikh")
      final s = hit / name.length + (hit >= 1 ? 0.5 : 0);
      if (hit >= 0.8 && s > bestC) {
        bestC = s;
        customer = c;
      }
    }
    if (customer != null) {
      for (final n in SmartSearch.words('${customer['name']}')) {
        text = text.replaceAll(RegExp('\\b${RegExp.escape(n)}\\b'), ' ');
      }
    }
    // items: split on "and", "ar", "aur", "plus", ","
    final parts = text.split(RegExp(r'\s*(?:,|;|\band\b|\bar\b|\baur\b|\bplus\b|\bsathe\b|\bsange\b|\bwith\b)\s*'));
    final lines = <VoiceLine>[];
    final unknown = <String>[];
    for (final raw in parts) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      int? qty;
      int? rate;
      final rest = <String>[];
      final tokens = part.split(' ');
      for (var i = 0; i < tokens.length; i++) {
        final w = tokens[i];
        if (_qtyWords.containsKey(w) && qty == null && w != 'a' && w != 'do') {
          qty = _qtyWords[w];
          continue;
        }
        if ((w == 'a' || w == 'do') && qty == null && i + 1 < tokens.length && !RegExp(r'^\d').hasMatch(tokens[i + 1])) {
          qty = _qtyWords[w];
          continue;
        }
        final n = RegExp(r'^\d+(?:\.\d+)?$').hasMatch(w) ? double.parse(w) : null;
        if (n != null) {
          final next = i + 1 < tokens.length ? tokens[i + 1] : '';
          final isQty = ['ta', 'ti', 'pcs', 'piece', 'pieces', 'unit', 'units', 'nos', 'x'].contains(next) ||
              (i > 0 && ['qty', 'quantity', 'x'].contains(tokens[i - 1]));
          if (isQty && n <= 999 && qty == null) {
            qty = n.round();
          } else if (n >= 10 && rate == null && !_numberInAName(w, tokens, i, products)) {
            rate = (n * 100).round();
          } else {
            rest.add(w); // model numbers: "t3", "15", "13c"
          }
          continue;
        }
        if (_filler.contains(w)) continue;
        rest.add(w);
      }
      final query = rest.join(' ').trim();
      if (query.isEmpty) continue;
      final hits = SmartSearch.rank(products, query, limit: 1);
      if (hits.isEmpty) {
        unknown.add(query);
        continue;
      }
      lines.add(VoiceLine(hits.first, qty ?? 1, rate));
    }
    return VoiceOrder(lines, customer, pay, unknown);
  }

  /// "15" in "iphone 15 65000" is part of the model, not a price.
  static bool _numberInAName(String n, List<String> tokens, int i, List<Rec> products) {
    if (i == 0) return false;
    final before = tokens.sublist(0, i).where((w) => !RegExp(r'^\d').hasMatch(w)).join(' ');
    if (before.isEmpty) return false;
    final withNum = SmartSearch.rank(products, '$before $n', limit: 1);
    if (withNum.isEmpty) return false;
    return SmartSearch.words(SmartSearch.haystack(withNum.first)).contains(n) && int.parse(n.split('.').first) < 10000;
  }
}

// ============================================================================
// Purchase bill photo
// ============================================================================

class ScannedLine {
  final Rec product;
  final int qty;
  final int? rate; // paise per unit
  final List<String> serials;
  ScannedLine(this.product, this.qty, this.rate, this.serials);
}

class BillScanResult {
  final List<ScannedLine> lines;
  final List<String> imeis; // every valid IMEI found
  final List<String> unmatched; // IMEIs whose product is not known
  final String? billNo;
  const BillScanResult(this.lines, this.imeis, this.unmatched, this.billNo);
}

/// Reads the text of a supplier's bill (from the camera's text recognition)
/// and turns it into purchase lines: products, quantities, rates and IMEIs.
class BillScan {
  static final _imei = RegExp(r'(?<!\d)(\d[\d \-]{13,20}\d)(?!\d)');

  /// Valid 15-digit IMEIs in the text (spaces / dashes inside are allowed).
  static List<String> imeis(String text) {
    final out = <String>[];
    for (final line in text.split('\n')) {
      // numbers split by spaces count only on an IMEI / serial line (a phone
      // number like "98300 11111 98300 22222" is not an IMEI)
      final labelled = RegExp(r'imei|serial|s\.?\s?no|sl\.?\s?no|\bsn\b', caseSensitive: false).hasMatch(line);
      _imeisIn(line, labelled, out);
    }
    return out;
  }

  static void _imeisIn(String line, bool labelled, List<String> out) {
    for (final m in _imei.allMatches(line)) {
      final raw = m.group(1)!;
      if (!labelled && RegExp(r'[\s\-]').hasMatch(raw)) {
        for (final w in RegExp(r'(?<!\d)\d{15}(?!\d)').allMatches(raw)) {
          final c = w.group(0)!;
          if (SmartImei.luhn(c) && !out.contains(c)) out.add(c);
        }
        continue;
      }
      final d = raw.replaceAll(RegExp(r'\D'), '');
      // a run of digits may hold two IMEIs printed side by side
      for (var i = 0; i + 15 <= d.length; i += 15) {
        final c = d.substring(i, i + 15);
        if (SmartImei.luhn(c) && !out.contains(c)) out.add(c);
      }
    }
  }

  static String? billNo(String text) {
    final m = RegExp(r'(?:invoice|bill|inv)\s*(?:no|number|#)?\.?\s*[:\-]?\s*([A-Z0-9][A-Z0-9/\-]{2,20})', caseSensitive: false).firstMatch(text);
    return m?.group(1);
  }

  /// [imeiProduct] finds the product of an IMEI from its model (Smart IMEI).
  static Future<BillScanResult> parse(String text, List<Rec> products, {Future<Rec?> Function(String imei)? imeiProduct}) async {
    final found = imeis(text);
    final rows = <int, ScannedLine>{}; // product id → line
    final order = <int>[];
    Rec? lastProduct;
    final byImeiLine = <String, Rec?>{};
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lineImeis = imeis(line);
      final words = line.replaceAll(RegExp(r'(?<!\d)\d{12,}(?!\d)'), ' ');
      final letters = words.replaceAll(RegExp(r'[^A-Za-z]'), '');
      Rec? p;
      if (letters.length >= 3) {
        final hits = SmartSearch.rank(products, _nameOnly(words), limit: 1);
        if (hits.isNotEmpty && SmartSearch.score(_nameOnly(words), hits.first) >= 0.7) p = hits.first;
      }
      if (p != null) {
        lastProduct = p;
        final id = asInt(p['id']);
        // storage (8/128, 128GB) and the model's own numbers are not qty / price
        final own = SmartSearch.words(SmartSearch.haystack(p)).toSet();
        final plain = words
            .replaceAll(RegExp(r'\d+\s*/\s*\d+(\s*(gb|tb))?', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\d+\s*(gb|tb)\b', caseSensitive: false), ' ');
        final nums = [
          for (final m in RegExp(r'(?<![\dA-Za-z])(\d{1,3}(?:,\d{2,3})+|\d+)(?:\.(\d{1,2}))?(?![\dA-Za-z])').allMatches(plain))
            if (!(m.group(2) == null && own.contains(m.group(1)) && int.parse(m.group(1)!.replaceAll(',', '')) < 100 && _isModelNumber(m.group(1)!, plain, m.start)))
              double.parse('${m.group(1)!.replaceAll(',', '')}.${m.group(2) ?? '0'}')
        ];
        // qty = a small whole number; rate = the price-looking number (the
        // amount column is qty × rate, so prefer the smaller of the two)
        int? qty;
        int? rate;
        final small = nums.where((n) => n >= 1 && n <= 500 && n == n.roundToDouble()).toList();
        final money = nums.where((n) => n >= 10).toList()..sort();
        if (small.isNotEmpty) qty = small.first.round();
        if (money.isNotEmpty) {
          final q = qty ?? 1;
          rate = money.length >= 2 && (money.last - money[money.length - 2] * q).abs() < 1 && q > 1
              ? (money[money.length - 2] * 100).round()
              : (money.last / (q > 1 && money.length == 1 ? q : 1) * 100).round();
          if (money.length >= 2 && q > 1 && (money.last - money.first * q).abs() < 1) rate = (money.first * 100).round();
        }
        final cur = rows[id];
        if (cur == null) {
          rows[id] = ScannedLine(p, qty ?? 1, rate, []);
          order.add(id);
        } else {
          rows[id] = ScannedLine(p, cur.qty + (qty ?? 1), cur.rate ?? rate, cur.serials);
        }
      }
      for (final i in lineImeis) {
        byImeiLine[i] = p ?? lastProduct;
      }
    }
    // IMEIs → their product: the model (TAC) first, then the product line above
    final unmatched = <String>[];
    for (final i in found) {
      Rec? p = imeiProduct == null ? null : await imeiProduct(i);
      if (p != null) p = products.where((x) => asInt(x['id']) == asInt(p!['id'])).firstOrNull ?? p;
      p ??= byImeiLine[i];
      if (p == null) {
        unmatched.add(i);
        continue;
      }
      final id = asInt(p['id']);
      final cur = rows[id];
      if (cur == null) {
        rows[id] = ScannedLine(p, 0, null, [i]);
        order.add(id);
      } else {
        cur.serials.add(i);
      }
    }
    final lines = <ScannedLine>[];
    for (final id in order) {
      final l = rows[id]!;
      final qty = l.qty < l.serials.length ? l.serials.length : (l.qty == 0 ? 1 : l.qty);
      lines.add(ScannedLine(l.product, qty, l.rate, l.serials));
    }
    return BillScanResult(lines, found, unmatched, billNo(text));
  }

  /// A number right after the model name ("iPhone 15 1 65000": 15).
  static bool _isModelNumber(String n, String line, int at) {
    final before = line.substring(0, at).trimRight();
    return before.isNotEmpty && RegExp(r'[A-Za-z]$').hasMatch(before);
  }

  static String _nameOnly(String line) => line
      .replaceAll(RegExp(r'(?<![A-Za-z])\d+(?:[.,]\d+)*(?![A-Za-z/])'), ' ')
      .replaceAll(RegExp(r'\b(hsn|sac|gst|igst|cgst|sgst|qty|rate|amount|amt|nos|pcs|rs|inr|total)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
