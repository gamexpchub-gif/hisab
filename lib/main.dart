import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dashboard.dart';
import 'screens/home.dart';
import 'screens/menu.dart';
import 'screens/products.dart';
import 'screens/sale_form.dart';
import 'ui/theme.dart';
import 'ui/liquid_nav.dart';
import 'ui/widgets.dart';

export 'ui/liquid_nav.dart';

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
    final navOuter = LiquidGlassNav.outerHeight(mq.padding.bottom, context);
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
              right: p(22),
              bottom: navOuter + p(22),
              child: NewSaleFab(onTap: () => open(context, const SaleForm())),
            ),
        ]),
        bottomNavigationBar: LiquidGlassNav(index: index, onTap: select),
      ),
    );
  }
}
