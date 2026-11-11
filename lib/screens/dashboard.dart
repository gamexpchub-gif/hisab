import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'products.dart';
import 'parties.dart';
import 'reports.dart';
import 'sales.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<DashboardData>(
      load: Books.dashboard,
      builder: (context, d) => PageShell(
        title: 'Dashboard',
        subtitle: 'Live business health · ${prettyDate(ymd(DateTime.now()))}',
        showBack: false,
        children: [
          KpiGrid([
            Kpi("Today's net profit", d.profitToday, accent: true),
            Kpi("Today's gross profit", d.grossToday, color: d.grossToday >= 0 ? C.green : C.red),
            Kpi('Receivable (customers)', d.receivable, color: C.red),
            Kpi('Payable (suppliers)', d.payable),
            for (final m in d.money) Kpi(m.key, m.value),
            Kpi('Stock value (at cost)', d.stockValue),
          ]),
          CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.bar_chart_rounded, color: C.blue),
                SizedBox(width: 8),
                Expanded(child: Text('Monthly revenue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                _Legend(Color(0xFF5B4BEA), 'Sales'),
                SizedBox(width: 10),
                _Legend(Color(0xFFB9C3F7), 'Purchase'),
              ]),
              const SizedBox(height: 12),
              _MonthChart(d.months),
            ]),
          ),
          CardBox(
            child: Column(children: [
              SectionTitle('This month P&L',
                  actionLabel: 'Full report', onAction: () => open(context, const ProfitLossScreen())),
              const SizedBox(height: 8),
              TotalLine('Sales revenue', Money.rs(d.month.revenue)),
              TotalLine('Cost of goods sold', '− ${Money.rs(d.month.cogs)}'),
              TotalLine('Gross profit', Money.rs(d.month.grossProfit)),
              TotalLine('Operating expenses', '− ${Money.rs(d.month.operatingExpenses)}'),
              const Divider(color: C.line),
              TotalLine('Net profit', Money.rs(d.month.netProfit),
                  bold: true, color: d.month.netProfit >= 0 ? C.green : C.red),
            ]),
          ),
          CardBox(
            child: Column(children: [
              SectionTitle('Low stock alerts',
                  actionLabel: 'All', onAction: () => open(context, const ProductsScreen(lowOnly: true))),
              if (d.lowStock.isEmpty) const EmptyState('All products are well stocked'),
              Divided([
                for (final p in d.lowStock)
                  ListRow(
                    leading: Avatar('${p['stock']}', bg: const Color(0xFFFDE8E8), fg: C.red),
                    title: p['name'] as String,
                    subtitle: 'Alert at ${p['low_stock']}',
                    trailing: 'Reorder',
                    trailingColor: C.red,
                    onTap: () => open(context, ProductView(id: asInt(p['id']))),
                  ),
              ]),
            ]),
          ),
          CardBox(
            child: Column(children: [
              const SectionTitle('Highest dues'),
              if (d.topDue.isEmpty) const EmptyState('No outstanding dues'),
              Divided([
                for (final c in d.topDue)
                  ListRow(
                    leading: Avatar((c['name'] as String)[0]),
                    title: c['name'] as String,
                    subtitle: c['phone'] as String?,
                    trailing: Money.rs(asInt(c['due'])),
                    trailingColor: C.red,
                    onTap: () => open(context, PartyView(type: 'customer', id: asInt(c['id']))),
                  ),
              ]),
            ]),
          ),
          CardBox(
            child: Column(children: [
              const SectionTitle('Top products this month'),
              if (d.topProducts.isEmpty) const EmptyState('No sales this month yet'),
              Divided([
                for (var i = 0; i < d.topProducts.length; i++)
                  ListRow(
                    leading: Avatar('${i + 1}'),
                    title: d.topProducts[i]['name'] as String,
                    subtitle: '${d.topProducts[i]['qty']} sold',
                    trailing: Money.rs(asInt(d.topProducts[i]['amount'])),
                  ),
              ]),
            ]),
          ),
          CardBox(
            child: Column(children: [
              SectionTitle('Recent invoices', actionLabel: 'All', onAction: () => open(context, const SalesScreen())),
              if (d.recentSales.isEmpty) const EmptyState('No invoices yet'),
              Divided([for (final s in d.recentSales) SaleRow(s)]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
      ]);
}

class _MonthChart extends StatelessWidget {
  final List<MonthBar> months;
  const _MonthChart(this.months);

  @override
  Widget build(BuildContext context) {
    var top = 1;
    for (final m in months) {
      if (m.sales > top) top = m.sales;
      if (m.purchases > top) top = m.purchases;
    }
    Widget bar(int v, List<Color> colors) => Container(
          width: 14,
          height: 3 + 140 * v / top,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)),
            gradient: LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
        );
    return SizedBox(
      height: 172,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final m in months)
          Expanded(
            child: Tooltip(
              message: 'Sales ${Money.rs(m.sales)}\nPurchase ${Money.rs(m.purchases)}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  bar(m.sales, const [Color(0xFF7B5CFF), Color(0xFF3155C8)]),
                  const SizedBox(width: 4),
                  bar(m.purchases, const [Color(0xFFC9BCFF), Color(0xFF9EB4F5)]),
                ]),
                const SizedBox(height: 6),
                Text(m.label, style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}
