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
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
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

  static void goTo(BuildContext context, int index) =>
      context.findAncestorStateOfType<_ShellState>()?.select(index);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  void select(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(0);
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: index, children: const [
          HomeScreen(),
          DashboardScreen(),
          ProductsScreen(),
          MenuScreen(),
        ]),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: index == 0 || index == 1
            ? GradientButton(
                label: 'New sale',
                fontSize: 17,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SaleForm())),
              )
            : null,
        bottomNavigationBar: _BottomNav(index: index, onTap: select),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.pie_chart_rounded, 'Dashboard'),
      (Icons.work_rounded, 'Products'),
      (Icons.menu_rounded, 'Menu'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x2E282E78), blurRadius: 30, offset: Offset(0, -10), spreadRadius: -12)],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(items[i].$1, size: 28, color: i == index ? C.purple2 : C.ink2),
                    const SizedBox(height: 4),
                    Text(items[i].$2,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                            color: i == index ? C.purple2 : C.ink2)),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 4,
                      width: i == index ? 64 : 0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(colors: [C.purple2, C.blue]),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
