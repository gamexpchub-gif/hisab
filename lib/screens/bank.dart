import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'ledgers.dart';

class BankScreen extends StatelessWidget {
  const BankScreen({super.key});

  Future<(List<(Rec, int)>, List<Rec>)> _load() async {
    final out = <(Rec, int)>[];
    for (final a in await Books.moneyAccounts()) {
      out.add((a, await Books.balance(asInt(a['id']), 'asset')));
    }
    final transfers = await Books.query(
        'SELECT t.*, f.name AS from_name, d.name AS to_name FROM transfers t JOIN accounts f ON f.id = t.from_id '
        'JOIN accounts d ON d.id = t.to_id ORDER BY t.id DESC LIMIT 20');
    return (out, transfers);
  }

  IconData _icon(String? kind) =>
      kind == 'cash' ? Icons.payments_rounded : kind == 'upi' ? Icons.qr_code_2_rounded : Icons.account_balance_rounded;

  @override
  Widget build(BuildContext context) {
    return Live<(List<(Rec, int)>, List<Rec>)>(
      load: _load,
      builder: (context, d) {
        final total = d.$1.fold<int>(0, (a, e) => a + e.$2);
        return PageShell(
          title: 'Cash & Bank',
          subtitle: 'Total money ${Money.rs(total)}',
          action: GradientButton(
            label: 'Transfer',
            icon: Icons.swap_horiz_rounded,
            onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const TransferSheet()),
          ),
          children: [
            CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Divided([
                for (final e in d.$1)
                  ListRow(
                    leading: Avatar('', icon: _icon(e.$1['kind'] as String?), bg: const Color(0xFFFFEAF0), fg: const Color(0xFFD81E4A)),
                    title: e.$1['name'] as String,
                    subtitle: '${e.$1['kind']}'.toUpperCase(),
                    trailing: Money.rs(e.$2),
                    trailingColor: e.$2 < 0 ? C.red : C.ink,
                    onTap: () => open(context, AccountLedgerScreen(accountId: asInt(e.$1['id']))),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const _NewAccountSheet()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add bank / UPI / wallet account'),
            ),
            CardBox(
              child: Column(children: [
                const SectionTitle('Recent transfers'),
                if (d.$2.isEmpty) const EmptyState('No transfers yet'),
                Divided([
                  for (final t in d.$2)
                    ListRow(
                      leading: const Avatar('', icon: Icons.swap_horiz_rounded),
                      title: '${t['from_name']} → ${t['to_name']}',
                      subtitle: '${t['number']} · ${prettyDate(t['date'] as String)}',
                      trailing: Money.rs(asInt(t['amount'])),
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

class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key});
  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final amount = TextEditingController();
  final note = TextEditingController();
  List<Rec> accounts = [];
  int? from, to;
  String date = ymd(DateTime.now());

  @override
  void initState() {
    super.initState();
    Books.moneyAccounts().then((a) => setState(() {
          accounts = a;
          if (a.length > 1) {
            from = asInt(a[0]['id']);
            to = asInt(a[1]['id']);
          }
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Transfer money', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const Text('e.g. cash deposited to bank, UPI settlement to bank', style: TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        RowPicker(label: 'From', rows: accounts, value: from, onChanged: (v) => setState(() => from = v)),
        RowPicker(label: 'To', rows: accounts, value: to, onChanged: (v) => setState(() => to = v)),
        field(amount, 'Amount ₹', number: true),
        DateField(value: date, onChanged: (v) => setState(() => date = v)),
        field(note, 'Note'),
        GradientButton(
          label: 'Save transfer',
          expand: true,
          fontSize: 16,
          onTap: () async {
            try {
              await Books.createTransfer(
                  fromId: from ?? 0, toId: to ?? 0, amount: Money.parse(amount.text), date: date, note: note.text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              toast(context, 'Transfer recorded');
            } catch (e) {
              toast(context, '$e', error: true);
            }
          },
        ),
      ]),
    );
  }
}

class _NewAccountSheet extends StatefulWidget {
  const _NewAccountSheet();
  @override
  State<_NewAccountSheet> createState() => _NewAccountSheetState();
}

class _NewAccountSheetState extends State<_NewAccountSheet> {
  final name = TextEditingController();
  String kind = 'bank';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('New money account', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        field(name, 'Name (e.g. HDFC Current, Paytm)'),
        Wrap(spacing: 8, children: [
          for (final k in ['bank', 'upi', 'cash'])
            ChoiceChip(label: Text(k.toUpperCase()), selected: kind == k, onSelected: (_) => setState(() => kind = k)),
        ]),
        const SizedBox(height: 14),
        GradientButton(
          label: 'Add account',
          expand: true,
          fontSize: 16,
          onTap: () async {
            try {
              await Books.addMoneyAccount(name.text, kind);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            } catch (e) {
              toast(context, '$e', error: true);
            }
          },
        ),
      ]),
    );
  }
}
