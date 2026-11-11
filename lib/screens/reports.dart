import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, IconData, Palette, Widget)>[
      ('Profit & Loss', 'Revenue, COGS, expenses, net profit', Icons.trending_up_rounded, Palette.green, const ProfitLossScreen()),
      ('Balance Sheet', 'Assets = Liabilities + Equity', Icons.account_balance_rounded, Palette.blue, const BalanceSheetScreen()),
      ('Trial Balance', 'Debit / credit check of every account', Icons.balance_rounded, Palette.purple, const TrialBalanceScreen()),
      ('Day Book', 'Every journal entry by date', Icons.menu_book_rounded, Palette.orange, const DayBookScreen()),
      ('GST Summary', 'Output GST, input credit, net payable', Icons.receipt_long_rounded, Palette.pink, const GstScreen()),
    ];
    return PageShell(title: 'Reports', subtitle: 'Generated live from your double-entry books', children: [
      CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Divided([
          for (final it in items)
            ListRow(
              leading: Orb(icon: it.$3, colors: it.$4.icon, bg: it.$4.bg, size: 44),
              title: it.$1,
              subtitle: it.$2,
              onTap: () => open(context, it.$5),
            ),
        ]),
      ),
    ]);
  }
}

class _RangeBar extends StatelessWidget {
  final String from, to;
  final void Function(String from, String to) onChanged;
  const _RangeBar(this.from, this.to, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final presets = <String, (String, String)>{
      'This month': (ymd(DateTime(now.year, now.month, 1)), ymd(now)),
      'Last month': (ymd(DateTime(now.year, now.month - 1, 1)), ymd(DateTime(now.year, now.month, 0))),
      'This FY': (ymd(DateTime(now.month >= 4 ? now.year : now.year - 1, 4, 1)), ymd(now)),
      'Today': (ymd(now), ymd(now)),
    };
    return CardBox(
      child: Column(children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final p in presets.entries)
            ChoiceChip(
              label: Text(p.key),
              selected: from == p.value.$1 && to == p.value.$2,
              onSelected: (_) => onChanged(p.value.$1, p.value.$2),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DateField(label: 'From', value: from, onChanged: (v) => onChanged(v, to))),
          const SizedBox(width: 10),
          Expanded(child: DateField(label: 'To', value: to, onChanged: (v) => onChanged(from, v))),
        ]),
      ]),
    );
  }
}

class ProfitLossScreen extends StatefulWidget {
  final String? from, to;
  const ProfitLossScreen({super.key, this.from, this.to});
  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  late String from = widget.from ?? ymd(DateTime(DateTime.now().year, DateTime.now().month, 1));
  late String to = widget.to ?? ymd(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Live<ProfitLoss>(
      key: ValueKey('$from$to'),
      load: () => Books.profitLoss(from, to),
      builder: (context, pl) => PageShell(
        title: 'Profit & Loss',
        subtitle: '${prettyDate(from)} – ${prettyDate(to)}',
        children: [
          _RangeBar(from, to, (f, t) => setState(() {
                from = f;
                to = t;
              })),
          CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FormHeading('Income'),
              for (final e in pl.income) TotalLine(e.key, Money.rs(e.value)),
              if (pl.income.isEmpty) const TotalLine('—', '₹0'),
              const Divider(color: C.line),
              TotalLine('Total income', Money.rs(pl.totalIncome), bold: true),
              const SizedBox(height: 10),
              TotalLine('Cost of goods sold', '− ${Money.rs(pl.cogs)}'),
              TotalLine('Gross profit (sales − COGS)', Money.rs(pl.grossProfit), color: pl.grossProfit >= 0 ? C.green : C.red),
              const SizedBox(height: 10),
              const FormHeading('Operating expenses'),
              for (final e in pl.expenses) TotalLine(e.key, Money.rs(e.value)),
              if (pl.expenses.isEmpty) const TotalLine('—', '₹0'),
              const Divider(color: C.line),
              TotalLine('Total expenses', Money.rs(pl.operatingExpenses)),
            ]),
          ),
          CardBox(
            gradient: LinearGradient(
                colors: pl.netProfit >= 0
                    ? const [Color(0xFF1BB574), Color(0xFF0F8C58)]
                    : const [Color(0xFFFF6B6B), Color(0xFFDC4545)]),
            child: Row(children: [
              Expanded(
                child: Text(pl.netProfit >= 0 ? 'Net profit' : 'Net loss',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              Text(Money.rs(pl.netProfit.abs()),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ),
    );
  }
}

class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});
  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  String to = ymd(DateTime.now());

  Widget _group(String title, List<MapEntry<String, int>> rows, int total, {List<Widget> extra = const []}) => CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FormHeading(title),
          for (final e in rows) TotalLine(e.key, Money.rs(e.value)),
          ...extra,
          const Divider(color: C.line),
          TotalLine('Total ${title.toLowerCase()}', Money.rs(total), bold: true),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Live<BalanceSheet>(
      key: ValueKey(to),
      load: () => Books.balanceSheet(to),
      builder: (context, bs) {
        final ok = bs.totalAssets == bs.totalLiabilities + bs.totalEquity;
        return PageShell(
          title: 'Balance Sheet',
          subtitle: 'As on ${prettyDate(to)}',
          children: [
            CardBox(child: DateField(label: 'As on', value: to, onChanged: (v) => setState(() => to = v))),
            _group('Assets', bs.assets, bs.totalAssets),
            _group('Liabilities', bs.liabilities, bs.totalLiabilities),
            _group('Equity', bs.equity, bs.totalEquity,
                extra: [TotalLine('Profit / loss to date', Money.rs(bs.profit))]),
            CardBox(
              child: TotalLine(
                ok ? '✓ Books are balanced' : '✗ Books do not balance',
                'Liab. + Equity ${Money.rs(bs.totalLiabilities + bs.totalEquity)}',
                color: ok ? C.green : C.red,
              ),
            ),
          ],
        );
      },
    );
  }
}

