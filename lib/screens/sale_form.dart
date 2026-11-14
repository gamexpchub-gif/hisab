import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';

export 'sale_pos.dart';

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
