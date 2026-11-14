import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud.dart';
import '../core/plan.dart';
import '../core/stores.dart';
import '../ui/widgets.dart';
import 'login.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _green = Color(0xFF16A36A);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

const planColors = <String, List<Color>>{
  'basic': [Color(0xFF6AA5FF), Color(0xFF1A47C8)],
  'gold': [Color(0xFFFFC14D), Color(0xFFE08A00)],
  'premium': [Color(0xFF8B5CF6), Color(0xFF1B1F6B)],
  'trial': [Color(0xFF3EE08F), Color(0xFF0E9F5E)],
  'none': [Color(0xFFFF7A9A), Color(0xFFD81E4A)],
};

const _planIcon = <String, IconData>{
  'basic': Icons.storefront_rounded,
  'gold': Icons.workspace_premium_rounded,
  'premium': Icons.diamond_rounded,
};

/// True when the plan opens [feature]; otherwise shows the upgrade sheet.
bool gate(BuildContext context, String feature) {
  if (Sub.can(feature)) return true;
  showUpgrade(context, feature);
  return false;
}

Future<void> showUpgrade(BuildContext context, String feature) {
  final f = Sub.feature(feature);
  final need = Sub.need(feature);
  final p = plans.firstWhere((x) => x.name == need);
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (c) => Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: planColors[p.id]!)),
          child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 12),
        Text(f?.name ?? 'Ei feature', textAlign: TextAlign.center, style: _j(19, FontWeight.w800, _ink)),
        const SizedBox(height: 6),
        Text(
          Sub.tier == 0
              ? 'Apnar plan-er meyad shesh. ${p.name} ba tar upore plan nile eta chalu hobe.'
              : 'Eta ${p.name} plan (₹${p.price}/mash) theke pawa jay. Apnar ekhon ${Sub.label} plan.',
          textAlign: TextAlign.center,
          style: _j(13, FontWeight.w500, _muted),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: planColors[p.id]!.last, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
            onPressed: () {
              Navigator.pop(c);
              open(context, const PlansScreen());
            },
            child: Text('Plan dekhun · ${p.name} ₹${p.price}', style: _j(15, FontWeight.w800, Colors.white)),
          ),
        ),
      ]),
    ),
  );
}

/// Small plan badge (Home / Menu).
class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final id = Sub.admin ? 'premium' : !Sub.active ? 'none' : Sub.plan;
    return GestureDetector(
      onTap: () => open(context, const PlansScreen()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(gradient: LinearGradient(colors: planColors[id] ?? planColors['premium']!), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Sub.admin ? Icons.shield_rounded : _planIcon[id] ?? Icons.bolt_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
              Sub.admin
                  ? 'Admin'
                  : !Sub.active
                      ? 'Expired'
                      : '${Sub.label}${Sub.daysLeft <= 7 ? ' · ${Sub.daysLeft}d' : ''}',
              style: _j(11, FontWeight.w800, Colors.white)),
        ]),
      ),
    );
  }
}

