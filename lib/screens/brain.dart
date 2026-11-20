import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/brain.dart';
import '../core/money.dart';
import '../ui/widgets.dart';
import 'ai_assistant.dart';
import 'party_profile.dart';
import 'products.dart';
import 'sale_view.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF0BA360);
const _red = Color(0xFFE0245E);
const _amber = Color(0xFFF97316);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

BoxDecoration _card() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x0F1B2163), blurRadius: 16, offset: Offset(0, 6))],
    );

Color scoreColor(int s) => s >= 80 ? _green : s >= 60 ? const Color(0xFF2563EB) : s >= 40 ? _amber : _red;

/// A small "credit score" badge for a customer.
class ScoreBadge extends StatelessWidget {
  final CustomerScore score;
  final bool compact;
  const ScoreBadge(this.score, {super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final c = scoreColor(score.score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield_rounded, size: 13, color: c),
        const SizedBox(width: 4),
        Text(compact ? '${score.score}' : '${score.score} · ${score.label}', style: _j(11, FontWeight.w800, c)),
      ]),
    );
  }
}

/// AI Brain: ask questions, forecast, mistake / theft alerts, customer scores.
class BrainScreen extends StatefulWidget {
  final int tab;
  const BrainScreen({super.key, this.tab = 0});
  @override
  State<BrainScreen> createState() => _BrainScreenState();
}

class _BrainScreenState extends State<BrainScreen> {
  late int tab = widget.tab;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'AI Brain',
      subtitle: 'Make bills by typing or speaking · forecast · alerts · scores',
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            _tab(0, Icons.auto_awesome_rounded, 'Assistant'),
            _tab(1, Icons.insights_rounded, 'Forecast'),
            _tab(2, Icons.gpp_maybe_rounded, 'Alerts'),
            _tab(3, Icons.shield_rounded, 'Scores'),
          ]),
        ),
        const SizedBox(height: 12),
        switch (tab) { 0 => const AiAssistant(), 1 => const _ForecastTab(), 2 => const _AlertsTab(), _ => const _ScoresTab() },
      ],
    );
  }

  Widget _tab(int i, IconData icon, String label) {
    final on = tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => tab = i);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: on ? Colors.white : _muted),
            Text(label, style: _j(10.5, FontWeight.w800, on ? Colors.white : _muted)),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// Forecast
// =============================================================================
class _ForecastTab extends StatelessWidget {
  const _ForecastTab();

