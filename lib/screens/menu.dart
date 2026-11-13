import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../main.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'account.dart';
import 'activity.dart';
import 'backup_screen.dart';
import 'emi.dart';
import 'imei.dart';
import 'security.dart';
import 'bank.dart';
import 'expenses.dart';
import 'ledgers.dart';
import 'notifications.dart';
import 'parties.dart';
import 'products.dart';
import 'purchase_form.dart';
import 'reports.dart';
import 'sale_form.dart';
import 'sales.dart';
import 'search.dart';
import 'settings.dart';

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);

TextStyle _j(double size, FontWeight w, Color c, {double? height}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
    );

class _MenuData {
  final Map<String, String> settings;
  final HomeMetrics m;
  final InventoryStats stock;
  final int alerts, sales, purchases, customers, suppliers, money, payable;
  _MenuData(this.settings, this.m, this.stock, this.alerts, this.sales, this.purchases, this.customers, this.suppliers,
      this.money, this.payable);
}

class _Item {
  final String title, sub;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final String? badge;
  final bool alert;
  const _Item(this.title, this.sub, this.icon, this.colors, this.onTap, {this.badge, this.alert = false});
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String q = '';

  Future<_MenuData> _load() async {
    Future<int> count(String t) async => asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']);
    var money = 0;
    for (final a in await Books.moneyAccounts()) {
      money += await Books.balance(asInt(a['id']), 'asset');
    }
    return _MenuData(
      await Books.settings(),
      await Books.homeMetrics(),
      await Books.inventoryStats(),
      (await Books.notifications()).length,
      await count('sales'),
      await count('purchases'),
      await count('customers'),
      await count('suppliers'),
      money,
      (await Books.partyBalances('supplier')).values.where((v) => v > 0).fold(0, (a, b) => a + b),
    );
  }

