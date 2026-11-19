/// AI Autopilot — the work the shop does every day, prepared automatically:
/// payment reminders that get firmer at 3 / 7 / 15 days, EMI reminders the
/// day before, after-sale follow-ups at 7 and 30 days, warranty-end notes,
/// a re-order list per supplier from the real sales speed, and the
/// end-of-day cash check. Messages open in WhatsApp ready to send.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'alarms.dart';
import 'books.dart';
import 'money.dart';

class AutoTask {
  final String key; // unique: sent once
  final String kind; // due | emi | follow7 | follow30 | warranty
  final String title, sub;
  final String? phone, message;
  final int amount;
  final int? customerId;
  final int level; // 1 gentle · 2 reminder · 3 firm (dues)
  const AutoTask(this.key, this.kind, this.title, this.sub,
      {this.phone, this.message, this.amount = 0, this.customerId, this.level = 1});
}

class ReorderItem {
  final Rec product;
  final int stock, sold30, suggest, lastRate;
  final double perDay;
  final int? daysLeft; // null = not selling
  final int? supplierId;
  final String? supplier, supplierPhone;
  const ReorderItem(this.product, this.stock, this.sold30, this.perDay, this.daysLeft, this.suggest, this.lastRate,
      this.supplierId, this.supplier, this.supplierPhone);
}

class CashClose {
  final String date;
  final int expected, counted;
  final String note;
  const CashClose(this.date, this.expected, this.counted, this.note);
  int get diff => counted - expected;
  Map<String, Object?> toJson() => {'date': date, 'expected': expected, 'counted': counted, 'note': note};
  static CashClose from(Map<String, dynamic> m) =>
      CashClose('${m['date']}', asInt(m['expected']), asInt(m['counted']), '${m['note'] ?? ''}');
}

class Autopilot {
  static const _sentKey = 'autopilot_sent';
  static const _closeKey = 'cash_closes';

