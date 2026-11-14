import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../main.dart';
import '../print/labels.dart';
import '../ui/photo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'notifications.dart';
import 'product_form.dart';
import 'purchase_form.dart';
import 'sale_form.dart';
import 'sales.dart';
import 'plans.dart';

export 'product_form.dart';

// ============================================================================
// Products screen — 1:1 with the reference design (tool/reference/products.webp,
// 851 px wide). Positions are reference pixels scaled to the screen width.
// ============================================================================

double _w = 393 / 851;

/// reference pixels → dp
double q(num px) => px * _w;

/// design font size (dp at 393 dp width) → dp on this screen
double fz(num dp) => dp * _w * 851 / 393;

const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);

TextStyle _j(double size, FontWeight w, Color c, {TextDecoration? deco, double height = 1.0}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: fz(size),
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
      decoration: deco,
      decorationColor: c,
    );

/// Text whose cap line sits at reference y [capY] inside a Stack.
Widget _textAt(double x, double capY, String s, TextStyle st, {double? right, TextAlign align = TextAlign.left}) => Positioned(
      left: q(x),
      right: right == null ? null : q(right),
      top: q(capY) - st.fontSize! * 0.25,
      child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align, style: st),
    );

Widget _asset(String name, double w, double h) => Image.asset('assets/products/$name.png',
    width: q(w), height: q(h), fit: BoxFit.fill, filterQuality: FilterQuality.high);

BoxDecoration _card(double r, {Color color = Colors.white}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(q(r)),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [
        BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
        BoxShadow(color: Color(0x0A2A2F7A), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );

/// Product image tile: the product's photo, a bundled design image, or a
/// category placeholder.
class ProductThumb extends StatelessWidget {
  final Rec p;
  final double width, height;
  const ProductThumb(this.p, {super.key, required this.width, required this.height});

  static String placeholderFor(String? category) {
    final c = (category ?? '').toLowerCase();
    if (c.contains('laptop') || c.contains('desktop') || c.contains('pc')) return 'laptop';
    if (c.contains('access') || c.contains('audio')) return 'accessory';
    return 'mobile';
  }

  @override
  Widget build(BuildContext context) {
    final img = p['image'] as String?;
    final placeholder = Image.asset('assets/products/tile_${placeholderFor(p['category'] as String?)}.png',
        fit: BoxFit.fill, color: const Color(0x66F6F7FC), colorBlendMode: BlendMode.srcATop);
    final hasOwn = img != null && img.isNotEmpty && !img.startsWith('asset:');
    return ClipRRect(
      borderRadius: BorderRadius.circular(width * 0.15),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFFEEF0F7),
        child: hasOwn
            ? storedImage(img, fit: BoxFit.cover, fallback: placeholder)
            : img != null && img.startsWith('asset:')
                ? storedImage(img, fit: BoxFit.fill)
                : placeholder,
      ),
    );
  }
}

class _InvData {
  final InventoryStats stats;
  final List<Rec> rows;
  final Map<String, String> settings;
  final int alerts;
  _InvData(this.stats, this.rows, this.settings, this.alerts);
}

class ProductsScreen extends StatefulWidget {
  final bool lowOnly;
  const ProductsScreen({super.key, this.lowOnly = false});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late String filter = widget.lowOnly ? 'low' : 'all';
  String search = '';
  final searchCtrl = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    searchCtrl.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<_InvData> _load() async => _InvData(
        await Books.inventoryStats(),
        await Books.inventory(filter: filter, search: search),
        await Books.settings(),
        (await Books.notifications()).length,
      );