  @override
  Widget build(BuildContext context) {
    return Live<Forecast>(
      load: Brain.forecast,
      builder: (context, f) {
        final parts = f.month.split('-');
        final name = '${monthName(int.parse(parts[1]))} ${parts[0]}';
        final max = [...f.history.map((h) => h.$2), f.sales].fold<int>(1, (a, v) => v > a ? v : a);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF0E7490), Color(0xFF4318D2)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Expected sales · $name', style: _j(12.5, FontWeight.w600, const Color(0xD9FFFFFF))),
              const SizedBox(height: 4),
              Text(Money.rs(f.sales), style: _j(30, FontWeight.w800, Colors.white)),
              Text('Likely between ${Money.compact(f.low)} and ${Money.compact(f.high)}', style: _j(12, FontWeight.w600, const Color(0xD9FFFFFF))),
              if (f.festival != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      '🎉 ${f.festival} · ${f.season >= 1 ? '+' : ''}${((f.season - 1) * 100).round()}% season effect — stock up early',
                      style: _j(11.5, FontWeight.w700, Colors.white)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Monthly sales', style: _j(14, FontWeight.w800, _ink)),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final (l, v) in [...f.history, ('Next', f.sales)])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text(Money.compact(v), style: _j(8.5, FontWeight.w700, _muted)),
                          const SizedBox(height: 3),
                          Container(
                            height: 100 * v / max + 2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: l == 'Next' ? const [Color(0xFFFFB84D), Color(0xFFF97316)] : const [Color(0xFF7B4DFF), Color(0xFF4318D2)],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(l, style: _j(9.5, FontWeight.w700, l == 'Next' ? _amber : _muted)),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Text('* this month so far · the forecast uses your trend, the season and last year', style: _j(10.5, FontWeight.w500, _muted)),
            ]),
          ),
          if (f.brands.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text('Brands next 30 days', style: _j(15, FontWeight.w800, _ink))),
            Container(
              decoration: _card(),
              child: Column(children: [
                for (final b in f.brands)
                  ListTile(
                    title: Text(b.brand, style: _j(14, FontWeight.w800, _ink)),
                    subtitle: Text('${b.units30} sold last 30 days', style: _j(11.5, FontWeight.w500, _muted)),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('~${b.forecast} pcs', style: _j(14, FontWeight.w800, _ink)),
                      Text('${b.changePct >= 0 ? '▲' : '▼'} ${b.changePct.abs()}%', style: _j(11, FontWeight.w800, b.changePct >= 0 ? _green : _red)),
                    ]),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}

// =============================================================================
// Alerts
// =============================================================================
class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context) {
    return Live<List<Flag>>(
      load: Brain.flags,
      builder: (context, flags) {
        final high = flags.where((f) => f.level == 'high').length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(colors: flags.isEmpty ? const [Color(0xFF0BA360), Color(0xFF0E7490)] : const [Color(0xFFE0245E), Color(0xFF7B3FF2)]),
            ),
            child: Row(children: [
              Icon(flags.isEmpty ? Icons.verified_rounded : Icons.gpp_maybe_rounded, color: Colors.white, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(flags.isEmpty ? 'Books look clean ✓' : '${flags.length} thing${flags.length == 1 ? '' : 's'} to check',
                      style: _j(17, FontWeight.w800, Colors.white)),
                  Text(
                      flags.isEmpty
                          ? 'No IMEI mismatch, negative stock, loss sale or big discount in 60 days'
                          : '$high serious · IMEI, stock, loss sales and big discounts (60 days)',
                      style: _j(12, FontWeight.w500, const Color(0xD9FFFFFF))),
                ]),
              ),
            ]),
          ),
          for (final f in flags)
            Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: _card(),
              child: ListTile(
                leading: Icon(
                  switch (f.kind) {
                    'imei_not_bought' || 'imei_twice' => Icons.qr_code_2_rounded,
                    'negative_stock' => Icons.inventory_2_rounded,
                    'below_cost' => Icons.trending_down_rounded,
                    _ => Icons.percent_rounded,
                  },
                  color: f.level == 'high' ? _red : _amber,
                ),
                title: Text(f.title, style: _j(13.5, FontWeight.w800, _ink)),
                subtitle: Text(f.detail, style: _j(11.5, FontWeight.w500, _muted)),
                trailing: f.targetId == null ? null : const Icon(Icons.chevron_right_rounded),
                onTap: f.targetId == null
                    ? null
                    : () {
                        if (f.target == 'sale') {
                          open(context, SaleView(id: f.targetId!));
                        } else if (f.target == 'product') {
                          open(context, ProductView(id: f.targetId!));
                        }
                      },
              ),
            ),
        ]);
      },
    );
  }
}

// =============================================================================
// Customer scores
// =============================================================================
class _ScoresTab extends StatelessWidget {
  const _ScoresTab();

  @override
  Widget build(BuildContext context) {
    return Live<List<(Rec, CustomerScore)>>(
      load: Brain.customerScores,
      builder: (context, list) {
        if (list.isEmpty) return const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('Scores appear once customers have bills'));
        final risky = list.where((x) => x.$2.score < 40).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2)])),
            child: Text(
              risky == 0 ? 'No risky customers 👍  Scores use dues, late days, reminders and loyalty' : '$risky risky customer${risky == 1 ? '' : 's'} — take cash or an advance',
              style: _j(14, FontWeight.w800, Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          for (final (c, s) in list)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: _card(),
              child: ListTile(
                onTap: () => open(context, PartyView(type: 'customer', id: asInt(c['id']))),
                leading: CircleAvatar(
                  backgroundColor: scoreColor(s.score).withAlpha(0x22),
                  child: Text('${s.score}', style: _j(13, FontWeight.w800, scoreColor(s.score))),
                ),
                title: Text('${c['name']}', style: _j(14, FontWeight.w800, _ink)),
                subtitle: Text(
                  [
                    s.label,
                    if (s.due > 0) 'owes ${Money.rs(s.due)}${s.daysLate > 0 ? ' · ${s.daysLate} days' : ''}',
                    '${s.bills} bill${s.bills == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: _j(11.5, FontWeight.w600, scoreColor(s.score)),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
