import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'purchase_form.dart';
import 'sale_form.dart';

class SaleRow extends StatelessWidget {
  final Rec s;
  const SaleRow(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final due = asInt(s['total']) - asInt(s['paid']);
    return ListRow(
      leading: const Avatar('', icon: Icons.shopping_cart_rounded, bg: Color(0xFFE3F7EC), fg: C.green),
      title: (s['customer'] as String?) ?? 'Walk-in customer',
      subtitle: '${s['number']} · ${prettyDate(s['date'] as String)}',
      trailing: Money.rs(asInt(s['total'])),
      trailingSub: due > 0 ? 'Due ${Money.rs(due)}' : 'Paid',
      trailingSubColor: due > 0 ? C.red : C.green,
      onTap: () => open(context, SaleView(id: asInt(s['id']))),
    );
  }
}

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      load: () => Books.recentSales(500),
      builder: (context, rows) {
        final total = rows.fold<int>(0, (a, s) => a + asInt(s['total']));
        return PageShell(
          title: 'Sales',
          subtitle: '${rows.length} invoices · ${Money.rs(total)}',
          action: GradientButton(label: 'New', icon: Icons.add_rounded, onTap: () => open(context, const SaleForm())),
          children: [
            CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: rows.isEmpty ? const EmptyState('No sales yet') : Divided([for (final s in rows) SaleRow(s)]),
            ),
          ],
        );
      },
    );
  }
}

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      load: () => Books.recentPurchases(500),
      builder: (context, rows) {
        final total = rows.fold<int>(0, (a, s) => a + asInt(s['total']));
        return PageShell(
          title: 'Purchases',
          subtitle: '${rows.length} bills · ${Money.rs(total)}',
          action: GradientButton(label: 'New', icon: Icons.add_rounded, onTap: () => open(context, const PurchaseForm())),
          children: [
            CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: rows.isEmpty
                  ? const EmptyState('No purchases yet')
                  : Divided([
                      for (final p in rows)
                        ListRow(
                          leading: const Avatar('', icon: Icons.shopping_bag_rounded),
                          title: p['supplier'] as String,
                          subtitle: '${p['number']}${p['bill_no'] != null ? ' · ${p['bill_no']}' : ''} · ${prettyDate(p['date'] as String)}',
                          trailing: Money.rs(asInt(p['total'])),
                          trailingSub: asInt(p['total']) > asInt(p['paid'])
                              ? 'Due ${Money.rs(asInt(p['total']) - asInt(p['paid']))}'
                              : 'Paid',
                          trailingSubColor: asInt(p['total']) > asInt(p['paid']) ? C.red : C.green,
                          onTap: () => open(context, PurchaseView(id: asInt(p['id']))),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

class _DocData {
  final Rec doc;
  final List<Rec> items;
  final Map<String, String> settings;
  _DocData(this.doc, this.items, this.settings);
}

class SaleView extends StatelessWidget {
  final int id;
  const SaleView({super.key, required this.id});

  Future<_DocData?> _load() async {
    final d = await Books.query(
        'SELECT s.*, c.name AS customer, c.phone, c.address, c.gstin, a.name AS account FROM sales s '
        'LEFT JOIN customers c ON c.id = s.customer_id LEFT JOIN accounts a ON a.id = s.account_id WHERE s.id = ?',
        [id]);
    if (d.isEmpty) return null;
    return _DocData(d.first, await Books.query('SELECT * FROM sale_items WHERE sale_id = ?', [id]), await Books.settings());
  }

  @override
  Widget build(BuildContext context) {
    return Live<_DocData?>(
      load: _load,
      builder: (context, data) {
        if (data == null) return const PageShell(title: 'Invoice', children: [EmptyState('Not found')]);
        final s = data.doc;
        final due = asInt(s['total']) - asInt(s['paid']);
        final profit = asInt(s['subtotal']) - asInt(s['discount']) - asInt(s['cogs']);
        return PageShell(
          title: 'Invoice ${s['number']}',
          subtitle: prettyDate(s['date'] as String),
          action: RoundIcon(
            icon: Icons.copy_rounded,
            onTap: () {
              Clipboard.setData(ClipboardData(text: invoiceText(data.settings, s, data.items)));
              toast(context, 'Invoice copied — paste it in WhatsApp');
            },
          ),
          children: [
            _DocCard(
              settings: data.settings,
              partyLabel: 'Bill to',
              partyName: (s['customer'] as String?) ?? 'Walk-in customer',
              partyLines: [s['phone'], s['address'], s['gstin'] != null ? 'GSTIN ${s['gstin']}' : null],
              items: data.items,
              totals: [
                ('Subtotal', Money.rs(asInt(s['subtotal']))),
                if (asInt(s['discount']) > 0) ('Discount', '− ${Money.rs(asInt(s['discount']))}'),
                ('GST', Money.rs(asInt(s['tax']))),
              ],
              total: asInt(s['total']),
              paid: asInt(s['paid']),
              paidVia: s['account'] as String?,
            ),
            CardBox(
              child: Column(children: [
                TotalLine('Balance due', Money.rs(due), bold: true, color: due > 0 ? C.red : C.green),
                TotalLine('Profit on this invoice', Money.rs(profit), color: profit >= 0 ? C.green : C.red),
                if (s['note'] != null) TotalLine('Note', s['note'] as String),
              ]),
            ),
          ],
        );
      },
    );
  }
}

class PurchaseView extends StatelessWidget {
  final int id;
  const PurchaseView({super.key, required this.id});

  Future<_DocData?> _load() async {
    final d = await Books.query(
        'SELECT p.*, s.name AS supplier, s.phone, s.address, s.gstin, a.name AS account FROM purchases p '
        'JOIN suppliers s ON s.id = p.supplier_id LEFT JOIN accounts a ON a.id = p.account_id WHERE p.id = ?',
        [id]);
    if (d.isEmpty) return null;
    return _DocData(
        d.first, await Books.query('SELECT * FROM purchase_items WHERE purchase_id = ?', [id]), await Books.settings());
  }

  @override
  Widget build(BuildContext context) {
    return Live<_DocData?>(
      load: _load,
      builder: (context, data) {
        if (data == null) return const PageShell(title: 'Purchase', children: [EmptyState('Not found')]);
        final p = data.doc;
        final due = asInt(p['total']) - asInt(p['paid']);
        return PageShell(
          title: 'Purchase ${p['number']}',
          subtitle: '${prettyDate(p['date'] as String)}${p['bill_no'] != null ? ' · Bill ${p['bill_no']}' : ''}',
          children: [
            _DocCard(
              settings: data.settings,
              partyLabel: 'Supplier',
              partyName: p['supplier'] as String,
              partyLines: [p['phone'], p['address'], p['gstin'] != null ? 'GSTIN ${p['gstin']}' : null],
              items: data.items,
              totals: [('Subtotal', Money.rs(asInt(p['subtotal']))), ('GST input', Money.rs(asInt(p['tax'])))],
              total: asInt(p['total']),
              paid: asInt(p['paid']),
              paidVia: p['account'] as String?,
            ),
            CardBox(child: TotalLine('Balance payable', Money.rs(due), bold: true, color: due > 0 ? C.red : C.green)),
          ],
        );
      },
    );
  }
}

class _DocCard extends StatelessWidget {
  final Map<String, String> settings;
  final String partyLabel, partyName;
  final List<Object?> partyLines;
  final List<Rec> items;
  final List<(String, String)> totals;
  final int total, paid;
  final String? paidVia;
  const _DocCard({
    required this.settings,
    required this.partyLabel,
    required this.partyName,
    required this.partyLines,
    required this.items,
    required this.totals,
    required this.total,
    required this.paid,
    this.paidVia,
  });

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const LogoTile(size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(settings['business_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(settings['tagline'] ?? '', style: const TextStyle(color: C.muted, fontSize: 12)),
              if ((settings['gstin'] ?? '').isNotEmpty)
                Text('GSTIN ${settings['gstin']}', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
        ]),
        const Divider(height: 24, color: C.line),
        Text(partyLabel.toUpperCase(), style: const TextStyle(fontSize: 11, color: C.muted, letterSpacing: .8)),
        Text(partyName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        for (final l in partyLines)
          if (l != null && '$l'.isNotEmpty) Text('$l', style: const TextStyle(color: C.ink2, fontSize: 12.5)),
        const SizedBox(height: 12),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${i['qty']} × ${Money.rs(asInt(i['rate']))} · GST ${asInt(i['gst_bp']) / 100}%'
                    '${i['serial'] != null ? '\nIMEI/SN ${i['serial']}' : ''}',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                ]),
              ),
              Text(Money.rs(asInt(i['amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        const Divider(color: C.line),
        for (final t in totals) TotalLine(t.$1, t.$2),
        TotalLine('Total', Money.rs(total), bold: true),
        TotalLine('Paid${paidVia != null && paid > 0 ? ' ($paidVia)' : ''}', Money.rs(paid)),
      ]),
    );
  }
}

String invoiceText(Map<String, String> st, Rec s, List<Rec> items) {
  final b = StringBuffer()
    ..writeln('*${st['business_name']}*')
    ..writeln('Invoice ${s['number']} · ${prettyDate(s['date'] as String)}')
    ..writeln('Customer: ${s['customer'] ?? 'Walk-in'}')
    ..writeln('');
  for (final i in items) {
    b.writeln('${i['name']}  ${i['qty']} × ${Money.rs(asInt(i['rate']))} = ${Money.rs(asInt(i['amount']))}');
  }
  b
    ..writeln('')
    ..writeln('GST: ${Money.rs(asInt(s['tax']))}');
  if (asInt(s['discount']) > 0) b.writeln('Discount: ${Money.rs(asInt(s['discount']))}');
  b
    ..writeln('*Total: ${Money.rs(asInt(s['total']))}*')
    ..writeln('Paid: ${Money.rs(asInt(s['paid']))}');
  final due = asInt(s['total']) - asInt(s['paid']);
  if (due > 0) b.writeln('Due: ${Money.rs(due)}');
  b.writeln('Thank you for shopping with us!');
  return b.toString();
}
