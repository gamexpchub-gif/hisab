import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../main.dart';
import '../ui/charts.dart';
import '../ui/widgets.dart';
import 'ledgers.dart';
import 'notifications.dart';
import 'parties.dart';
import 'products.dart';
import 'reports.dart';
import 'sales.dart';

// Design tokens shared with the Products screen.
const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _purple = Color(0xFF5B2EE0);
const _blue = Color(0xFF2F6BFF);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFF29D0B);

TextStyle _j(double size, FontWeight w, Color c, {double? height}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
    );

TextStyle _num(double size, Color c) => TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: FontWeight.w800,
      fontVariations: [FontVariation('wght', 800)],
      color: c,
      letterSpacing: -0.5,
      height: 1.05,
    );

BoxDecoration _card({double r = 22}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [
        BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
        BoxShadow(color: Color(0x0A2A2F7A), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );

String _range(DateTime a, DateTime b) {
  String d(DateTime x) => '${x.day} ${monthName(x.month)}';
  if (a.year == b.year && a.month == b.month && a.day == b.day) return '${d(a)} ${a.year}';
  return '${d(a)} – ${d(b)} ${b.year}';
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const periods = ['today', 'week', 'month', 'year', 'custom'];
  static const periodLabels = ['Today', 'Week', 'Month', 'Year', 'Custom'];
  String period = 'month';
  DateTimeRange? custom;
  final hidden = <String>{};

  (DateTime, DateTime) get _dates {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'today':
        return (today, today);
      case 'week':
        return (today.subtract(Duration(days: today.weekday - 1)), today);
      case 'year':
        return (DateTime(today.year, 1, 1), today);
      case 'custom':
        final c = custom;
        if (c != null) return (c.start, c.end);
        return (DateTime(today.year, today.month, 1), today);
      default:
        return (DateTime(today.year, today.month, 1), today);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: 'Select report period',
    );
    if (r != null) {
      setState(() {
        custom = r;
        period = 'custom';
      });
    }
  }

  void _select(String p) {
    HapticFeedback.selectionClick();
    if (p == 'custom') {
      _pickCustom();
      return;
    }
    setState(() => period = p);
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _dates;
    final bottom = LiquidGlassNav.outerHeight(MediaQuery.of(context).padding.bottom) + 90;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Live<(Analytics, int)>(
          reloadKey: '$period|${ymd(from)}|${ymd(to)}',
          load: () async => (await Books.analytics(from, to), (await Books.notifications()).length),
          builder: (context, d) {
            final a = d.$1;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
              children: [
                _header(d.$2),
                const SizedBox(height: 16),
                _periodBar(),
                const SizedBox(height: 10),
                _rangeLine(a),
                const SizedBox(height: 14),
                _HeroProfit(a),
                const SizedBox(height: 14),
                _kpis(a),
                const SizedBox(height: 14),
                _trend(a),
                const SizedBox(height: 14),
                _categoryCard(a),
                const SizedBox(height: 14),
                _collectionCard(a),
                const SizedBox(height: 14),
                _customerReport(a),
                const SizedBox(height: 14),
                _topProducts(a),
                const SizedBox(height: 14),
                _expenses(a),
                const SizedBox(height: 14),
                _moneyCard(a),
                const SizedBox(height: 14),
                _reportsGrid(from, to),
                const SizedBox(height: 14),
                _lowStockAndRecent(a),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header
  Widget _header(int alerts) {
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset('assets/home/logo.png', width: 50, height: 50, fit: BoxFit.fill),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Business Dashboard', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(19, FontWeight.w800, _navy)),
          const SizedBox(height: 2),
          Text('Live analytics & reports', style: _j(12.5, FontWeight.w500, const Color(0xFF323B60))),
        ]),
      ),
      _roundBtn(Icons.date_range_rounded, _pickCustom),
      const SizedBox(width: 10),
      Stack(clipBehavior: Clip.none, children: [
        _roundBtn(Icons.notifications_none_rounded, () => open(context, const NotificationsScreen())),
        if (alerts > 0)
          Positioned(
            right: -2,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF72552),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(alerts > 99 ? '99+' : '$alerts', style: _j(9.5, FontWeight.w700, Colors.white)),
            ),
          ),
      ]),
    ]);
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFBFBFF),
            boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
          ),
          child: Icon(icon, color: const Color(0xFF1B2A8F), size: 22),
        ),
      );

  // ---------------------------------------------------------------- period selector
  Widget _periodBar() {
    final i = periods.indexOf(period);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: _card(r: 24),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / periods.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            left: i * w,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
                boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -4)],
              ),
            ),
          ),
          Row(children: [
            for (var k = 0; k < periods.length; k++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _select(periods[k]),
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (periods[k] == 'custom')
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(Icons.event_rounded, size: 14, color: k == i ? Colors.white : _muted),
                        ),
                      Text(periodLabels[k],
                          style: _j(12.5, k == i ? FontWeight.w700 : FontWeight.w600, k == i ? Colors.white : const Color(0xFF3A4155))),
                    ]),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }

  Widget _rangeLine(Analytics a) {
    final prevTo = a.from.subtract(const Duration(days: 1));
    final days = a.to.difference(a.from).inDays + 1;
    final prevFrom = prevTo.subtract(Duration(days: days - 1));
    return Row(children: [
      const Icon(Icons.calendar_today_rounded, size: 14, color: _purple),
      const SizedBox(width: 6),
      Text(_range(a.from, a.to), style: _j(12.5, FontWeight.w700, _navy)),
      const SizedBox(width: 6),
      Expanded(
        child: Text('vs ${_range(prevFrom, prevTo)}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w500, _muted)),
      ),
    ]);
  }

  // ---------------------------------------------------------------- KPI grid
  Widget _kpis(Analytics a) {
    final sales = [for (final s in a.series) s.sales];
    final purch = [for (final s in a.series) s.purchases];
    final profit = [for (final s in a.series) s.profit];
    final tiles = [
      _Kpi('Total sales', Money.rs(a.cur.sales), a.change((p) => p.sales), 'qa_sales', sales, _purple,
          onTap: () => open(context, const SalesScreen())),
      _Kpi('Purchases', Money.rs(a.cur.purchases), a.change((p) => p.purchases), 'qa_purchase', purch, const Color(0xFF8B5CF6),
          goodWhenUp: false, onTap: () => open(context, const PurchasesScreen())),
      _Kpi('Gross profit', Money.rs(a.cur.grossProfit), a.change((p) => p.grossProfit), 'qa_expense', profit, _green),
      _Kpi('Collected', Money.rs(a.cur.collected), a.change((p) => p.collected), 'qa_bank', sales, const Color(0xFFD81E4A)),
      _Kpi('Invoices', '${a.cur.invoices}', a.change((p) => p.invoices), 'qa_ledger', sales, _amber),
      _Kpi('Avg. bill value', Money.rs(a.cur.avgBill), a.change((p) => p.avgBill), 'qa_product', sales, _blue),
      _Kpi('New customers', '${a.cur.newCustomers}', a.change((p) => p.newCustomers), 'qa_customer', sales, const Color(0xFF139DB0),
          onTap: () => open(context, const PartiesScreen(type: 'customer'))),
      _Kpi('GST collected', Money.rs(a.cur.gstCollected), a.change((p) => p.gstCollected), 'qa_supplier', sales, const Color(0xFFF06A1A),
          onTap: () => open(context, const GstScreen())),
    ];
    return Column(children: [
      for (var r = 0; r < tiles.length; r += 2) ...[
        if (r > 0) const SizedBox(height: 12),
        Row(children: [Expanded(child: tiles[r]), const SizedBox(width: 12), Expanded(child: tiles[r + 1])]),
      ],
    ]);
  }

  // ---------------------------------------------------------------- trend chart
  Widget _trend(Analytics a) {
    final all = [
      ChartSeries('Sales', [for (final s in a.series) s.sales], _purple, area: true),
      ChartSeries('Purchases', [for (final s in a.series) s.purchases], const Color(0xFF38BDF8)),
      ChartSeries('Net profit', [for (final s in a.series) s.profit], _green),
    ];
    final shown = all.where((s) => !hidden.contains(s.name)).toList();
    SeriesPoint? best;
    for (final s in a.series) {
      if (best == null || s.sales > best.sales) best = s;
    }
    final unit = {'hour': 'hourly', 'day': 'daily', 'week': 'weekly', 'month': 'monthly'}[a.granularity];
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.show_chart_rounded, color: _purple, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sales & profit trend', style: _j(15, FontWeight.w800, _ink)),
              Text('${unit![0].toUpperCase()}${unit.substring(1)} · tap the chart for details', style: _j(11, FontWeight.w500, _muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final s in all)
            GestureDetector(
              onTap: () => setState(() => hidden.contains(s.name) ? hidden.remove(s.name) : hidden.add(s.name)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hidden.contains(s.name) ? const Color(0xFFF2F3F8) : s.color.withAlpha(0x1F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: hidden.contains(s.name) ? const Color(0xFFB9BCD6) : s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(s.name, style: _j(11.5, FontWeight.w600, hidden.contains(s.name) ? _muted : _ink)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        TrendChart(labels: [for (final s in a.series) s.label], series: shown, height: 230),
        if (best != null && best.sales > 0) ...[
          const Divider(color: Color(0xFFEDEEF6), height: 20),
          Row(children: [
            const Icon(Icons.emoji_events_rounded, color: _amber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Best ${a.granularity == 'hour' ? 'hour' : a.granularity}: ${best.label}',
                  style: _j(12, FontWeight.w600, _ink)),
            ),
            Text(Money.rs(best.sales), style: _j(12.5, FontWeight.w800, _purple)),
          ]),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- category donut
  static const _palette = [
    Color(0xFF5B2EE0),
    Color(0xFF38BDF8),
    Color(0xFF16A36A),
    Color(0xFFF29D0B),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF94A3B8),
  ];

  Widget _categoryCard(Analytics a) {
    final parts = [for (final c in a.categories) MapEntry(c['name'] as String, asInt(c['v']))];
    final total = parts.fold<int>(0, (s, e) => s + e.value);
    return _section(
      icon: Icons.donut_large_rounded,
      title: 'Sales by category',
      sub: 'Taxable value, excluding GST',
      child: total == 0
          ? const EmptyState('No sales in this period')
          : Row(children: [
              DonutChart(
                parts: parts,
                colors: _palette,
                size: 132,
                centerTop: Money.compact(total),
                centerBottom: '${parts.length} categories',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(children: [
                  for (var i = 0; i < parts.length && i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: _palette[i % _palette.length], borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(parts[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w600, _ink)),
                        ),
                        Text('${(parts[i].value * 100 / total).round()}%', style: _j(12, FontWeight.w800, _ink)),
                      ]),
                    ),
                ]),
              ),
            ]),
    );
  }

  // ---------------------------------------------------------------- collection by account
  Widget _collectionCard(Analytics a) {
    final total = a.payments.fold<int>(0, (s, r) => s + asInt(r['v']));
    IconData icon(String? k) =>
        k == 'cash' ? Icons.payments_rounded : k == 'upi' ? Icons.qr_code_2_rounded : Icons.account_balance_rounded;
    Color color(String? k) => k == 'cash' ? _green : k == 'upi' ? _purple : _blue;
    return _section(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Money collected',
      sub: 'Sales payments + customer receipts · ${Money.rs(total)}',
      child: total == 0
          ? const EmptyState('No collections in this period')
          : Column(children: [
              for (final r in a.payments)
                _BarRow(
                  icon: icon(r['kind'] as String?),
                  color: color(r['kind'] as String?),
                  label: r['name'] as String,
                  value: Money.rs(asInt(r['v'])),
                  fraction: asInt(r['v']) / total,
                ),
            ]),
    );
  }

  // ---------------------------------------------------------------- customer report
  Widget _customerReport(Analytics a) {
    final maxV = a.topCustomers.isEmpty ? 1 : asInt(a.topCustomers.first['v']);
    return _section(
      icon: Icons.groups_rounded,
      title: 'Customer report',
      sub: 'Top customers in this period',
      action: ('All customers', () => open(context, const PartiesScreen(type: 'customer'))),
      child: Column(children: [
        if (a.topCustomers.isEmpty && a.walkInSales == 0) const EmptyState('No customer sales in this period'),
        for (var i = 0; i < a.topCustomers.length; i++)
          _CustomerRow(
            rank: i + 1,
            r: a.topCustomers[i],
            fraction: maxV == 0 ? 0 : asInt(a.topCustomers[i]['v']) / maxV,
            onTap: () => open(context, PartyView(type: 'customer', id: asInt(a.topCustomers[i]['id']))),
          ),
        if (a.walkInSales > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.storefront_rounded, size: 18, color: _muted),
              const SizedBox(width: 8),
              Expanded(child: Text('Walk-in (cash) customers', style: _j(12, FontWeight.w600, _muted))),
              Text(Money.rs(a.walkInSales), style: _j(12.5, FontWeight.w800, _ink)),
            ]),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- top products
  Widget _topProducts(Analytics a) {
    final maxV = a.topProducts.isEmpty ? 1 : asInt(a.topProducts.first['v']);
    return _section(
      icon: Icons.local_fire_department_rounded,
      title: 'Top selling products',
      sub: 'By sales value',
      action: ('Products', () => Shell.goTo(context, 2)),
      child: a.topProducts.isEmpty
          ? const EmptyState('No product sales in this period')
          : Column(children: [
              for (var i = 0; i < a.topProducts.length; i++)
                GestureDetector(
                  onTap: () => open(context, ProductView(id: asInt(a.topProducts[i]['id']))),
                  child: _BarRow(
                    rankText: '${i + 1}',
                    color: _palette[i % _palette.length],
                    label: a.topProducts[i]['name'] as String,
                    sub: '${a.topProducts[i]['qty']} sold · profit ${Money.rs(asInt(a.topProducts[i]['profit']))}',
                    value: Money.rs(asInt(a.topProducts[i]['v'])),
                    fraction: maxV == 0 ? 0 : asInt(a.topProducts[i]['v']) / maxV,
                  ),
                ),
            ]),
    );
  }

  // ---------------------------------------------------------------- expenses
  Widget _expenses(Analytics a) {
    final total = a.expenseHeads.fold<int>(0, (s, r) => s + asInt(r['v']));
    return _section(
      icon: Icons.receipt_long_rounded,
      title: 'Expenses',
      sub: 'Total ${Money.rs(total)} · ${a.change((p) => p.expenses) >= 0 ? '+' : ''}${a.change((p) => p.expenses)}% vs previous',
      child: total == 0
          ? const EmptyState('No expenses in this period')
          : Column(children: [
              for (var i = 0; i < a.expenseHeads.length; i++)
                _BarRow(
                  icon: Icons.sell_rounded,
                  color: const [_red, _amber, Color(0xFFEC4899), _purple, _blue, Color(0xFF14B8A6)][i % 6],
                  label: a.expenseHeads[i]['name'] as String,
                  value: Money.rs(asInt(a.expenseHeads[i]['v'])),
                  fraction: asInt(a.expenseHeads[i]['v']) / total,
                ),
            ]),
    );
  }

  // ---------------------------------------------------------------- money position
  Widget _moneyCard(Analytics a) {
    final total = a.money.fold<int>(0, (s, e) => s + e.value);
    return _section(
      icon: Icons.savings_rounded,
      title: 'Cash & bank position',
      sub: 'Current balances',
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('Total money', style: _j(13, FontWeight.w600, _muted))),
          Text(Money.rs(total), style: _num(18, _ink)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in a.money)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFF4F3FF), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.key, style: _j(11, FontWeight.w600, _muted)),
                Text(Money.rs(m.value), style: _j(13.5, FontWeight.w800, m.value < 0 ? _red : _ink)),
              ]),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _pair('To receive', a.receivable, _red, () => open(context, const PartiesScreen(type: 'customer')))),
          const SizedBox(width: 10),
          Expanded(child: _pair('To pay', a.payable, _amber, () => open(context, const PartiesScreen(type: 'supplier')))),
        ]),
      ]),
    );
  }

  Widget _pair(String label, int v, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _j(11.5, FontWeight.w600, c)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(Money.rs(v), style: _num(16, _ink))),
          ]),
        ),
      );

  // ---------------------------------------------------------------- reports
  Widget _reportsGrid(DateTime from, DateTime to) {
    final items = <(String, IconData, Color, Widget)>[
      ('Profit & Loss', Icons.trending_up_rounded, _green, ProfitLossScreen(from: ymd(from), to: ymd(to))),
      ('Balance Sheet', Icons.account_balance_rounded, _blue, const BalanceSheetScreen()),
      ('GST Summary', Icons.receipt_long_rounded, const Color(0xFFEC4899), GstScreen(from: ymd(from), to: ymd(to))),
      ('Day Book', Icons.menu_book_rounded, _amber, DayBookScreen(from: ymd(from), to: ymd(to))),
      ('Trial Balance', Icons.balance_rounded, _purple, const TrialBalanceScreen()),
      ('Ledgers', Icons.library_books_rounded, const Color(0xFF14B8A6), const LedgersScreen()),
    ];
    return _section(
      icon: Icons.analytics_rounded,
      title: 'Reports',
      sub: 'Opens for the selected period',
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => open(context, it.$4),
              child: Container(
                decoration: BoxDecoration(
                  color: it.$3.withAlpha(0x12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: it.$3.withAlpha(0x26)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Icon(it.$2, color: it.$3, size: 21),
                  ),
                  const SizedBox(height: 8),
                  Text(it.$1, textAlign: TextAlign.center, style: _j(11.5, FontWeight.w700, _ink)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lowStockAndRecent(Analytics a) {
    return Column(children: [
      _section(
        icon: Icons.warning_amber_rounded,
        title: 'Low stock alerts',
        sub: '${a.lowStock.length} product${a.lowStock.length == 1 ? '' : 's'} need reorder',
        action: ('View all', () => open(context, const ProductsScreen(lowOnly: true))),
        child: a.lowStock.isEmpty
            ? const EmptyState('All products are well stocked')
            : Column(children: [
                for (final p in a.lowStock)
                  ListRow(
                    leading: ProductThumb(p, width: 42, height: 42),
                    title: p['name'] as String,
                    subtitle: 'Alert at ${p['low_stock']}',
                    trailing: '${p['stock']} left',
                    trailingColor: asInt(p['stock']) <= 0 ? _red : _amber,
                    onTap: () => open(context, ProductView(id: asInt(p['id']))),
                  ),
              ]),
      ),
      const SizedBox(height: 14),
      _section(
        icon: Icons.receipt_rounded,
        title: 'Recent invoices',
        sub: 'Latest sales',
        action: ('All', () => open(context, const SalesScreen())),
        child: a.recentSales.isEmpty
            ? const EmptyState('No invoices yet')
            : Divided([for (final s in a.recentSales) SaleRow(s)]),
      ),
    ]);
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String sub,
    required Widget child,
    (String, VoidCallback)? action,
  }) {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _purple, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: _j(15, FontWeight.w800, _ink)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w500, _muted)),
            ]),
          ),
          if (action != null)
            GestureDetector(
              onTap: action.$2,
              child: Row(children: [
                Text(action.$1, style: _j(12, FontWeight.w700, const Color(0xFF3427CF))),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF3427CF), size: 20),
              ]),
            ),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

