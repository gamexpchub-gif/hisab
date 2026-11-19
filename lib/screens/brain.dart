import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/brain.dart';
import '../core/money.dart';
import '../ui/voice.dart';
import '../ui/widgets.dart';
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
      subtitle: 'Ask anything · forecast · alerts · customer scores',
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            _tab(0, Icons.forum_rounded, 'Ask'),
            _tab(1, Icons.insights_rounded, 'Forecast'),
            _tab(2, Icons.gpp_maybe_rounded, 'Alerts'),
            _tab(3, Icons.shield_rounded, 'Scores'),
          ]),
        ),
        const SizedBox(height: 12),
        switch (tab) { 0 => const _AskTab(), 1 => const _ForecastTab(), 2 => const _AlertsTab(), _ => const _ScoresTab() },
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
// Ask
// =============================================================================
class _AskTab extends StatefulWidget {
  const _AskTab();
  @override
  State<_AskTab> createState() => _AskTabState();
}

class _AskTabState extends State<_AskTab> {
  final q = TextEditingController();
  final chat = <(String, Answer?)>[];
  bool busy = false;

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> _ask(String text) async {
    text = text.trim();
    if (text.isEmpty || busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      busy = true;
      chat.insert(0, (text, null));
      q.clear();
    });
    Answer a;
    try {
      a = await Brain.ask(text);
      await Brain.remember(text);
    } catch (e) {
      a = Answer('Sorry, I could not work that out ($e)');
    }
    if (!mounted) return;
    setState(() {
      chat[0] = (text, a);
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2)]),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFE08A)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: q,
              textInputAction: TextInputAction.search,
              onSubmitted: _ask,
              style: _j(14.5, FontWeight.w700, Colors.white),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Ask: last month profit on Vivo…',
                hintStyle: _j(13, FontWeight.w500, Colors.white54),
              ),
            ),
          ),
          IconButton(
            onPressed: () async {
              final t = await VoiceSheet.listen(context, title: 'Ask Hisab AI', hint: 'e.g. gato mash-e Vivo-te koto labh?');
              if (t != null) await _ask(t);
            },
            icon: const Icon(Icons.mic_rounded, color: Colors.white),
          ),
          IconButton(onPressed: () => _ask(q.text), icon: const Icon(Icons.send_rounded, color: Colors.white)),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in Brain.examples)
          ActionChip(
            label: Text(e, style: _j(11.5, FontWeight.w700, const Color(0xFF4318D2))),
            backgroundColor: const Color(0xFFEFEAFF),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onPressed: () => _ask(e),
          ),
      ]),
      for (final (question, answer) in chat) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF4318D2),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18)),
            ),
            child: Text(question, style: _j(13.5, FontWeight.w700, Colors.white)),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _card(),
          child: answer == null
              ? const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Thinking…')])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.smart_toy_rounded, color: Color(0xFF4318D2), size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(answer.text, style: _j(15, FontWeight.w800, _ink))),
                  ]),
                  if (answer.detail != null) ...[
                    const SizedBox(height: 4),
                    Padding(padding: const EdgeInsets.only(left: 28), child: Text(answer.detail!, style: _j(12, FontWeight.w600, _muted))),
                  ],
                  if (answer.rows.isNotEmpty) ...[
                    const Divider(height: 18),
                    for (final (l, v) in answer.rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w600, _ink))),
                          Text(v, style: _j(12.5, FontWeight.w800, _ink)),
                        ]),
                      ),
                  ],
                ]),
        ),
      ],
      if (chat.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: EmptyState('Ask about sales, profit, stock, dues, expenses or purchases — any day, week, month or brand'),
        ),
    ]);
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
