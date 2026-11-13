import 'books.dart';
import 'money.dart';

/// One point on the time axis.
class Bucket {
  final String label;
  int sales = 0, purchases = 0, expenses = 0, profit = 0, collected = 0, due = 0, bills = 0;
  Bucket(this.label);
}

class Share {
  final String name;
  final int value;
  final String? sub;
  final int? id;
  const Share(this.name, this.value, {this.sub, this.id});
}

/// Everything the analytics page shows for a period, with the same-length
/// period before it for comparison, and an AI reading of the numbers.
class Analytics {
  final String period, from, to, prevFrom, prevTo;
  final List<Bucket> buckets = [];
  // period totals (and previous period)
  int sales = 0, purchases = 0, expenses = 0, gross = 0, net = 0, cogs = 0, bills = 0, items = 0;
  int collected = 0, paidOut = 0, newDue = 0, newCustomers = 0, activeCustomers = 0, interest = 0, returns = 0;
  int pSales = 0, pPurchases = 0, pExpenses = 0, pGross = 0, pNet = 0, pBills = 0, pCollected = 0;
  // position now
  int receivable = 0, payable = 0, cash = 0, bank = 0, upi = 0, card = 0, loans = 0, capital = 0, stock = 0;
  final List<Share> topProducts = [], categories = [], expenseHeads = [], topCustomers = [], topSuppliers = [], payModes = [], debtors = [];
  final List<String> ai = [];
  Analytics(this.period, this.from, this.to, this.prevFrom, this.prevTo);

  int get avgBill => bills == 0 ? 0 : sales ~/ bills;
  int get margin => sales == 0 ? 0 : (gross * 100 / sales).round();
  int get money => cash + bank + upi;

  /// [from, to, prevFrom, prevTo] for a period, or a custom range.
  static List<String> range(String period, {String? from, String? to, DateTime? today}) {
    final t = today ?? DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    switch (period) {
      case 'today':
        final y = d.subtract(const Duration(days: 1));
        return [ymd(d), ymd(d), ymd(y), ymd(y)];
      case 'week':
        final s = d.subtract(const Duration(days: 6));
        return [ymd(s), ymd(d), ymd(s.subtract(const Duration(days: 7))), ymd(s.subtract(const Duration(days: 1)))];
      case 'month':
        final s = DateTime(d.year, d.month, 1);
        final pe = s.subtract(const Duration(days: 1));
        final ps = DateTime(pe.year, pe.month, 1);
        final same = DateTime(ps.year, ps.month, d.day > pe.day ? pe.day : d.day);
        return [ymd(s), ymd(d), ymd(ps), ymd(same)];
      case 'year':
        final s = DateTime(d.year, 1, 1);
        return [ymd(s), ymd(d), ymd(DateTime(d.year - 1, 1, 1)), ymd(DateTime(d.year - 1, d.month, d.day > 28 && d.month == 2 ? 28 : d.day))];
      default:
        final f = DateTime.parse(from!), e = DateTime.parse(to!);
        final days = e.difference(f).inDays + 1;
        final pe = f.subtract(const Duration(days: 1));
        return [from, to, ymd(pe.subtract(Duration(days: days - 1))), ymd(pe)];
    }
  }

  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static Future<int> _v(String sql, List<Object?> a) async => asInt((await Books.query(sql, a)).first['v']);

  static Future<Analytics> load(String period, {String? from, String? to}) async {
    final r = range(period, from: from, to: to);
    final a = Analytics(period, r[0], r[1], r[2], r[3]);
    final f = DateTime.parse(a.from), e = DateTime.parse(a.to);
    final days = e.difference(f).inDays + 1;

    // ---- time axis
    final hourly = days == 1;
    final monthly = days > 62 && days <= 800;
    final yearly = days > 800;
    String keyOf(String date, [String? created]) {
      if (hourly) {
        final h = int.tryParse((created ?? '').length >= 13 ? created!.substring(11, 13) : '') ?? 12;
        return '${(h ~/ 3) * 3}';
      }
      if (yearly) return date.substring(0, 4);
      if (monthly) return date.substring(0, 7);
      return date;
    }

    final map = <String, Bucket>{};
    if (hourly) {
      for (var h = 0; h < 24; h += 3) {
        map['$h'] = Bucket('${h == 0 ? 12 : h > 12 ? h - 12 : h}${h < 12 ? 'a' : 'p'}');
      }
    } else if (yearly) {
      for (var y = f.year; y <= e.year; y++) {
        map['$y'] = Bucket('$y');
      }
    } else if (monthly) {
      var m = DateTime(f.year, f.month, 1);
      while (!m.isAfter(e)) {
        map[ymd(m).substring(0, 7)] = Bucket(_mon[m.month - 1]);
        m = DateTime(m.year, m.month + 1, 1);
      }
    } else {
      for (var i = 0; i < days; i++) {
        final d = f.add(Duration(days: i));
        map[ymd(d)] = Bucket(days <= 7 ? ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][d.weekday - 1] : '${d.day}');
      }
    }
    Bucket? b(String date, [String? created]) => map[keyOf(date, created)];

