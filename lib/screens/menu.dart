import 'package:flutter/material.dart';

import '../core/books.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'activity.dart';
import 'bank.dart';
import 'expenses.dart';
import 'ledgers.dart';
import 'parties.dart';
import 'products.dart';
import 'purchase_form.dart';
import 'reports.dart';
import 'sale_form.dart';
import 'sales.dart';
import 'settings.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<(String, IconData, Palette, Widget)>)>[
      ('Billing', [
        ('New Sale', Icons.add_shopping_cart_rounded, Palette.green, const SaleForm()),
        ('Sales', Icons.bar_chart_rounded, Palette.violet, const SalesScreen()),
        ('New Purchase', Icons.shopping_bag_rounded, Palette.purple, const PurchaseForm()),
        ('Purchases', Icons.inventory_rounded, Palette.purple, const PurchasesScreen()),
        ('Expenses', Icons.sell_rounded, Palette.red, const ExpensesScreen()),
        ('Cash & Bank', Icons.account_balance_rounded, Palette.pink, const BankScreen()),
      ]),
      ('Parties & stock', [
        ('Customers', Icons.groups_rounded, Palette.teal, const PartiesScreen(type: 'customer')),
        ('Suppliers', Icons.local_shipping_rounded, Palette.amber, const PartiesScreen(type: 'supplier')),
        ('Products', Icons.view_in_ar_rounded, Palette.blue, const ProductsScreen()),
        ('Low Stock', Icons.warning_amber_rounded, Palette.red, const ProductsScreen(lowOnly: true)),
      ]),
      ('Accounting & reports', [
        ('Ledgers', Icons.menu_book_rounded, Palette.orange, const LedgersScreen()),
        ('Profit & Loss', Icons.trending_up_rounded, Palette.green, const ProfitLossScreen()),
        ('Balance Sheet', Icons.account_balance_wallet_rounded, Palette.blue, const BalanceSheetScreen()),
        ('Trial Balance', Icons.balance_rounded, Palette.purple, const TrialBalanceScreen()),
        ('Day Book', Icons.event_note_rounded, Palette.orange, const DayBookScreen()),
        ('GST Summary', Icons.receipt_long_rounded, Palette.pink, const GstScreen()),
        ('All Reports', Icons.analytics_rounded, Palette.violet, const ReportsScreen()),
        ('Activity Log', Icons.history_rounded, Palette.teal, const ActivityScreen()),
      ]),
      ('App', [
        ('Settings', Icons.settings_rounded, Palette.blue, const SettingsScreen()),
      ]),
    ];
    return Scaffold(
      body: SafeArea(
        child: Live<Map<String, String>>(
          load: Books.settings,
          builder: (context, s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
            children: [
              Glass(
                child: Row(children: [
                  const RoundIcon(size: 52, child: Icon(Icons.person_rounded, color: C.blue2, size: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s['owner_name'] ?? 'Super Admin', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(s['business_name'] ?? '', style: const TextStyle(color: C.ink2)),
                    ]),
                  ),
                  RoundIcon(icon: Icons.settings_rounded, onTap: () => open(context, const SettingsScreen())),
                ]),
              ),
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
                  child: Text(g.$1.toUpperCase(),
                      style: const TextStyle(fontSize: 12.5, letterSpacing: .8, color: C.muted, fontWeight: FontWeight.w600)),
                ),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.0,
                  children: [
                    for (final it in g.$2)
                      ActionTile(label: it.$1, icon: it.$2, palette: it.$3, onTap: () => open(context, it.$4)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
