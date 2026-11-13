/// Smart Business AI — an offline engine that reads the books every time
/// they change and turns them into short, actionable suggestions:
/// payments to collect today, EMI kistis, warranty ends, low and dead
/// stock, best sellers, loss-making sales and the sales trend.
/// Everything runs on the phone; nothing is sent anywhere.
library;

import 'books.dart';
import 'money.dart';

class Insight {
  /// urgent | warn | good | info — also the sort order.
  final String level;
  /// due | emi | collect | warranty | stock | dead | best | trend | loss | today | payable | margin
  final String kind;
  final String title, text;
  final int? amount;
  /// For WhatsApp: the party's phone and a ready message.
  final String? phone, message;
  /// What to open: ('customer'|'supplier'|'product'|'emi'|'low'|'sale', id)
  final String? target;
  final int? targetId;
  const Insight(this.level, this.kind, this.title, this.text,
      {this.amount, this.phone, this.message, this.target, this.targetId});

  int get rank => switch (level) { 'urgent' => 0, 'warn' => 1, 'good' => 2, _ => 3 };
}

class Insights {
  static String _shop(Map<String, String> s) {
    final n = (s['business_name'] ?? '').trim();
    return n.isEmpty ? 'GameX Pc Hub' : n;
  }

  static String _upi(Map<String, String> s) {
    final u = (s['upi_id'] ?? '').trim();
    return u.isEmpty ? '' : '\nUPI: $u';
  }

  /// WhatsApp text for a payment promised on [date].
  static String dueMessage(Map<String, String> s, String name, int amount, String date, {bool overdue = false}) =>
      'Namaskar $name 🙏\n${_shop(s)} theke mone korano hocche — apnar ${Money.rs(amount)} '
      '${overdue ? 'debar tarikh ${prettyDate(date)} periye geche' : 'debar tarikh ${prettyDate(date)}'}.'
      '${_upi(s)}\nDoya kore somoy moto pay korun. Dhonnobad!\n— ${_shop(s)}${(s['phone'] ?? '').isEmpty ? '' : ', ${s['phone']}'}';

  static String emiMessage(Map<String, String> s, String name, int amount, String date, String product, int n, int months) =>
      'Namaskar $name 🙏\n$product-er EMI kisti $n/$months — ${Money.rs(amount)}, tarikh ${prettyDate(date)}.'
      '${_upi(s)}\nSomoy moto jama korle late charge lagbe na. Dhonnobad!\n— ${_shop(s)}';

  static String warrantyMessage(Map<String, String> s, String name, String device, int daysLeft) =>
      'Namaskar $name 🙏\nApnar $device-er warranty ${daysLeft <= 0 ? 'shesh hoye geche' : '$daysLeft din-e shesh hobe'}. '
      'Kono somossa thakle ekhoni ${_shop(s)}-e niye ashun — free check-up kore debo. '
      'Extended warranty, accessories ar exchange offer-o ache!\n— ${_shop(s)}';