    for (final s in await Books.query('SELECT date, created_at, total, paid FROM sales WHERE date >= ? AND date <= ?', [a.from, a.to])) {
      final x = b('${s['date']}', '${s['created_at']}');
      if (x == null) continue;
      x
        ..sales += asInt(s['total'])
        ..bills += 1
        ..collected += asInt(s['paid'])
        ..due += asInt(s['total']) - asInt(s['paid']);
    }
    for (final s in await Books.query(
        'SELECT s.date, s.created_at, i.amount - i.unit_cost * i.qty AS p FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE s.date >= ? AND s.date <= ?',
        [a.from, a.to])) {
      b('${s['date']}', '${s['created_at']}')?.profit += asInt(s['p']);
    }
    for (final s in await Books.query('SELECT date, created_at, total FROM purchases WHERE date >= ? AND date <= ?', [a.from, a.to])) {
      b('${s['date']}', '${s['created_at']}')?.purchases += asInt(s['total']);
    }
    for (final s in await Books.query('SELECT date, created_at, amount FROM expenses WHERE date >= ? AND date <= ?', [a.from, a.to])) {
      b('${s['date']}', '${s['created_at']}')?.expenses += asInt(s['amount']);
    }
    for (final s in await Books.query("SELECT date, created_at, amount FROM payments WHERE kind = 'receipt' AND date >= ? AND date <= ?", [a.from, a.to])) {
      b('${s['date']}', '${s['created_at']}')?.collected += asInt(s['amount']);
    }
    a.buckets.addAll(map.values);

    // ---- totals, this period and the one before
    Future<List<int>> totals(String f, String t) async {
      final pl = await Books.profitLoss(f, t);
      return [
        await _v('SELECT IFNULL(SUM(total),0) AS v FROM sales WHERE date >= ? AND date <= ?', [f, t]),
        await _v('SELECT IFNULL(SUM(total),0) AS v FROM purchases WHERE date >= ? AND date <= ?', [f, t]),
        pl.operatingExpenses,
        pl.grossProfit,
        pl.netProfit,
        await _v('SELECT COUNT(*) AS v FROM sales WHERE date >= ? AND date <= ?', [f, t]),
        await _v('SELECT IFNULL(SUM(paid),0) AS v FROM sales WHERE date >= ? AND date <= ?', [f, t]) +
            await _v("SELECT IFNULL(SUM(amount),0) AS v FROM payments WHERE kind = 'receipt' AND date >= ? AND date <= ?", [f, t]),
        pl.cogs,
      ];
    }

    final c = await totals(a.from, a.to), p = await totals(a.prevFrom, a.prevTo);
    a
      ..sales = c[0]
      ..purchases = c[1]
      ..expenses = c[2]
      ..gross = c[3]
      ..net = c[4]
      ..bills = c[5]
      ..collected = c[6]
      ..cogs = c[7]
      ..pSales = p[0]
      ..pPurchases = p[1]
      ..pExpenses = p[2]
      ..pGross = p[3]
      ..pNet = p[4]
      ..pBills = p[5]
      ..pCollected = p[6];
    a.items = await _v('SELECT IFNULL(SUM(i.qty),0) AS v FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE s.date >= ? AND s.date <= ?', [a.from, a.to]);
    a.newDue = await _v('SELECT IFNULL(SUM(total - paid),0) AS v FROM sales WHERE date >= ? AND date <= ?', [a.from, a.to]);
    a.paidOut = await _v("SELECT IFNULL(SUM(amount),0) AS v FROM payments WHERE kind = 'payment' AND date >= ? AND date <= ?", [a.from, a.to]) +
        await _v('SELECT IFNULL(SUM(paid),0) AS v FROM purchases WHERE date >= ? AND date <= ?', [a.from, a.to]);
    a.newCustomers = await _v('SELECT COUNT(*) AS v FROM customers WHERE substr(created_at, 1, 10) >= ? AND substr(created_at, 1, 10) <= ?', [a.from, a.to]);
    a.activeCustomers =
        await _v('SELECT COUNT(DISTINCT customer_id) AS v FROM sales WHERE customer_id IS NOT NULL AND date >= ? AND date <= ?', [a.from, a.to]);
    a.interest = await _v('SELECT IFNULL(SUM(interest),0) AS v FROM loan_payments WHERE date >= ? AND date <= ?', [a.from, a.to]);
    a.returns = await _v('SELECT IFNULL(SUM(value),0) AS v FROM sale_returns WHERE date >= ? AND date <= ?', [a.from, a.to]);