  void _setFilter(String f) {
    HapticFeedback.selectionClick();
    setState(() => filter = f);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    _w = mq.size.width / 851;
    final embedded = !Navigator.of(context).canPop();
    final fabBottom = embedded ? LiquidGlassNav.outerHeight(mq.padding.bottom, context) + q(16) : mq.padding.bottom + q(40);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FC),
        body: Stack(children: [
          SafeArea(
            bottom: false,
            child: Live<_InvData>(
              reloadKey: '$filter|$search',
              load: _load,
              builder: (context, d) => ListView(
                controller: scroll,
                padding: EdgeInsets.only(top: q(8), bottom: fabBottom + q(120)),
                children: [
                  _pad(_header(context, d)),
                  SizedBox(height: q(15)),
                  _pad(_banner(d.stats)),
                  SizedBox(height: q(23)),
                  _pad(_tiles(d.stats)),
                  SizedBox(height: q(28)),
                  _pad(_searchRow()),
                  SizedBox(height: q(25)),
                  _chips(d.stats),
                  SizedBox(height: q(23)),
                  if (d.stats.out > 0) ...[
                    _pad(_alert(
                      color: const [Color(0xFFFCE4ED), Color(0xFFFADBE6)],
                      button: const Color(0xFFF6C8D8),
                      fg: const Color(0xFF3A0418),
                      icon: Icon(Icons.block_rounded, size: q(44), color: const Color(0xFFC8102E)),
                      title: '${d.stats.out} out of stock product${d.stats.out == 1 ? '' : 's'}',
                      sub: 'Add stock to avoid sales interruption',
                      onTap: () => _setFilter('out'),
                    )),
                    SizedBox(height: q(15)),
                  ],
                  if (d.stats.low > 0) ...[
                    _pad(_alert(
                      color: const [Color(0xFFFDF1CF), Color(0xFFFBEABF)],
                      button: const Color(0xFFF8E1A9),
                      fg: const Color(0xFF3A2400),
                      icon: Icon(Icons.warning_rounded, size: q(46), color: const Color(0xFFE59A0C)),
                      title: '${d.stats.low} product${d.stats.low == 1 ? '' : 's'} running low',
                      sub: 'Only few items left in stock',
                      onTap: () => _setFilter('low'),
                    )),
                    SizedBox(height: q(15)),
                  ],
                  SizedBox(height: q(6)),
                  if (d.rows.isEmpty)
                    _pad(Container(
                      decoration: _card(34),
                      padding: EdgeInsets.all(q(30)),
                      child: EmptyState(search.isNotEmpty
                          ? 'No products match “$search”'
                          : filter == 'all'
                              ? 'No products yet — tap Add Product'
                              : 'Nothing in this list'),
                    )),
                  for (final r in d.rows) ...[_pad(_ProductCard(r)), SizedBox(height: q(22))],
                ],
              ),
            ),
          ),
          Positioned(
            right: q(19),
            bottom: fabBottom,
            child: _AddProductFab(onTap: () => open(context, const ProductForm())),
          ),
        ]),
      ),
    );
  }

  Widget _pad(Widget child) => Padding(padding: EdgeInsets.only(left: q(35), right: q(31)), child: child);

  // ---------------------------------------------------------------- header
  Widget _header(BuildContext context, _InvData d) {
    final name = (d.settings['business_name'] ?? 'GameX PC Hub').replaceAll('GAMEX', 'GameX');
    final photo = d.settings['owner_photo'];
    return SizedBox(
      height: q(104),
      child: Row(children: [
        SizedBox(width: q(106), height: q(104), child: Image.asset('assets/home/logo.png', fit: BoxFit.fill)),
        SizedBox(width: q(38)),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(16.8, FontWeight.w800, _navy)),
            SizedBox(height: q(14)),
            Text('Inventory & Products', style: _j(10.8, FontWeight.w500, const Color(0xFF323B60))),
          ]),
        ),
        Stack(clipBehavior: Clip.none, children: [
          GestureDetector(
            onTap: () => open(context, const NotificationsScreen()),
            child: Container(
              width: q(84),
              height: q(84),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFBFBFF),
                boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -4)],
              ),
              child: Icon(Icons.notifications_none_rounded, size: q(48), color: const Color(0xFF1B2A8F)),
            ),
          ),
          if (d.alerts > 0)
            Positioned(
              right: -q(4),
              top: -q(14),
              child: Container(
                constraints: BoxConstraints(minWidth: q(36)),
                height: q(36),
                padding: EdgeInsets.symmetric(horizontal: q(7)),
                decoration: BoxDecoration(
                  color: const Color(0xFFF72552),
                  borderRadius: BorderRadius.circular(q(18)),
                  border: Border.all(color: Colors.white, width: q(3)),
                ),
                alignment: Alignment.center,
                child: Text(d.alerts > 99 ? '99+' : '${d.alerts}', style: _j(8.6, FontWeight.w700, Colors.white)),
              ),
            ),
        ]),
        SizedBox(width: q(26)),
        GestureDetector(
          onTap: () => Shell.goTo(context, 3),
          child: Container(
            width: q(90),
            height: q(90),
            padding: EdgeInsets.all(q(4)),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF3D8BFF)]),
              boxShadow: [BoxShadow(color: Color(0x404A17C9), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
            ),
            child: Container(
              padding: EdgeInsets.all(q(3)),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: ClipOval(
                child: storedImage(
                  photo,
                  fallback: Container(
                    color: const Color(0xFFEAF0FF),
                    child: Icon(Icons.person_rounded, size: q(54), color: const Color(0xFF2F6BFF)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- stock overview banner
  Widget _banner(InventoryStats s) {
    final up = s.growth >= 0;
    return Container(
      height: q(238),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(q(40)),
        border: Border.all(color: const Color(0xE6FFFFFF), width: 1.4),
        boxShadow: const [BoxShadow(color: Color(0x332F3FD8), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(q(40)),
        child: Stack(children: [
          Positioned.fill(child: Image.asset('assets/products/banner_bg.png', fit: BoxFit.fill)),
          Positioned(
            left: q(30),
            top: q(35),
            child: Container(
              height: q(42),
              padding: EdgeInsets.only(left: q(12), right: q(18)),
              decoration: BoxDecoration(color: const Color(0xD9FFFFFF), borderRadius: BorderRadius.circular(q(21))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _asset('chip_chart', 28, 28),
                SizedBox(width: q(12)),
                Text('Stock Overview', style: _j(9.6, FontWeight.w700, _navy)),
              ]),
            ),
          ),
          Positioned(
            left: q(32),
            top: q(96) - fz(50) * 0.17,
            width: q(360),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${s.total}',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: fz(50),
                    fontWeight: FontWeight.w800,
                    fontVariations: [FontVariation('wght', 800)],
                    color: const Color(0xFF0A0E5A),
                    height: 1.0,
                    letterSpacing: -1,
                  )),
            ),
          ),
          Positioned(left: q(33), top: q(171), child: _asset('cube_small', 40, 40)),
          _textAt(83, 183, 'Total Products', _j(10.8, FontWeight.w700, _navy)),
          Positioned(
            left: q(655),
            top: q(23),
            child: Container(
              width: q(118),
              height: q(54),
              decoration: BoxDecoration(
                color: const Color(0xF2FFFFFF),
                borderRadius: BorderRadius.circular(q(27)),
                boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: q(32), color: up ? const Color(0xFF0F8A2E) : const Color(0xFFC8102E)),
                SizedBox(width: q(6)),
                Text('${up ? '+' : '-'}${s.growth.abs()}%',
                    style: _j(9.5, FontWeight.w700, up ? const Color(0xFF0B6B1E) : const Color(0xFF96091D))),
              ]),
            ),
          ),
          _textAt(658, 88, 'vs last month', _j(8.25, FontWeight.w500, Colors.white).copyWith(shadows: const [
            Shadow(color: Color(0x40000000), blurRadius: 4),
          ])),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- stat tiles
  Widget _tiles(InventoryStats s) {
    String pct(int n) => '${s.pct(n).toStringAsFixed(1).replaceAll('.0', '')}%';
    Widget pill(Color bg, IconData icon, Color ic, String text, Color fg) => Container(
          height: q(42),
          padding: EdgeInsets.symmetric(horizontal: q(14)),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(q(21))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: q(26), color: ic),
            SizedBox(width: q(8)),
            Text(text, style: _j(7.5, FontWeight.w700, fg)),
          ]),
        );
    Widget chevron(String f) => GestureDetector(
          onTap: () => _setFilter(f),
          child: Container(
            width: q(38),
            height: q(38),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEDEBFA)),
            child: Icon(Icons.chevron_right_rounded, size: q(30), color: const Color(0xFF3A2BC9)),
          ),
        );
    Widget tile(String orb, int n, String label, Widget bottom, String f) => Expanded(
          child: GestureDetector(
            onTap: () => _setFilter(f),
            child: Container(
              height: q(214),
              decoration: _card(32),
              child: Stack(children: [
                Positioned(left: 0, right: 0, top: q(6), child: Center(child: _asset(orb, 80, 80))),
                _textAt(0, 86, '$n', _j(16.8, FontWeight.w800, _ink), right: 0, align: TextAlign.center),
                _textAt(4, 128, label, _j(8.1, FontWeight.w400, const Color(0xFF2B324A)), right: 4, align: TextAlign.center),
                Positioned(left: 0, right: 0, top: q(160), height: q(42), child: bottom),
              ]),
            ),
          ),
        );
    Widget pillWithChevron(Widget p, String f) => Stack(clipBehavior: Clip.none, children: [
          Positioned(left: q(22), top: 0, child: p),
          Positioned(left: q(128), top: q(2), child: chevron(f)),
        ]);
    return Row(children: [
      tile('orb_out', s.out, 'Out of Stock',
          pillWithChevron(pill(const Color(0xFFFFDDE3), Icons.warning_rounded, const Color(0xFFE0103A), pct(s.out), const Color(0xFF96091D)), 'out'),
          'out'),
      SizedBox(width: q(18)),
      tile('orb_low', s.low, 'Running Low',
          pillWithChevron(pill(const Color(0xFFFFEACB), Icons.warning_rounded, const Color(0xFFE39A0F), pct(s.low), const Color(0xFF8A5200)), 'low'),
          'low'),
      SizedBox(width: q(18)),
      tile('orb_in', s.inStock, 'In Stock',
          Center(child: pill(const Color(0xFFDDF6E6), Icons.check_circle_rounded, const Color(0xFF13A84A), pct(s.inStock), const Color(0xFF0E7A2E))),
          'in'),
      SizedBox(width: q(18)),
      tile('orb_alert', s.alerts, 'Low Stock Alert', Stack(children: [Positioned(left: q(128), top: q(2), child: chevron('low'))]), 'low'),
    ]);
  }

  // ---------------------------------------------------------------- search
  Widget _searchRow() {
    return Row(children: [
      Expanded(
        child: Container(
          height: q(74),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(q(37)),
            border: Border.all(color: const Color(0xFFE9EAF5)),
            boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -4)],
          ),
          child: Row(children: [
            SizedBox(width: q(28)),
            Icon(Icons.search_rounded, size: q(46), color: const Color(0xFF2C3B8F)),
            SizedBox(width: q(16)),
            Expanded(
              child: TextField(
                controller: searchCtrl,
                textInputAction: TextInputAction.search,
                style: _j(10.1, FontWeight.w500, _ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Search product or category...',
                  hintStyle: _j(10.1, FontWeight.w400, const Color(0xFF515673)),
                ),
                onChanged: (v) => setState(() => search = v.trim()),
              ),
            ),
            if (search.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close_rounded, size: q(36), color: const Color(0xFF515673)),
                onPressed: () {
                  searchCtrl.clear();
                  setState(() => search = '');
                },
              ),
            SizedBox(width: q(12)),
          ]),
        ),
      ),
      SizedBox(width: q(11)),
      GestureDetector(
        onTap: _filterSheet,
        child: Container(
          width: q(68),
          height: q(68),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFECEBFC),
            boxShadow: [BoxShadow(color: Color(0x142A2F7A), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Icon(Icons.tune_rounded, size: q(40), color: const Color(0xFF2A2BC0)),
        ),
      ),
    ]);
  }

  void _filterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Show products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ),
          for (final e in const {'all': 'All products', 'in': 'In stock', 'low': 'Running low', 'out': 'Out of stock'}.entries)
            ListTile(
              title: Text(e.value),
              trailing: filter == e.key ? const Icon(Icons.check_rounded, color: C.purple2) : null,
              onTap: () {
                Navigator.pop(c);
                _setFilter(e.key);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- filter chips
  Widget _chips(InventoryStats s) {
    Widget chip(String key, IconData icon, Color ic, String label, int n, {Color? countColor, bool chevron = false}) {
      final on = filter == key;
      return GestureDetector(
        onTap: () => _setFilter(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: q(55),
          padding: EdgeInsets.only(left: q(20), right: q(chevron ? 12 : 20)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(q(28)),
            gradient: on ? const LinearGradient(colors: [Color(0xFF5B2EE6), Color(0xFF4318D2)]) : null,
            color: on ? null : Colors.white,
            border: on ? null : Border.all(color: const Color(0xFFECECF6)),
            boxShadow: [
              BoxShadow(
                color: on ? const Color(0x664A17C9) : const Color(0x142A2F7A),
                blurRadius: on ? 14 : 10,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: q(30), color: on ? Colors.white : ic),
            SizedBox(width: q(12)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$label ('),
                TextSpan(text: '$n', style: TextStyle(color: on ? Colors.white : (countColor ?? _ink))),
                const TextSpan(text: ')'),
              ]),
              style: _j(on ? 8.6 : 8.1, on ? FontWeight.w600 : FontWeight.w500, on ? Colors.white : _ink),
            ),
            if (chevron) ...[
              SizedBox(width: q(8)),
              Icon(Icons.chevron_right_rounded, size: q(28), color: on ? Colors.white : const Color(0xFF3A2BC9)),
            ],
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(left: q(37), right: q(31), top: q(6), bottom: q(10)),
      child: Row(children: [
        chip('all', Icons.view_in_ar_rounded, const Color(0xFF5B2EE6), 'All', s.total),
        SizedBox(width: q(25)),
        chip('in', Icons.check_circle_rounded, const Color(0xFF13A84A), 'In Stock', s.inStock),
        SizedBox(width: q(14)),
        chip('low', Icons.warning_rounded, const Color(0xFFF29D0B), 'Low Stock', s.low),
        SizedBox(width: q(14)),
        chip('out', Icons.cancel_rounded, const Color(0xFFE8174A), 'Out of Stock', s.out,
            countColor: const Color(0xFFE8174A), chevron: true),
      ]),
    );
  }

  // ---------------------------------------------------------------- alert banners
  Widget _alert({
    required List<Color> color,
    required Color button,
    required Color fg,
    required Widget icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: q(90),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(q(30)),
          gradient: LinearGradient(colors: color),
          border: Border.all(color: const Color(0xB3FFFFFF)),
          boxShadow: [BoxShadow(color: color.last.withAlpha(0x99), blurRadius: 14, offset: const Offset(0, 5), spreadRadius: -6)],
        ),
        child: Stack(children: [
          Positioned(left: q(25), top: q(23), child: SizedBox(width: q(44), height: q(44), child: Center(child: icon))),
          _textAt(94, 24, title, _j(9.6, FontWeight.w700, fg), right: 230),
          _textAt(94, 54, sub, _j(8.1, FontWeight.w400, fg.withAlpha(0xD9)), right: 230),
          Positioned(
            right: q(17),
            top: q(15),
            child: Container(
              width: q(193),
              height: q(59),
              decoration: BoxDecoration(color: button, borderRadius: BorderRadius.circular(q(30))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('View Details', style: _j(8.1, FontWeight.w600, fg)),
                SizedBox(width: q(14)),
                Icon(Icons.arrow_forward_rounded, size: q(30), color: fg),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- product card
class _ProductCard extends StatelessWidget {
  final Rec p;
  const _ProductCard(this.p);

  @override
  Widget build(BuildContext context) {
    final stock = asInt(p['stock']);
    final low = asInt(p['low_stock']);
    final price = asInt(p['price']);
    final mrp = asInt(p['mrp']);
    final off = mrp > price && mrp > 0 ? ((mrp - price) * 100 / mrp).round() : 0;
    final (String status, Color bg, Color fg, IconData icon) = stock <= 0
        ? ('Out of Stock', const Color(0xFFFDE0E6), const Color(0xFFB0102E), Icons.cancel_rounded)
        : stock <= low
            ? ('Low Stock', const Color(0xFFFFE6CC), const Color(0xFFB24A00), Icons.trending_down_rounded)
            : ('In Stock', const Color(0xFFDDF6E3), const Color(0xFF0F6B23), Icons.check_circle_rounded);
    final variant = [p['variant'], if ((p['variant'] ?? '') == '') p['brand']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(' • ');
    const statColor = Color(0xFF4B53A6);
    final statStyle = _j(7.8, FontWeight.w500, const Color(0xFF343C4F));
    Widget stat(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: q(24), color: statColor),
          SizedBox(width: q(10)),
          Text(t, style: statStyle),
        ]);
    Widget sep() => Padding(
          padding: EdgeInsets.symmetric(horizontal: q(26)),
          child: Text('|', style: statStyle),
        );
    return Container(
      height: q(200),
      decoration: _card(34),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(q(34)),
          onTap: () => open(context, ProductView(id: asInt(p['id']))),
          child: Stack(children: [
            Positioned(left: q(22), top: q(17), child: ProductThumb(p, width: q(145), height: q(167))),
            Positioned(
              left: q(199),
              top: q(16),
              child: Container(
                height: q(34),
                padding: EdgeInsets.symmetric(horizontal: q(10)),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(q(17))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: q(24), color: fg),
                  SizedBox(width: q(8)),
                  Text(status, style: _j(8.0, FontWeight.w600, fg)),
                ]),
              ),
            ),
            _textAt(202, 63, p['name'] as String, _j(12.5, FontWeight.w700, const Color(0xFF020618)), right: 190),
            _textAt(202, 99, variant.isEmpty ? (p['category'] as String? ?? '') : variant,
                _j(9.2, FontWeight.w400, const Color(0xFF3A4156)), right: 190),
            Positioned(
              left: q(201),
              right: q(20),
              top: q(124),
              height: q(36),
              child: Row(children: [
                Text('₹${Money.inr(price)}', style: _j(12.4, FontWeight.w800, const Color(0xFF1C1CA0))),
                if (off > 0) ...[
                  SizedBox(width: q(20)),
                  Flexible(
                    child: Text('₹${Money.inr(mrp)}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: _j(9.5, FontWeight.w500, const Color(0xFF7E8198), deco: TextDecoration.lineThrough)),
                  ),
                  SizedBox(width: q(18)),
                  Container(
                    height: q(34),
                    padding: EdgeInsets.symmetric(horizontal: q(16)),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFFDDDE3), borderRadius: BorderRadius.circular(q(17))),
                    child: Text('$off% OFF', style: _j(7.7, FontWeight.w700, const Color(0xFF8A0818))),
                  ),
                ],
              ]),
            ),
            Positioned(
              left: q(205),
              right: q(10),
              top: q(175) - fz(7.8) * 0.25 - q(2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  stat(Icons.bar_chart_rounded, 'Sold: ${asInt(p['sold'])}'),
                  sep(),
                  stat(Icons.view_in_ar_rounded, 'Stock: $stock'),
                  sep(),
                  stat(Icons.sell_rounded, 'Profit: ₹${Money.inr(asInt(p['profit']))}'),
                ]),
              ),
            ),
            Positioned(
              right: q(54),
              top: q(20),
              child: GestureDetector(
                onTap: () => open(context, ProductView(id: asInt(p['id']))),
                child: Container(
                  width: q(124),
                  height: q(50),
                  decoration: BoxDecoration(color: const Color(0xFFECEAFD), borderRadius: BorderRadius.circular(q(25))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.visibility_rounded, size: q(32), color: const Color(0xFF2D0FB8)),
                    SizedBox(width: q(10)),
                    Text('View', style: _j(9.3, FontWeight.w600, const Color(0xFF2D0FB8))),
                  ]),
                ),
              ),
            ),
            Positioned(
              right: q(18),
              top: q(20),
              child: _MoreMenu(p),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final Rec p;
  const _MoreMenu(this.p);

  @override
  Widget build(BuildContext context) {
    final id = asInt(p['id']);
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            open(context, ProductForm(product: p));
            break;
          case 'label':
            if (gate(context, 'labels')) open(context, LabelStudio(products: [p]));
            break;
          case 'buy':
            open(context, const PurchaseForm());
            break;
          case 'sell':
            open(context, const SaleForm());
            break;
          case 'delete':
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Delete product?'),
                content: Text('${p['name']} will be removed. This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: C.red))),
                ],
              ),
            );
            if (ok == true) {
              try {
                await Books.deleteProduct(id);
                if (context.mounted) toast(context, 'Product deleted');
              } catch (e) {
                if (context.mounted) toast(context, '$e', error: true);
              }
            }
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit product'))),
        PopupMenuItem(value: 'label', child: ListTile(leading: Icon(Icons.qr_code_2_rounded), title: Text('Print barcode labels'))),
        PopupMenuItem(value: 'buy', child: ListTile(leading: Icon(Icons.add_shopping_cart_rounded), title: Text('Purchase stock'))),
        PopupMenuItem(value: 'sell', child: ListTile(leading: Icon(Icons.point_of_sale_rounded), title: Text('Sell'))),
        PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: C.red), title: Text('Delete'))),
      ],
      child: Container(
        width: q(28),
        height: q(52),
        decoration: BoxDecoration(color: const Color(0xFFEEEEF9), borderRadius: BorderRadius.circular(q(14))),
        child: Icon(Icons.more_vert_rounded, size: q(32), color: const Color(0xFF1E1B6B)),
      ),
    );
  }
}

