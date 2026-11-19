/// AI Brain — business intelligence that runs on the phone:
/// margin guard, mistake / theft flags, customer credit score, sales
/// forecast (with festival seasons) and "Ask Hisab AI" questions in plain
/// English or Banglish ("gato mash-e Vivo-te koto labh?").
library;

import 'dart:convert';
import 'dart:math' as math;

import 'autopilot.dart';
import 'books.dart';
import 'money.dart';
import 'quick.dart';

// ============================================================================
// Margin guard
// ============================================================================

class MarginIssue {
  final String name;
  final int price, cost; // per unit, before GST (paise)
  const MarginIssue(this.name, this.price, this.cost);
  bool get loss => price < cost;
  double get marginPct => price == 0 ? -100 : (price - cost) * 100 / price;
}

// ============================================================================
// Flags
// ============================================================================

class Flag {
  final String level; // high | medium
  final String kind; // imei_not_bought | imei_twice | negative_stock | below_cost | big_discount
  final String title, detail;
  final String? target; // sale | product | purchase
  final int? targetId;
  const Flag(this.level, this.kind, this.title, this.detail, {this.target, this.targetId});
}

// ============================================================================
// Customer score
// ============================================================================

class CustomerScore {
  final int score; // 0..100
  final int due, daysLate, bills, firmReminders;
  final int bought; // lifetime purchase value
  const CustomerScore(this.score, this.due, this.daysLate, this.bills, this.firmReminders, this.bought);
  String get label => score >= 80
      ? 'Excellent'
      : score >= 60
          ? 'Good'
          : score >= 40
              ? 'Careful'
              : 'Risky';
  String get advice => score >= 80
      ? 'Pays on time — credit is safe'
      : score >= 60
          ? 'Usually pays — keep credit small'
          : score >= 40
              ? 'Slow payer — take an advance before credit'
              : 'High risk — cash only until the dues are cleared';
}

// ============================================================================
// Forecast
// ============================================================================

class BrandTrend {
  final String brand;
  final int units30, unitsPrev; // last 30 days, the 30 before
  final int forecast; // units next 30 days
  const BrandTrend(this.brand, this.units30, this.unitsPrev, this.forecast);
  int get changePct => unitsPrev == 0 ? (units30 > 0 ? 100 : 0) : ((units30 - unitsPrev) * 100 / unitsPrev).round();
}

class Forecast {
  final String month; // yyyy-mm being forecast
  final int sales, low, high; // paise
  final int lastMonth, sameMonthLastYear;
  final double season; // festival multiplier used
  final String? festival;
  final List<BrandTrend> brands;
  final List<(String, int)> history; // month label → sales
  const Forecast(this.month, this.sales, this.low, this.high, this.lastMonth, this.sameMonthLastYear, this.season, this.festival,
      this.brands, this.history);
}

// ============================================================================
// Ask
// ============================================================================

class Answer {
  final String text;
  final String? detail;
  final List<(String, String)> rows; // label → value
  const Answer(this.text, {this.detail, this.rows = const []});
}

class Brain {
  // ---------------------------------------------------------------- margin guard
  /// Lines selling below cost, or under [minPct] % margin.
  static List<MarginIssue> marginCheck(Iterable<(Rec product, int rate)> lines, {double minPct = 3}) {
    final out = <MarginIssue>[];
    for (final (p, rate) in lines) {
      final cost = asInt(p['cost']);
      if (cost <= 0) continue;
      final m = MarginIssue('${p['name']}', rate, cost);
      if (m.loss || m.marginPct < minPct) out.add(m);
    }
    return out;
  }