class TrialBalanceScreen extends StatelessWidget {
  const TrialBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      load: () => Books.trialBalance(),
      builder: (context, rows) {
        var dr = 0, cr = 0;
        final lines = <Widget>[];
        for (final r in rows) {
          final net = asInt(r['dr']) - asInt(r['cr']);
          if (net > 0) dr += net;
          if (net < 0) cr -= net;
          lines.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              Expanded(child: Text('${r['code']}  ${r['name']}', style: const TextStyle(fontSize: 13.5))),
              SizedBox(width: 92, child: Text(net > 0 ? Money.inr(net) : '', textAlign: TextAlign.right)),
              SizedBox(width: 92, child: Text(net < 0 ? Money.inr(-net) : '', textAlign: TextAlign.right)),
            ]),
          ));
        }
        const head = TextStyle(fontWeight: FontWeight.w700, color: C.muted, fontSize: 12);
        return PageShell(title: 'Trial Balance', subtitle: 'All accounts · to date', children: [
          CardBox(
            child: Column(children: [
              const Row(children: [
                Expanded(child: Text('ACCOUNT', style: head)),
                SizedBox(width: 92, child: Text('DEBIT ₹', textAlign: TextAlign.right, style: head)),
                SizedBox(width: 92, child: Text('CREDIT ₹', textAlign: TextAlign.right, style: head)),
              ]),
              const Divider(color: C.line),
              ...lines,
              const Divider(color: C.line),
              Row(children: [
                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(width: 92, child: Text(Money.inr(dr), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(width: 92, child: Text(Money.inr(cr), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 8),
              Text(dr == cr ? '✓ Debits equal credits' : '✗ Difference ${Money.rs(dr - cr)}',
                  style: TextStyle(color: dr == cr ? C.green : C.red, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]);
      },
    );
  }
}

class DayBookScreen extends StatefulWidget {
  final String? from, to;
  const DayBookScreen({super.key, this.from, this.to});
  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> {
  late String from = widget.from ?? ymd(DateTime.now());
  late String to = widget.to ?? ymd(DateTime.now());

  Future<List<Rec>> _load() => Books.query(
      'SELECT e.id, e.date, e.ref, e.narration, a.name AS account, l.debit, l.credit FROM journal_entries e '
      'JOIN journal_lines l ON l.entry_id = e.id JOIN accounts a ON a.id = l.account_id '
      'WHERE e.date >= ? AND e.date <= ? ORDER BY e.date DESC, e.id DESC, l.id',
      [from, to]);

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      key: ValueKey('$from$to'),
      load: _load,
      builder: (context, rows) {
        final entries = <int, List<Rec>>{};
        for (final r in rows) {
          entries.putIfAbsent(asInt(r['id']), () => []).add(r);
        }
        return PageShell(title: 'Day Book', subtitle: '${entries.length} journal entries', children: [
          _RangeBar(from, to, (f, t) => setState(() {
                from = f;
                to = t;
              })),
          if (entries.isEmpty) const CardBox(child: EmptyState('No entries in this period')),
          for (final lines in entries.values)
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${lines.first['narration'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${lines.first['ref']} · ${prettyDate(lines.first['date'] as String)}',
                    style: const TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 6),
                for (final l in lines)
                  Row(children: [
                    Expanded(
                      child: Text(asInt(l['debit']) > 0 ? '${l['account']}  Dr' : '      To ${l['account']}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(Money.inr(asInt(l['debit']) > 0 ? asInt(l['debit']) : asInt(l['credit'])),
                        style: TextStyle(fontSize: 13, color: asInt(l['debit']) > 0 ? C.ink : C.green)),
                  ]),
              ]),
            ),
        ]);
      },
    );
  }
}

class GstScreen extends StatefulWidget {
  final String? from, to;
  const GstScreen({super.key, this.from, this.to});
  @override
  State<GstScreen> createState() => _GstScreenState();
}

class _GstScreenState extends State<GstScreen> {
  late String from = widget.from ?? ymd(DateTime(DateTime.now().year, DateTime.now().month, 1));
  late String to = widget.to ?? ymd(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Live<List<int>>(
      key: ValueKey('$from$to'),
      load: () async => [
        await Books.balanceByCode(gstOutCode, from: from, to: to),
        await Books.balanceByCode(gstInCode, from: from, to: to),
        asInt((await Books.query('SELECT COALESCE(SUM(subtotal - discount),0) AS v FROM sales WHERE date >= ? AND date <= ?',
                [from, to]))
            .first['v']),
        asInt((await Books.query('SELECT COALESCE(SUM(subtotal),0) AS v FROM purchases WHERE date >= ? AND date <= ?',
                [from, to]))
            .first['v']),
      ],
      builder: (context, g) => PageShell(title: 'GST Summary', subtitle: 'Estimate — verify before filing', children: [
        _RangeBar(from, to, (f, t) => setState(() {
              from = f;
              to = t;
            })),
        CardBox(
          child: Column(children: [
            TotalLine('Taxable sales', Money.rs(g[2])),
            TotalLine('Output GST (collected)', Money.rs(g[0])),
            const Divider(color: C.line),
            TotalLine('Taxable purchases', Money.rs(g[3])),
            TotalLine('Input tax credit (paid)', Money.rs(g[1])),
            const Divider(color: C.line),
            TotalLine('Net GST payable', Money.rs(g[0] - g[1]), bold: true, color: g[0] - g[1] > 0 ? C.red : C.green),
          ]),
        ),
      ]),
    );
  }
}