  List<(String, List<_Item>)> _groups(_MenuData d) {
    void go(Widget w) => open(context, w);
    return [
      ('Sales & billing', [
        _Item('Sales invoices', 'Every sale, payments and dues', Icons.receipt_long_rounded,
            const [Color(0xFF8B5CF6), Color(0xFF5B2EE0)], () => go(const SalesScreen()), badge: '${d.sales}'),
        _Item('Purchases', 'Supplier bills and stock in', Icons.shopping_bag_rounded,
            const [Color(0xFFB58CFF), Color(0xFF7B3FF2)], () => go(const PurchasesScreen()), badge: '${d.purchases}'),
        _Item('Expenses', 'Rent, salary, bills & more', Icons.sell_rounded,
            const [Color(0xFFFF7A7A), Color(0xFFDC4545)], () => go(const ExpensesScreen())),
        _Item('Cash & Bank', 'Cash, SBI, UPI · transfers', Icons.account_balance_rounded,
            const [Color(0xFFFF5C7A), Color(0xFFD81E4A)], () => go(const BankScreen()), badge: Money.compact(d.money)),
        _Item('EMI / Kisti', 'Finance & shop instalments, reminders', Icons.calendar_month_rounded,
            const [Color(0xFF2DD4BF), Color(0xFF0E7490)], () => go(const EmiScreen())),
      ]),
      ('Parties', [
        _Item('Customers', 'Ledger, dues & payments', Icons.groups_rounded, const [Color(0xFF4FD8E0), Color(0xFF139DB0)],
            () => go(const PartiesScreen(type: 'customer')),
            badge: d.m.totalDue > 0 ? 'Due ${Money.compact(d.m.totalDue)}' : '${d.customers}', alert: d.m.totalDue > 0),
        _Item('Suppliers', 'Bills, payable & payments', Icons.local_shipping_rounded,
            const [Color(0xFFFFA24A), Color(0xFFF06A1A)], () => go(const PartiesScreen(type: 'supplier')),
            badge: d.payable > 0 ? 'Pay ${Money.compact(d.payable)}' : '${d.suppliers}', alert: d.payable > 0),
      ]),
      ('Inventory', [
        _Item('Products', 'Stock, photos, prices & profit', Icons.view_in_ar_rounded,
            const [Color(0xFF6AA5FF), Color(0xFF1A47C8)], () => Shell.goTo(context, 2), badge: '${d.stock.total}'),
        _Item('Low stock', 'Running low or out of stock', Icons.warning_amber_rounded,
            const [Color(0xFFFFC14D), Color(0xFFF29D0B)], () => go(const ProductsScreen(lowOnly: true)),
            badge: '${d.stock.alerts}', alert: d.stock.alerts > 0),
        _Item('IMEI & Warranty', 'Scan to see device history & warranty', Icons.qr_code_scanner_rounded,
            const [Color(0xFF818CF8), Color(0xFF4338CA)], () => go(const ImeiScreen())),
      ]),
      ('Accounting & reports', [
        _Item('Analytics dashboard', 'Charts by day, week, month, year', Icons.insights_rounded,
            const [Color(0xFF7B5CFF), Color(0xFF3155C8)], () => Shell.goTo(context, 1)),
        _Item('Ledgers', 'Customer, supplier & account books', Icons.menu_book_rounded,
            const [Color(0xFFFFB547), Color(0xFFF08A24)], () => go(const LedgersScreen())),
        _Item('Profit & Loss', 'Revenue, cost, expenses, net profit', Icons.trending_up_rounded,
            const [Color(0xFF3EE08F), Color(0xFF0E9F5E)], () => go(const ProfitLossScreen())),
        _Item('Balance Sheet', 'Assets = Liabilities + Equity', Icons.account_balance_wallet_rounded,
            const [Color(0xFF6AA5FF), Color(0xFF2F6BFF)], () => go(const BalanceSheetScreen())),
        _Item('GST Summary', 'Output GST, input credit, payable', Icons.request_quote_rounded,
            const [Color(0xFFF472B6), Color(0xFFDB2777)], () => go(const GstScreen())),
        _Item('Trial Balance', 'Debit = credit check', Icons.balance_rounded,
            const [Color(0xFFA47BFF), Color(0xFF6A35D9)], () => go(const TrialBalanceScreen())),
        _Item('Day Book', 'Every journal entry by date', Icons.event_note_rounded,
            const [Color(0xFF5EEAD4), Color(0xFF0D9488)], () => go(const DayBookScreen())),
      ]),
      ('App', [
        _Item('Notifications', 'Stock, dues and payables', Icons.notifications_rounded,
            const [Color(0xFFFF7A9A), Color(0xFFF72552)], () => go(const NotificationsScreen()),
            badge: d.alerts > 0 ? '${d.alerts}' : null, alert: d.alerts > 0),
        _Item('Activity log', 'Audit trail of every action', Icons.history_rounded,
            const [Color(0xFF94A3B8), Color(0xFF475569)], () => go(const ActivityScreen())),
        _Item('Search everything', 'Customers, invoices, products, IMEI', Icons.manage_search_rounded,
            const [Color(0xFF818CF8), Color(0xFF4F46E5)], () => go(const SearchScreen())),
        _Item('Account & Cloud', 'Login · cloud backup on any phone', Icons.account_circle_rounded,
            const [Color(0xFF8B5CF6), Color(0xFF1B2163)], () => go(const AccountScreen())),
        _Item('Backup & Restore', 'Save everything to Drive, restore anytime', Icons.cloud_upload_rounded,
            const [Color(0xFF34D399), Color(0xFF0F8C58)], () => go(const BackupScreen())),
        _Item('Security', 'App lock with PIN & fingerprint', Icons.lock_rounded,
            const [Color(0xFF6B35EE), Color(0xFF1B2163)], () => go(const SecurityScreen())),
        _Item('Business settings', 'Shop profile, photo, GSTIN, demo data', Icons.settings_rounded,
            const [Color(0xFF64748B), Color(0xFF1E293B)], () => go(const SettingsScreen())),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = LiquidGlassNav.outerHeight(MediaQuery.of(context).padding.bottom, context) + 24;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Live<_MenuData>(
          load: _load,
          builder: (context, d) {
            final groups = _groups(d);
            final query = q.trim().toLowerCase();
            final results = query.isEmpty
                ? <_Item>[]
                : [
                    for (final g in groups)
                      for (final it in g.$2)
                        if (it.title.toLowerCase().contains(query) || it.sub.toLowerCase().contains(query)) it
                  ];
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
              children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Menu', style: _j(24, FontWeight.w800, _navy)),
                      Text('Every feature in one place', style: _j(12.5, FontWeight.w500, const Color(0xFF323B60))),
                    ]),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/home/logo.png', width: 46, height: 46, fit: BoxFit.fill),
                  ),
                ]),
                const SizedBox(height: 14),
                _ProfileCard(d),
                const SizedBox(height: 14),
                _searchField(),
                const SizedBox(height: 14),
                if (query.isNotEmpty) ...[
                  if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Nothing matches “$q”', textAlign: TextAlign.center, style: _j(13, FontWeight.w500, _muted)),
                    )
                  else
                    _group('Results', results),
                ] else ...[
                  _quickActions(),
                  for (final g in groups) ...[const SizedBox(height: 18), _group(g.$1, g.$2)],
                  const SizedBox(height: 26),
                  _footer(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _searchField() => Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: const Color(0xFFE9EAF5)),
          boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -4)],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: Color(0xFF2C3B8F)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              style: _j(14, FontWeight.w500, _ink),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search features, reports, settings…',
                hintStyle: _j(13.5, FontWeight.w400, const Color(0xFF8A8FAD)),
              ),
            ),
          ),
        ]),
      );

  Widget _quickActions() {
    final items = <(String, String, VoidCallback)>[
      ('New sale', 'qa_sales', () => open(context, const SaleForm())),
      ('Purchase', 'qa_purchase', () => open(context, const PurchaseForm())),
      ('Add product', 'qa_product', () => open(context, const ProductForm())),
      ('Expense', 'qa_expense', () => open(context, const ExpensesScreen())),
    ];
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: items[i].$3,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFEEF0F8)),
                boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -6)],
              ),
              child: Column(children: [
                Image.asset('assets/home/${items[i].$2}.png', width: 46, height: 46),
                const SizedBox(height: 6),
                Text(items[i].$1, maxLines: 1, style: _j(11.5, FontWeight.w600, _ink)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _group(String title, List<_Item> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(title.toUpperCase(), style: _j(11.5, FontWeight.w700, _muted).copyWith(letterSpacing: 1.1)),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEEF0F8)),
          boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 68, color: Color(0xFFEEF0F8)),
              _row(items[i]),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _row(_Item it) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: it.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(colors: it.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: it.colors.last.withAlpha(0x59), blurRadius: 10, offset: const Offset(0, 4), spreadRadius: -3)],
              ),
              child: Stack(children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withAlpha(0x4D), Colors.white.withAlpha(0)],
                      ),
                    ),
                  ),
                ),
                Center(child: Icon(it.icon, color: Colors.white, size: 21)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, style: _j(14, FontWeight.w700, _ink)),
                const SizedBox(height: 2),
                Text(it.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w500, _muted)),
              ]),
            ),
            if (it.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: it.alert ? const Color(0xFFFDE4EA) : const Color(0xFFF0EEFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(it.badge!,
                    style: _j(11, FontWeight.w700, it.alert ? const Color(0xFFC8102E) : const Color(0xFF4A17C9))),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9BCD6)),
          ]),
        ),
      ),
    );
  }

  Widget _footer() => Column(children: [
        Opacity(
          opacity: .9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/home/logo.png', width: 34, height: 34),
          ),
        ),
        const SizedBox(height: 8),
        Text('GameX Hisab · v1.0', style: _j(12, FontWeight.w700, _navy)),
        const SizedBox(height: 2),
        Text('Offline & private — your data stays on this phone', style: _j(11, FontWeight.w500, _muted)),
      ]);
}