// ---------------------------------------------------------------- hero card
class _HeroProfit extends StatelessWidget {
  final Analytics a;
  const _HeroProfit(this.a);

  @override
  Widget build(BuildContext context) {
    final c = a.change((p) => p.netProfit);
    final loss = a.cur.netProfit < 0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)],
                ),
              ),
            ),
          ),
          // glass bubbles
          Positioned(right: -40, top: -50, child: _bubble(170, 0x26)),
          Positioned(left: -30, bottom: -60, child: _bubble(150, 0x1A)),
          Positioned(right: 6, top: 16, child: Opacity(opacity: .95, child: Image.asset('assets/home/ov_art.png', width: 108))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      color: const Color(0x33FFFFFF),
                      child: Text(loss ? 'Net loss' : 'Net profit', style: _j(12, FontWeight.w700, Colors.white)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(Money.rs(a.cur.netProfit.abs()), style: _num(32, Colors.white)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(c >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 13, color: c >= 0 ? _green : _red),
                    const SizedBox(width: 2),
                    Text('${c.abs()}%', style: _j(11.5, FontWeight.w800, c >= 0 ? _green : _red)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text('vs previous period · margin ${a.cur.margin.toStringAsFixed(1)}%',
                    style: _j(11.5, FontWeight.w500, const Color(0xD9FFFFFF))),
              ]),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x40FFFFFF)),
                    ),
                    child: Row(children: [
                      _mini('Revenue', a.cur.revenue),
                      _divider(),
                      _mini('Cost of goods', a.cur.cogs),
                      _divider(),
                      _mini('Expenses', a.cur.expenses),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static Widget _bubble(double s, int alpha) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color.fromARGB(alpha, 255, 255, 255), const Color(0x00FFFFFF)]),
        ),
      );

  static Widget _divider() => Container(width: 1, height: 30, color: const Color(0x40FFFFFF));

  static Widget _mini(String label, int v) => Expanded(
        child: Column(children: [
          Text(label, style: _j(10.5, FontWeight.w500, const Color(0xCCFFFFFF))),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text(Money.compact(v), style: _j(14, FontWeight.w800, Colors.white))),
        ]),
      );
}

