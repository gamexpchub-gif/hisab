import 'dart:async';

import 'alarms.dart';
import 'books.dart';
import 'plan.dart';
import 'money.dart';

/// The end-of-day AI report: today's sales, profit, money in and out,
/// who pays tomorrow and what to reorder — shown as a notification every
/// evening and on its own page, shareable on WhatsApp.
class DailyReport {
  final String day;
  int sales = 0, invoices = 0, profit = 0, items = 0;
  int collected = 0, supplierPaid = 0, expenses = 0, purchases = 0, newDue = 0;
  int prevSales = 0, totalDue = 0;
  String? best;
  final List<Rec> tomorrow = []; // dues + EMI for tomorrow
  final List<Rec> reorder = []; // products to order (name, stock, need)
  final Map<String, int> cash = {}; // money accounts → balance now
  DailyReport(this.day);

  int get change => Books.pctChange(sales, prevSales);
  int get margin => sales == 0 ? 0 : (profit * 100 / sales).round();

  static Future<int> _v(String sql, List<Object?> args) async => asInt((await Books.query(sql, args)).first['v']);

  static Future<DailyReport> load([DateTime? date]) async {
    final d = date ?? DateTime.now();
    final t = ymd(d), y = ymd(d.subtract(const Duration(days: 1))), tm = ymd(d.add(const Duration(days: 1)));
    final r = DailyReport(t);
    r.sales = await _v('SELECT IFNULL(SUM(total),0) AS v FROM sales WHERE date = ?', [t]);
    r.invoices = await _v('SELECT COUNT(*) AS v FROM sales WHERE date = ?', [t]);
    r.prevSales = await _v('SELECT IFNULL(SUM(total),0) AS v FROM sales WHERE date = ?', [y]);
    r.newDue = await _v('SELECT IFNULL(SUM(total - paid),0) AS v FROM sales WHERE date = ?', [t]);
    r.profit = await _v(
        'SELECT IFNULL(SUM(i.amount - i.unit_cost * i.qty),0) AS v FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE s.date = ?', [t]);
    r.items = await _v('SELECT IFNULL(SUM(i.qty),0) AS v FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE s.date = ?', [t]);
    r.collected = await _v('SELECT IFNULL(SUM(paid),0) AS v FROM sales WHERE date = ?', [t]) +
        await _v("SELECT IFNULL(SUM(amount),0) AS v FROM payments WHERE date = ? AND kind = 'receipt'", [t]);
    r.supplierPaid = await _v("SELECT IFNULL(SUM(amount),0) AS v FROM payments WHERE date = ? AND kind = 'payment'", [t]);
    r.expenses = await _v('SELECT IFNULL(SUM(amount),0) AS v FROM expenses WHERE date = ?', [t]);
    r.purchases = await _v('SELECT IFNULL(SUM(total),0) AS v FROM purchases WHERE date = ?', [t]);
    final b = await Books.query(
        'SELECT i.name, SUM(i.qty) AS q FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE s.date = ? GROUP BY i.product_id ORDER BY q DESC LIMIT 1',
        [t]);
    if (b.isNotEmpty) r.best = '${b.first['name']} × ${b.first['q']}';
    r.totalDue = (await Books.partyBalances('customer')).values.where((v) => v > 0).fold(0, (a, v) => a + v);

    for (final x in await Books.dues()) {
      if ('${x['due_date']}'.compareTo(tm) <= 0) {
        r.tomorrow.add({'name': x['party'], 'amount': asInt(x['amount']), 'what': x['party_type'] == 'customer' ? 'debe' : 'dite hobe', 'late': '${x['due_date']}'.compareTo(t) < 0});
      }
    }
    for (final e in await Books.query(
        'SELECT c.name, i.amount - i.paid_amount AS left, i.due_date FROM emi_installments i JOIN emi_plans p ON p.id = i.plan_id '
        "JOIN customers c ON c.id = p.customer_id WHERE p.status = 'active' AND i.paid_amount < i.amount AND i.due_date <= ? ORDER BY i.due_date",
        [tm])) {
      r.tomorrow.add({'name': e['name'], 'amount': asInt(e['left']), 'what': 'EMI', 'late': '${e['due_date']}'.compareTo(t) < 0});
    }

    for (final l in await Loans.list()) {
      final next = l['next_due'] as String?;
      if (next != null && next.compareTo(tm) <= 0) {
        r.tomorrow.add({'name': l['lender'], 'amount': asInt(l['next_emi']), 'what': 'loan EMI dite hobe', 'late': next.compareTo(t) < 0});
      }
    }

    // reorder: what sells and will run out within a week
    final since = ymd(d.subtract(const Duration(days: 30)));
    for (final p in await Books.query(
        'SELECT p.name, p.stock, p.low_stock, (SELECT IFNULL(SUM(i.qty),0) FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'WHERE i.product_id = p.id AND s.date >= ?) AS sold FROM products p ORDER BY sold DESC',
        [since])) {
      final perDay = asInt(p['sold']) / 30;
      final stock = asInt(p['stock']);
      final lowNow = stock <= asInt(p['low_stock']);
      final daysLeft = perDay > 0 ? stock / perDay : double.infinity;
      if ((perDay > 0 && daysLeft <= 7) || (lowNow && asInt(p['sold']) > 0)) {
        final need = (perDay * 14).ceil() - stock;
        r.reorder.add({'name': p['name'], 'stock': stock, 'need': need < 1 ? 1 : need, 'days': perDay > 0 ? daysLeft.floor() : null});
      }
    }