/// Gradient profile card with the owner's photo and today's numbers.
class _ProfileCard extends StatelessWidget {
  final _MenuData d;
  const _ProfileCard(this.d);

  @override
  Widget build(BuildContext context) {
    final owner = d.settings['owner_name'] ?? 'Super Admin';
    final biz = (d.settings['business_name'] ?? 'GameX PC Hub').replaceAll('GAMEX', 'GameX');
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -60,
            top: -60,
            child: Container(
              width: 190,
              height: 190,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)]),
              ),
            ),
          ),
          Positioned(right: -8, top: 4, child: Opacity(opacity: .9, child: Image.asset('assets/home/hero.png', width: 170))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => open(context, const SettingsScreen()),
                  child: Container(
                    width: 60,
                    height: 60,
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFC4B5FD)]),
                    ),
                    child: ClipOval(
                      child: storedImage(
                        d.settings['owner_photo'],
                        fallback: Container(
                          color: const Color(0xFFEAF0FF),
                          child: const Icon(Icons.person_rounded, color: Color(0xFF2F6BFF), size: 36),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(owner, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(18, FontWeight.w800, Colors.white)),
                    Text(biz, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w500, const Color(0xD9FFFFFF))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.verified_rounded, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                        Text('Super Admin', style: _j(10.5, FontWeight.w700, Colors.white)),
                      ]),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x40FFFFFF)),
                    ),
                    child: Row(children: [
                      _stat("Today's sales", Money.compact(d.m.todaySales)),
                      _div(),
                      _stat('Total due', Money.compact(d.m.totalDue)),
                      _div(),
                      _stat('Stock alerts', '${d.stock.alerts}'),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static Widget _div() => Container(width: 1, height: 30, color: const Color(0x40FFFFFF));

  static Widget _stat(String label, String v) => Expanded(
        child: Column(children: [
          Text(label, style: _j(10.5, FontWeight.w500, const Color(0xCCFFFFFF))),
          const SizedBox(height: 3),
          Text(v, style: _j(15, FontWeight.w800, Colors.white)),
        ]),
      );
}
