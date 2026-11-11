import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dashboard.dart';
import 'screens/home.dart';
import 'screens/menu.dart';
import 'screens/products.dart';
import 'screens/sale_form.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const HisabApp());
}

class HisabApp extends StatelessWidget {
  const HisabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameX Hisab',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}

/// Bottom-navigation shell: Home · Dashboard · Products · Menu.
class Shell extends StatefulWidget {
  final int initialIndex;
  const Shell({super.key, this.initialIndex = 0});

  static void goTo(BuildContext context, int index) => context.findAncestorStateOfType<_ShellState>()?.select(index);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int index = widget.initialIndex;

  void select(int i) {
    if (i == index) return;
    HapticFeedback.selectionClick();
    setState(() => index = i);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    Ref.u = mq.size.width / 849;
    final navOuter = LiquidGlassNav.outerHeight(mq.padding.bottom);
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(0);
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(children: [
          Positioned.fill(
            child: IndexedStack(index: index, children: const [
              HomeScreen(),
              DashboardScreen(),
              ProductsScreen(),
              MenuScreen(),
            ]),
          ),
          if (index <= 1)
            Positioned(
              right: p(15),
              bottom: navOuter - p(9),
              child: NewSaleFab(onTap: () => open(context, const SaleForm())),
            ),
        ]),
        bottomNavigationBar: LiquidGlassNav(index: index, onTap: select),
      ),
    );
  }
}

/// Floating "liquid glass" navigation bar (matches the Products reference):
/// a frosted white panel with a specular top highlight, and a soft lavender
/// glass lens with a purple underline that glides to the active tab.
class LiquidGlassNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const LiquidGlassNav({super.key, required this.index, required this.onTap});

  static const _labels = ['Home', 'Dashboard', 'Products', 'Menu'];
  static const _icons = [Icons.home_rounded, Icons.pie_chart_rounded, null, Icons.menu_rounded];

  static double get barHeight => p(112);
  static double get bottomGap => p(28);
  static double outerHeight(double safeBottom) => barHeight + bottomGap + safeBottom;

  static const _active = Color(0xFF5B1FD9);
  static const _inactive = Color(0xFF3A4155);

  Widget _icon(int i, bool on) {
    final size = p(46);
    if (_icons[i] == null) {
      // 3D cube from the design; tinted grey when inactive
      final img = Image.asset('assets/products/nav_cube.png', width: size, height: size, fit: BoxFit.contain);
      return on ? img : ColorFiltered(colorFilter: const ColorFilter.mode(_inactive, BlendMode.srcIn), child: img);
    }
    if (!on) return Icon(_icons[i], size: size, color: _inactive);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7A45F5), Color(0xFF4A17C9)],
      ).createShader(r),
      child: Icon(_icons[i], size: size, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    final radius = BorderRadius.circular(p(44));
    final n = _labels.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(p(10), 0, p(10), bottomGap + safe),
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: Color(0x262A2F7A), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -8),
            BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xE6FFFFFF), Color(0xCCF8F8FF)],
                ),
                border: Border.all(color: const Color(0xF2FFFFFF), width: 1.3),
              ),
              child: Stack(children: [
                // specular highlight along the top edge
                Positioned(
                  left: p(30),
                  right: p(30),
                  top: 0,
                  height: p(30),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(p(30))),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xF2FFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
                // gliding glass lens + underline
                AnimatedAlign(
                  alignment: Alignment(-1 + 2 * index / (n - 1), 0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: p(35)),
                      child: Stack(children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: p(10),
                          bottom: p(10),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(p(24)),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFF3F0FF), Color(0xFFE9E3FF)],
                              ),
                              border: Border.all(color: const Color(0xFFFFFFFF), width: 1.2),
                              boxShadow: const [
                                BoxShadow(color: Color(0x2E4A17C9), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -6),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: p(1),
                          height: p(5),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(p(3)),
                              gradient: const LinearGradient(colors: [Color(0xFF6B2FE8), Color(0xFF4A17C9)]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(
                            scale: i == index ? 1.06 : 1,
                            duration: const Duration(milliseconds: 250),
                            child: _icon(i, i == index),
                          ),
                          SizedBox(height: p(8)),
                          Text(
                            _labels[i],
                            maxLines: 1,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontFamily: 'Jakarta',
                              fontSize: fs(9.3),
                              height: 1.0,
                              fontWeight: i == index ? FontWeight.w700 : FontWeight.w600,
                              fontVariations: [FontVariation('wght', i == index ? 700 : 600)],
                              color: i == index ? _active : _inactive,
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