  // ---------------------------------------------------------------- flags
  static Future<List<Flag>> flags({DateTime? now, int days = 60}) async {
    final t0 = now ?? DateTime.now();
    final since = ymd(t0.subtract(Duration(days: days)));
    final out = <Flag>[];

    // IMEI sold that was never bought
    for (final r in await Books.query(
        'SELECT i.serial, i.name, s.id, s.number, s.date FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        "WHERE s.date >= ? AND length(TRIM(IFNULL(i.serial, ''))) >= 8 "
        'AND NOT EXISTS (SELECT 1 FROM purchase_items p WHERE TRIM(p.serial) = TRIM(i.serial))',
        [since])) {
      out.add(Flag('high', 'imei_not_bought', 'IMEI ${r['serial']} sold but never purchased',
          '${r['name']} · ${r['number']} · ${prettyDate('${r['date']}')} — enter the purchase or check the number',
          target: 'sale', targetId: asInt(r['id'])));
    }
    // the same IMEI sold twice (without a return)
    for (final r in await Books.query(
        'SELECT TRIM(i.serial) AS serial, COUNT(*) AS n, MAX(i.sale_id) AS sid, MAX(i.name) AS name FROM sale_items i '
        "WHERE length(TRIM(IFNULL(i.serial, ''))) >= 8 AND NOT EXISTS (SELECT 1 FROM sale_return_items r WHERE r.sale_item_id = i.id) "
        'GROUP BY TRIM(i.serial) HAVING COUNT(*) > 1')) {
      out.add(Flag('high', 'imei_twice', 'IMEI ${r['serial']} sold ${r['n']} times', '${r['name']} — one device can be sold only once',
          target: 'sale', targetId: asInt(r['sid'])));
    }
    // the same IMEI bought twice
    for (final r in await Books.query(
        'SELECT TRIM(serial) AS serial, COUNT(*) AS n, MAX(purchase_id) AS pid, MAX(name) AS name FROM purchase_items '
        "WHERE length(TRIM(IFNULL(serial, ''))) >= 8 GROUP BY TRIM(serial) HAVING COUNT(*) > 1")) {
      final sold = asInt((await Books.query('SELECT COUNT(*) AS c FROM sale_items WHERE TRIM(serial) = ?', [r['serial']])).first['c']);
      if (sold >= asInt(r['n']) - 1) continue; // bought back after a sale (exchange) is fine
      out.add(Flag('medium', 'imei_twice', 'IMEI ${r['serial']} purchased ${r['n']} times', '${r['name']} — check for a double entry',
          target: 'purchase', targetId: asInt(r['pid'])));
    }
    // negative stock
    for (final p in await Books.query('SELECT id, name, stock FROM products WHERE stock < 0')) {
      out.add(Flag('high', 'negative_stock', '${p['name']}: stock ${p['stock']}',
          'More sold than bought — a purchase is missing or the count is wrong', target: 'product', targetId: asInt(p['id'])));
    }
    // sold below cost
    for (final r in await Books.query(
        'SELECT s.id, s.number, s.date, i.name, i.rate, i.unit_cost FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'WHERE s.date >= ? AND i.unit_cost > 0 AND i.rate < i.unit_cost ORDER BY (i.unit_cost - i.rate) * i.qty DESC LIMIT 15',
        [since])) {
      out.add(Flag('medium', 'below_cost', '${r['name']} sold at a loss',
          '${r['number']} · sold ${Money.rs(asInt(r['rate']))}, cost ${Money.rs(asInt(r['unit_cost']))}',
          target: 'sale', targetId: asInt(r['id'])));
    }
    // big discounts
    for (final r in await Books.query(
        'SELECT id, number, date, discount, subtotal FROM sales WHERE date >= ? AND discount > 0 AND subtotal > 0 '
        'AND discount * 100 > subtotal * 15 ORDER BY discount DESC LIMIT 10',
        [since])) {
      final pct = (asInt(r['discount']) * 100 / asInt(r['subtotal'])).round();
      out.add(Flag('medium', 'big_discount', '$pct% discount on ${r['number']}',
          '${Money.rs(asInt(r['discount']))} off · ${prettyDate('${r['date']}')} — was it approved?',
          target: 'sale', targetId: asInt(r['id'])));
    }
    out.sort((a, b) => a.level == b.level ? 0 : (a.level == 'high' ? -1 : 1));
    return out;
  }

  // ---------------------------------------------------------------- customer score
  static Future<CustomerScore> customerScore(int id, {DateTime? now}) async {
    final t0 = now ?? DateTime.now();
    final due = (await Books.partyBalances('customer'))[id] ?? 0;
    final r = (await Books.query('SELECT COUNT(*) AS n, IFNULL(SUM(total), 0) AS v FROM sales WHERE customer_id = ?', [id])).first;
    final bills = asInt(r['n']), bought = asInt(r['v']);
    var late = 0;
    if (due > 0) {
      final since = await Autopilot.oldestUnpaid(id, due);
      if (since != null) late = t0.difference(DateTime.parse(since)).inDays;
    }
    final sent = await Autopilot.sent();
    final firm = sent.keys.where((k) => k.startsWith('due:$id:') && (k.endsWith(':3') || k.endsWith(':2'))).length;
    var s = 85.0;
    if (due > 0) {
      s -= math.min(late, 60) * 0.9; // every late day costs
      final avg = bills == 0 ? due : bought / bills;
      s -= math.min(due / math.max(avg, 1), 3) * 6; // owes several bills' worth
    }
    s -= firm * 6;
    s += math.min(bills, 15); // loyalty
    if (bills == 0) s = 60; // new customer: neutral
    return CustomerScore(s.round().clamp(0, 100), due, late, bills, firm, bought);
  }