  // ---------------------------------------------------------------- sent log
  static Future<Map<String, String>> sent() async {
    try {
      final raw = (await Books.settings())[_sentKey];
      if (raw == null || raw.isEmpty) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  /// Remembers that a task was done (keeps the last 120 days).
  static Future<void> markSent(String key, {DateTime? now}) async {
    final m = await sent();
    final t = now ?? DateTime.now();
    m[key] = ymd(t);
    final cut = ymd(t.subtract(const Duration(days: 120)));
    m.removeWhere((_, d) => d.compareTo(cut) < 0);
    await Books.setSetting(_sentKey, jsonEncode(m));
  }

  static String _shop(Map<String, String> s) {
    final n = (s['business_name'] ?? '').trim();
    return n.isEmpty ? 'our shop' : n;
  }

  static String _upi(Map<String, String> s) {
    final u = (s['upi_id'] ?? '').trim();
    return u.isEmpty ? '' : '\nPay by UPI: $u';
  }

  // ---------------------------------------------------------------- messages
  static String dueText(Map<String, String> s, String name, int amount, int days, int level) {
    final shop = _shop(s);
    return switch (level) {
      1 => 'Hello $name 🙏\nThank you for shopping at $shop. A gentle reminder: ${Money.rs(amount)} is pending on your account.'
          '${_upi(s)}\nPlease pay at your convenience. — $shop',
      2 => 'Hello $name,\nThis is a reminder from $shop — ${Money.rs(amount)} has been pending for $days days.'
          '${_upi(s)}\nKindly clear it this week. Thank you! — $shop',
      _ => 'Dear $name,\n${Money.rs(amount)} is overdue at $shop for $days days. Please clear the payment today '
          'or tell us a date you will pay.${_upi(s)}\n— $shop${(s['phone'] ?? '').isEmpty ? '' : ', ${s['phone']}'}',
    };
  }

  static String follow7Text(Map<String, String> s, String name, String item) =>
      'Hello $name 😊\nIt has been a week with your new $item from ${_shop(s)}. Is everything working well? '
      'If you need any help — setup, data transfer, anything — just reply here. Thank you!';

  static String follow30Text(Map<String, String> s, String name, String item) =>
      'Hello $name 🎁\nKeep your $item safe! Special offer at ${_shop(s)} this week: back cover, tempered glass, '
      'earphones and chargers at a discount for our customers. Visit us or reply to order.';

  static String warrantyText(Map<String, String> s, String name, String item, int daysLeft) =>
      'Hello $name 🙏\nThe warranty on your $item ${daysLeft <= 0 ? 'ends today' : 'ends in $daysLeft days'}. '
      'If anything is wrong, bring it to ${_shop(s)} now for a free check. Extended warranty available too.';

  static String emiText(Map<String, String> s, String name, int amount, String date, String product) =>
      'Hello $name 🙏\nYour $product EMI of ${Money.rs(amount)} is due ${date == ymd(DateTime.now()) ? 'today' : 'tomorrow (${prettyDate(date)})'}.'
      '${_upi(s)}\nPlease pay on time. — ${_shop(s)}';

  static String orderText(Map<String, String> s, String supplier, List<ReorderItem> items) {
    final b = StringBuffer('Hello $supplier 🙏\nOrder from ${_shop(s)}:\n');
    for (var i = 0; i < items.length; i++) {
      final x = items[i];
      final v = '${x.product['variant'] ?? ''}'.trim();
      b.writeln('${i + 1}. ${x.product['name']}${v.isEmpty ? '' : ' ($v)'} — ${x.suggest} pcs');
    }
    b.write('Please confirm the rates and the delivery date. Thank you!');
    return b.toString();
  }

  // ---------------------------------------------------------------- today's tasks
  static Future<List<AutoTask>> today({DateTime? now}) async {
    final t0 = now ?? DateTime.now();
    final today = ymd(t0), tomorrow = ymd(t0.add(const Duration(days: 1)));
    final s = await Books.settings();
    final done = await sent();
    final out = <AutoTask>[];

    // 1 · dues: 3 / 7 / 15 days after the oldest unpaid bill
    final bal = await Books.partyBalances('customer');
    for (final c in await Books.query('SELECT id, name, phone FROM customers')) {
      final id = asInt(c['id']);
      final b = bal[id] ?? 0;
      if (b <= 0) continue;
      final since = await oldestUnpaid(id, b);
      if (since == null) continue;
      final days = t0.difference(DateTime.parse(since)).inDays;
      final level = days >= 15 ? 3 : days >= 7 ? 2 : days >= 3 ? 1 : 0;
      if (level == 0) continue;
      final key = 'due:$id:$since:$level';
      if (done.containsKey(key)) continue;
      out.add(AutoTask(key, 'due', '${c['name']} · ${Money.rs(b)} pending $days days',
          ['Gentle reminder', 'Reminder', 'Firm reminder'][level - 1],
          phone: c['phone'] as String?, message: dueText(s, '${c['name']}', b, days, level), amount: b, customerId: id, level: level));
    }

    // 2 · EMI instalments due today or tomorrow
    for (final i in await Books.query(
        'SELECT i.id, i.due_date, i.amount - i.paid_amount AS left, e.product, c.id AS cid, c.name, c.phone FROM emi_installments i '
        'JOIN emi_plans e ON e.id = i.plan_id JOIN customers c ON c.id = e.customer_id '
        "WHERE e.status = 'active' AND i.paid_amount < i.amount AND i.due_date BETWEEN ? AND ? ORDER BY i.due_date",
        [today, tomorrow])) {
      final key = 'emi:${i['id']}';
      if (done.containsKey(key)) continue;
      final date = '${i['due_date']}';
      out.add(AutoTask(key, 'emi', '${i['name']} · EMI ${Money.rs(asInt(i['left']))}', date == today ? 'Due today' : 'Due tomorrow',
          phone: i['phone'] as String?,
          message: emiText(s, '${i['name']}', asInt(i['left']), date, '${i['product'] ?? 'phone'}'),
          amount: asInt(i['left']),
          customerId: asInt(i['cid'])));
    }

    // 3 · after-sale follow-ups (devices): 7 and 30 days
    Future<void> follow(String kind, int from, int to, String Function(String, String) text, String sub) async {
      final rows = await Books.query(
          'SELECT s.id, s.date, c.id AS cid, c.name, c.phone, '
          "(SELECT i.name FROM sale_items i JOIN products p ON p.id = i.product_id LEFT JOIN categories g ON g.id = p.category_id "
          "WHERE i.sale_id = s.id AND (LOWER(IFNULL(g.name, '')) LIKE '%mobile%' OR LOWER(IFNULL(g.name, '')) LIKE '%laptop%' "
          "OR LOWER(IFNULL(g.name, '')) LIKE '%tablet%' OR TRIM(IFNULL(i.serial, '')) <> '') ORDER BY i.amount DESC LIMIT 1) AS item "
          'FROM sales s JOIN customers c ON c.id = s.customer_id '
          "WHERE s.date BETWEEN ? AND ? AND TRIM(IFNULL(c.phone, '')) <> '' ORDER BY s.date",
          [ymd(t0.subtract(Duration(days: to))), ymd(t0.subtract(Duration(days: from)))]);
      for (final r in rows) {
        if (r['item'] == null) continue;
        final key = '$kind:${r['id']}';
        if (done.containsKey(key)) continue;
        out.add(AutoTask(key, kind, '${r['name']} · ${r['item']}', sub,
            phone: r['phone'] as String?, message: text('${r['name']}', '${r['item']}'), customerId: asInt(r['cid'])));
      }
    }

    await follow('follow7', 7, 10, (n, i) => follow7Text(s, n, i), 'Bought 1 week ago — ask how it is going');
    await follow('follow30', 30, 34, (n, i) => follow30Text(s, n, i), 'Bought 1 month ago — accessory offer');

    // 4 · warranties ending in the next 7 days
    for (final w in await Books.query(
        'SELECT i.id, i.name, s.date, p.warranty_months AS m, c.id AS cid, c.name AS customer, c.phone FROM sale_items i '
        'JOIN sales s ON s.id = i.sale_id JOIN products p ON p.id = i.product_id JOIN customers c ON c.id = s.customer_id '
        "WHERE p.warranty_months > 0 AND TRIM(IFNULL(c.phone, '')) <> ''")) {
      final d = DateTime.parse('${w['date']}');
      final end = DateTime(d.year, d.month + asInt(w['m']), d.day);
      final left = end.difference(DateTime(t0.year, t0.month, t0.day)).inDays;
      if (left < 0 || left > 7) continue;
      final key = 'warranty:${w['id']}';
      if (done.containsKey(key)) continue;
      out.add(AutoTask(key, 'warranty', '${w['customer']} · ${w['name']}', 'Warranty ends ${left == 0 ? 'today' : 'in $left days'}',
          phone: w['phone'] as String?, message: warrantyText(s, '${w['customer']}', '${w['name']}', left), customerId: asInt(w['cid'])));
    }

    const order = {'due': 0, 'emi': 1, 'warranty': 2, 'follow7': 3, 'follow30': 4};
    out.sort((a, b) {
      final k = order[a.kind]!.compareTo(order[b.kind]!);
      if (k != 0) return k;
      return b.level != a.level ? b.level.compareTo(a.level) : b.amount.compareTo(a.amount);
    });
    return out;
  }

  /// Date of the oldest bill still unpaid (newest bills are paid last).
  static Future<String?> oldestUnpaid(int customerId, int balance) async {
    var left = balance;
    String? date;
    // bills and delivered repair charges, newest first (they are paid last)
    for (final r in await Books.query(
        'SELECT date, total, id FROM sales WHERE customer_id = ? '
        "UNION ALL SELECT delivered_at AS date, charge AS total, id FROM repairs WHERE customer_id = ? AND status = 'delivered' AND charge > 0 "
        'ORDER BY date DESC, id DESC',
        [customerId, customerId])) {
      date = '${r['date']}';
      left -= asInt(r['total']);
      if (left <= 0) break;
    }
    return date;
  }

  // ---------------------------------------------------------------- re-order
  static Future<List<ReorderItem>> reorder({DateTime? now, int coverDays = 30, int alertDays = 10}) async {
    final t0 = now ?? DateTime.now();
    final since = ymd(t0.subtract(const Duration(days: 30)));
    final rows = await Books.query(
        'SELECT p.*, '
        '(SELECT IFNULL(SUM(i.qty), 0) FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE i.product_id = p.id AND s.date >= ?) AS sold30, '
        '(SELECT b.supplier_id FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id WHERE i.product_id = p.id ORDER BY b.date DESC, b.id DESC LIMIT 1) AS sup, '
        '(SELECT i.rate FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id WHERE i.product_id = p.id ORDER BY b.date DESC, b.id DESC LIMIT 1) AS last_rate '
        'FROM products p',
        [since]);
    final sups = {for (final x in await Books.query('SELECT id, name, phone FROM suppliers')) asInt(x['id']): x};
    final out = <ReorderItem>[];
    for (final p in rows) {
      final stock = asInt(p['stock']), sold = asInt(p['sold30']), low = asInt(p['low_stock']);
      if (sold <= 0) continue; // only what actually sells
      final perDay = sold / 30;
      final daysLeft = stock <= 0 ? 0 : (stock / perDay).floor();
      if (daysLeft > alertDays && !(low > 0 && stock <= low)) continue;
      final suggest = math.max<int>(1, (perDay * coverDays).ceil() - math.max<int>(0, stock));
      final sid = p['sup'] == null ? null : asInt(p['sup']);
      final sup = sid == null ? null : sups[sid];
      out.add(ReorderItem(p, stock, sold, perDay, daysLeft, suggest, asInt(p['last_rate'] ?? p['cost']), sid, sup?['name'] as String?,
          sup?['phone'] as String?));
    }
    out.sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));
    return out;
  }