    // ---- position now
    a.receivable = (await Books.partyBalances('customer')).values.where((v) => v > 0).fold(0, (s, v) => s + v);
    a.payable = (await Books.partyBalances('supplier')).values.where((v) => v > 0).fold(0, (s, v) => s + v);
    for (final m in await Books.moneyAccounts(withCards: true)) {
      final v = await Books.balance(asInt(m['id']), '${m['type']}');
      switch ('${m['kind']}') {
        case 'cash':
          a.cash += v;
        case 'bank':
          a.bank += v;
        case 'card':
          a.card += v;
        default:
          a.upi += v;
      }
    }
    a.loans = await Books.balanceByCode('2500');
    a.capital = await Books.balanceByCode('3000');
    a.stock = await _v('SELECT IFNULL(SUM(CASE WHEN stock > 0 THEN stock * cost ELSE 0 END),0) AS v FROM products', []);

    // ---- breakdowns
    for (final x in await Books.query(
        'SELECT i.product_id, i.name, SUM(i.qty) AS q, SUM(i.amount) AS rev, SUM(i.amount - i.unit_cost * i.qty) AS pr FROM sale_items i '
        'JOIN sales s ON s.id = i.sale_id WHERE s.date >= ? AND s.date <= ? GROUP BY i.product_id ORDER BY rev DESC LIMIT 6',
        [a.from, a.to])) {
      a.topProducts.add(Share('${x['name']}', asInt(x['rev']), sub: '${x['q']} ta · lav ${Money.compact(asInt(x['pr']))}', id: asInt(x['product_id'])));
    }
    for (final x in await Books.query(
        "SELECT IFNULL(c.name, 'Other') AS n, SUM(i.amount) AS v FROM sale_items i JOIN sales s ON s.id = i.sale_id "
        'LEFT JOIN products p ON p.id = i.product_id LEFT JOIN categories c ON c.id = p.category_id '
        'WHERE s.date >= ? AND s.date <= ? GROUP BY n ORDER BY v DESC',
        [a.from, a.to])) {
      a.categories.add(Share('${x['n']}', asInt(x['v'])));
    }
    for (final x in await Books.query(
        'SELECT h.name AS n, SUM(e.amount) AS v FROM expenses e JOIN accounts h ON h.id = e.head_id WHERE e.date >= ? AND e.date <= ? GROUP BY h.id ORDER BY v DESC',
        [a.from, a.to])) {
      a.expenseHeads.add(Share('${x['n']}', asInt(x['v'])));
    }
    if (a.interest > 0) a.expenseHeads.add(Share('Loan interest', a.interest));
    for (final x in await Books.query(
        'SELECT c.id, c.name, COUNT(*) AS n, SUM(s.total) AS v FROM sales s JOIN customers c ON c.id = s.customer_id '
        'WHERE s.date >= ? AND s.date <= ? GROUP BY c.id ORDER BY v DESC LIMIT 5',
        [a.from, a.to])) {
      a.topCustomers.add(Share('${x['name']}', asInt(x['v']), sub: '${x['n']} bill', id: asInt(x['id'])));
    }
    for (final x in await Books.query(
        'SELECT s.id, s.name, COUNT(*) AS n, SUM(b.total) AS v FROM purchases b JOIN suppliers s ON s.id = b.supplier_id '
        'WHERE b.date >= ? AND b.date <= ? GROUP BY s.id ORDER BY v DESC LIMIT 5',
        [a.from, a.to])) {
      a.topSuppliers.add(Share('${x['name']}', asInt(x['v']), sub: '${x['n']} bill', id: asInt(x['id'])));
    }
    for (final x in await Books.query(
        'SELECT a.name AS n, SUM(p.amount) AS v FROM sale_payments p JOIN sales s ON s.id = p.sale_id JOIN accounts a ON a.id = p.account_id '
        'WHERE s.date >= ? AND s.date <= ? GROUP BY a.id ORDER BY v DESC',
        [a.from, a.to])) {
      a.payModes.add(Share('${x['n']}', asInt(x['v'])));
    }
    if (a.newDue > 0) a.payModes.add(Share('Baki (credit)', a.newDue));
    final bal = await Books.partyBalances('customer');
    final names = {for (final c in await Books.query('SELECT id, name FROM customers')) asInt(c['id']): '${c['name']}'};
    final top = bal.entries.where((x) => x.value > 0).toList()..sort((x, y) => y.value.compareTo(x.value));
    for (final x in top.take(5)) {
      a.debtors.add(Share(names[x.key] ?? 'Customer', x.value, id: x.key));
    }