  /// Scores of every customer with history, worst first.
  static Future<List<(Rec, CustomerScore)>> customerScores() async {
    final out = <(Rec, CustomerScore)>[];
    for (final c in await Books.query('SELECT c.* FROM customers c WHERE EXISTS (SELECT 1 FROM sales s WHERE s.customer_id = c.id)')) {
      out.add((c, await customerScore(asInt(c['id']))));
    }
    out.sort((a, b) => a.$2.score.compareTo(b.$2.score));
    return out;
  }

  // ---------------------------------------------------------------- forecast
  /// Indian retail seasons: Diwali / Durga Puja (Oct–Nov), Eid / new
  /// financial year (Apr), wedding season (Dec, Feb), monsoon slow (Jul).
  static const seasons = {
    1: (1.0, null),
    2: (1.05, 'Wedding season'),
    3: (1.0, null),
    4: (1.08, 'Eid & Poila Baishakh'),
    5: (1.0, null),
    6: (0.97, null),
    7: (0.93, 'Monsoon (slower)'),
    8: (1.0, 'Independence Day sales'),
    9: (1.05, 'Ganesh Chaturthi'),
    10: (1.25, 'Durga Puja & Navratri'),
    11: (1.2, 'Diwali'),
    12: (1.08, 'Christmas & weddings'),
  };

  static Future<Forecast> forecast({DateTime? now}) async {
    final t0 = now ?? DateTime.now();
    final next = DateTime(t0.year, t0.month + 1, 1);
    Future<int> month(DateTime m) async {
      final e = DateTime(m.year, m.month + 1, 0);
      return asInt((await Books.query('SELECT IFNULL(SUM(total), 0) AS v FROM sales WHERE date BETWEEN ? AND ?', [ymd(m), ymd(e)])).first['v']);
    }

    // last 6 full months + this month so far (scaled to a full month)
    final hist = <(String, int)>[];
    final vals = <double>[];
    for (var i = 6; i >= 1; i--) {
      final m = DateTime(t0.year, t0.month - i, 1);
      final v = await month(m);
      hist.add((monthName(m.month), v));
      vals.add(v / (seasons[m.month]!.$1)); // de-seasonalised
    }
    final cur = await month(DateTime(t0.year, t0.month, 1));
    final daysIn = DateTime(t0.year, t0.month + 1, 0).day;
    final curFull = t0.day >= 7 ? cur * daysIn / t0.day : null;
    hist.add(('${monthName(t0.month)}*', cur));
    if (curFull != null) vals.add(curFull / seasons[t0.month]!.$1);

    // weighted trend: recent months count more; ignore empty months at the start
    final data = <double>[];
    var started = false;
    for (final v in vals) {
      if (v > 0) started = true;
      if (started) data.add(v);
    }
    double base;
    if (data.isEmpty) {
      base = 0;
    } else if (data.length < 3) {
      base = data.reduce((a, b) => a + b) / data.length;
    } else {
      // least squares on the last points, then one step ahead
      final n = data.length;
      final xs = List.generate(n, (i) => i.toDouble());
      final mx = xs.reduce((a, b) => a + b) / n, my = data.reduce((a, b) => a + b) / n;
      var num = 0.0, den = 0.0;
      for (var i = 0; i < n; i++) {
        num += (xs[i] - mx) * (data[i] - my);
        den += (xs[i] - mx) * (xs[i] - mx);
      }
      final slope = den == 0 ? 0 : num / den;
      final trend = my + slope * (n - mx);
      final wavg = [for (var i = 0; i < n; i++) data[i] * (i + 1)].reduce((a, b) => a + b) / (n * (n + 1) / 2);
      base = math.max(0, (trend + wavg) / 2);
    }
    final (mult, fest) = seasons[next.month]!;
    final lastYear = await month(DateTime(next.year - 1, next.month, 1));
    var sales = base * mult;
    if (lastYear > 0 && base > 0) {
      // the shop's own last-year pattern, if any, counts for a third
      final ly = lastYear.toDouble() * (vals.isEmpty ? 1 : 1);
      sales = sales * 2 / 3 + ly / 3;
    }
    // spread: how much the months jump around
    final spread = data.length < 2 ? 0.25 : math.min(0.4, _cv(data));
    final s = sales.round();

    // brands: last 30 days vs the 30 before, projected
    final d30 = ymd(t0.subtract(const Duration(days: 30))), d60 = ymd(t0.subtract(const Duration(days: 60)));
    final rows = await Books.query(
        "SELECT IFNULL(NULLIF(TRIM(p.brand), ''), 'Other') AS brand, "
        'SUM(CASE WHEN s.date >= ? THEN i.qty ELSE 0 END) AS a, SUM(CASE WHEN s.date < ? THEN i.qty ELSE 0 END) AS b '
        'FROM sale_items i JOIN sales s ON s.id = i.sale_id JOIN products p ON p.id = i.product_id WHERE s.date >= ? '
        'GROUP BY 1 ORDER BY a DESC LIMIT 8',
        [d30, d30, d60]);
    final brands = [
      for (final r in rows)
        BrandTrend('${r['brand']}', asInt(r['a']), asInt(r['b']),
            (((asInt(r['a']) * 2 + asInt(r['b'])) / 3) * mult).round()),
    ];
    return Forecast('${next.year}-${next.month.toString().padLeft(2, '0')}', s, (s * (1 - spread)).round(), (s * (1 + spread)).round(),
        hist.length >= 2 ? hist[hist.length - 2].$2 : 0, lastYear, mult, fest, brands, hist);
  }