  static Future<List<Insight>> build({DateTime? now}) async {
    final out = <Insight>[];
    final s = await Books.settings();
    final t0 = now ?? DateTime.now();
    final today = ymd(t0), tomorrow = ymd(t0.add(const Duration(days: 1)));

    // 1 · promised payments: today, overdue, tomorrow
    for (final d in await Books.dues()) {
      final date = '${d['due_date']}';
      if (date.compareTo(tomorrow) > 0) continue;
      final isC = d['party_type'] == 'customer';
      final amt = asInt(d['amount']);
      final name = '${d['party'] ?? 'Party'}';
      final over = date.compareTo(today) < 0;
      final when = over ? '${t0.difference(DateTime.parse(date)).inDays} din late' : date == today ? 'aaj' : 'kal';
      out.add(Insight(
        over || date == today ? 'urgent' : 'warn',
        'due',
        isC ? '$name — ${Money.rs(amt)} collect korun ($when)' : '$name-ke ${Money.rs(amt)} dite hobe ($when)',
        '${(d['note'] ?? '').toString().isEmpty ? 'Payment' : d['note']} · tarikh ${prettyDate(date)}'
            '${isC ? ' · WhatsApp-e mone koran' : ''}',
        amount: amt,
        phone: d['phone'] as String?,
        message: isC ? dueMessage(s, name, amt, date, overdue: over) : null,
        target: d['party_type'] as String,
        targetId: asInt(d['party_id']),
      ));
    }

    // 2 · EMI kistis due today / overdue / tomorrow
    for (final i in await Books.query(
        'SELECT i.*, e.customer_id, e.product, e.months, e.kind, c.name AS customer, c.phone FROM emi_installments i '
        "JOIN emi_plans e ON e.id = i.plan_id JOIN customers c ON c.id = e.customer_id WHERE e.status = 'active' "
        'AND i.paid_amount < i.amount AND i.due_date <= ? ORDER BY i.due_date LIMIT 12',
        [tomorrow])) {
      final date = '${i['due_date']}';
      final left = asInt(i['amount']) - asInt(i['paid_amount']);
      final over = date.compareTo(today) < 0;
      out.add(Insight(
        over || date == today ? 'urgent' : 'warn',
        'emi',
        '${i['customer']} — EMI ${Money.rs(left)} ${over ? 'overdue' : date == today ? 'aaj' : 'kal'}',
        '${i['product'] ?? 'EMI'} · kisti ${i['n']}/${i['months']} · ${prettyDate(date)}',
        amount: left,
        phone: i['phone'] as String?,
        message: emiMessage(s, '${i['customer']}', left, date, '${i['product'] ?? 'Phone'}', asInt(i['n']), asInt(i['months'])),
        target: 'emi',
        targetId: asInt(i['plan_id']),
      ));
    }

    // 3 · old dues with no promised date
    final bal = await Books.partyBalances('customer');
    final dated = {for (final d in await Books.dues(partyType: null)) if (d['party_type'] == 'customer') asInt(d['party_id'])};
    if (bal.isNotEmpty) {
      final rows = await Books.query(
          'SELECT c.id, c.name, c.phone, (SELECT MAX(date) FROM sales WHERE customer_id = c.id) AS last FROM customers c');
      final old = <(Rec, int, int)>[];
      for (final c in rows) {
        final b = bal[asInt(c['id'])] ?? 0;
        if (b <= 0 || dated.contains(asInt(c['id']))) continue;
        final last = DateTime.tryParse('${c['last'] ?? ''}');
        final days = last == null ? 0 : t0.difference(last).inDays;
        if (days >= 15) old.add((c, b, days));
      }
      old.sort((a, b) => b.$2.compareTo(a.$2));
      for (final (c, b, days) in old.take(3)) {
        out.add(Insight('warn', 'collect', '${c['name']}-er ${Money.rs(b)} $days din dhore baki',
            'Kono tarikh set nei — WhatsApp reminder pathan ba debar tarikh set korun',
            amount: b,
            phone: c['phone'] as String?,
            message: dueMessage(s, '${c['name']}', b, today),
            target: 'customer',
            targetId: asInt(c['id'])));
      }
    }

    // 4 · warranties ending within a week
    for (final w in (await Books.warrantyEndingSoon(days: 7)).take(3)) {
      final left = w.warrantyDaysLeft ?? 0;
      final name = '${w.sale?['party'] ?? 'Customer'}';
      out.add(Insight('info', 'warranty', '${w.name} — warranty ${left <= 0 ? 'shesh' : '$left din baki'}',
          '$name · ${w.serial} · service / extended warranty offer korun',
          phone: w.sale?['phone'] as String?,
          message: warrantyMessage(s, name, w.name, left),
          target: w.sale?['party_id'] == null ? null : 'customer',
          targetId: w.sale?['party_id'] == null ? null : asInt(w.sale!['party_id'])));
    }

    // 5 · low stock with how fast it sells
    final low = await Books.query(
        'SELECT p.id, p.name, p.stock, p.low_stock, (SELECT IFNULL(SUM(i.qty),0) FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'WHERE i.product_id = p.id AND s.date >= ?) AS sold30 FROM products p WHERE p.stock <= p.low_stock ORDER BY sold30 DESC, p.stock LIMIT 20',
        [ymd(t0.subtract(const Duration(days: 30)))]);
    if (low.isNotEmpty) {
      final hot = low.where((p) => asInt(p['sold30']) > 0).toList();
      final top = (hot.isNotEmpty ? hot : low).first;
      final sold = asInt(top['sold30']);
      out.add(Insight(
        hot.isNotEmpty ? 'urgent' : 'warn',
        'stock',
        low.length == 1 ? '${top['name']} — matro ${top['stock']} ta ache' : '${low.length} ta product shesh hoye asche',
        sold > 0
            ? '${top['name']} mashe $sold ta bikri hoy — ekhoni order din (${(sold / 30 * 7).ceil()}+ ta 1 shoptaher jonno)'
            : low.take(3).map((p) => '${p['name']} (${p['stock']})').join(', '),
        target: low.length == 1 ? 'product' : 'low',
        targetId: asInt(top['id']),
      ));
    }

