import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../main.dart';
import '../ui/art.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'activity.dart';
import 'bank.dart';
import 'expenses.dart';
import 'ledgers.dart';
import 'notifications.dart';
import 'parties.dart';
import 'purchase_form.dart';
import 'sales.dart';
import 'search.dart';

class HomeData {
  final Map<String, String> settings;
  final HomeMetrics m;
  final List<Rec> activity;
  final int alerts;
  HomeData(this.settings, this.m, this.activity, this.alerts);
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<HomeData> _load() async => HomeData(
        await Books.settings(),
        await Books.homeMetrics(),
        await Books.activity(3),
        (await Books.notifications()).length,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Live<HomeData>(
          load: _load,
          builder: (context, d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              _Header(d),
              _Welcome(d.settings),
              _StatsGrid(d.m),
              const _QuickActions(),
              const _OverviewCard(),
              _SearchBar(),
              _RecentActivity(d.activity),
              const _GrowBanner(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final HomeData d;
  const _Header(this.d);

  @override
  Widget build(BuildContext context) {
    final name = d.settings['business_name'] ?? 'GAMEX PC Hub';
    final parts = name.split(' ');
    final first = parts.first;
    final rest = parts.skip(1).join(' ');
    return Row(children: [
      const LogoTile(),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(first.toUpperCase(),
                  style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: C.navy, letterSpacing: .3)),
              if (rest.isNotEmpty) ...[
                const SizedBox(width: 7),
                ShaderMask(
                  shaderCallback: (r) => C.brandGradient.createShader(r),
                  child: Text(rest,
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 2),
          Text(d.settings['tagline'] ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.ink2, fontSize: 13.5)),
        ]),
      ),
      RoundIcon(
        icon: Icons.notifications_none_rounded,
        size: 48,
        badge: d.alerts,
        onTap: () => open(context, const NotificationsScreen()),
      ),
      const SizedBox(width: 10),
      RoundIcon(
        size: 48,
        onTap: () => Shell.goTo(context, 3),
        child: const Icon(Icons.person_rounded, color: C.blue2, size: 30),
      ),
    ]);
  }
}

class _Welcome extends StatelessWidget {
  final Map<String, String> settings;
  const _Welcome(this.settings);

