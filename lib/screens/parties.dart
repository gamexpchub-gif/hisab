import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'purchase_form.dart';
import 'sale_form.dart';
import 'sales.dart';

String _table(String type) => type == 'customer' ? 'customers' : 'suppliers';

class PartiesScreen extends StatefulWidget {
  final String type; // customer | supplier
  const PartiesScreen({super.key, required this.type});
  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  String q = '';
  bool dueOnly = false;

  @override
  Widget build(BuildContext context) {
    final isC = widget.type == 'customer';
    return Live<(List<Rec>, Map<int, int>)>(
      key: ValueKey(q),
      load: () async => (
        await Books.query(
            'SELECT * FROM ${_table(widget.type)} WHERE name LIKE ? OR IFNULL(phone,\'\') LIKE ? ORDER BY name', ['%$q%', '%$q%']),
        await Books.partyBalances(widget.type),
      ),
      builder: (context, data) {
        final bal = data.$2;
        var rows = data.$1;
        if (dueOnly) rows = rows.where((r) => (bal[asInt(r['id'])] ?? 0) > 0).toList();
        final total = bal.values.where((v) => v > 0).fold<int>(0, (a, b) => a + b);
        return PageShell(
          title: isC ? 'Customers' : 'Suppliers',
          subtitle: '${data.$1.length} ${isC ? 'customers' : 'suppliers'} · ${isC ? 'receivable' : 'payable'} ${Money.rs(total)}',
          action: GradientButton(
              label: 'Add', icon: Icons.add_rounded, onTap: () => open(context, PartyForm(type: widget.type))),
          children: [
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(hintText: 'Search name or phone', prefixIcon: Icon(Icons.search_rounded)),
              onSubmitted: (v) => setState(() => q = v.trim()),
            ),
            const SizedBox(height: 10),
            Row(children: [
              ChoiceChip(label: const Text('All'), selected: !dueOnly, onSelected: (_) => setState(() => dueOnly = false)),
              const SizedBox(width: 8),
              ChoiceChip(
                  label: Text(isC ? 'With due' : 'To pay'),
                  selected: dueOnly,
                  onSelected: (_) => setState(() => dueOnly = true)),
            ]),
            CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: rows.isEmpty
                  ? EmptyState(isC ? 'No customers yet' : 'No suppliers yet')
                  : Divided([
                      for (final r in rows)
                        ListRow(
                          leading: Avatar((r['name'] as String).isEmpty ? '?' : (r['name'] as String)[0].toUpperCase(),
                              bg: isC ? const Color(0xFFE2FAFA) : const Color(0xFFFFF1E0),
                              fg: isC ? const Color(0xFF139DB0) : C.orange),
                          title: r['name'] as String,
                          subtitle: r['phone'] as String?,
                          trailing: Money.rs(bal[asInt(r['id'])] ?? 0),
                          trailingColor: (bal[asInt(r['id'])] ?? 0) > 0 ? C.red : C.green,
                          trailingSub: (bal[asInt(r['id'])] ?? 0) > 0 ? (isC ? 'Will receive' : 'Will pay') : 'Settled',
                          onTap: () => open(context, PartyView(type: widget.type, id: asInt(r['id']))),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

class PartyView extends StatelessWidget {
  final String type;
  final int id;
  const PartyView({super.key, required this.type, required this.id});

  @override
  Widget build(BuildContext context) {
    final isC = type == 'customer';
    return Live<(Rec?, int, List<Rec>)>(
      load: () async {
        final r = await Books.query('SELECT * FROM ${_table(type)} WHERE id = ?', [id]);
        return (
          r.isEmpty ? null : r.first,
          await Books.partyBalance(type, id),
          await Books.ledger(partyType: type, partyId: id),
        );
      },
      builder: (context, d) {
        final p = d.$1;
        if (p == null) return const PageShell(title: 'Not found', children: []);
        final bal = d.$2;
        return PageShell(
          title: p['name'] as String,
          subtitle: [p['phone'], p['gstin']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
          action: RoundIcon(icon: Icons.edit_rounded, onTap: () => open(context, PartyForm(type: type, party: p))),
          children: [
            CardBox(
              gradient: const LinearGradient(colors: [Color(0xFF5B2EE0), Color(0xFF3155C8)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isC ? 'Outstanding (you will receive)' : 'Outstanding (you will pay)',
                    style: const TextStyle(color: Color(0xCCFFFFFF))),
                const SizedBox(height: 4),
                Text(Money.rs(bal), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                if (isC && asInt(p['credit_limit']) > 0)
                  Text('Credit limit ${Money.rs(asInt(p['credit_limit']))}',
                      style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _WhiteButton(
                      icon: Icons.currency_rupee_rounded,
                      label: isC ? 'Receive payment' : 'Make payment',
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => PaymentSheet(kind: isC ? 'receipt' : 'payment', partyId: id, suggested: bal),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _WhiteButton(
                      icon: isC ? Icons.receipt_long_rounded : Icons.shopping_bag_rounded,
                      label: isC ? 'New sale' : 'New purchase',
                      onTap: () => open(context, isC ? SaleForm(customerId: id) : PurchaseForm(supplierId: id)),
                    ),
                  ),
                ]),
              ]),
            ),
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Ledger statement'),
                const SizedBox(height: 6),
                if (d.$3.isEmpty) const EmptyState('No transactions yet'),
                LedgerTable(d.$3),
              ]),
            ),
            if (isC)
              Live<List<Rec>>(
                load: () => Books.query(
                    'SELECT s.*, c.name AS customer FROM sales s LEFT JOIN customers c ON c.id = s.customer_id '
                    'WHERE s.customer_id = ? ORDER BY s.date DESC, s.id DESC',
                    [id]),
                builder: (context, sales) => sales.isEmpty
                    ? const SizedBox()
                    : CardBox(
                        child: Column(children: [
                          const SectionTitle('Invoices'),
                          Divided([for (final s in sales) SaleRow(s)]),
                        ]),
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _WhiteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _WhiteButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: C.purple2),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.purple2, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Running-balance statement (date, particulars, debit, credit, balance).
class LedgerTable extends StatelessWidget {
  final List<Rec> rows;
  const LedgerTable(this.rows, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final r in rows.reversed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['narration'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5)),
                Text('${prettyDate(r['date'] as String)} · ${r['ref']}',
                    style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (asInt(r['debit']) > 0)
                Text('Dr ${Money.rs(asInt(r['debit']))}', style: const TextStyle(color: C.ink, fontWeight: FontWeight.w600)),
              if (asInt(r['credit']) > 0)
                Text('Cr ${Money.rs(asInt(r['credit']))}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w600)),
              Text('Bal ${Money.rs(asInt(r['balance']))}', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ]),
        ),
    ]);
  }
}

class PaymentSheet extends StatefulWidget {
  final String kind; // receipt | payment
  final int partyId;
  final int suggested;
  const PaymentSheet({super.key, required this.kind, required this.partyId, this.suggested = 0});
  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final amount = TextEditingController(text: widget.suggested > 0 ? Money.edit(widget.suggested) : '');
  final ref = TextEditingController();
  List<Rec> accounts = [];
  int? account;
  String date = ymd(DateTime.now());

  @override
  void initState() {
    super.initState();
    Books.moneyAccounts().then((a) => setState(() {
          accounts = a;
          account = a.isNotEmpty ? asInt(a.first['id']) : null;
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.kind == 'receipt' ? 'Receive payment' : 'Make payment',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        field(amount, 'Amount ₹', number: true),
        RowPicker(
            label: widget.kind == 'receipt' ? 'Received in' : 'Paid from',
            rows: accounts,
            value: account,
            onChanged: (v) => setState(() => account = v)),
        DateField(value: date, onChanged: (v) => setState(() => date = v)),
        field(ref, 'Reference (UPI / cheque no.)'),
        GradientButton(
          label: 'Save',
          expand: true,
          fontSize: 16,
          onTap: () async {
            try {
              await Books.createPayment(
                kind: widget.kind,
                partyId: widget.partyId,
                amount: Money.parse(amount.text),
                accountId: account ?? 0,
                date: date,
                reference: ref.text.trim().isEmpty ? null : ref.text.trim(),
              );
              if (!context.mounted) return;
              Navigator.of(context).pop();
              toast(context, 'Payment recorded');
            } catch (e) {
              toast(context, '$e', error: true);
            }
          },
        ),
      ]),
    );
  }
}

class PartyForm extends StatefulWidget {
  final String type;
  final Rec? party;
  const PartyForm({super.key, required this.type, this.party});
  @override
  State<PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends State<PartyForm> {
  late final name = TextEditingController(text: '${widget.party?['name'] ?? ''}');
  late final phone = TextEditingController(text: '${widget.party?['phone'] ?? ''}');
  late final email = TextEditingController(text: '${widget.party?['email'] ?? ''}');
  late final address = TextEditingController(text: '${widget.party?['address'] ?? ''}');
  late final gstin = TextEditingController(text: '${widget.party?['gstin'] ?? ''}');
  late final limit = TextEditingController(
      text: widget.party == null ? '' : Money.edit(asInt(widget.party!['credit_limit'])));
  final opening = TextEditingController();

  String? _v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    try {
      await Books.saveParty(
        widget.type,
        {
          'name': name.text,
          'phone': _v(phone),
          'email': _v(email),
          'address': _v(address),
          'gstin': _v(gstin)?.toUpperCase(),
          'credit_limit': Money.parse(limit.text),
        },
        id: widget.party == null ? null : asInt(widget.party!['id']),
        opening: Money.parse(opening.text),
      );
      if (!mounted) return;
      toast(context, 'Saved');
      Navigator.of(context).pop();
    } catch (e) {
      toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isC = widget.type == 'customer';
    final isNew = widget.party == null;
    return PageShell(
      title: '${isNew ? 'New' : 'Edit'} ${isC ? 'customer' : 'supplier'}',
      children: [
        CardBox(
          child: Column(children: [
            field(name, 'Name *'),
            field(phone, 'Mobile number', number: true),
            field(email, 'Email'),
            field(address, 'Address', maxLines: 2),
            field(gstin, 'GSTIN'),
            if (isC) field(limit, 'Credit limit ₹ (0 = no limit)', number: true),
            if (isNew)
              field(opening, isC ? 'Opening due — they owe you ₹' : 'Opening due — you owe them ₹', number: true),
          ]),
        ),
        const SizedBox(height: 16),
        GradientButton(label: 'Save', expand: true, fontSize: 16, onTap: _save),
      ],
    );
  }
}