// ---------------------------------------------------------------- KPI tile
class _Kpi extends StatelessWidget {
  final String label, value, orb;
  final int change;
  final List<int> spark;
  final Color color;
  final bool goodWhenUp;
  final VoidCallback? onTap;
  const _Kpi(this.label, this.value, this.change, this.orb, this.spark, this.color, {this.goodWhenUp = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    final good = goodWhenUp ? change >= 0 : change <= 0;
    final c = change == 0 ? _muted : (good ? _green : _red);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: _card(r: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset('assets/home/$orb.png', width: 38, height: 38),
            const Spacer(),
            Sparkline(spark, color, width: 56, height: 24),
          ]),
          const SizedBox(height: 8),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w600, _muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: _j(17.5, FontWeight.w800, _ink)),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(change >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 11, color: c),
                Text('${change.abs()}%', style: _j(10.5, FontWeight.w800, c)),
              ]),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text('vs prev.', maxLines: 1, style: _j(10.5, FontWeight.w500, _muted))),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- bar row
class _BarRow extends StatelessWidget {
  final IconData? icon;
  final String? rankText;
  final Color color;
  final String label, value;
  final String? sub;
  final double fraction;
  const _BarRow({
    this.icon,
    this.rankText,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withAlpha(0x1F), borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: icon != null ? Icon(icon, color: color, size: 19) : Text(rankText ?? '', style: _j(14, FontWeight.w800, color)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w700, _ink))),
              const SizedBox(width: 8),
              Text(value, style: _j(12.5, FontWeight.w800, _ink)),
            ]),
            if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w500, _muted)),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(children: [
                Container(height: 6, color: const Color(0xFFF0F1F8)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction.clamp(0, 1).toDouble()),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, f, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: f,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withAlpha(0xB3), color])),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- customer row
class _CustomerRow extends StatelessWidget {
  final int rank;
  final Rec r;
  final double fraction;
  final VoidCallback onTap;
  const _CustomerRow({required this.rank, required this.r, required this.fraction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = r['name'] as String;
    final due = asInt(r['due']);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _DashboardScreenState._palette[(rank - 1) % 7].withAlpha(0x33),
                _DashboardScreenState._palette[(rank - 1) % 7].withAlpha(0x14),
              ]),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: _j(15, FontWeight.w800, _DashboardScreenState._palette[(rank - 1) % 7])),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w700, _ink))),
                Text(Money.rs(asInt(r['v'])), style: _j(12.5, FontWeight.w800, _ink)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: Text('${r['n']} invoice${asInt(r['n']) == 1 ? '' : 's'} · last ${prettyDate(r['last'] as String)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w500, _muted)),
                ),
                Text(due > 0 ? 'Due ${Money.rs(due)}' : 'Settled', style: _j(10.5, FontWeight.w700, due > 0 ? _red : _green)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0, 1).toDouble(),
                  minHeight: 5,
                  backgroundColor: const Color(0xFFF0F1F8),
                  valueColor: AlwaysStoppedAnimation(_DashboardScreenState._palette[(rank - 1) % 7]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