  @override
  Widget build(BuildContext context) {
    final owner = settings['owner_name'] ?? 'Super Admin';
    final biz = (settings['business_name'] ?? 'GameX PC Hub').replaceAll('GAMEX', 'GameX');
    return Glass(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 108,
        child: Stack(children: [
          Positioned(right: -6, bottom: 0, child: Art(ArtKind.hero, width: 150)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 140, 16),
            child: Row(children: [
              const Text('👋', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Hello, '),
                      TextSpan(text: '$owner!', style: const TextStyle(color: C.blue)),
                    ]), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 3),
                  Text('Have a great day at $biz',
                      maxLines: 2, style: const TextStyle(fontSize: 12.5, color: C.ink2)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int amount;
  final Widget headIcon;
  final Widget pill;
  final ArtKind art;
  final List<Color> colors;
  final Color pillBg;
  final VoidCallback onTap;
  const _StatCard({
    required this.title,
    required this.amount,
    required this.headIcon,
    required this.pill,
    required this.art,
    required this.colors,
    required this.pillBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 152,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: C.shadow,
        border: Border.all(color: const Color(0xE6FFFFFF)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Stack(children: [
            Positioned(right: 4, top: 40, child: Art(art, width: 76)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 10, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: Color(0xBFFFFFFF), shape: BoxShape.circle),
                    child: Center(child: headIcon),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const Spacer(),
                SizedBox(
                  width: 110,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('₹ ${Money.inr(amount)}',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.5)),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)),
                  child: pill,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _pill(IconData icon, String text, Color color, {bool chevron = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      if (chevron) Icon(Icons.chevron_right_rounded, size: 16, color: color),
    ]);

class _StatsGrid extends StatelessWidget {
  final HomeMetrics m;
  const _StatsGrid(this.m);

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        title: "Today's sales",
        amount: m.todaySales,
        headIcon: const Icon(Icons.trending_up_rounded, size: 18, color: C.green),
        pill: _pill(Icons.show_chart_rounded, '${m.todayInvoices} invoices', const Color(0xFF0E6E47)),
        art: ArtKind.cart,
        colors: const [Color(0xFFECFBF3), Color(0xFFC9F2DC)],
        pillBg: const Color(0x2416A36A),
        onTap: () => open(context, const SalesScreen()),
      ),
      _StatCard(
        title: "Today's purchases",
        amount: m.todayPurchases,
        headIcon: const Icon(Icons.shopping_cart_rounded, size: 17, color: C.purple2),
        pill: _pill(Icons.inventory_2_rounded, '${m.todayBills} bills', const Color(0xFF4C2AA8)),
        art: ArtKind.box,
        colors: const [Color(0xFFF4F0FF), Color(0xFFDCD0FF)],
        pillBg: const Color(0x247044D8),
        onTap: () => open(context, const PurchasesScreen()),
      ),
      _StatCard(
        title: 'Yesterday',
        amount: m.yesterdaySales,
        headIcon: const Icon(Icons.calendar_month_rounded, size: 17, color: C.blue),
        pill: _pill(Icons.event_note_rounded, 'Previous day', const Color(0xFF2342A8)),
        art: ArtKind.calendar,
        colors: const [Color(0xFFEEF4FF), Color(0xFFCFE0FF)],
        pillBg: const Color(0x1F3155C8),
        onTap: () => open(context, const SalesScreen()),
      ),
      _StatCard(
        title: 'Total due',
        amount: m.totalDue,
        headIcon: const Icon(Icons.currency_rupee_rounded, size: 17, color: C.red),
        pill: _pill(Icons.bolt_rounded, 'Open ledger', const Color(0xFFB42323), chevron: true),
        art: ArtKind.moneyBag,
        colors: const [Color(0xFFFFF1F1), Color(0xFFFFD6D3)],
        pillBg: const Color(0x1FDC4545),
        onTap: () => open(context, const PartiesScreen(type: 'customer')),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(children: [
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = <(String, IconData, Palette, Widget?)>[
      ('Purchase', Icons.shopping_bag_rounded, Palette.purple, const PurchaseForm()),
      ('Ledger', Icons.menu_book_rounded, Palette.orange, const LedgersScreen()),
      ('Product', Icons.view_in_ar_rounded, Palette.blue, null),
      ('Expense', Icons.sell_rounded, Palette.green, const ExpensesScreen()),
      ('Sales', Icons.bar_chart_rounded, Palette.violet, const SalesScreen()),
      ('Customer', Icons.groups_rounded, Palette.teal, const PartiesScreen(type: 'customer')),
      ('Supplier', Icons.local_shipping_rounded, Palette.amber, const PartiesScreen(type: 'supplier')),
      ('Bank', Icons.account_balance_rounded, Palette.pink, const BankScreen()),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.86,
        children: [
          for (final it in items)
            ActionTile(
              label: it.$1,
              icon: it.$2,
              palette: it.$3,
              onTap: () => it.$4 == null ? Shell.goTo(context, 2) : open(context, it.$4!),
            ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard();
  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  String period = 'month';
  static const labels = {'today': 'Today', 'week': 'This Week', 'month': 'This Month', 'year': 'This Year'};

  Widget _trend(int pct, {bool blue = false}) {
    final up = pct >= 0;
    final fg = blue ? const Color(0xFF2F55D4) : (up ? const Color(0xFF13945F) : const Color(0xFFC53030));
    final bg = blue ? const Color(0xFFE7EEFF) : (up ? const Color(0xFFE3F7EC) : const Color(0xFFFDE8E8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: fg),
        const SizedBox(width: 2),
        Text('${pct.abs()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  Widget _figure(int v, String label, Widget trend) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('₹ ${Money.inr(v)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          trend,
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(children: [
        Row(children: [
          const Icon(Icons.bar_chart_rounded, color: C.blue, size: 26),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('Business Overview', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.only(left: 14, right: 6),
            decoration: BoxDecoration(color: const Color(0xFFF1F2F9), borderRadius: BorderRadius.circular(999)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: period,
                isDense: true,
                borderRadius: BorderRadius.circular(16),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: C.ink),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: C.ink),
                items: [
                  for (final e in labels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => period = v ?? 'month'),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Live<Overview>(
          key: ValueKey(period),
          load: () => Books.overview(period),
          builder: (context, ov) => Row(children: [
            Expanded(child: _figure(ov.sales, 'Total Sales', _trend(ov.salesChange))),
            Container(width: 1, height: 70, color: C.line, margin: const EdgeInsets.symmetric(horizontal: 12)),
            Expanded(child: _figure(ov.purchases, 'Total Purchase', _trend(ov.purchaseChange, blue: true))),
            if (MediaQuery.of(context).size.width > 360) const Art(ArtKind.bars, width: 76),
          ]),
        ),
      ]),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      onTap: () => open(context, const SearchScreen()),
      child: Row(children: [
        const Icon(Icons.search_rounded, size: 26, color: C.ink),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(999)),
            child: const Text('Search customer or invoice...', style: TextStyle(color: C.muted, fontSize: 14.5)),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.tune_rounded, color: C.ink),
      ]),
    );
  }
}

const activityStyle = <String, (IconData, Palette)>{
  'sale': (Icons.shopping_cart_rounded, Palette.green),
  'purchase': (Icons.shopping_bag_rounded, Palette.purple),
  'receipt': (Icons.currency_rupee_rounded, Palette.blue),
  'payment': (Icons.currency_rupee_rounded, Palette.amber),
  'expense': (Icons.sell_rounded, Palette.red),
  'transfer': (Icons.swap_horiz_rounded, Palette.pink),
  'product': (Icons.view_in_ar_rounded, Palette.blue),
  'customer': (Icons.groups_rounded, Palette.teal),
  'supplier': (Icons.local_shipping_rounded, Palette.amber),
};

class _RecentActivity extends StatelessWidget {
  final List<Rec> rows;
  const _RecentActivity(this.rows);

  @override
  Widget build(BuildContext context) {
    Widget item(Rec? a, bool first) {
      final st = activityStyle[a?['kind']] ?? activityStyle['sale']!;
      final amount = a?['amount'];
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Stack(children: [
            Orb(icon: st.$1, colors: st.$2.icon, bg: st.$2.bg, size: 52),
            if (first)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF18B26B),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a == null ? 'No activity yet' : a['message'] as String,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              Text(
                a == null
                    ? 'Your first sale will show here'
                    : '${timeAgo(a['created_at'] as String)}${amount != null ? ' • ₹ ${Money.inr(asInt(amount))}' : ''}',
                style: const TextStyle(color: C.muted, fontSize: 13),
              ),
            ]),
          ),
        ]),
      );
    }

    return CardBox(
      child: Column(children: [
        SectionTitle('Recent Activity',
            icon: Icons.access_time_filled_rounded,
            actionLabel: 'View All',
            onAction: () => open(context, const ActivityScreen())),
        if (rows.isEmpty) item(null, true),
        for (var i = 0; i < rows.length; i++) item(rows[i], i == 0),
      ]),
    );
  }
}

class _GrowBanner extends StatelessWidget {
  const _GrowBanner();

  @override
  Widget build(BuildContext context) {
    return Glass(
      gradient: const LinearGradient(colors: [Color(0xFFF3F0FF), Color(0xFFECEBFF), Color(0xFFE4E8FF)]),
      child: Row(children: [
        const Art(ArtKind.rocket, width: 58),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [C.purple2, C.purple]).createShader(r),
              child: const Text('Grow Your Business',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(height: 2),
            const Text('Manage sales, purchases and more with ease!', style: TextStyle(fontSize: 12, color: C.ink2)),
          ]),
        ),
        const SizedBox(width: 6),
        GradientButton(
          label: 'Explore',
          icon: Icons.arrow_forward_rounded,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          onTap: () => Shell.goTo(context, 3),
        ),
      ]),
    );
  }
}
