import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../main.dart';
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

/// Home screen — a 1:1 reproduction of the GameX PC Hub reference design
/// (tool/reference/home.webp, 849 px wide). Every position and size below is
/// written in reference-screenshot pixels and scaled to the phone's width, so
/// the layout keeps the exact proportions of the design on any screen.
class Ref {
  static double u = 393 / 849; // dp per reference pixel (set from screen width)
}

/// reference pixels → dp
double p(num px) => px * Ref.u;

/// design font size (dp at the 393 dp reference width) → dp on this screen
double fs(num dp) => dp * 2.1603 * Ref.u;

const _bg = Color(0xFFF6F8FE);
const _ink = Color(0xFF0E1022);
const _navy = Color(0xFF0B1153);
const _muted = Color(0xFF3E4266);

TextStyle _t(double size, FontWeight w, Color c, {bool mont = false}) => TextStyle(
      fontSize: fs(size),
      fontWeight: w,
      color: c,
      height: 1.0,
      letterSpacing: mont ? 0 : -0.1,
      fontFamily: mont ? 'Montserrat' : null,
      fontVariations: mont ? [FontVariation('wght', w.value.toDouble())] : null,
    );

Widget _img(String name, double w, double h) =>
    Image.asset('assets/home/$name.png', width: p(w), height: p(h), fit: BoxFit.fill, filterQuality: FilterQuality.high);

