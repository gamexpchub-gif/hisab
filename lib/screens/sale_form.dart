import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'parties.dart';
import 'sales.dart';

/// One editable invoice/bill line.
class LineEdit {
  int? productId;
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController();
  final serial = TextEditingController();
  void dispose() {
    qty.dispose();
    rate.dispose();
    serial.dispose();
  }
}

/// Shared line-item editor for sales and purchases.
class LineItemsEditor extends StatelessWidget {
  final List<LineEdit> lines;
  final List<Rec> products;
  final bool isSale;
  final VoidCallback onChanged;
  const LineItemsEditor({
    super.key,
    required this.lines,
    required this.products,
    required this.isSale,
    required this.onChanged,
  });

  Rec? _p(int? id) {
    for (final p in products) {
      if (asInt(p['id']) == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < lines.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFCFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: RowPicker(
                  label: 'Product',
                  rows: products,
                  value: lines[i].productId,
                  text: (r) => '${r['name']}  (stock ${r['stock']})',
                  onChanged: (v) {
                    lines[i].productId = v;
                    final p = _p(v);
                    if (p != null) lines[i].rate.text = Money.edit(asInt(isSale ? p['price'] : p['cost']));
                    onChanged();
                  },
                ),
              ),
              if (lines.length > 1)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: C.red),
                  onPressed: () {
                    lines.removeAt(i);
                    onChanged();
                  },
                ),
            ]),
            Row(children: [
              Expanded(flex: 2, child: field(lines[i].qty, 'Qty', number: true, onChanged: (_) => onChanged())),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: field(lines[i].rate, 'Rate ₹', number: true, onChanged: (_) => onChanged())),
            ]),
            field(lines[i].serial, 'IMEI / Serial no. (optional)'),
            Builder(builder: (_) {
              final p = _p(lines[i].productId);
              if (p == null) return const SizedBox(height: 8);
              final amt = _amount(lines[i]);
              final tax = Money.percent(amt, asInt(p['gst_bp']));
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${Money.rs(amt)} + GST ${asInt(p['gst_bp']) / 100}% ${Money.rs(tax)}'
                    '${isSale ? ' · in stock ${p['stock']}' : ''}',
                    style: const TextStyle(fontSize: 12, color: C.muted),
                  ),
                ),
              );
            }),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            lines.add(LineEdit());
            onChanged();
          },
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text('Add item'),
        ),
      ),
    ]);
  }

  static int _amount(LineEdit l) {
    final q = int.tryParse(l.qty.text.trim()) ?? 0;
    int r;
    try {
      r = Money.parse(l.rate.text);
    } catch (_) {
      r = 0;
    }
    return q * r;
  }

  /// [subtotal, tax]
  static List<int> totals(List<LineEdit> lines, List<Rec> products) {
    var sub = 0, tax = 0;
    for (final l in lines) {
      Rec? p;
      for (final x in products) {
        if (asInt(x['id']) == l.productId) p = x;
      }
      if (p == null) continue;
      final a = _amount(l);
      sub += a;
      tax += Money.percent(a, asInt(p['gst_bp']));
    }
    return [sub, tax];
  }

  static List<ItemIn> items(List<LineEdit> lines) => [
        for (final l in lines)
          if (l.productId != null)
            ItemIn(l.productId!, int.tryParse(l.qty.text.trim()) ?? 0, Money.parse(l.rate.text), l.serial.text)
      ];
}

class SaleForm extends StatefulWidget {
  final int? customerId;
  const SaleForm({super.key, this.customerId});
  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  List<Rec> products = [], customers = [], accounts = [];
  final lines = [LineEdit()];
  final discount = TextEditingController();
  final paid = TextEditingController();
  final note = TextEditingController();
  bool paidTouched = false;
  int? customer;
  int? account;
  String date = ymd(DateTime.now());
  bool saving = false;

  @override
  void initState() {
    super.initState();
    customer = widget.customerId;
    _load();
  }

  Future<void> _load() async {
    products = await Books.query('SELECT * FROM products ORDER BY name');
    customers = await Books.query('SELECT * FROM customers ORDER BY name');
    accounts = await Books.moneyAccounts();
    account ??= accounts.isNotEmpty ? asInt(accounts.first['id']) : null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
    discount.dispose();
    paid.dispose();
    note.dispose();
    super.dispose();
  }

  int get _discount {
    try {
      return Money.parse(discount.text);
    } catch (_) {
      return 0;
    }
  }

  int get _total {
    final t = LineItemsEditor.totals(lines, products);
    return t[0] + t[1] - _discount;
  }

  void _changed() {
    if (!paidTouched) paid.text = Money.edit(_total);
    setState(() {});
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final id = await Books.createSale(
        items: LineItemsEditor.items(lines),
        customerId: customer,
        paid: paid.text.trim().isEmpty ? null : Money.parse(paid.text),
        accountId: account,
        discount: _discount,
        date: date,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      if (!mounted) return;
      toast(context, 'Sale saved');
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SaleView(id: id)));
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LineItemsEditor.totals(lines, products);
    return PageShell(
      title: 'New sale',
      subtitle: 'Invoice · stock & accounts update automatically',
      children: [
        CardBox(
          child: Column(children: [
            Row(children: [
              Expanded(
                child: RowPicker(
                  label: 'Customer',
                  rows: customers,
                  value: customer,
                  noneLabel: 'Walk-in customer (cash)',
                  onChanged: (v) => setState(() => customer = v),
                ),
              ),
              IconButton(
                tooltip: 'New customer',
                icon: const Icon(Icons.person_add_alt_1_rounded, color: C.purple2),
                onPressed: () async {
                  await open(context, const PartyForm(type: 'customer'));
                  _load();
                },
              ),
            ]),
            DateField(value: date, onChanged: (v) => setState(() => date = v)),
          ]),
        ),
        CardBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FormHeading('Items'),
            if (products.isEmpty) const EmptyState('Add products first (Products → Add)'),
            LineItemsEditor(lines: lines, products: products, isSale: true, onChanged: _changed),
          ]),
        ),
        CardBox(
          child: Column(children: [
            field(discount, 'Discount ₹', number: true, onChanged: (_) => _changed()),
            TotalLine('Subtotal', Money.rs(t[0])),
            TotalLine('GST', Money.rs(t[1])),
            if (_discount > 0) TotalLine('Discount', '− ${Money.rs(_discount)}'),
            const Divider(color: C.line),
            TotalLine('Total', Money.rs(_total), bold: true),
            const SizedBox(height: 12),
            field(paid, 'Amount received now ₹', number: true, onChanged: (_) {
              paidTouched = true;
              setState(() {});
            }),
            RowPicker(label: 'Received in', rows: accounts, value: account, onChanged: (v) => setState(() => account = v)),
            field(note, 'Note (optional)'),
          ]),
        ),
        const SizedBox(height: 16),
        GradientButton(
          label: saving ? 'Saving…' : 'Save invoice',
          expand: true,
          fontSize: 16,
          gradient: const LinearGradient(colors: [Color(0xFF1BB574), Color(0xFF0F8C58)]),
          onTap: _save,
        ),
      ],
    );
  }
}
