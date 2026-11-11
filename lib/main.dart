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
  const Shell({super.key});

  static void goTo(BuildContext context, int index) => context.findAncestorStateOfType<_ShellState>()?.select(index);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

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

/// Floating "liquid glass" navigation bar: frosted, translucent capsule with
/// a specular top highlight and a glass lens that slides to the active tab.
class LiquidGlassNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const LiquidGlassNav({super.key, required this.index, required this.onTap});

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.pie_chart_rounded, 'Dashboard'),
    (Icons.work_rounded, 'Products'),
    (Icons.menu_rounded, 'Menu'),
  ];

  static double get barHeight => p(132);
  static double get bottomGap => p(18);
  static double outerHeight(double safeBottom) => barHeight + bottomGap + safeBottom;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    final radius = BorderRadius.circular(p(66));
    const active = Color(0xFF4A17C9);
    const inactive = Color(0xFF23253F);
    return Padding(
      padding: EdgeInsets.fromLTRB(p(26), 0, p(26), bottomGap + safe),
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: Color(0x2E2A2F7A), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -8),
            BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xC7FFFFFF), Color(0x9EF4F3FF)],
                ),
                border: Border.all(color: const Color(0xE6FFFFFF), width: 1.3),
              ),
              child: Stack(children: [
                // specular sheen across the top edge
                Positioned(
                  left: p(40),
                  right: p(40),
                  top: 0,
                  height: p(46),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(p(40))),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
                // sliding glass lens behind the active tab
                AnimatedAlign(
                  alignment: Alignment(-1 + 2 * index / (_items.length - 1), 0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  child: FractionallySizedBox(
                    widthFactor: 1 / _items.length,
                    heightFactor: 1,
                    child: Padding(
                      padding: EdgeInsets.all(p(11)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(p(56)),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x2E7B5CFF), Color(0x1A3155C8), Color(0x335B2EE0)],
                          ),
                          border: Border.all(color: const Color(0xF2FFFFFF), width: 1.4),
                          boxShadow: const [
                            BoxShadow(color: Color(0x404A17C9), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -8),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: FractionallySizedBox(
                            widthFactor: .7,
                            heightFactor: .42,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(p(30))),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(
                            scale: i == index ? 1.08 : 1,
                            duration: const Duration(milliseconds: 250),
                            child: i == index
                                ? ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (r) => const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF6B3BF0), Color(0xFF3A12C8)],
                                    ).createShader(r),
                                    child: Icon(_items[i].$1, size: p(52), color: Colors.white),
                                  )
                                : Icon(_items[i].$1, size: p(50), color: inactive),
                          ),
                          SizedBox(height: p(6)),
                          Text(
                            _items[i].$2,
                            maxLines: 1,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: fs(11.4),
                              height: 1.0,
                              fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                              color: i == index ? active : inactive,
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
