import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';

export 'parties_list.dart';
export 'party_form.dart';
export 'party_profile.dart';


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
