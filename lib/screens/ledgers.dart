import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'parties.dart';

class LedgersScreen extends StatelessWidget {
  const LedgersScreen({super.key});

  Future<(List<(Rec, int)>, List<Rec>, Map<int, int>, List<Rec>, Map<int, int>)> _load() async {
    final accts = <(Rec, int)>[];
    for (final a in await Books.accounts()) {
      accts.add((a, await Books.balance(asInt(a['id']), a['type'] as String)));
    }
    return (
      accts,
      await Books.query('SELECT * FROM customers ORDER BY name'),
      await Books.partyBalances('customer'),
      await Books.query('SELECT * FROM suppliers ORDER BY name'),
      await Books.partyBalances('supplier'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Live<(List<(Rec, int)>, List<Rec>, Map<int, int>, List<Rec>, Map<int, int>)>(
        load: _load,
        builder: (context, d) => Scaffold(
          appBar: AppBar(
            title: const Text('Ledgers'),
            bottom: const TabBar(tabs: [Tab(text: 'Customers'), Tab(text: 'Suppliers'), Tab(text: 'Accounts')]),
          ),
          body: TabBarView(children: [
            _partyList(context, 'customer', d.$2, d.$3),
            _partyList(context, 'supplier', d.$4, d.$5),
            ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              CardBox(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Divided([
                  for (final e in d.$1)
                    ListRow(
                      leading: Avatar((e.$1['code'] as String).substring(0, 1), bg: _typeBg(e.$1['type'] as String)),
                      title: e.$1['name'] as String,
                      subtitle: '${e.$1['code']} · ${e.$1['type']}',
                      trailing: Money.rs(e.$2),
                      onTap: () => open(context, AccountLedgerScreen(accountId: asInt(e.$1['id']))),
                    ),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  static Color _typeBg(String t) => switch (t) {
        'asset' => const Color(0xFFEAF1FF),
        'liability' => const Color(0xFFFFF1E0),
        'equity' => const Color(0xFFEFEBFF),
        'income' => const Color(0xFFE3F7EC),
        _ => const Color(0xFFFFECEC),
      };

  Widget _partyList(BuildContext context, String type, List<Rec> rows, Map<int, int> bal) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
      CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: rows.isEmpty
            ? const EmptyState('Nothing here yet')
            : Divided([
                for (final r in rows)
                  ListRow(
                    leading: Avatar((r['name'] as String)[0].toUpperCase()),
                    title: r['name'] as String,
                    subtitle: r['phone'] as String?,
                    trailing: Money.rs(bal[asInt(r['id'])] ?? 0),
                    trailingColor: (bal[asInt(r['id'])] ?? 0) > 0 ? C.red : C.green,
                    onTap: () => open(context, PartyView(type: type, id: asInt(r['id']))),
                  ),
              ]),
      ),
    ]);
  }
}

class AccountLedgerScreen extends StatefulWidget {
  final int accountId;
  const AccountLedgerScreen({super.key, required this.accountId});
  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  String from = ymd(DateTime(DateTime.now().year, DateTime.now().month, 1));
  String to = ymd(DateTime.now());

  Future<(Rec, int, List<Rec>)> _load() async {
    final a = (await Books.query('SELECT * FROM accounts WHERE id = ?', [widget.accountId])).first;
    final type = a['type'] as String;
    final dayBefore = ymd(DateTime.parse(from).subtract(const Duration(days: 1)));
    final opening = await Books.balance(widget.accountId, type, to: dayBefore);
    final rows = await Books.ledger(accountId: widget.accountId, accountType: type, from: from, to: to);
    return (a, opening, [for (final r in rows) {...r, 'balance': asInt(r['balance']) + opening}]);
  }

  @override
  Widget build(BuildContext context) {
    return Live<(Rec, int, List<Rec>)>(
      key: ValueKey('$from$to'),
      load: _load,
      builder: (context, d) => PageShell(
        title: d.$1['name'] as String,
        subtitle: 'Account ${d.$1['code']} · ${d.$1['type']}',
        children: [
          CardBox(
            child: Column(children: [
              Row(children: [
                Expanded(child: DateField(label: 'From', value: from, onChanged: (v) => setState(() => from = v))),
                const SizedBox(width: 10),
                Expanded(child: DateField(label: 'To', value: to, onChanged: (v) => setState(() => to = v))),
              ]),
              TotalLine('Opening balance', Money.rs(d.$2)),
              TotalLine('Closing balance', Money.rs(d.$3.isEmpty ? d.$2 : asInt(d.$3.last['balance'])), bold: true),
            ]),
          ),
          CardBox(child: d.$3.isEmpty ? const EmptyState('No entries in this period') : LedgerTable(d.$3)),
        ],
      ),
    );
  }
}