  static double _cv(List<double> v) {
    final m = v.reduce((a, b) => a + b) / v.length;
    if (m == 0) return 0.25;
    final sd = math.sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length);
    return sd / m;
  }

  // ---------------------------------------------------------------- ask
  static const examples = [
    'Today\'s sale',
    'Last month profit',
    'Gato mash-e Vivo-te koto labh?',
    'Best seller this month',
    'Who owes me the most?',
    'Stock of iPhone',
    'This week expenses',
    'Purchases last 30 days',
  ];

  /// (from, to, label) for the time words in [q].
  static (String, String, String) period(String q, DateTime t0) {
    String d(DateTime x) => ymd(x);
    final today = DateTime(t0.year, t0.month, t0.day);
    final n = RegExp(r'(?:last|past|gato|sesh)\s+(\d{1,3})\s*(?:days?|din)').firstMatch(q);
    if (n != null) {
      final k = int.parse(n.group(1)!);
      return (d(today.subtract(Duration(days: k - 1))), d(today), 'last $k days');
    }
    bool has(List<String> w) => w.any((x) => RegExp('(^|\\W)$x(\\W|\$)').hasMatch(q));
    if (has(['yesterday', 'kal', 'gotokal', 'gatokal'])) {
      final y = today.subtract(const Duration(days: 1));
      return (d(y), d(y), 'yesterday');
    }
    if (has(['last week', 'gato soptaho', 'gato week', 'previous week'])) {
      final s = today.subtract(Duration(days: today.weekday + 6));
      return (d(s), d(s.add(const Duration(days: 6))), 'last week');
    }
    if (has(['this week', 'ei soptaho', 'ei week', 'week'])) {
      final s = today.subtract(Duration(days: today.weekday - 1));
      return (d(s), d(today), 'this week');
    }
    if (has(['last month', 'gato mash', 'gato mas', 'gotomash', 'previous month', 'agের mash', 'ager mash'])) {
      final s = DateTime(t0.year, t0.month - 1, 1);
      return (d(s), d(DateTime(t0.year, t0.month, 0)), monthName(s.month));
    }
    if (has(['last year', 'gato bochor', 'previous year'])) {
      return ('${t0.year - 1}-01-01', '${t0.year - 1}-12-31', '${t0.year - 1}');
    }
    if (has(['this year', 'ei bochor', 'year', 'bochor'])) return ('${t0.year}-01-01', d(today), '${t0.year}');
    if (has(['this month', 'ei mash', 'month', 'mash', 'mas'])) return (d(DateTime(t0.year, t0.month, 1)), d(today), 'this month');
    if (has(['all time', 'total', 'ekhon porjonto', 'sob'])) return ('2000-01-01', d(today), 'all time');
    return (d(today), d(today), 'today');
  }

  static Future<Answer> ask(String question, {DateTime? now}) async {
    final t0 = now ?? DateTime.now();
    final q = ' ${question.toLowerCase().replaceAll(RegExp(r'[?!.,]'), ' ').replaceAll('-e ', ' ').replaceAll('-te ', ' ')} '
        .replaceAll(RegExp(r'\s+'), ' ');
    bool has(List<String> w) => w.any((x) => q.contains(' $x ') || q.contains(' $x') && x.length > 4);
    final (from, to, label) = period(q, t0);

    // what the question is about: a brand, product, category or customer
    final products = await Books.query('SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id');
    String? brand, category;
    Rec? product;
    final words = SmartSearch.words(q).where((w) => w.length >= 3 && !_stop.contains(w)).toList();
    final brands = {for (final p in products) if ('${p['brand'] ?? ''}'.trim().isNotEmpty) '${p['brand']}'.trim().toLowerCase(): '${p['brand']}'.trim()};
    for (final w in words) {
      if (brands.containsKey(w)) brand = brands[w];
    }
    final cats = {for (final p in products) if ('${p['category'] ?? ''}'.trim().isNotEmpty) '${p['category']}'.toLowerCase(): '${p['category']}'};
    for (final w in words) {
      for (final c in cats.entries) {
        if (c.key.startsWith(w) || w.startsWith(c.key)) category = c.value;
      }
    }
    if (brand == null && category == null && words.isNotEmpty) {
      final hits = SmartSearch.rank(products, words.join(' '), limit: 1);
      if (hits.isNotEmpty && SmartSearch.score(words.join(' '), hits.first) >= 0.8) product = hits.first;
      // a brand by its product names ("vivo" when brand is blank)
      if (product == null) {
        for (final w in words) {
          final any = products.where((p) => '${p['name']}'.toLowerCase().split(' ').first == w).toList();
          if (any.isNotEmpty) brand = w[0].toUpperCase() + w.substring(1);
        }
      }
    }
    final args = <Object?>[from, to];
    var filter = '';
    var what = '';
    if (product != null) {
      filter = ' AND i.product_id = ?';
      args.add(product['id']);
      what = ' on ${product['name']}';
    } else if (brand != null) {
      filter = " AND (LOWER(IFNULL(p.brand, '')) = ? OR LOWER(p.name) LIKE ?)";
      args
        ..add(brand.toLowerCase())
        ..add('${brand.toLowerCase()}%');
      what = ' on $brand';
    } else if (category != null) {
      filter = ' AND LOWER(IFNULL(c.name, \'\')) = ?';
      args.add(category.toLowerCase());
      what = ' on $category';
    }
    const join = 'FROM sale_items i JOIN sales s ON s.id = i.sale_id JOIN products p ON p.id = i.product_id '
        'LEFT JOIN categories c ON c.id = p.category_id WHERE s.date BETWEEN ? AND ?';

    // ---- intents
    if (has(['owe', 'owes', 'due', 'dues', 'baki', 'udhar', 'pabo', 'pawna', 'receivable'])) {
      final bal = await Books.partyBalances('customer');
      final names = {for (final c in await Books.query('SELECT id, name FROM customers')) asInt(c['id']): '${c['name']}'};
      final list = bal.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
      final total = list.fold<int>(0, (a, e) => a + e.value);
      return Answer(list.isEmpty ? 'Nobody owes you money right now 🎉' : '${Money.rs(total)} to collect from ${list.length} customers',
          rows: [for (final e in list.take(8)) (names[e.key] ?? 'Customer', Money.rs(e.value))]);
    }
    if (has(['stock', 'koto ache', 'kotogulo', 'available', 'inventory', 'maal'])) {
      final list = product != null
          ? [product]
          : products
              .where((p) =>
                  (brand == null || '${p['brand']}'.toLowerCase() == brand.toLowerCase() || '${p['name']}'.toLowerCase().startsWith(brand.toLowerCase())) &&
                  (category == null || '${p['category']}' == category))
              .toList();
      final units = list.fold<int>(0, (a, p) => a + asInt(p['stock']));
      final value = list.fold<int>(0, (a, p) => a + asInt(p['stock']) * asInt(p['cost']));
      list.sort((a, b) => asInt(b['stock']).compareTo(asInt(a['stock'])));
      return Answer('$units in stock$what · worth ${Money.rs(value)}', rows: [for (final p in list.take(8)) ('${p['name']}', '${p['stock']}')]);
    }
    if (has(['best', 'top', 'beshi', 'sobcheye', 'most sold', 'popular', 'hit'])) {
      final r = await Books.query(
          'SELECT i.name, SUM(i.qty) AS q, SUM(i.amount) AS v $join$filter GROUP BY i.product_id ORDER BY q DESC, v DESC LIMIT 8', args);
      if (r.isEmpty) return Answer('No sales$what $label');
      return Answer('Best seller $label$what: ${r.first['name']} (${r.first['q']} sold)',
          rows: [for (final x in r) ('${x['name']}', '${x['q']} · ${Money.rs(asInt(x['v']))}')]);
    }
    if (has(['expense', 'expenses', 'khoroch', 'khorch', 'cost of shop', 'spent'])) {
      final r = await Books.query(
          'SELECT a.name, SUM(e.amount) AS v FROM expenses e JOIN accounts a ON a.id = e.head_id WHERE e.date BETWEEN ? AND ? GROUP BY a.name ORDER BY v DESC',
          [from, to]);
      final total = r.fold<int>(0, (a, x) => a + asInt(x['v']));
      return Answer('Expenses $label: ${Money.rs(total)}', rows: [for (final x in r.take(8)) ('${x['name']}', Money.rs(asInt(x['v'])))]);
    }
    if (has(['purchase', 'purchases', 'kena', 'kinechi', 'bought', 'kinlam'])) {
      final r = (await Books.query('SELECT COUNT(*) AS n, IFNULL(SUM(total), 0) AS v FROM purchases WHERE date BETWEEN ? AND ?', [from, to])).first;
      return Answer('Purchases $label: ${Money.rs(asInt(r['v']))}', detail: '${r['n']} bill${asInt(r['n']) == 1 ? '' : 's'}');
    }
    final r = (await Books.query(
            'SELECT IFNULL(SUM(i.amount), 0) AS v, IFNULL(SUM(i.amount - i.unit_cost * i.qty), 0) AS profit, IFNULL(SUM(i.qty), 0) AS q, '
            'COUNT(DISTINCT s.id) AS bills $join$filter',
            args))
        .first;
    final v = asInt(r['v']), profit = asInt(r['profit']);
    final margin = v == 0 ? 0 : (profit * 100 / v).round();
    if (has(['profit', 'labh', 'lav', 'munafa', 'income', 'margin', 'earn', 'kamai', 'lābh'])) {
      return Answer('Profit $label$what: ${Money.rs(profit)}', detail: 'On sales of ${Money.rs(v)} · margin $margin% · ${r['q']} items', rows: [
        ('Sales (before GST)', Money.rs(v)),
        ('Cost of goods', Money.rs(v - profit)),
        ('Gross profit', Money.rs(profit)),
        ('Margin', '$margin%'),
      ]);
    }
    // default: sales
    final total = what.isEmpty
        ? asInt((await Books.query('SELECT IFNULL(SUM(total), 0) AS v FROM sales WHERE date BETWEEN ? AND ?', [from, to])).first['v'])
        : v;
    return Answer('Sales $label$what: ${Money.rs(total)}', detail: '${r['bills']} bill${asInt(r['bills']) == 1 ? '' : 's'} · ${r['q']} items · profit ${Money.rs(profit)}');
  }

  static const _stop = {
    'koto', 'how', 'much', 'what', 'was', 'the', 'and', 'this', 'last', 'month', 'today', 'sale', 'sales', 'profit', 'labh', 'hoyeche',
    'holo', 'hoise', 'gato', 'mash', 'mas', 'week', 'year', 'bochor', 'stock', 'ache', 'best', 'seller', 'top', 'who', 'owes', 'most',
    'expense', 'expenses', 'purchase', 'purchases', 'days', 'din', 'yesterday', 'kal', 'bikri', 'kena', 'khoroch', 'baki', 'due',
    'dues', 'sobcheye', 'beshi', 'amar', 'ami', 'for', 'from', 'with', 'koyta', 'kotogulo', 'all', 'time', 'total', 'past', 'sesh',
    'soptaho', 'koro', 'dekhao', 'show', 'tell', 'me', 'ei', 'available', 'inventory', 'previous', 'margin', 'munafa', 'lav', 'income',
  };

  /// Saved questions for the chat history (last 30).
  static Future<List<String>> history() async {
    try {
      final raw = (await Books.settings())['ai_ask_history'];
      return raw == null ? [] : [for (final x in jsonDecode(raw) as List) '$x'];
    } catch (_) {
      return [];
    }
  }

  static Future<void> remember(String q) async {
    final h = (await history())..remove(q);
    h.insert(0, q);
    await Books.setSetting('ai_ask_history', jsonEncode(h.take(30).toList()));
  }
}