  // ---------------------------------------------------------------- cash close
  static Future<int> expectedCash() => Books.balanceByCode(cashCode);

  static Future<List<CashClose>> closes() async {
    try {
      final raw = (await Books.settings())[_closeKey];
      if (raw == null || raw.isEmpty) return [];
      return [for (final m in jsonDecode(raw) as List) CashClose.from(m as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static Future<CashClose> close(int counted, {String note = '', DateTime? now}) async {
    final c = CashClose(ymd(now ?? DateTime.now()), await expectedCash(), counted, note.trim());
    final list = (await closes()).where((x) => x.date != c.date).toList()
      ..insert(0, c);
    await Books.setSetting(_closeKey, jsonEncode([for (final x in list.take(120)) x.toJson()]));
    return c;
  }

  /// Morning notification (10:00): how many messages and re-orders wait.
  static Future<void> scheduleMorning() async {
    try {
      final now = DateTime.now();
      var at = DateTime(now.year, now.month, now.day, 10);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      final tasks = await today(now: at);
      final orders = await reorder(now: at);
      if (tasks.isEmpty && orders.isEmpty) return;
      final money = tasks.where((t) => t.kind == 'due' || t.kind == 'emi').fold<int>(0, (a, t) => a + t.amount);
      final parts = [
        if (tasks.isNotEmpty) '${tasks.length} WhatsApp message${tasks.length == 1 ? '' : 's'} ready${money > 0 ? ' · ${Money.rs(money)} to collect' : ''}',
        if (orders.isNotEmpty) '${orders.length} product${orders.length == 1 ? '' : 's'} to re-order',
      ];
      await Alarms.scheduleAutopilot(at, '🤖 AI Autopilot · ${parts.first}', '${parts.join('\n')}\nOpen Hisab AI → Menu → AI Autopilot');
    } catch (_) {}
  }

  static Future<CashClose?> closedToday({DateTime? now}) async {
    final d = ymd(now ?? DateTime.now());
    return (await closes()).where((c) => c.date == d).firstOrNull;
  }
}