    a._think();
    return a;
  }

  /// The AI reading: what changed, what is strong, what needs attention.
  void _think() {
    final word = switch (period) { 'today' => 'kal', 'week' => 'ager shoptaho', 'month' => 'gato mash', 'year' => 'gato bochor', _ => 'ager somoy' };
    if (sales == 0 && pSales == 0) {
      ai.add('Ei somoye kono bikri nei — bikri korle AI analysis shuru hobe.');
      return;
    }
    final ch = Books.pctChange(sales, pSales);
    ai.add(ch >= 0 ? '📈 Bikri $word-er theke $ch% beshi (${Money.compact(sales)} vs ${Money.compact(pSales)}).' : '📉 Bikri $word-er theke ${ch.abs()}% kom — offer ba purono customer-der message pathan.');
    if (sales > 0) {
      ai.add('💰 Gross margin $margin%${margin < 10 ? ' — kom; accessories / combo bechle margin barbe' : margin > 25 ? ' — darun!' : ''}. Net lav ${Money.compact(net)}.');
    }
    if (pNet != 0 || net != 0) {
      final nc = Books.pctChange(net, pNet);
      if (net < 0) ai.add('⚠️ Ei somoye loss ${Money.compact(-net)} — khoroch ${Money.compact(expenses)} komano dorkar.');
      if (net > 0 && nc > 0 && pNet > 0) ai.add('✅ Net lav $nc% bereche.');
    }
    if (expenses > 0 && sales > 0) {
      final ep = (expenses * 100 / sales).round();
      if (ep > 15) ai.add('🧾 Khoroch bikri-r $ep% — ${expenseHeads.isEmpty ? '' : '${expenseHeads.first.name}-e shobcheye beshi'}.');
    }
    if (newDue > 0 && sales > 0) {
      final dp = (newDue * 100 / sales).round();
      if (dp >= 20) ai.add('⏳ Bikri-r $dp% baki-te geche (${Money.compact(newDue)}) — collection-e jor din.');
    }
    if (receivable > 0 && money > 0 && receivable > money) {
      ai.add('🔔 Bazar-e baki ${Money.compact(receivable)}, hate taka ${Money.compact(money)} — baki tolar dorkar.');
    }
    if (topProducts.isNotEmpty) ai.add('🔥 Top: ${topProducts.first.name} — ${Money.compact(topProducts.first.value)} (${topProducts.first.sub}).');
    if (categories.length > 1 && sales > 0) {
      final cat = categories.first;
      final total = categories.fold(0, (s, x) => s + x.value);
      ai.add('📦 ${cat.name} theke ${(cat.value * 100 / (total == 0 ? 1 : total)).round()}% bikri.');
    }
    if (topCustomers.isNotEmpty) ai.add('👑 Best customer: ${topCustomers.first.name} (${Money.compact(topCustomers.first.value)}).');
    if (loans > 0) {
      ai.add('🏦 Loan baki ${Money.compact(loans)}${interest > 0 ? ', ei somoye sud ${Money.compact(interest)}' : ''}'
          '${net > 0 && interest > 0 ? ' — lav-er ${(interest * 100 / net).round()}% sud-e jacche' : ''}.');
    }
    if (stock > 0 && cogs > 0) {
      final days = period == 'today' ? 1 : DateTime.parse(to).difference(DateTime.parse(from)).inDays + 1;
      final turn = (stock / (cogs / days)).round();
      ai.add('🗃️ Stock ${Money.compact(stock)} — ei speed-e ~$turn din cholbe${turn > 90 ? ' (beshi maal pore ache)' : turn < 10 ? ' (shiggiri order din)' : ''}.');
    }
    if (returns > 0) ai.add('↩️ Return ${Money.compact(returns)} — quality / customer-er proyojon check korun.');
  }
}