/// Positions a child at reference coordinates inside a Stack.
Widget _at(double x, double y, Widget child) => Positioned(left: p(x), top: p(y), child: child);

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
        await Books.activity(1),
        (await Books.notifications()).length,
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    Ref.u = mq.size.width / 849;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.noScaling),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(children: [
            // soft lavender glow on the right, as in the design
            Positioned(
              right: -p(200),
              top: p(500),
              child: Container(
                width: p(520),
                height: p(900),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0x0F8E6CFF), Color(0x008E6CFF)]),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Live<HomeData>(
                load: _load,
                builder: (context, d) => ListView(
                  padding: EdgeInsets.only(top: p(14), bottom: mq.padding.bottom + p(300)),
                  children: [
                    _side(_Header(d)),
                    SizedBox(height: p(25)),
                    _Welcome(d.settings),
                    SizedBox(height: p(20)),
                    _side(_StatsGrid(d.m)),
                    SizedBox(height: p(23)),
                    _side(const _QuickActions()),
                    SizedBox(height: p(26)),
                    _side(const _OverviewCard()),
                    SizedBox(height: p(30)),
                    _side(const _SearchBar()),
                    SizedBox(height: p(23)),
                    _side(_RecentActivity(d.activity)),
                    SizedBox(height: p(23)),
                    _side(const _GrowBanner()),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static Widget _side(Widget child) => Padding(padding: EdgeInsets.only(left: p(30), right: p(31)), child: child);
}

/// White card used by every section of the design.
BoxDecoration _whiteCard(double radius) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(p(radius)),
      border: Border.all(color: const Color(0xFFF1F2F9), width: 1),
      boxShadow: const [
        BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
        BoxShadow(color: Color(0x0A2A2F7A), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );

Widget _tap(Widget child, VoidCallback onTap, double radius) => Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(p(radius)), onTap: onTap, child: child),
    );

// ------------------------------------------------------------------ header
class _Header extends StatelessWidget {
  final HomeData d;
  const _Header(this.d);

  Widget _circle({required Widget child, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: p(78),
          height: p(78),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFAFAFE),
            boxShadow: [
              BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -3),
            ],
          ),
          alignment: Alignment.center,
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = d.settings['business_name'] ?? 'GAMEX PC Hub';
    final sp = name.indexOf(' ');
    final first = sp < 0 ? name : name.substring(0, sp);
    final rest = sp < 0 ? '' : name.substring(sp + 1);
    return SizedBox(
      height: p(101),
      child: Row(children: [
        Padding(padding: EdgeInsets.only(left: p(1)), child: _img('logo', 100, 101)),
        SizedBox(width: p(30)),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(first.toUpperCase(), style: _t(20.2, FontWeight.w800, _navy, mont: true)),
                if (rest.isNotEmpty) ...[
                  SizedBox(width: p(10)),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) =>
                        const LinearGradient(colors: [Color(0xFF7A2AD8), Color(0xFF9C36E3)]).createShader(r),
                    child: Text(rest, style: _t(20.2, FontWeight.w800, Colors.white, mont: true)),
                  ),
                ],
              ]),
            ),
            SizedBox(height: p(14)),
            Text(d.settings['tagline'] ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11.7, FontWeight.w400, _muted)),
          ]),
        ),
        SizedBox(width: p(8)),
        Stack(clipBehavior: Clip.none, children: [
          _circle(
            onTap: () => open(context, const NotificationsScreen()),
            child: Icon(Icons.notifications_none_rounded, size: p(46), color: const Color(0xFF14152A)),
          ),
          if (d.alerts > 0)
            Positioned(
              right: -p(4),
              top: -p(12),
              child: Container(
                constraints: BoxConstraints(minWidth: p(36)),
                height: p(36),
                padding: EdgeInsets.symmetric(horizontal: p(8)),
                decoration: BoxDecoration(
                  color: const Color(0xFFFB1D3C),
                  borderRadius: BorderRadius.circular(p(18)),
                  border: Border.all(color: Colors.white, width: p(3)),
                ),
                alignment: Alignment.center,
                child: Text(d.alerts > 99 ? '99+' : '${d.alerts}', style: _t(9.5, FontWeight.w500, Colors.white)),
              ),
            ),
        ]),
        SizedBox(width: p(28)),
        _circle(
          onTap: () => Shell.goTo(context, 3),
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => const LinearGradient(
              colors: [Color(0xFF2F7BFF), Color(0xFF0846E6)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(r),
            child: Icon(Icons.person_rounded, size: p(56), color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ welcome banner
class _Welcome extends StatelessWidget {
  final Map<String, String> settings;
  const _Welcome(this.settings);

  @override
  Widget build(BuildContext context) {
    final owner = settings['owner_name'] ?? 'Super Admin';
    final biz = (settings['business_name'] ?? 'GameX PC Hub').replaceAll('GAMEX', 'GameX');
    // banner: x 30 → screen edge, y 214 → 352 in the reference
    return Padding(
      padding: EdgeInsets.only(left: p(30)),
      child: SizedBox(
        height: p(138),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(p(30))),
                gradient: const LinearGradient(colors: [Color(0xFFEBEEFC), Color(0xFFEDEFFE), Color(0xFFEEEFFB)]),
                border: Border.all(color: const Color(0xCCFFFFFF), width: 1.2),
                boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -6)],
              ),
            ),
          ),
          Positioned(left: p(448), top: -p(16), child: _img('hero', 371, 155)),
          _at(20, 33, _img('wave', 58, 55)),
          Positioned(
            left: p(93),
            top: p(258 - 214) - fs(15.4) * 0.22,
            right: p(380),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Hello, '),
                TextSpan(text: '$owner!', style: const TextStyle(color: Color(0xFF1C2CB4))),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(15.4, FontWeight.w700, _ink),
            ),
          ),
          Positioned(
            left: p(92),
            top: p(300 - 214) - fs(9.9) * 0.22,
            right: p(370),
            child: Text('Have a great day at $biz',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(9.9, FontWeight.w400, const Color(0xFF2B2E4D))),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ stat cards
class _CardSpec {
  final String title, pillText, icon, pillIcon, art;
  final int amount;
  final List<Color> base; // top-left → bottom-right
  final Color pillBg, pillFg;
  final Offset iconAt, titleAt, valueAt, pillAt, artAt;
  final Size iconSize, artSize;
  final bool chevron;
  final VoidCallback onTap;
  const _CardSpec({
    required this.title,
    required this.pillText,
    required this.icon,
    required this.pillIcon,
    required this.art,
    required this.amount,
    required this.base,
    required this.pillBg,
    required this.pillFg,
    required this.iconAt,
    required this.titleAt,
    required this.valueAt,
    required this.pillAt,
    required this.artAt,
    required this.iconSize,
    required this.artSize,
    required this.onTap,
    this.chevron = false,
  });
}

class _StatCard extends StatelessWidget {
  final _CardSpec s;
  final double height;
  const _StatCard(this.s, this.height);

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(p(34));
    return Container(
      height: p(height),
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          colors: s.base,
          stops: const [0, .58, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xD9FFFFFF), width: 1.4),
        boxShadow: [
          BoxShadow(color: s.base.last.withAlpha(0x55), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -8),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: _tap(
          Stack(children: [
            // glossy top sheen
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: p(height * .45),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
            _at(s.artAt.dx, s.artAt.dy, _img(s.art, s.artSize.width, s.artSize.height)),
            _at(s.iconAt.dx, s.iconAt.dy, _img(s.icon, s.iconSize.width, s.iconSize.height)),
            Positioned(
              left: p(s.titleAt.dx),
              top: p(s.titleAt.dy) - fs(11.1) * 0.22,
              right: p(8),
              child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11.1, FontWeight.w500, _ink)),
            ),
            Positioned(
              left: p(s.valueAt.dx),
              top: p(s.valueAt.dy) - fs(21.9) * 0.22,
              width: p(s.artAt.dx - s.valueAt.dx - 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('₹ ${Money.inr(s.amount)}', style: _t(21.9, FontWeight.w700, _ink)),
              ),
            ),
            _at(
              s.pillAt.dx,
              s.pillAt.dy,
              Container(
                height: p(34),
                padding: EdgeInsets.only(left: p(10), right: p(s.chevron ? 8 : 14)),
                decoration: BoxDecoration(color: s.pillBg, borderRadius: BorderRadius.circular(p(17))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _img(s.pillIcon, 24, 24),
                  SizedBox(width: p(4)),
                  Text(s.pillText, style: _t(9.8, FontWeight.w500, s.pillFg)),
                  if (s.chevron) Icon(Icons.chevron_right_rounded, size: p(28), color: s.pillFg),
                ]),
              ),
            ),
          ]),
          s.onTap,
          34,
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final HomeMetrics m;
  const _StatsGrid(this.m);

  @override
  Widget build(BuildContext context) {
    final sales = _CardSpec(
      title: "Today's sales",
      pillText: '${m.todayInvoices} invoices',
      icon: 'ic_sales',
      pillIcon: 'pill_sales',
      art: 'cart',
      amount: m.todaySales,
      base: const [Color(0xFFE6FDF0), Color(0xFFD9FBE6), Color(0xFFA9F3C8)],
      pillBg: const Color(0xFFA3F5C3),
      pillFg: const Color(0xFF0B1A12),
      iconAt: const Offset(27, 20),
      iconSize: const Size(50, 50),
      titleAt: const Offset(90, 34),
      valueAt: const Offset(39, 82),
      pillAt: const Offset(32, 135),
      artAt: const Offset(248, 26),
      artSize: const Size(134, 130),
      onTap: () => open(context, const SalesScreen()),
    );
    final purchases = _CardSpec(
      title: "Today's purchases",
      pillText: '${m.todayBills} bills',
      icon: 'ic_purchase',
      pillIcon: 'pill_purchase',
      art: 'box',
      amount: m.todayPurchases,
      base: const [Color(0xFFF5EEFF), Color(0xFFEEE5FF), Color(0xFFBC94FD)],
      pillBg: const Color(0xFFD9C2FC),
      pillFg: const Color(0xFF14105A),
      iconAt: const Offset(24, 19),
      iconSize: const Size(50, 50),
      titleAt: const Offset(84, 34),
      valueAt: const Offset(36, 82),
      pillAt: const Offset(26, 135),
      artAt: const Offset(258, 28),
      artSize: const Size(120, 128),
      onTap: () => open(context, const PurchasesScreen()),
    );
    final yesterday = _CardSpec(
      title: 'Yesterday',
      pillText: 'Previous day',
      icon: 'ic_yesterday',
      pillIcon: 'pill_yesterday',
      art: 'calendar',
      amount: m.yesterdaySales,
      base: const [Color(0xFFEEF5FF), Color(0xFFE3EEFF), Color(0xFFB2D2FA)],
      pillBg: const Color(0xFFC9DCFC),
      pillFg: const Color(0xFF0D1C80),
      iconAt: const Offset(28, 20),
      iconSize: const Size(48, 48),
      titleAt: const Offset(90, 34),
      valueAt: const Offset(39, 82),
      pillAt: const Offset(32, 134),
      artAt: const Offset(258, 24),
      artSize: const Size(114, 124),
      onTap: () => open(context, const SalesScreen()),
    );
    final due = _CardSpec(
      title: 'Total due',
      pillText: 'Open ledger',
      icon: 'ic_due',
      pillIcon: 'pill_due',
      art: 'moneybag',
      amount: m.totalDue,
      base: const [Color(0xFFFFF0EF), Color(0xFFFDE8E9), Color(0xFFF7CBD1)],
      pillBg: const Color(0xFFFFCDCD),
      pillFg: const Color(0xFFC21F25),
      iconAt: const Offset(28, 20),
      iconSize: const Size(48, 48),
      titleAt: const Offset(89, 34),
      valueAt: const Offset(39, 82),
      pillAt: const Offset(29, 134),
      artAt: const Offset(256, 22),
      artSize: const Size(118, 126),
      chevron: true,
      onTap: () => open(context, const PartiesScreen(type: 'customer')),
    );
    return Column(children: [
      Row(children: [
        Expanded(child: _StatCard(sales, 190)),
        SizedBox(width: p(18)),
        Expanded(child: _StatCard(purchases, 190)),
      ]),
      SizedBox(height: p(22)),
      Row(children: [
        Expanded(child: _StatCard(yesterday, 186)),
        SizedBox(width: p(18)),
        Expanded(child: _StatCard(due, 186)),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------ quick actions
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, Widget?)>[
      ('Purchase', 'qa_purchase', const PurchaseForm()),
      ('Ledger', 'qa_ledger', const LedgersScreen()),
      ('Product', 'qa_product', null),
      ('Expense', 'qa_expense', const ExpensesScreen()),
      ('Sales', 'qa_sales', const SalesScreen()),
      ('Customer', 'qa_customer', const PartiesScreen(type: 'customer')),
      ('Supplier', 'qa_supplier', const PartiesScreen(type: 'supplier')),
      ('Bank', 'qa_bank', const BankScreen()),
    ];
    Widget tile((String, String, Widget?) it) => Container(
          height: p(139),
          decoration: _whiteCard(30),
          child: _tap(
            Stack(children: [
              Positioned(left: 0, right: 0, top: p(10), child: Center(child: _img(it.$2, 88, 88))),
              Positioned(
                left: 0,
                right: 0,
                top: p(103) - fs(11) * 0.22,
                child: Text(it.$1, textAlign: TextAlign.center, maxLines: 1, style: _t(11, FontWeight.w400, _ink)),
              ),
            ]),
            () => it.$3 == null ? Shell.goTo(context, 2) : open(context, it.$3!),
            30,
          ),
        );
    Widget row(int start) => Row(children: [
          for (var i = start; i < start + 4; i++) ...[
            if (i > start) SizedBox(width: p(15)),
            Expanded(child: tile(items[i])),
          ],
        ]);
    return Column(children: [row(0), SizedBox(height: p(17)), row(4)]);
  }
}

// ------------------------------------------------------------------ business overview
class _OverviewCard extends StatefulWidget {
  const _OverviewCard();
  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  String period = 'month';
  static const labels = {'today': 'Today', 'week': 'This Week', 'month': 'This Month', 'year': 'This Year'};

  Widget _chip(int pct, Color bg, Color fg) => Container(
        height: p(28),
        padding: EdgeInsets.symmetric(horizontal: p(10)),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(p(14))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(pct >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: p(20), color: fg),
          SizedBox(width: p(4)),
          Text('${pct.abs()}%', style: _t(8.6, FontWeight.w500, fg)),
        ]),
      );

  Widget _value(double x, int v, double width) => Positioned(
        left: p(x),
        top: p(87) - fs(22.3) * 0.22,
        width: p(width),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('₹ ${Money.inr(v)}', style: _t(22.3, FontWeight.w700, _ink)),
        ),
      );

  Widget _label(double x, String s) =>
      Positioned(left: p(x), top: p(142) - fs(10.6) * 0.22, child: Text(s, style: _t(10.6, FontWeight.w400, _ink)));

  @override
  Widget build(BuildContext context) {
    return Container(
      height: p(187),
      decoration: _whiteCard(34),
      child: Live<Overview>(
        reloadKey: period,
        load: () => Books.overview(period),
        builder: (context, ov) => Stack(children: [
          _at(28, 22, _img('ov_icon', 36, 35)),
          Positioned(
            left: p(82),
            top: p(28) - fs(12.7) * 0.22,
            child: Text('Business Overview', style: _t(12.7, FontWeight.w700, _ink)),
          ),
          Positioned(
            right: p(17),
            top: p(17),
            child: PopupMenuButton<String>(
              initialValue: period,
              onSelected: (v) => setState(() => period = v),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              itemBuilder: (_) => [for (final e in labels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
              child: Container(
                width: p(194),
                height: p(48),
                padding: EdgeInsets.only(left: p(22), right: p(12)),
                decoration: BoxDecoration(color: const Color(0xFFF1F2FA), borderRadius: BorderRadius.circular(p(24))),
                child: Row(children: [
                  Expanded(child: Text(labels[period]!, style: _t(10.6, FontWeight.w500, _ink))),
                  Icon(Icons.keyboard_arrow_down_rounded, size: p(34), color: _ink),
                ]),
              ),
            ),
          ),
          _value(39, ov.sales, 255),
          _label(38, 'Total Sales'),
          _at(185, 137, _chip(ov.salesChange, const Color(0xFFE2F8EC), const Color(0xFF2A9A45))),
          Positioned(left: p(304), top: p(82), child: Container(width: 1.2, height: p(83), color: const Color(0xFFDDE0EE))),
          _value(338, ov.purchases, 280),
          _label(338, 'Total Purchase'),
          _at(503, 137, _chip(ov.purchaseChange, const Color(0xFFE8EFFF), const Color(0xFF1F49CF))),
          _at(630, 67, _img('ov_art', 130, 115)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ search
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: p(75),
      decoration: _whiteCard(38),
      child: _tap(
        Row(children: [
          SizedBox(width: p(32)),
          Icon(Icons.search_rounded, size: p(36), color: const Color(0xFF12163A)),
          SizedBox(width: p(20)),
          Expanded(
            child: Container(
              height: p(58),
              decoration: BoxDecoration(color: const Color(0xFFF2F3FB), borderRadius: BorderRadius.circular(p(29))),
              padding: EdgeInsets.only(left: p(20), right: p(16)),
              child: Row(children: [
                Expanded(
                  child: Text('Search customer or invoice...',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11.5, FontWeight.w400, const Color(0xFF5B5D7A))),
                ),
                Icon(Icons.tune_rounded, size: p(34), color: const Color(0xFF12163A)),
              ]),
            ),
          ),
          SizedBox(width: p(10)),
        ]),
        () => open(context, const SearchScreen()),
        38,
      ),
    );
  }
}

// ------------------------------------------------------------------ recent activity
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
    final a = rows.isEmpty ? null : rows.first;
    final kind = a?['kind'] as String?;
    final amount = a?['amount'];
    final Widget icon = kind == null || kind == 'sale'
        ? _img('act_cart', 84, 84)
        : SizedBox(
            width: p(84),
            height: p(84),
            child: Center(
              child: Orb(
                icon: activityStyle[kind]?.$1 ?? Icons.bolt_rounded,
                colors: (activityStyle[kind]?.$2 ?? Palette.green).icon,
                bg: (activityStyle[kind]?.$2 ?? Palette.green).bg,
                size: p(68),
              ),
            ),
          );
    return Container(
      height: p(137),
      decoration: _whiteCard(30),
      child: _tap(
        Stack(children: [
          _at(26, 8, _img('clock', 46, 46)),
          Positioned(
            left: p(91),
            top: p(21) - fs(12.8) * 0.22,
            child: Text('Recent Activity', style: _t(12.8, FontWeight.w700, _ink)),
          ),
          Positioned(
            right: p(22),
            top: p(14),
            child: Row(children: [
              Text('View All', style: _t(10.4, FontWeight.w500, const Color(0xFF3427CF))),
              SizedBox(width: p(10)),
              Icon(Icons.arrow_forward_rounded, size: p(30), color: const Color(0xFF3427CF)),
            ]),
          ),
          _at(23, 52, icon),
          Positioned(
            left: p(131),
            top: p(73) - fs(10.5) * 0.22,
            right: p(20),
            child: Text(a == null ? 'No activity yet' : a['message'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(10.5, FontWeight.w500, _ink)),
          ),
          Positioned(
            left: p(129),
            top: p(105) - fs(9.4) * 0.22,
            right: p(20),
            child: Text(
              a == null
                  ? 'Your first sale will show here'
                  : '${timeAgo(a['created_at'] as String)}${amount != null ? ' • ₹ ${Money.inr(asInt(amount))}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(9.4, FontWeight.w400, const Color(0xFF3D4058)),
            ),
          ),
        ]),
        () => open(context, const ActivityScreen()),
        30,
      ),
    );
  }
}

// ------------------------------------------------------------------ grow banner
class _GrowBanner extends StatelessWidget {
  const _GrowBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: p(102),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(p(30)),
        gradient: const LinearGradient(colors: [Color(0xFFE9ECFF), Color(0xFFE5EBFF), Color(0xFFD6DFFC)]),
        border: Border.all(color: const Color(0xCCFFFFFF), width: 1.2),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        _at(20, 2, _img('rocket', 95, 90)),
        Positioned(
          left: p(132),
          top: p(28) - fs(11.9) * 0.27,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF4318D6), Color(0xFF2D10C6)]).createShader(r),
            child: Text('Grow Your Business', style: _t(11.9, FontWeight.w700, Colors.white, mont: true)),
          ),
        ),
        Positioned(
          left: p(132),
          top: p(63) - fs(7.8) * 0.22,
          right: p(270),
          child: Text('Manage sales, purchases and more with ease!',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(7.8, FontWeight.w400, const Color(0xFF23264A))),
        ),
        Positioned(
          right: p(17),
          top: p(12),
          child: GestureDetector(
            onTap: () => Shell.goTo(context, 3),
            child: Container(
              width: p(244),
              height: p(55),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(p(28)),
                gradient: const LinearGradient(colors: [Color(0xFF5016E2), Color(0xFF3F10D2)]),
                boxShadow: const [BoxShadow(color: Color(0x553F10D2), blurRadius: 12, offset: Offset(0, 5), spreadRadius: -3)],
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Explore Features', style: _t(9.9, FontWeight.w500, Colors.white)),
                SizedBox(width: p(10)),
                Icon(Icons.arrow_forward_rounded, size: p(28), color: Colors.white),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The purple "+ New sale" pill that floats above the navigation bar.
class NewSaleFab extends StatelessWidget {
  final VoidCallback onTap;
  const NewSaleFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(p(32));
    return Container(
      width: p(199),
      height: p(70),
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6029DE), Color(0xFF4A1AD6), Color(0xFF300ECB)],
        ),
        border: Border.all(color: const Color(0x40FFFFFF), width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x803D13D7), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -6),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_rounded, size: p(46), color: Colors.white),
            SizedBox(width: p(12)),
            Text('New sale',
                style: TextStyle(fontSize: fs(12.8), fontWeight: FontWeight.w500, color: Colors.white, height: 1.0)),
          ]),
        ),
      ),
    );
  }
}