    // 6 · dead stock: in stock, nothing sold for 60 days
    final since = ymd(t0.subtract(const Duration(days: 60)));
    final dead = await Books.query(
        'SELECT p.id, p.name, p.stock, p.cost FROM products p WHERE p.stock > 0 AND p.created_at < ? AND NOT EXISTS '
        '(SELECT 1 FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE i.product_id = p.id AND s.date >= ?) '
        'ORDER BY p.stock * p.cost DESC LIMIT 20',
        [since, since]);
    if (dead.isNotEmpty) {
      final value = dead.fold<int>(0, (a, p) => a + asInt(p['stock']) * asInt(p['cost']));
      out.add(Insight('warn', 'dead', '${Money.rs(value)} er maal 60 din dhore bikri hoyni',
          '${dead.take(2).map((p) => p['name']).join(', ')}${dead.length > 2 ? ' + ${dead.length - 2} more' : ''} · offer / discount diye bechun',
          amount: value, target: dead.length == 1 ? 'product' : null, targetId: asInt(dead.first['id'])));
    }

    // 7 · loss-making sales in the last 7 days
    final week = ymd(t0.subtract(const Duration(days: 6)));
    final loss = await Books.query(
        'SELECT i.name, s.number, s.id AS sale_id, i.amount - i.unit_cost * i.qty AS p FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'WHERE s.date >= ? AND i.unit_cost > 0 AND i.amount < i.unit_cost * i.qty ORDER BY p LIMIT 10',
        [week]);
    if (loss.isNotEmpty) {
      final lost = loss.fold<int>(0, (a, l) => a - asInt(l['p']));
      out.add(Insight('warn', 'loss', '${loss.length} ta item kena damer niche bikri hoyeche',
          '${loss.first['name']} (${loss.first['number']}) · e shoptahe loss ${Money.rs(lost)} · price check korun',
          amount: lost, target: 'sale', targetId: asInt(loss.first['sale_id'])));
    }

    // 8 · best seller this week
    final best = await Books.query(
        'SELECT i.product_id, i.name, SUM(i.qty) AS q, SUM(i.amount - i.unit_cost * i.qty) AS profit FROM sale_items i '
        'JOIN sales s ON s.id = i.sale_id WHERE s.date >= ? GROUP BY i.product_id ORDER BY q DESC, profit DESC LIMIT 1',
        [week]);
    if (best.isNotEmpty && asInt(best.first['q']) >= 2) {
      final b = best.first;
      out.add(Insight('good', 'best', 'Best seller: ${b['name']}',
          'Ei shoptahe ${b['q']} ta bikri · lav ${Money.rs(asInt(b['profit']))} · stock-e rakhun',
          target: 'product', targetId: asInt(b['product_id'])));
    }

    // 9 · sales trend: last 7 days vs the 7 before
    Future<int> sum(String a, String b) async =>
        asInt((await Books.query('SELECT IFNULL(SUM(total),0) AS v FROM sales WHERE date >= ? AND date <= ?', [a, b])).first['v']);
    final cur = await sum(week, today);
    final prev = await sum(ymd(t0.subtract(const Duration(days: 13))), ymd(t0.subtract(const Duration(days: 7))));
    if (cur > 0 || prev > 0) {
      final pc = Books.pctChange(cur, prev);
      out.add(Insight(
        pc >= 0 ? 'good' : 'warn',
        'trend',
        pc >= 0 ? 'Bikri ${pc.abs()}% bereche 📈' : 'Bikri ${pc.abs()}% kome geche',
        'Shesh 7 din ${Money.rs(cur)} · tar ager 7 din ${Money.rs(prev)}'
            '${pc < 0 ? ' · purono customer-der offer pathan' : ''}',
        amount: cur,
      ));
    }

    // 10 · profit margin this month
    final ms = ymd(DateTime(t0.year, t0.month, 1));
    final m = (await Books.query(
            'SELECT IFNULL(SUM(i.amount),0) AS rev, IFNULL(SUM(i.unit_cost * i.qty),0) AS cost FROM sale_items i '
            'JOIN sales s ON s.id = i.sale_id WHERE s.date >= ? AND s.date <= ?',
            [ms, today]))
        .first;
    final rev = asInt(m['rev']), cost = asInt(m['cost']);
    if (rev > 0) {
      final pct = ((rev - cost) * 100 / rev).round();
      out.add(Insight(pct < 8 ? 'warn' : 'info', 'margin', 'E mashe gross margin $pct%',
          'Bikri ${Money.rs(rev)} · lav ${Money.rs(rev - cost)}${pct < 8 ? ' · margin kom — accessories/combo bechun' : ''}',
          amount: rev - cost));
    }

    // 11 · today so far vs the daily average
    final todaySales = await sum(today, today);
    final avg = (await sum(ymd(t0.subtract(const Duration(days: 30))), ymd(t0.subtract(const Duration(days: 1))))) ~/ 30;
    if (todaySales > 0 && avg > 0 && todaySales > avg) {
      out.add(Insight('good', 'today', 'Aaj darun din! ${Money.rs(todaySales)} bikri',
          'Dainik gor ${Money.rs(avg)} theke ${Books.pctChange(todaySales, avg)}% beshi', amount: todaySales));
    }

    out.sort((a, b) => a.rank.compareTo(b.rank));
    return out;
  }
}