class _AddProductFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddProductFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(q(39));
    return Container(
      width: q(219),
      height: q(78),
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5E24E8), Color(0xFF4317D6), Color(0xFF2A0ECB)],
        ),
        border: Border.all(color: const Color(0x40FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x803D13D7), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -6)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_rounded, size: q(46), color: Colors.white),
            SizedBox(width: q(14)),
            Text('Add Product', style: _j(9.6, FontWeight.w700, Colors.white)),
          ]),
        ),
      ),
    );
  }
}

// ============================================================================
// Product detail
// ============================================================================
class ProductView extends StatelessWidget {
  final int id;
  const ProductView({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Live<List<List<Rec>>>(
      load: () async => [
        await Books.query(
            'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id WHERE p.id = ?',
            [id]),
        await Books.query(
            'SELECT i.*, s.number, s.date, s.id AS sid FROM sale_items i JOIN sales s ON s.id = i.sale_id '
            'WHERE i.product_id = ? ORDER BY s.date DESC LIMIT 20',
            [id]),
        await Books.query(
            'SELECT i.*, p.number, p.date, p.id AS pid FROM purchase_items i JOIN purchases p ON p.id = i.purchase_id '
            'WHERE i.product_id = ? ORDER BY p.date DESC LIMIT 20',
            [id]),
      ],
      builder: (context, data) {
        if (data[0].isEmpty) return const PageShell(title: 'Product', children: [EmptyState('Not found')]);
        final p = data[0].first;
        final stock = asInt(p['stock']);
        final margin = asInt(p['price']) - asInt(p['cost']);
        final sold = data[1].fold<int>(0, (a, s) => a + asInt(s['qty']));
        final profit = data[1].fold<int>(0, (a, s) => a + asInt(s['amount']) - asInt(s['unit_cost']) * asInt(s['qty']));
        return PageShell(
          title: p['name'] as String,
          subtitle: [p['variant'], p['brand'], p['category'], p['sku']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
          action: Row(mainAxisSize: MainAxisSize.min, children: [
            RoundIcon(icon: Icons.qr_code_2_rounded, onTap: () => gate(context, 'labels') ? open(context, LabelStudio(products: [p])) : null),
            const SizedBox(width: 8),
            RoundIcon(icon: Icons.edit_rounded, onTap: () => open(context, ProductForm(product: p))),
          ]),
          children: [
            const SizedBox(height: 12),
            Center(child: ProductThumb(p, width: 170, height: 196)),
            KpiGrid([
              Kpi('Selling price', asInt(p['price']), accent: true),
              Kpi('Avg. cost', asInt(p['cost'])),
              Kpi('Margin / unit', margin, color: margin >= 0 ? C.green : C.red),
              Kpi('Stock value', stock > 0 ? stock * asInt(p['cost']) : 0),
              Kpi('Profit earned', profit, color: profit >= 0 ? C.green : C.red),
              if (asInt(p['mrp']) > 0) Kpi('MRP', asInt(p['mrp'])),
            ]),
            CardBox(
              child: Column(children: [
                TotalLine('In stock', '$stock', bold: true, color: stock <= asInt(p['low_stock']) ? C.red : C.ink),
                TotalLine('Units sold', '$sold'),
                TotalLine('Low-stock alert at', '${p['low_stock']}'),
                TotalLine('GST', '${asInt(p['gst_bp']) / 100}%'),
                TotalLine('HSN', '${p['hsn'] ?? '—'}'),
                TotalLine('Condition', '${p['condition']}'),
              ]),
            ),
            Row(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: GradientButton(
                    label: 'Purchase stock',
                    icon: Icons.add_shopping_cart_rounded,
                    onTap: () => open(context, const PurchaseForm()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: GradientButton(
                    label: 'Sell',
                    icon: Icons.point_of_sale_rounded,
                    gradient: const LinearGradient(colors: [Color(0xFF1BB574), Color(0xFF0F8C58)]),
                    onTap: () => open(context, const SaleForm()),
                  ),
                ),
              ),
            ]),
            CardBox(
              child: Column(children: [
                const SectionTitle('Recent sales'),
                if (data[1].isEmpty) const EmptyState('Not sold yet'),
                Divided([
                  for (final s in data[1])
                    ListRow(
                      leading: const Avatar('', icon: Icons.shopping_cart_rounded, bg: Color(0xFFE3F7EC), fg: C.green),
                      title: '${s['number']} · ${s['qty']} × ${Money.rs(asInt(s['rate']))}',
                      subtitle: '${prettyDate(s['date'] as String)}${s['serial'] != null ? ' · IMEI ${s['serial']}' : ''}',
                      trailing: Money.rs(asInt(s['amount'])),
                      onTap: () => open(context, SaleView(id: asInt(s['sid']))),
                    ),
                ]),
              ]),
            ),
            CardBox(
              child: Column(children: [
                const SectionTitle('Recent purchases'),
                if (data[2].isEmpty) const EmptyState('No purchases yet'),
                Divided([
                  for (final s in data[2])
                    ListRow(
                      leading: const Avatar('', icon: Icons.shopping_bag_rounded),
                      title: '${s['number']} · ${s['qty']} × ${Money.rs(asInt(s['rate']))}',
                      subtitle: prettyDate(s['date'] as String),
                      trailing: Money.rs(asInt(s['amount'])),
                      onTap: () => open(context, PurchaseView(id: asInt(s['pid']))),
                    ),
                ]),
              ]),
            ),
          ],
        );
      },
    );
  }
}
