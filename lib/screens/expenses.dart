import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/charts.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';

// =============================================================================
// Expenses — spending control centre.
// Period switch · hero card (total, change, daily average, month-end
// projection, % of revenue, 6-month bars) · Smart insights (recurring bills
// not yet paid this month, unusual spikes, cost ratio) · category donut with
// monthly budgets · one-tap repeat of recent expenses · searchable timeline ·
// add sheet with category grid, note-based category detection, account
// memory and receipt photo.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);

const _palette = [
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFF3B82F6),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
  Color(0xFF22C55E),
  Color(0xFF64748B),
];

TextStyle _j(double size, FontWeight w, Color c, {double? height}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
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

/// Icon for an expense head, from its name.
IconData expenseIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('rent')) return Icons.storefront_rounded;
  if (n.contains('electric')) return Icons.bolt_rounded;
  if (n.contains('salary') || n.contains('staff')) return Icons.badge_rounded;
  if (n.contains('transport') || n.contains('courier')) return Icons.local_shipping_rounded;
  if (n.contains('internet') || n.contains('phone')) return Icons.wifi_rounded;
  if (n.contains('market') || n.contains('ads')) return Icons.campaign_rounded;
  if (n.contains('repair') || n.contains('mainten')) return Icons.build_rounded;
  if (n.contains('bank')) return Icons.account_balance_rounded;
  if (n.contains('food') || n.contains('refresh')) return Icons.local_cafe_rounded;
  return Icons.receipt_rounded;
}

