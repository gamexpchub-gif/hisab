import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'parties.dart';
import 'sale_form.dart';
import 'sales.dart';

class PurchaseForm extends StatefulWidget {
  final int? supplierId;
  const PurchaseForm({super.key, this.supplierId});
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  List<Rec> products = [], suppliers = [], accounts = [];
  final lines = [LineEdit()];
  final paid = TextEditingController(text: '0');
  final billNo = TextEditingController();
  final note = TextEditingController();
  int? supplier;
  int? account;
  String date = ymd(DateTime.now());
  bool saving = false;

  @override
  void initState() {
    super.initState();
    supplier = widget.supplierId;
    _load();
  }

  Future<void> _load() async {
    products = await Books.query('SELECT * FROM products ORDER BY name');
    suppliers = await Books.query('SELECT * FROM suppliers ORDER BY name');
    accounts = await Books.moneyAccounts();
    account ??= accounts.isNotEmpty ? asInt(accounts.first['id']) : null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
    paid.dispose();
    billNo.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    if (supplier == null) {
      toast(context, 'Select a supplier', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      final id = await Books.createPurchase(
        items: LineItemsEditor.items(lines),
        supplierId: supplier!,
        paid: Money.parse(paid.text),
        accountId: account,
        date: date,
        billNo: billNo.text.trim().isEmpty ? null : billNo.text.trim(),
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      if (!mounted) return;
      toast(context, 'Purchase saved — stock updated');
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PurchaseView(id: id)));
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LineItemsEditor.totals(lines, products);
    return PageShell(
      title: 'New purchase',
      subtitle: 'Supplier bill · adds stock at weighted average cost',
      children: [
        CardBox(
          child: Column(children: [
            Row(children: [
              Expanded(
                child: RowPicker(
                    label: 'Supplier *', rows: suppliers, value: supplier, onChanged: (v) => setState(() => supplier = v)),
              ),
              IconButton(
                tooltip: 'New supplier',
                icon: const Icon(Icons.add_business_rounded, color: C.purple2),
                onPressed: () async {
                  await open(context, const PartyForm(type: 'supplier'));
                  _load();
                },
              ),
            ]),
            Row(children: [
              Expanded(child: DateField(value: date, onChanged: (v) => setState(() => date = v))),
              const SizedBox(width: 10),
              Expanded(child: field(billNo, 'Supplier bill no.')),
            ]),
          ]),
        ),
        CardBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FormHeading('Items (rate = purchase price per unit)'),
            if (products.isEmpty) const EmptyState('Add products first (Products → Add)'),
            LineItemsEditor(lines: lines, products: products, isSale: false, onChanged: () => setState(() {})),
          ]),
        ),
        CardBox(
          child: Column(children: [
            TotalLine('Subtotal', Money.rs(t[0])),
            TotalLine('GST input', Money.rs(t[1])),
            const Divider(color: C.line),
            TotalLine('Bill total', Money.rs(t[0] + t[1]), bold: true),
            const SizedBox(height: 12),
            field(paid, 'Paid now ₹', number: true),
            RowPicker(label: 'Paid from', rows: accounts, value: account, onChanged: (v) => setState(() => account = v)),
            field(note, 'Note (optional)'),
          ]),
        ),
        const SizedBox(height: 16),
        GradientButton(label: saving ? 'Saving…' : 'Save purchase', expand: true, fontSize: 16, onTap: _save),
      ],
    );
  }
}
