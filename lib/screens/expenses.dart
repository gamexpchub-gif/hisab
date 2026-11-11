import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final monthStart = ymd(DateTime(DateTime.now().year, DateTime.now().month, 1));
    return Live<List<Rec>>(
      load: () => Books.query(
          'SELECT e.*, h.name AS head, a.name AS account FROM expenses e JOIN accounts h ON h.id = e.head_id '
          'JOIN accounts a ON a.id = e.account_id ORDER BY e.date DESC, e.id DESC LIMIT 500'),
      builder: (context, rows) {
        final month = rows.where((e) => (e['date'] as String).compareTo(monthStart) >= 0).fold<int>(0, (a, e) => a + asInt(e['amount']));
        return PageShell(
          title: 'Expenses',
          subtitle: 'This month ${Money.rs(month)}',
          action: GradientButton(
            label: 'Add',
            icon: Icons.add_rounded,
            onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const ExpenseSheet()),
          ),
          children: [
            CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: rows.isEmpty
                  ? const EmptyState('No expenses recorded')
                  : Divided([
                      for (final e in rows)
                        ListRow(
                          leading: const Avatar('', icon: Icons.sell_rounded, bg: Color(0xFFFFECEC), fg: C.red),
                          title: e['head'] as String,
                          subtitle: '${prettyDate(e['date'] as String)} · ${e['account']}${e['note'] != null ? ' · ${e['note']}' : ''}',
                          trailing: Money.rs(asInt(e['amount'])),
                          trailingColor: C.red,
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key});
  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  final amount = TextEditingController();
  final note = TextEditingController();
  final newHead = TextEditingController();
  List<Rec> heads = [], accounts = [];
  int? head, account;
  String date = ymd(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    heads = await Books.accounts(kind: 'expense');
    accounts = await Books.moneyAccounts();
    head ??= heads.isNotEmpty ? asInt(heads.first['id']) : null;
    account ??= accounts.isNotEmpty ? asInt(accounts.first['id']) : null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add expense', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: RowPicker(label: 'Category', rows: heads, value: head, onChanged: (v) => setState(() => head = v))),
            IconButton(
              tooltip: 'New category',
              icon: const Icon(Icons.add_circle_outline_rounded, color: C.purple2),
              onPressed: () async {
                final name = await showDialog<String>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('New expense category'),
                    content: TextField(controller: newHead, autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, newHead.text), child: const Text('Add')),
                    ],
                  ),
                );
                if (name != null && name.trim().isNotEmpty) {
                  head = await Books.addExpenseHead(name);
                  newHead.clear();
                  _load();
                }
              },
            ),
          ]),
          field(amount, 'Amount ₹', number: true),
          RowPicker(label: 'Paid from', rows: accounts, value: account, onChanged: (v) => setState(() => account = v)),
          DateField(value: date, onChanged: (v) => setState(() => date = v)),
          field(note, 'Note'),
          GradientButton(
            label: 'Save expense',
            expand: true,
            fontSize: 16,
            onTap: () async {
              try {
                await Books.createExpense(
                  headId: head ?? 0,
                  amount: Money.parse(amount.text),
                  accountId: account ?? 0,
                  date: date,
                  note: note.text.trim().isEmpty ? null : note.text.trim(),
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
                toast(context, 'Expense saved');
              } catch (e) {
                toast(context, '$e', error: true);
              }
            },
          ),
        ]),
      ),
    );
  }
}