/// Guesses the expense head from words in the note.
int? guessHead(String note, List<Rec> heads) {
  final n = note.toLowerCase();
  const rules = {
    'rent': ['rent', 'bhara', 'ভাড়া'],
    'electric': ['electric', 'current', 'cesc', 'wbsedcl', 'light bill', 'বিদ্যুৎ'],
    'salary': ['salary', 'staff', 'wage', 'helper', 'বেতন'],
    'transport': ['transport', 'courier', 'delivery', 'petrol', 'fuel', 'auto', 'toto', 'cab', 'parcel', 'shipping'],
    'internet': ['internet', 'wifi', 'broadband', 'recharge', 'jio', 'airtel', 'mobile bill'],
    'market': ['ads', 'facebook', 'instagram', 'google', 'banner', 'poster', 'marketing', 'flex', 'leaflet'],
    'repair': ['repair', 'maintenance', 'service', 'fix', 'plumber', 'electrician', 'ac '],
    'bank': ['bank', 'charges', 'fee', 'gst late', 'penalty', 'emi'],
    'food': ['tea', 'chai', 'food', 'snack', 'lunch', 'coffee', 'water', 'biscuit', 'cha', 'খাবার'],
  };
  for (final e in rules.entries) {
    if (e.value.any(n.contains)) {
      for (final h in heads) {
        if ((h['name'] as String).toLowerCase().contains(e.key)) return asInt(h['id']);
      }
    }
  }
  return null;
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String period = 'month'; // month | last | year
  String q = '';

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      'last' => (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)),
      'year' => (DateTime(now.year, 1, 1), today),
      _ => (DateTime(now.year, now.month, 1), today),
    };
  }

  Future<(ExpenseInsights, List<Rec>)> _load() async {
    final (from, to) = _range;
    return (
      await Books.expenseInsights(from, to),
      await Books.query(
          'SELECT e.*, h.name AS head, a.name AS account FROM expenses e JOIN accounts h ON h.id = e.head_id '
          'JOIN accounts a ON a.id = e.account_id WHERE e.date >= ? AND e.date <= ? ORDER BY e.date DESC, e.id DESC',
          [ymd(from), ymd(to)]),
    );
  }

  void _add({int? headId, int? amount, int? accountId, String? note}) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ExpenseSheet(headId: headId, amount: amount, accountId: accountId, note: note),
      );

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: Live<(ExpenseInsights, List<Rec>)>(
            reloadKey: period,
            load: _load,
            builder: (context, d) => ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 110 + safe),
              children: [
                _header(),
                const SizedBox(height: 14),
                _periodBar(),
                const SizedBox(height: 14),
                _hero(d.$1),
                const SizedBox(height: 14),
                _insights(d.$1),
                const SizedBox(height: 14),
                _categories(d.$1),
                if (d.$1.repeat.isNotEmpty) ...[const SizedBox(height: 14), _repeat(d.$1)],
                const SizedBox(height: 14),
                _list(d.$2),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + safe,
          child: GestureDetector(
            onTap: () => _add(),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFDC2626)]),
                boxShadow: const [BoxShadow(color: Color(0x80DC2626), blurRadius: 20, offset: Offset(0, 8), spreadRadius: -6)],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 26),
                const SizedBox(width: 8),
                Text('Add expense', style: _j(15.5, FontWeight.w800, Colors.white)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header() => Row(children: [
        if (Navigator.of(context).canPop()) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
              ),
              child: const Icon(Icons.arrow_back_rounded, color: _ink),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Expenses', style: _j(22, FontWeight.w800, _navy)),
            Text('Spending, budgets & smart insights', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
          ]),
        ),
      ]);

  Widget _periodBar() {
    const items = [('month', 'This month'), ('last', 'Last month'), ('year', 'This year')];
    final i = items.indexWhere((e) => e.$1 == period);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: _card(r: 23),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            left: i * w,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                gradient: const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFDC2626)]),
              ),
            ),
          ),
          Row(children: [
            for (final e in items)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => period = e.$1);
                  },
                  child: Center(child: Text(e.$2, style: _j(12.5, FontWeight.w700, e.$1 == period ? Colors.white : _ink))),
                ),
              ),
          ]),
        ]);
      }),
    );
  }

  // ---------------------------------------------------------------- hero
  Widget _hero(ExpenseInsights x) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final projection = period == 'month' && now.day > 0 ? x.total * daysInMonth ~/ now.day : 0;
    final up = x.change > 0;
    final maxBar = x.months.fold<int>(1, (a, m) => math.max(a, m.sales));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4C1D95)]),
        boxShadow: const [BoxShadow(color: Color(0x664C1D95), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Total spent', style: _j(12.5, FontWeight.w600, const Color(0xCCFFFFFF)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: (up ? const Color(0xFFFF8A8A) : const Color(0xFF6EE7B7)).withAlpha(0x33), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: up ? const Color(0xFFFFB4B4) : const Color(0xFF9CF5C4)),
              Text(' ${x.change.abs()}% vs previous', style: _j(11, FontWeight.w800, up ? const Color(0xFFFFB4B4) : const Color(0xFF9CF5C4))),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(Money.rs(x.total),
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 32,
                fontWeight: FontWeight.w800,
                fontVariations: [FontVariation('wght', 800)],
                color: Colors.white,
                letterSpacing: -0.5,
              )),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _mini('Daily average', Money.compact(x.dailyAvg)),
          _mini(period == 'month' ? 'Month-end estimate' : 'Previous period', Money.compact(period == 'month' ? projection : x.previous)),
          _mini('Of revenue', x.revenue == 0 ? '—' : '${x.ofRevenue.toStringAsFixed(1)}%'),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 70,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < x.months.length; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: x.months[i].sales / maxBar),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Container(
                      width: 18,
                      height: 4 + 44 * v,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: i == x.months.length - 1
                              ? const [Color(0xFFFF8A8A), Color(0xFFF43F5E)]
                              : const [Color(0x99C4B5FD), Color(0x667C3AED)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(x.months[i].label, style: _j(10, FontWeight.w600, const Color(0xB3FFFFFF))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _mini(String l, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w500, const Color(0xB3FFFFFF))),
          const SizedBox(height: 2),
          Text(v, style: _j(15, FontWeight.w800, Colors.white)),
        ]),
      );

  // ---------------------------------------------------------------- smart insights
  Widget _insights(ExpenseInsights x) {
    final now = DateTime.now();
    final items = <Widget>[];
    for (final r in x.recurring.where((r) => !r.paidThisMonth)) {
      final overdue = now.day > r.day;
      items.add(_insight(
        overdue ? Icons.event_busy_rounded : Icons.event_rounded,
        overdue ? _red : _amber,
        '${r.name} — usually ${Money.rs(r.typical)} around day ${r.day}',
        overdue ? 'Not recorded this month yet' : 'Coming up in ${r.day - now.day} day${r.day - now.day == 1 ? '' : 's'}',
        action: ('Record', () => _add(headId: r.headId, amount: r.typical)),
      ));
    }
    for (final s in x.spikes) {
      items.add(_insight(Icons.trending_up_rounded, _red, '${s.key} is ${s.value}% above its usual level',
          'Compared with the last 3 months\' average'));
    }
    if (x.revenue > 0 && x.ofRevenue > 25) {
      items.add(_insight(Icons.pie_chart_rounded, _amber, 'Expenses are ${x.ofRevenue.toStringAsFixed(0)}% of sales revenue',
          'Healthy shops usually keep this under 15–20%'));
    }
    for (final h in x.heads) {
      final budget = x.budgets[asInt(h['id'])] ?? 0;
      if (period == 'month' && budget > 0 && asInt(h['v']) > budget) {
        items.add(_insight(Icons.savings_rounded, _red, '${h['name']} crossed its budget',
            '${Money.rs(asInt(h['v']))} of ${Money.rs(budget)}'));
      }
    }
    if (items.isEmpty) {
      items.add(_insight(Icons.verified_rounded, _green, 'Spending looks normal', 'No unusual spikes or missed regular bills'));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF5B2EE0)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Smart insights', style: _j(15, FontWeight.w800, _ink)),
        ]),
        const SizedBox(height: 6),
        ...items,
      ]),
    );
  }

  Widget _insight(IconData i, Color c, String title, String sub, {(String, VoidCallback)? action}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(11)),
            child: Icon(i, color: c, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: _j(12.5, FontWeight.w700, _ink)),
              Text(sub, style: _j(11, FontWeight.w500, _muted)),
            ]),
          ),
          if (action != null)
            GestureDetector(
              onTap: action.$2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
                child: Text(action.$1, style: _j(11.5, FontWeight.w800, _purple)),
              ),
            ),
        ]),
      );

  // ---------------------------------------------------------------- categories + budgets
  Widget _categories(ExpenseInsights x) {
    final parts = [for (final h in x.heads) MapEntry(h['name'] as String, asInt(h['v']))];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Where the money went', style: _j(15, FontWeight.w800, _ink))),
          Text('tap to set budget', style: _j(11, FontWeight.w500, _muted)),
        ]),
        const SizedBox(height: 12),
        if (parts.isEmpty)
          const EmptyState('No expenses in this period')
        else ...[
          Center(
            child: DonutChart(
              parts: parts,
              colors: _palette,
              size: 150,
              centerTop: Money.compact(x.total),
              centerBottom: '${parts.length} categor${parts.length == 1 ? 'y' : 'ies'}',
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < x.heads.length; i++) _catRow(x, x.heads[i], _palette[i % _palette.length]),
        ],
      ]),
    );
  }

  Widget _catRow(ExpenseInsights x, Rec h, Color c) {
    final v = asInt(h['v']);
    final budget = x.budgets[asInt(h['id'])] ?? 0;
    final frac = budget > 0 ? v / budget : (x.total == 0 ? 0.0 : v / x.total);
    final over = budget > 0 && v > budget;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _setBudget(asInt(h['id']), h['name'] as String, budget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(12)),
            child: Icon(expenseIcon(h['name'] as String), color: c, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(h['name'] as String, style: _j(13, FontWeight.w700, _ink))),
                Text(Money.rs(v), style: _j(13, FontWeight.w800, _ink)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac.clamp(0.0, 1.0).toDouble(),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF0F1F8),
                  valueColor: AlwaysStoppedAnimation(over ? _red : c),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                budget > 0
                    ? '${(v * 100 / budget).round()}% of ${Money.compact(budget)} budget${over ? ' — over by ${Money.compact(v - budget)}' : ''}'
                    : '${h['n']} entr${asInt(h['n']) == 1 ? 'y' : 'ies'} · ${x.total == 0 ? 0 : (v * 100 / x.total).round()}% of total',
                style: _j(10.5, FontWeight.w600, over ? _red : _muted),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _setBudget(int headId, String name, int current) async {
    final c = TextEditingController(text: current > 0 ? Money.edit(current) : '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Monthly budget · $name'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ ', hintText: '0 = no budget'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (r == null) return;
    try {
      await Books.setBudget(headId, Money.parse(r));
    } catch (_) {
      if (mounted) toast(context, 'Enter a valid amount', error: true);
    }
  }

  // ---------------------------------------------------------------- repeat
  Widget _repeat(ExpenseInsights x) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.replay_rounded, size: 17, color: _purple),
          const SizedBox(width: 6),
          Text('Repeat a recent expense', style: _j(12.5, FontWeight.w700, const Color(0xFF3A4155))),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final r in x.repeat)
              GestureDetector(
                onTap: () => _add(
                  headId: asInt(r['head_id']),
                  amount: asInt(r['amount']),
                  accountId: asInt(r['account_id']),
                  note: r['note'] as String?,
                ),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: _card(r: 16),
                  child: Row(children: [
                    Icon(expenseIcon(r['head'] as String), size: 18, color: _red),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['head'] as String, style: _j(12, FontWeight.w700, _ink)),
                      Text(Money.rs(asInt(r['amount'])), style: _j(11.5, FontWeight.w800, _red)),
                    ]),
                  ]),
                ),
              ),
          ]),
        ),
      ]);

  // ---------------------------------------------------------------- list
  Widget _list(List<Rec> rows) {
    final filtered = rows
        .where((e) => q.isEmpty || '${e['head']} ${e['note'] ?? ''} ${e['account']}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    final byDate = <String, List<Rec>>{};
    for (final e in filtered) {
      byDate.putIfAbsent(e['date'] as String, () => []).add(e);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('All expenses', style: _j(15, FontWeight.w800, _ink))),
          Text('${filtered.length}', style: _j(12, FontWeight.w700, _muted)),
        ]),
        const SizedBox(height: 10),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFFF4F5FB), borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: _muted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => q = v.trim()),
                style: _j(13.5, FontWeight.w600, _ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Search category, note, account',
                  hintStyle: _j(13, FontWeight.w400, const Color(0xFF8A8FAD)),
                ),
              ),
            ),
          ]),
        ),
        if (filtered.isEmpty) const EmptyState('Nothing here'),
        for (final g in byDate.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Row(children: [
              Text(_dayLabel(g.key).toUpperCase(), style: _j(11, FontWeight.w800, _muted).copyWith(letterSpacing: 1)),
              const Spacer(),
              Text(Money.rs(g.value.fold<int>(0, (a, e) => a + asInt(e['amount']))), style: _j(11.5, FontWeight.w800, _muted)),
            ]),
          ),
          for (final e in g.value) _row(e),
        ],
      ]),
    );
  }

  String _dayLabel(String d) {
    final now = DateTime.now();
    if (d == ymd(now)) return 'Today';
    if (d == ymd(now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return prettyDate(d);
  }

  Widget _row(Rec e) {
    final img = e['image'] as String?;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: img == null || img.isEmpty
          ? null
          : () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: storedImage(img, fit: BoxFit.contain),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFFFECEC), borderRadius: BorderRadius.circular(12)),
            child: Icon(expenseIcon(e['head'] as String), color: _red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['head'] as String, style: _j(13.5, FontWeight.w700, _ink)),
              Text([e['account'], if ((e['note'] as String? ?? '').isNotEmpty) e['note']].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w500, _muted)),
            ]),
          ),
          if (img != null && img.isNotEmpty) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.image_rounded, size: 17, color: _purple)),
          Text('−${Money.rs(asInt(e['amount']))}', style: _j(13.5, FontWeight.w800, _red)),
        ]),
      ),
    );
  }
}

