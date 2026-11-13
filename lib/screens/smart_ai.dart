import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/insights.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/widgets.dart';
import 'emi.dart';
import 'party_profile.dart';
import 'products.dart';
import 'sale_view.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

(IconData, List<Color>) _look(Insight i) {
  final icon = switch (i.kind) {
    'due' || 'collect' => Icons.currency_rupee_rounded,
    'emi' => Icons.calendar_month_rounded,
    'warranty' => Icons.verified_user_rounded,
    'stock' => Icons.inventory_2_rounded,
    'dead' => Icons.hourglass_bottom_rounded,
    'best' => Icons.local_fire_department_rounded,
    'trend' => Icons.trending_up_rounded,
    'loss' => Icons.trending_down_rounded,
    'margin' => Icons.pie_chart_rounded,
    'today' => Icons.celebration_rounded,
    _ => Icons.auto_awesome_rounded,
  };
  final colors = switch (i.level) {
    'urgent' => const [Color(0xFFFF5C7A), Color(0xFFD81E4A)],
    'warn' => const [Color(0xFFFFB547), Color(0xFFE38A0B)],
    'good' => const [Color(0xFF3EE08F), Color(0xFF0E9F5E)],
    _ => const [Color(0xFF8B5CF6), Color(0xFF4318D2)],
  };
  return (icon, colors);
}

/// Opens what an insight is about.
void openInsight(BuildContext context, Insight i) {
  final id = i.targetId;
  switch (i.target) {
    case 'customer' || 'supplier' when id != null:
      open(context, PartyView(type: i.target!, id: id));
    case 'product' when id != null:
      open(context, ProductView(id: id));
    case 'emi' when id != null:
      open(context, EmiPlanView(id: id));
    case 'sale' when id != null:
      open(context, SaleView(id: id));
    case 'low':
      open(context, const ProductsScreen(lowOnly: true));
    default:
      open(context, const SmartAiScreen());
  }
}

Future<void> whatsappInsight(BuildContext context, Insight i) async {
  if (i.message == null) return;
  HapticFeedback.selectionClick();
  final ok = await Contact.whatsapp(i.phone, i.message!);
  if (!ok && context.mounted) toast(context, 'WhatsApp khola gelo na — message copy kora holo');
}

/// The "Smart AI" strip at the top of Home: the most important suggestions,
/// sliding every few seconds.
class SmartAiStrip extends StatefulWidget {
  final List<Insight> items;
  final double scale;
  const SmartAiStrip(this.items, {super.key, this.scale = 1});
  @override
  State<SmartAiStrip> createState() => _SmartAiStripState();
}

class _SmartAiStripState extends State<SmartAiStrip> {
  final page = PageController();
  Timer? timer;
  int index = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.items.length < 2 || !page.hasClients) return;
      final next = (index + 1) % widget.items.take(6).length;
      page.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items.take(6).toList();
    final urgent = widget.items.where((i) => i.level == 'urgent').length;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B1F6B), Color(0xFF4318D2), Color(0xFF7B3FF2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Color(0x404318D2), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => open(context, const SmartAiScreen()),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFFFE08A)),
                const SizedBox(width: 5),
                Text('Smart AI', style: _j(11.5, FontWeight.w800, Colors.white)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                items.isEmpty
                    ? 'Shob thik ache — kono kaj baki nei ✓'
                    : urgent > 0
                        ? '$urgent ta jinish aaj-i dekhun'
                        : '${widget.items.length} ta suggestion',
                style: _j(11.5, FontWeight.w600, const Color(0xCCFFFFFF)),
              ),
            ),
            Text('Shob dekhun ›', style: _j(11.5, FontWeight.w800, Colors.white)),
          ]),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: PageView.builder(
              controller: page,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => index = i),
              itemBuilder: (context, n) {
                final it = items[n];
                final (icon, colors) = _look(it);
                return GestureDetector(
                  onTap: () => openInsight(context, it),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: colors)),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, Colors.white)),
                        const SizedBox(height: 2),
                        Text(it.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w500, const Color(0xD9FFFFFF))),
                      ]),
                    ),
                    if (it.message != null)
                      GestureDetector(
                        onTap: () => whatsappInsight(context, it),
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF25D366)),
                          child: const Icon(Icons.chat_rounded, color: Colors.white, size: 19),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
          if (items.length > 1)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: i == index ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : const Color(0x55FFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
        ],
      ]),
    );
  }
}

/// Every suggestion, grouped: do today, watch, going well, good to know.
class SmartAiScreen extends StatelessWidget {
  const SmartAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<Insight>>(
      load: Insights.build,
      builder: (context, items) {
        final groups = [
          ('urgent', 'Aaj-i korun', Icons.priority_high_rounded),
          ('warn', 'Nojor rakhun', Icons.visibility_rounded),
          ('good', 'Bhalo cholche', Icons.thumb_up_alt_rounded),
          ('info', 'Jene rakhun', Icons.lightbulb_rounded),
        ];
        final urgent = items.where((i) => i.level == 'urgent').toList();
        final collect = urgent.where((i) => i.amount != null && (i.kind == 'due' || i.kind == 'emi')).fold<int>(0, (a, i) => a + i.amount!);
        return PageShell(
          title: 'Smart Business AI',
          subtitle: items.isEmpty ? 'Shob thik ache' : '${items.length} suggestion · protibar hisab bodlale update hoy',
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2), Color(0xFF7B3FF2)]),
              ),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFE08A), size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(urgent.isEmpty ? 'Aaj kono joruri kaj nei 🎉' : '${urgent.length} ta joruri kaj',
                        style: _j(17, FontWeight.w800, Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                        collect > 0
                            ? 'Aaj ${Money.rs(collect)} collect korar ache — niche WhatsApp button-e ek tap-e reminder pathan'
                            : 'Apnar bikri, stock, baki ar EMI dekhe AI ei suggestion gulo diyeche',
                        style: _j(12, FontWeight.w500, const Color(0xD9FFFFFF))),
                  ]),
                ),
              ]),
            ),
            for (final g in groups)
              if (items.any((i) => i.level == g.$1)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Row(children: [
                    Icon(g.$3, size: 18, color: _ink),
                    const SizedBox(width: 6),
                    Text(g.$2, style: _j(15, FontWeight.w800, _ink)),
                  ]),
                ),
                for (final it in items.where((i) => i.level == g.$1)) _InsightCard(it),
              ],
            if (items.isEmpty) const EmptyState('Kono suggestion nei — bikri korle AI shikhe suggestion debe'),
          ],
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Insight it;
  const _InsightCard(this.it);

  @override
  Widget build(BuildContext context) {
    final (icon, colors) = _look(it);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F2F9)),
        boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -6)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: it.target == null ? null : () => openInsight(context, it),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: colors)),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.title, style: _j(14, FontWeight.w800, _ink)),
                  const SizedBox(height: 3),
                  Text(it.text, style: _j(12, FontWeight.w500, _muted)),
                ]),
              ),
              if (it.message != null)
                IconButton(
                  tooltip: 'WhatsApp reminder',
                  onPressed: () => whatsappInsight(context, it),
                  icon: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF25D366)),
                    child: const Icon(Icons.chat_rounded, color: Colors.white, size: 19),
                  ),
                )
              else if (it.target != null)
                const Icon(Icons.chevron_right_rounded, color: _muted),
            ]),
          ),
        ),
      ),
    );
  }
}