// =============================================================================
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool yearly = true;
  int months = 1; // monthly mode: 1 / 3 / 6
  bool syncing = false;

  int get term => yearly ? 12 : months;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() => syncing = true);
    await Accounts.sync();
    if (mounted) setState(() => syncing = false);
  }

  Future<void> _request(PlanDef p) async {
    await Cloud.load();
    if (!mounted) return;
    if (Cloud.user == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Account login korun'),
          content: const Text('Plan nite Hisab AI account lagbe — login ba notun account khulun.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Pore')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Login')),
          ],
        ),
      );
      if (ok == true && mounted) {
        await open(context, LoginScreen(fromSettings: true, onDone: () => Navigator.of(context).pop()));
        await _sync();
      }
      return;
    }
    final note = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.name} plan · ${yearly ? '1 bochor' : '$months mash'}', style: _j(19, FontWeight.w800, _ink)),
            const SizedBox(height: 4),
            Text('Mot ₹${inr(p.amount(term))}', style: _j(26, FontWeight.w800, planColors[p.id]!.last)),
            const SizedBox(height: 10),
            Text('Taka pathanor por niche UTR / transaction ID ba note likhun. Admin check kore plan chalu kore deben.',
                style: _j(12.5, FontWeight.w500, _muted)),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'UTR / note (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: planColors[p.id]!.last, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                onPressed: () => Navigator.pop(c, true),
                child: Text('Request pathan', style: _j(15, FontWeight.w800, Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (go != true || !mounted) return;
    try {
      await Accounts.requestPlan(p.id, term, note.text);
      if (!mounted) return;
      toast(context, 'Request pathano holo — approve hole plan nijei chalu hobe');
      setState(() {});
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Live<(int, int)>(
      load: Sub.usage,
      builder: (context, u) {
        final d = Sub.def;
        final curId = Sub.admin ? 'premium' : !Sub.active ? 'none' : Sub.plan;
        return PageShell(
          title: 'Hisab AI Plans',
          subtitle: syncing ? 'Account check hocche…' : 'Apnar business-er jonno thik plan',
          children: [
            const SizedBox(height: 6),
            // current plan
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(colors: planColors[curId] ?? planColors['premium']!, begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Apnar plan', style: _j(12.5, FontWeight.w600, const Color(0xD9FFFFFF))),
                  const Spacer(),
                  if (Sub.pending != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(8)),
                      child: Text('Request: ${Sub.pending}', style: _j(11, FontWeight.w800, Colors.white)),
                    ),
                ]),
                Text(Sub.label, style: _j(28, FontWeight.w800, Colors.white)),
                Text(
                  Sub.admin
                      ? 'Shob feature, kono limit nei'
                      : !Sub.active
                          ? 'Meyad shesh — notun bill / product korte plan nin'
                          : '${Sub.daysLeft} din baki · ${Sub.until == null ? '' : '${Sub.until!.day}/${Sub.until!.month}/${Sub.until!.year} porjonto'}',
                  style: _j(12.5, FontWeight.w600, const Color(0xE6FFFFFF)),
                ),
                if (!Sub.admin && d != null) ...[
                  const SizedBox(height: 14),
                  _usage('Product (30 din)', u.$1, d.products),
                  _usage('Bill (30 din)', u.$2, d.sales),
                  _usage('Store', Stores.all.length, d.stores),
                ],
                const SizedBox(height: 10),
                Text('${featurePercent(Sub.tier)}% feature chalu', style: _j(12, FontWeight.w800, Colors.white)),
              ]),
            ),
            const SizedBox(height: 14),
            _billing(),
            const SizedBox(height: 6),
            for (final p in plans) _planCard(p, current: !Sub.admin && Sub.active && Sub.plan == p.id),
            const SizedBox(height: 16),
            _showcase(),
            const SizedBox(height: 12),
            _compare(),
            const SizedBox(height: 12),
            Text('Online payment shiggiri ashche. Ekhon: taka pathiye request korun, admin approve korle plan chalu.',
                textAlign: TextAlign.center, style: _j(11.5, FontWeight.w500, _muted)),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  static String inr(int v) {
    final s = '$v';
    if (s.length <= 3) return s;
    final last = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last';
  }

  Widget _billing() {
    final best = plans.map((p) => p.yearSavingPct).fold<int>(0, (a, b) => a > b ? a : b);
    Widget seg(bool y, String l, String? badge) => Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => yearly = y);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: yearly == y ? const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF5B2EE0)]) : null,
                boxShadow: yearly == y ? const [BoxShadow(color: Color(0x405B2EE0), blurRadius: 12, offset: Offset(0, 5))] : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(l, style: _j(14, FontWeight.w800, yearly == y ? Colors.white : _ink)),
                if (badge != null) Text(badge, style: _j(10.5, FontWeight.w800, yearly == y ? const Color(0xFF7CF2B4) : _green)),
              ]),
            ),
          ),
        );
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        child: Row(children: [
          seg(false, 'Mashik', null),
          seg(true, 'Bochorik', best > 0 ? 'Save up to $best%' : null),
        ]),
      ),
      if (!yearly) ...[
        const SizedBox(height: 10),
        Row(children: [
          Text('Koto mash', style: _j(12.5, FontWeight.w700, _muted)),
          const Spacer(),
          for (final m in const [1, 3, 6])
            GestureDetector(
              onTap: () => setState(() => months = m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: months == m ? _ink : Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: months == m ? _ink : _line),
                ),
                child: Text('$m mash', style: _j(12, FontWeight.w800, months == m ? Colors.white : _ink)),
              ),
            ),
        ]),
      ],
    ]);
  }

  static const _featureIcon = <String, IconData>{
    'sales': Icons.point_of_sale_rounded,
    'purchases': Icons.shopping_bag_rounded,
    'products': Icons.inventory_2_rounded,
    'parties': Icons.groups_rounded,
    'expenses': Icons.sell_rounded,
    'print': Icons.print_rounded,
    'scanner': Icons.qr_code_scanner_rounded,
    'cash_bank': Icons.account_balance_rounded,
    'backup': Icons.backup_rounded,
    'search': Icons.manage_search_rounded,
    'dashboard': Icons.dashboard_rounded,
    'returns': Icons.assignment_return_rounded,
    'emi': Icons.calendar_month_rounded,
    'imei': Icons.verified_user_rounded,
    'labels': Icons.qr_code_2_rounded,
    'whatsapp': Icons.chat_rounded,
    'due_alarm': Icons.alarm_rounded,
    'reports': Icons.menu_book_rounded,
    'gst': Icons.request_quote_rounded,
    'excel': Icons.table_view_rounded,
    'cloud': Icons.cloud_done_rounded,
    'lock': Icons.fingerprint_rounded,
    'multi_store': Icons.store_mall_directory_rounded,
    'opp_id': Icons.badge_rounded,
    'smart_ai': Icons.auto_awesome_rounded,
    'daily_ai': Icons.summarize_rounded,
    'analytics': Icons.query_stats_rounded,
    'loans': Icons.account_balance_wallet_rounded,
    'smart_imei': Icons.phone_android_rounded,
    'batch_scan': Icons.burst_mode_rounded,
    'custom_print': Icons.tune_rounded,
    'balance_sheet': Icons.balance_rounded,
    'unlimited': Icons.all_inclusive_rounded,
    'stores10': Icons.storefront_rounded,
    'loan_alarm': Icons.notifications_active_rounded,
    'priority': Icons.support_agent_rounded,
    'early': Icons.rocket_launch_rounded,
  };

  /// Every feature as a tile, coloured by the plan that opens it.
  Widget _showcase() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF0F1240), Color(0xFF241A7A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFE08A), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Hisab AI-te ${features.length} ta feature', style: _j(16, FontWeight.w800, Colors.white))),
          ]),
          const SizedBox(height: 4),
          Text('Rong dekhe bujhun kon plan-e ki pabe', style: _j(12, FontWeight.w500, const Color(0xB3FFFFFF))),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 4, children: [
            for (final p in plans)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: planColors[p.id]!))),
                const SizedBox(width: 5),
                Text('${p.name} ${featurePercent(p.tier)}%', style: _j(11.5, FontWeight.w700, Colors.white)),
              ]),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 16) / 3;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in features)
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: planColors[plans[f.tier - 1].id]!.first.withAlpha(0x88)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), gradient: LinearGradient(colors: planColors[plans[f.tier - 1].id]!)),
                      child: Icon(_featureIcon[f.key] ?? Icons.check_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(height: 6),
                    Text(f.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w700, Colors.white)),
                  ]),
                ),
            ]);
          }),
        ]),
      );

  Widget _usage(String l, int used, int max) {
    final unlimited = max == 0;
    final frac = unlimited ? 0.0 : (used / max).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(width: 112, child: Text(l, style: _j(11.5, FontWeight.w600, const Color(0xE6FFFFFF)))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: unlimited ? 1 : frac,
              backgroundColor: const Color(0x33FFFFFF),
              valueColor: AlwaysStoppedAnimation(frac > .85 ? const Color(0xFFFFB5C2) : Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(unlimited ? '$used / ∞' : '$used / $max', style: _j(11.5, FontWeight.w800, Colors.white)),
      ]),
    );
  }

  Widget _planCard(PlanDef p, {required bool current}) {
    final pct = featurePercent(p.tier);
    final colors = planColors[p.id]!;
    final popular = p.id == 'gold';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: current || popular ? colors.last : const Color(0xFFF1F2F9), width: current || popular ? 2 : 1),
        boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -6)],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            Icon(_planIcon[p.id], color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(p.name, style: _j(19, FontWeight.w800, Colors.white)),
                  if (popular) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                      child: Text('POPULAR', style: _j(9, FontWeight.w800, colors.last)),
                    ),
                  ],
                ]),
                Text(p.tagline, style: _j(11.5, FontWeight.w600, const Color(0xE6FFFFFF))),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (yearly && p.yearSaving > 0)
                Text('₹${inr(p.price * 12)}',
                    style: _j(12, FontWeight.w700, const Color(0xB3FFFFFF)).copyWith(decoration: TextDecoration.lineThrough, decorationColor: Colors.white)),
              Text('₹${inr(yearly ? p.yearly : p.price)}', style: _j(24, FontWeight.w800, Colors.white)),
              Text(yearly ? '/bochor · ₹${p.yearlyPerMonth}/mash' : '/mash', style: _j(11, FontWeight.w600, const Color(0xE6FFFFFF))),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (yearly && p.yearSaving > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFE6F7EE), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.savings_rounded, size: 16, color: _green),
                  const SizedBox(width: 6),
                  Text('Bochore ₹${inr(p.yearSaving)} bachan (${p.yearSavingPct}% kom)', style: _j(12, FontWeight.w800, _green)),
                ]),
              ),
            if (yearly && p.yearSaving <= 0)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFF1ECFF), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_clock_rounded, size: 16, color: Color(0xFF5B2EE0)),
                  const SizedBox(width: 6),
                  Text('Ek bar pay — 12 mash nishchinto', style: _j(12, FontWeight.w800, const Color(0xFF5B2EE0))),
                ]),
              ),
            Row(children: [
              Text('$pct% feature', style: _j(13.5, FontWeight.w800, _ink)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: pct / 100,
                    backgroundColor: const Color(0xFFF1F2F9),
                    valueColor: AlwaysStoppedAnimation(colors.last),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _li(p.products == 0 ? 'Unlimited product' : '30 dine ${p.products} ta product'),
            _li(p.sales == 0 ? 'Unlimited bill / sale' : '30 dine ${p.sales} ta bill'),
            _li(p.stores == 1 ? '1 ta store' : '${p.stores} ta store'),
            for (final f in features.where((f) => f.tier == p.tier).take(p.tier == 1 ? 6 : 7)) _li(f.name),
            if (p.tier > 1) _li('+ ${plans[p.tier - 2].name}-er shob kichu', bold: true),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: current
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                      onPressed: () => _request(p),
                      child: Text('Chalu ache ✓ · Renew', style: _j(14, FontWeight.w800, colors.last)),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: colors.last, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                      onPressed: Sub.admin ? null : () => _request(p),
                      child: Text('${p.name} nin · ₹${inr(p.amount(term))}${yearly ? '/bochor' : ''}', style: _j(14, FontWeight.w800, Colors.white)),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _li(String t, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, size: 16, color: bold ? _muted : _green),
          const SizedBox(width: 7),
          Expanded(child: Text(t, style: _j(12.5, bold ? FontWeight.w800 : FontWeight.w600, _ink))),
        ]),
      );

  Widget _compare() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF1F2F9))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Shob feature tulona', style: _j(15, FontWeight.w800, _ink)),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: SizedBox()),
            for (final p in plans) SizedBox(width: 54, child: Text(p.name, textAlign: TextAlign.center, style: _j(11, FontWeight.w800, planColors[p.id]!.last))),
          ]),
          const Divider(color: _line),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(f.name, style: _j(12, FontWeight.w600, _ink))),
                for (final p in plans)
                  SizedBox(
                    width: 54,
                    child: Icon(p.tier >= f.tier ? Icons.check_rounded : Icons.close_rounded,
                        size: 17, color: p.tier >= f.tier ? _green : const Color(0xFFD5D8EA)),
                  ),
              ]),
            ),
        ]),
      );
}

