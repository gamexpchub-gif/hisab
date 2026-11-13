import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/charts.dart';
import '../ui/widgets.dart';
import 'loans.dart';
import 'party_profile.dart';
import 'products.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);

const _cSales = Color(0xFF5B2EE0);
const _cPurch = Color(0xFFF08A24);
const _cProfit = Color(0xFF16A36A);
const _cExp = Color(0xFFDC4545);
const _cColl = Color(0xFF2F6BFF);
const _cDue = Color(0xFFE39A0F);

const _palette = [Color(0xFF5B2EE0), Color(0xFF2F6BFF), Color(0xFF16A36A), Color(0xFFF08A24), Color(0xFFD81E4A), Color(0xFF0D9488), Color(0xFF8B5CF6), Color(0xFF64748B)];

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

/// Professional analytics for the shop: every number of the business over
/// any period, with charts, comparisons and an AI reading.
class AnalyticsScreen extends StatefulWidget {
  final String period;
  const AnalyticsScreen({super.key, this.period = 'month'});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late String period = widget.period;
  String? from, to;
  String chart = 'sales'; // sales | profit | cash

  @override
  Widget build(BuildContext context) {
    return Live<Analytics>(
      key: ValueKey('$period$from$to'),
      load: () => Analytics.load(period, from: from, to: to),
      builder: (context, a) => PageShell(
        title: 'Pro Analytics',
        subtitle: '${prettyDate(a.from)}${a.from == a.to ? '' : ' – ${prettyDate(a.to)}'} · AI analysis',
        children: [
          _periods(a),
          const SizedBox(height: 8),
          _hero(a),
          const SizedBox(height: 12),
          _kpis(a),
          _card(
            'Trend',
            trailing: _seg(),
            child: Column(children: [
              const SizedBox(height: 6),
              _chart(a),
              const SizedBox(height: 8),
              _legend(chart == 'sales'
                  ? [('Bikri', _cSales), ('Purchase', _cPurch)]
                  : chart == 'profit'
                      ? [('Lav', _cProfit), ('Khoroch', _cExp)]
                      : [('Collection', _cColl), ('Notun baki', _cDue)]),
            ]),
          ),
          _aiCard(a),
          _card('Bill-er sonkha', child: _Bars(a.buckets.map((b) => b.bills).toList(), a.buckets.map((b) => b.label).toList(), _cSales)),
          _card('Taka kothay ache (ekhon)', child: _moneyGrid(a)),
          if (a.categories.isNotEmpty || a.payModes.isNotEmpty)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (a.categories.isNotEmpty) Expanded(child: _donutCard('Category', a.categories, 'bikri')),
              if (a.categories.isNotEmpty && a.payModes.isNotEmpty) const SizedBox(width: 10),
              if (a.payModes.isNotEmpty) Expanded(child: _donutCard('Payment', a.payModes, 'collection')),
            ]),
          if (a.topProducts.isNotEmpty)
            _card('Top products',
                child: _ranked(a.topProducts, _cSales, onTap: (s) => open(context, ProductView(id: s.id!)))),
          if (a.topCustomers.isNotEmpty)
            _card('Top customers',
                child: _ranked(a.topCustomers, _cColl, onTap: (s) => open(context, PartyView(type: 'customer', id: s.id!)))),
          if (a.debtors.isNotEmpty)
            _card('Kar kache koto baki',
                trailing: Text(Money.compact(a.receivable), style: _j(13, FontWeight.w800, _red)),
                child: _ranked(a.debtors, _cDue, onTap: (s) => open(context, PartyView(type: 'customer', id: s.id!)))),
          if (a.topSuppliers.isNotEmpty)
            _card('Top suppliers',
                trailing: Text('Payable ${Money.compact(a.payable)}', style: _j(12, FontWeight.w800, _muted)),
                child: _ranked(a.topSuppliers, _cPurch, onTap: (s) => open(context, PartyView(type: 'supplier', id: s.id!)))),
          if (a.expenseHeads.isNotEmpty) _card('Khoroch kothay', child: _ranked(a.expenseHeads, _cExp)),
          _card('Profit & Loss', child: _pl(a)),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ period chips
  Widget _periods(Analytics a) {
    Widget chip(String id, String l) {
      final on = period == id;
      return GestureDetector(
        onTap: () async {
          HapticFeedback.selectionClick();
          if (id == 'custom') {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2015),
              lastDate: DateTime.now(),
              initialDateRange: DateTimeRange(start: DateTime.parse(a.from), end: DateTime.parse(a.to)),
            );
            if (r == null) return;
            setState(() {
              period = 'custom';
              from = ymd(r.start);
              to = ymd(r.end);
            });
            return;
          }
          setState(() => period = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: on ? null : Border.all(color: _line),
          ),
          child: Text(l, style: _j(12.5, FontWeight.w700, on ? Colors.white : _ink)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('today', 'Aaj'),
        chip('week', '7 din'),
        chip('month', 'Ei mash'),
        chip('year', 'Ei bochor'),
        chip('custom', period == 'custom' ? '📅 ${prettyDate(a.from).substring(0, 6)} – ${prettyDate(a.to).substring(0, 6)}' : '📅 Custom'),
      ]),
    );
  }

  // ------------------------------------------------------------ hero
  Widget _hero(Analytics a) {
    final ch = Books.pctChange(a.sales, a.pSales);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF0F1240), Color(0xFF2A1E8F), Color(0xFF6B35EE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x404318D2), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Mot bikri', style: _j(13, FontWeight.w600, const Color(0xD9FFFFFF))),
          const Spacer(),
          _pill(ch),
        ]),
        Text(Money.rs(a.sales), style: _j(31, FontWeight.w800, Colors.white)),
        const SizedBox(height: 2),
        Text('${a.bills} bill · ${a.items} item · gor bill ${Money.compact(a.avgBill)}', style: _j(12, FontWeight.w600, const Color(0xD9FFFFFF))),
        const SizedBox(height: 12),
        SizedBox(height: 42, child: Sparkline(a.buckets.map((b) => b.sales).toList(), const Color(0xFF9F7BFF), width: double.infinity, height: 42)),
        const SizedBox(height: 12),
        Row(children: [
          _heroStat('Net lav', a.net, a.net >= 0 ? const Color(0xFF3EE08F) : const Color(0xFFFFB5C2)),
          _heroStat('Margin', null, Colors.white, text: '${a.margin}%'),
          _heroStat('Collection', a.collected, Colors.white),
        ]),
      ]),
    );
  }

  Widget _pill(int ch, {bool light = true}) {
    final up = ch >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: light ? (up ? const Color(0x333EE08F) : const Color(0x33FF7A9A)) : (up ? const Color(0xFFE6F7EE) : const Color(0xFFFDECEC)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text('${up ? '▲' : '▼'} ${ch.abs()}%',
          style: _j(11, FontWeight.w800, light ? (up ? const Color(0xFF3EE08F) : const Color(0xFFFFB5C2)) : (up ? _green : _red))),
    );
  }

  Widget _heroStat(String l, int? v, Color c, {String? text}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: _j(11, FontWeight.w600, const Color(0xB3FFFFFF))),
          Text(text ?? Money.compact(v!), style: _j(16, FontWeight.w800, c)),
        ]),
      );

  // ------------------------------------------------------------ KPI grid
  Widget _kpis(Analytics a) {
    final items = [
      ('Purchase', a.purchases, Books.pctChange(a.purchases, a.pPurchases), Icons.shopping_bag_rounded, _cPurch, false),
      ('Gross lav', a.gross, Books.pctChange(a.gross, a.pGross), Icons.trending_up_rounded, _cProfit, false),
      ('Khoroch', a.expenses, Books.pctChange(a.expenses, a.pExpenses), Icons.sell_rounded, _cExp, true),
      ('Collection', a.collected, Books.pctChange(a.collected, a.pCollected), Icons.south_west_rounded, _cColl, false),
      ('Notun baki', a.newDue, null, Icons.schedule_rounded, _cDue, true),
      ('Supplier-ke dewa', a.paidOut, null, Icons.north_east_rounded, const Color(0xFF64748B), false),
      ('Customer', a.activeCustomers, null, Icons.groups_rounded, const Color(0xFF0D9488), false),
      ('Notun customer', a.newCustomers, null, Icons.person_add_alt_1_rounded, const Color(0xFF8B5CF6), false),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (i, k) in items.indexed)
          Container(
            width: w,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF1F2F9))),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: k.$5.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
                child: Icon(k.$4, color: k.$5, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w600, _muted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(i >= 6 ? '${k.$2}' : Money.compact(k.$2), style: _j(15.5, FontWeight.w800, _ink)),
                  ),
                  if (k.$3 != null)
                    Text('${k.$3! >= 0 ? '▲' : '▼'} ${k.$3!.abs()}%',
                        style: _j(10.5, FontWeight.w800, (k.$3! >= 0) != k.$6 ? _green : _red)),
                ]),
              ),
            ]),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------ cards
  Widget _card(String title, {required Widget child, Widget? trailing}) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F2F9)),
          boxShadow: const [BoxShadow(color: Color(0x0F2A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(title, style: _j(15, FontWeight.w800, _ink))), if (trailing != null) trailing]),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _seg() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: const Color(0xFFF1F2F9), borderRadius: BorderRadius.circular(11)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final s in const [('sales', 'Bikri'), ('profit', 'Lav'), ('cash', 'Taka')])
            GestureDetector(
              onTap: () => setState(() => chart = s.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: chart == s.$1 ? Colors.white : null, borderRadius: BorderRadius.circular(9)),
                child: Text(s.$2, style: _j(11.5, FontWeight.w800, chart == s.$1 ? _ink : _muted)),
              ),
            ),
        ]),
      );

  Widget _chart(Analytics a) {
    final labels = a.buckets.map((b) => b.label).toList();
    final series = switch (chart) {
      'profit' => [
          ChartSeries('Lav', a.buckets.map((b) => b.profit - b.expenses).toList(), _cProfit, area: true),
          ChartSeries('Khoroch', a.buckets.map((b) => b.expenses).toList(), _cExp),
        ],
      'cash' => [
          ChartSeries('Collection', a.buckets.map((b) => b.collected).toList(), _cColl, area: true),
          ChartSeries('Notun baki', a.buckets.map((b) => b.due).toList(), _cDue),
        ],
      _ => [
          ChartSeries('Bikri', a.buckets.map((b) => b.sales).toList(), _cSales, area: true),
          ChartSeries('Purchase', a.buckets.map((b) => b.purchases).toList(), _cPurch),
        ],
    };
    return TrendChart(labels: labels, series: series, height: 220);
  }

  Widget _legend(List<(String, Color)> items) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final (l, c) in items) ...[
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(l, style: _j(11.5, FontWeight.w700, _muted)),
          const SizedBox(width: 14),
        ],
      ]);

  Widget _aiCard(Analytics a) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFFF4F0FF), Color(0xFFEAF2FF)]),
          border: Border.all(color: const Color(0xFFDCD3FF)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF5B2EE0)),
            const SizedBox(width: 8),
            Text('AI analysis', style: _j(15, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 8),
          for (final s in a.ai)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(s, style: _j(13, FontWeight.w600, const Color(0xFF262B55))),
            ),
        ]),
      );

  Widget _moneyGrid(Analytics a) {
    final rows = [
      ('Cash', a.cash, Icons.payments_rounded, _green),
      ('Bank', a.bank, Icons.account_balance_rounded, _cColl),
      ('UPI / wallet', a.upi, Icons.qr_code_rounded, _cSales),
      if (a.card != 0) ('Card', a.card, Icons.credit_card_rounded, const Color(0xFF64748B)),
      ('Stock value', a.stock, Icons.inventory_2_rounded, _cPurch),
      ('Bazare baki', a.receivable, Icons.call_received_rounded, _cDue),
      ('Supplier payable', -a.payable, Icons.call_made_rounded, _red),
      ('Loan baki', -a.loans, Icons.request_quote_rounded, _red),
    ];
    final worth = a.cash + a.bank + a.upi + a.card + a.stock + a.receivable - a.payable - a.loans;
    final maxV = rows.fold<int>(1, (m, r) => math.max(m, r.$2.abs()));
    return Column(children: [
      for (final r in rows)
        GestureDetector(
          onTap: r.$1 == 'Loan baki' ? () => open(context, const LoansScreen()) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Icon(r.$3, size: 18, color: r.$4),
              const SizedBox(width: 8),
              SizedBox(width: 108, child: Text(r.$1, style: _j(12.5, FontWeight.w600, _ink))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: r.$2.abs() / maxV,
                    backgroundColor: const Color(0xFFF1F2F9),
                    valueColor: AlwaysStoppedAnimation(r.$4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: Text(Money.compact(r.$2), textAlign: TextAlign.right, style: _j(12.5, FontWeight.w800, r.$2 < 0 ? _red : _ink)),
              ),
            ]),
          ),
        ),
      const Divider(color: _line),
      Row(children: [
        Expanded(child: Text('Business-er mot mullo (net worth)', style: _j(13, FontWeight.w800, _ink))),
        Text(Money.compact(worth), style: _j(15, FontWeight.w800, worth >= 0 ? _green : _red)),
      ]),
      if (a.capital != 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text('Owner / partner capital', style: _j(12, FontWeight.w600, _muted))),
            Text(Money.compact(a.capital), style: _j(12.5, FontWeight.w800, _muted)),
          ]),
        ),
    ]);
  }

  Widget _donutCard(String title, List<Share> parts, String label) {
    final top = parts.take(6).toList();
    final total = top.fold<int>(0, (s, x) => s + x.value);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF1F2F9))),
      child: Column(children: [
        Text(title, style: _j(14, FontWeight.w800, _ink)),
        const SizedBox(height: 8),
        DonutChart(
          parts: [for (final p in top) MapEntry(p.name, p.value)],
          colors: _palette,
          size: 112,
          centerTop: Money.compact(total),
          centerBottom: label,
        ),
        const SizedBox(height: 8),
        for (final (i, p) in top.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w600, _muted))),
              Text('${total == 0 ? 0 : (p.value * 100 / total).round()}%', style: _j(11, FontWeight.w800, _ink)),
            ]),
          ),
      ]),
    );
  }

  Widget _ranked(List<Share> items, Color color, {void Function(Share)? onTap}) {
    final maxV = items.fold<int>(1, (m, x) => math.max(m, x.value));
    return Column(children: [
      for (final (i, s) in items.indexed)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap == null || s.id == null ? null : () => onTap(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: i == 0 ? color : color.withValues(alpha: .12), shape: BoxShape.circle),
                child: Text('${i + 1}', style: _j(11, FontWeight.w800, i == 0 ? Colors.white : color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w700, _ink))),
                    Text(Money.compact(s.value), style: _j(13, FontWeight.w800, _ink)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: s.value / maxV,
                      backgroundColor: const Color(0xFFF1F2F9),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  if (s.sub != null) ...[
                    const SizedBox(height: 2),
                    Text(s.sub!, style: _j(10.5, FontWeight.w600, _muted)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _pl(Analytics a) {
    Widget row(String l, int v, {bool bold = false, Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(l, style: _j(13, bold ? FontWeight.w800 : FontWeight.w500, bold ? _ink : _muted))),
            Text(Money.rs(v), style: _j(13.5, FontWeight.w800, c ?? _ink)),
          ]),
        );
    return Column(children: [
      row('Bikri (GST soho)', a.sales),
      row('Kena dam (COGS)', -a.cogs),
      row('Gross lav', a.gross, bold: true, c: a.gross >= 0 ? _green : _red),
      row('Khoroch (sud soho)', -a.expenses),
      const Divider(color: _line),
      row('Net lav', a.net, bold: true, c: a.net >= 0 ? _green : _red),
      if (a.pNet != 0 || a.net != 0)
        Align(alignment: Alignment.centerRight, child: _pill(Books.pctChange(a.net, a.pNet), light: false)),
    ]);
  }
}

/// Simple animated vertical bars with value on top of the tallest.
class _Bars extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  final Color color;
  const _Bars(this.values, this.labels, this.color);

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<int>(0, math.max);
    final step = (labels.length / 8).ceil().clamp(1, 99);
    return SizedBox(
      height: 130,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (values[i] == maxV && maxV > 0) Text('${values[i]}', style: _j(10, FontWeight.w800, color)),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: values.length > 20 ? 1 : 3),
                  height: maxV == 0 ? 2 : math.max(2, 90 * t * values[i] / maxV),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [color.withValues(alpha: .55), color],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: i % step == 0
                      ? Text(labels[i], maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: _j(9, FontWeight.w600, _muted))
                      : null,
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