// =============================================================================
// Add expense
// =============================================================================
class ExpenseSheet extends StatefulWidget {
  final int? headId, amount, accountId;
  final String? note;
  const ExpenseSheet({super.key, this.headId, this.amount, this.accountId, this.note});
  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  late final amount = TextEditingController(text: widget.amount == null ? '' : Money.edit(widget.amount!));
  late final note = TextEditingController(text: widget.note ?? '');
  List<Rec> heads = [], accounts = [];
  int? head, account;
  bool headPicked = false;
  int? suggested;
  String date = ymd(DateTime.now());
  String? image;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    head = widget.headId;
    headPicked = widget.headId != null;
    account = widget.accountId;
    note.addListener(() {
      final g = guessHead(note.text, heads);
      if (g != suggested) setState(() => suggested = g);
    });
    _load();
  }

  Future<void> _load() async {
    heads = await Books.accounts(kind: 'expense');
    accounts = await Books.moneyAccounts();
    final st = await Books.settings();
    final last = int.tryParse(st['last_expense_account'] ?? '');
    account ??= (last != null && accounts.any((a) => asInt(a['id']) == last)) ? last : (accounts.isNotEmpty ? asInt(accounts.first['id']) : null);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _newHead() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New expense category'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Cleaning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final id = await Books.addExpenseHead(name);
    heads = await Books.accounts(kind: 'expense');
    setState(() {
      head = id;
      headPicked = true;
    });
  }

  Future<void> _save() async {
    if (saving) return;
    final h = head ?? suggested;
    if (h == null) {
      toast(context, 'Choose a category', error: true);
      return;
    }
    int amt;
    try {
      amt = Money.parse(amount.text);
    } catch (_) {
      amt = 0;
    }
    if (amt <= 0) {
      toast(context, 'Enter the amount', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await Books.createExpense(
        headId: h,
        amount: amt,
        accountId: account ?? 0,
        date: date,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        image: image,
      );
      if (account != null) await Books.setSetting('last_expense_account', '$account');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      toast(context, 'Expense saved');
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = head ?? (headPicked ? null : suggested);
    return Container(
      decoration: const BoxDecoration(color: _bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(height: 14),
            Text('Add expense', style: _j(19, FontWeight.w800, _navy)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: _card(r: 20),
              child: Row(children: [
                Text('₹', style: _j(30, FontWeight.w800, _red)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: amount,
                    autofocus: widget.amount == null,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: _j(30, FontWeight.w800, _ink),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: '0',
                      hintStyle: _j(30, FontWeight.w800, const Color(0xFFD5D8EA)),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _card(r: 16),
              child: TextField(
                controller: note,
                style: _j(13.5, FontWeight.w600, _ink),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF8B7FD6)),
                  hintText: 'What was it for? (e.g. tea for staff, courier)',
                  hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
                ),
              ),
            ),
            if (suggested != null && !headPicked) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, size: 15, color: _purple),
                const SizedBox(width: 6),
                Text('Smart category: ${heads.firstWhere((h) => asInt(h['id']) == suggested, orElse: () => const {'name': ''})['name']}',
                    style: _j(12, FontWeight.w700, _purple)),
              ]),
            ],
            const SizedBox(height: 14),
            Text('Category', style: _j(12.5, FontWeight.w700, const Color(0xFF3A4155))),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .95,
              children: [
                for (var i = 0; i < heads.length; i++)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        head = asInt(heads[i]['id']);
                        headPicked = true;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: selected == asInt(heads[i]['id']) ? _palette[i % _palette.length].withAlpha(0x26) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected == asInt(heads[i]['id']) ? _palette[i % _palette.length] : _line,
                          width: selected == asInt(heads[i]['id']) ? 1.6 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(expenseIcon(heads[i]['name'] as String), color: _palette[i % _palette.length], size: 22),
                        const SizedBox(height: 4),
                        Text(heads[i]['name'] as String,
                            maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: _j(10, FontWeight.w700, _ink, height: 1.15)),
                      ]),
                    ),
                  ),
                GestureDetector(
                  onTap: _newHead,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F3FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCFC4FF)),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_rounded, color: _purple),
                      Text('New', style: _j(10.5, FontWeight.w800, _purple)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Paid from', style: _j(12.5, FontWeight.w700, const Color(0xFF3A4155))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in accounts)
                GestureDetector(
                  onTap: () => setState(() => account = asInt(a['id'])),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: account == asInt(a['id']) ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                      color: account == asInt(a['id']) ? null : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: account == asInt(a['id']) ? null : Border.all(color: _line),
                    ),
                    child: Text(a['name'] as String, style: _j(12.5, FontWeight.w700, account == asInt(a['id']) ? Colors.white : _ink)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(date),
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) setState(() => date = ymd(d));
                  },
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: _card(r: 16),
                    child: Row(children: [
                      const Icon(Icons.event_rounded, color: _purple, size: 20),
                      const SizedBox(width: 8),
                      Text(date == ymd(DateTime.now()) ? 'Today' : prettyDate(date), style: _j(13.5, FontWeight.w700, _ink)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  final r = await pickPhoto(context, folder: 'receipts', allowRemove: image != null);
                  if (r != null) setState(() => image = r.isEmpty ? null : r);
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: _card(r: 16),
                  clipBehavior: Clip.antiAlias,
                  child: image == null ? const Icon(Icons.add_a_photo_rounded, color: _purple) : storedImage(image),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _save,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFDC2626)]),
                  boxShadow: const [BoxShadow(color: Color(0x80DC2626), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
                ),
                alignment: Alignment.center,
                child: saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text('Save expense', style: _j(15, FontWeight.w800, Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