    for (final a in await Books.moneyAccounts()) {
      r.cash['${a['name']}'] = await Books.balance(asInt(a['id']), 'asset');
    }
    return r;
  }

  /// Short line for the notification.
  String headline() => invoices == 0
      ? 'Aaj kono bikri entry hoyni${tomorrow.isEmpty ? '' : ' · kal ${tomorrow.length} jon-er payment'}'
      : 'Bikri ${Money.rs(sales)} · lav ${Money.rs(profit)} · collection ${Money.rs(collected)}';

  String body() => [
        if (invoices > 0) '$invoices bill, $items item${best == null ? '' : ' · best: $best'}',
        if (expenses > 0) 'Khoroch ${Money.rs(expenses)}',
        if (tomorrow.isNotEmpty) 'Kal: ${tomorrow.take(3).map((x) => '${x['name']} ${Money.rs(asInt(x['amount']))}').join(', ')}',
        if (reorder.isNotEmpty) 'Order: ${reorder.take(3).map((x) => '${x['name']} ×${x['need']}').join(', ')}',
      ].join('\n');

  /// Full text for WhatsApp.
  String text(String shop) {
    final b = StringBuffer()
      ..writeln('📊 *$shop — Daily Report*')
      ..writeln(prettyDate(day))
      ..writeln()
      ..writeln('🧾 Bikri: *${Money.rs(sales)}* ($invoices bill, $items item)')
      ..writeln('💰 Lav: *${Money.rs(profit)}* ($margin%)')
      ..writeln('📥 Collection: ${Money.rs(collected)}')
      ..writeln('📤 Khoroch: ${Money.rs(expenses)}${supplierPaid > 0 ? ' · supplier-ke ${Money.rs(supplierPaid)}' : ''}')
      ..writeln('🛒 Purchase: ${Money.rs(purchases)}')
      ..writeln('⏳ Aajker notun baki: ${Money.rs(newDue)} · mot baki ${Money.rs(totalDue)}');
    if (prevSales > 0 || sales > 0) b.writeln('${change >= 0 ? '📈' : '📉'} Kal-er theke ${change.abs()}% ${change >= 0 ? 'beshi' : 'kom'}');
    if (best != null) b.writeln('🔥 Best: $best');
    if (cash.isNotEmpty) {
      b
        ..writeln()
        ..writeln('🏦 ${cash.entries.map((e) => '${e.key} ${Money.rs(e.value)}').join(' · ')}');
    }
    if (tomorrow.isNotEmpty) {
      b
        ..writeln()
        ..writeln('📅 *Kal collect / pay:*');
      for (final x in tomorrow.take(8)) {
        b.writeln('• ${x['name']} — ${Money.rs(asInt(x['amount']))} ${x['what']}${x['late'] == true ? ' (late)' : ''}');
      }
    }
    if (reorder.isNotEmpty) {
      b
        ..writeln()
        ..writeln('📦 *Order korte hobe:*');
      for (final x in reorder.take(8)) {
        b.writeln('• ${x['name']} — ${x['need']} ta (stock ${x['stock']}${x['days'] == null ? '' : ', ~${x['days']} din cholbe'})');
      }
    }
    b
      ..writeln()
      ..write('— Hisab AI');
    return b.toString();
  }

  // ---------------------------------------------------------------- schedule
  static Timer? _debounce;
  static bool _listening = false;

  /// Keeps tonight's report notification up to date: every change to the
  /// books re-schedules it with fresh numbers (the books only change in the
  /// app, so the evening notification is always exact).
  static void start() {
    if (_listening) return;
    _listening = true;
    Books.changes.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), reschedule);
    });
    reschedule();
  }

  static Future<void> reschedule() async {
    try {
      final s = await Books.settings();
      if (s['daily_report'] == '0' || !Sub.can('daily_ai')) {
        await Alarms.cancelDaily();
        return;
      }
      final at = (s['daily_report_at'] ?? '21:00').split(':');
      final h = int.tryParse(at.first) ?? 21, m = int.tryParse(at.length > 1 ? at[1] : '0') ?? 0;
      final now = DateTime.now();
      final today = await load(now);
      final todayAt = DateTime(now.year, now.month, now.day, h, m);
      if (todayAt.isAfter(now)) {
        await Alarms.scheduleDaily(0, todayAt, '📊 Aajker report · ${today.headline()}', today.body());
      }
      // tomorrow's, in case the app is not opened tomorrow
      final tm = now.add(const Duration(days: 1));
      final next = await load(tm);
      await Alarms.scheduleDaily(1, DateTime(tm.year, tm.month, tm.day, h, m), '📊 Aajker report · ${next.headline()}',
          next.body().isEmpty ? 'App khule aajker hisab dekhun' : next.body());
    } catch (_) {
      // a report is a convenience; never disturb the app
    }
  }
}
