import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'sales.dart';

class ProductsScreen extends StatefulWidget {
  final bool lowOnly;
  const ProductsScreen({super.key, this.lowOnly = false});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late bool low = widget.lowOnly;
  String q = '';

  Future<List<Rec>> _load() => Books.query(
      'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id '
      'WHERE (? = 0 OR p.stock <= p.low_stock) AND (p.name LIKE ? OR IFNULL(p.brand,\'\') LIKE ? OR IFNULL(p.sku,\'\') LIKE ?) '
      'ORDER BY p.name',
      [low ? 1 : 0, '%$q%', '%$q%', '%$q%']);

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      key: ValueKey('$low|$q'),
      load: _load,
      builder: (context, rows) {
        final value = rows.fold<int>(0, (a, p) => a + (asInt(p['stock']) > 0 ? asInt(p['stock']) * asInt(p['cost']) : 0));
        return PageShell(
          title: 'Products',
          subtitle: '${rows.length} items · stock value ${Money.rs(value)}',
          action: GradientButton(label: 'Add', icon: Icons.add_rounded, onTap: () => open(context, const ProductForm())),
          children: [
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(hintText: 'Search name, brand or SKU', prefixIcon: Icon(Icons.search_rounded)),
              onSubmitted: (v) => setState(() => q = v.trim()),
            ),
            const SizedBox(height: 10),
            Row(children: [
              ChoiceChip(label: const Text('All'), selected: !low, onSelected: (_) => setState(() => low = false)),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Low stock'), selected: low, onSelected: (_) => setState(() => low = true)),
            ]),
            CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: rows.isEmpty
                  ? const EmptyState('No products yet — tap Add to create one')
                  : Divided([
                      for (final p in rows)
                        ListRow(
                          leading: Avatar('${p['stock']}',
                              bg: asInt(p['stock']) <= asInt(p['low_stock']) ? const Color(0xFFFDE8E8) : const Color(0xFFEFEBFF),
                              fg: asInt(p['stock']) <= asInt(p['low_stock']) ? C.red : C.purple2),
                          title: p['name'] as String,
                          subtitle: [p['brand'], p['category'], p['condition']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                          trailing: Money.rs(asInt(p['price'])),
                          trailingSub: 'Cost ${Money.rs(asInt(p['cost']))}',
                          onTap: () => open(context, ProductView(id: asInt(p['id']))),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

class ProductView extends StatelessWidget {
  final int id;
  const ProductView({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Live<List<List<Rec>>>(
      load: () async => [
        await Books.query(
            'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id WHERE p.id = ?',
            [id]),
        await Books.query(
            'SELECT i.*, s.number, s.date, s.id AS sid FROM sale_items i JOIN sales s ON s.id = i.sale_id '
            'WHERE i.product_id = ? ORDER BY s.date DESC LIMIT 20',
            [id]),
        await Books.query(
            'SELECT i.*, p.number, p.date, p.id AS pid FROM purchase_items i JOIN purchases p ON p.id = i.purchase_id '
            'WHERE i.product_id = ? ORDER BY p.date DESC LIMIT 20',
            [id]),
      ],
      builder: (context, data) {
        if (data[0].isEmpty) return const PageShell(title: 'Product', children: [EmptyState('Not found')]);
        final p = data[0].first;
        final stock = asInt(p['stock']);
        final margin = asInt(p['price']) - asInt(p['cost']);
        return PageShell(
          title: p['name'] as String,
          subtitle: [p['brand'], p['category'], p['sku']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
          action: RoundIcon(icon: Icons.edit_rounded, onTap: () => open(context, ProductForm(product: p))),
          children: [
            KpiGrid([
              Kpi('Selling price', asInt(p['price']), accent: true),
              Kpi('Avg. cost', asInt(p['cost'])),
              Kpi('Margin / unit', margin, color: margin >= 0 ? C.green : C.red),
              Kpi('Stock value', stock > 0 ? stock * asInt(p['cost']) : 0),
            ]),
            CardBox(
              child: Column(children: [
                TotalLine('In stock', '$stock', bold: true, color: stock <= asInt(p['low_stock']) ? C.red : C.ink),
                TotalLine('Low-stock alert at', '${p['low_stock']}'),
                TotalLine('GST', '${asInt(p['gst_bp']) / 100}%'),
                TotalLine('HSN', '${p['hsn'] ?? '—'}'),
                TotalLine('Condition', '${p['condition']}'),
              ]),
            ),
            CardBox(
              child: Column(children: [
                const SectionTitle('Recent sales'),
                if (data[1].isEmpty) const EmptyState('Not sold yet'),
                Divided([
                  for (final s in data[1])
                    ListRow(
                      leading: const Avatar('', icon: Icons.shopping_cart_rounded, bg: Color(0xFFE3F7EC), fg: C.green),
                      title: '${s['number']} · ${s['qty']} × ${Money.rs(asInt(s['rate']))}',
                      subtitle: '${prettyDate(s['date'] as String)}${s['serial'] != null ? ' · IMEI ${s['serial']}' : ''}',
                      trailing: Money.rs(asInt(s['amount'])),
                      onTap: () => open(context, SaleView(id: asInt(s['sid']))),
                    ),
                ]),
              ]),
            ),
            CardBox(
              child: Column(children: [
                const SectionTitle('Recent purchases'),
                if (data[2].isEmpty) const EmptyState('No purchases yet'),
                Divided([
                  for (final s in data[2])
                    ListRow(
                      leading: const Avatar('', icon: Icons.shopping_bag_rounded),
                      title: '${s['number']} · ${s['qty']} × ${Money.rs(asInt(s['rate']))}',
                      subtitle: prettyDate(s['date'] as String),
                      trailing: Money.rs(asInt(s['amount'])),
                      onTap: () => open(context, PurchaseView(id: asInt(s['pid']))),
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

class ProductForm extends StatefulWidget {
  final Rec? product;
  const ProductForm({super.key, this.product});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final f = <String, TextEditingController>{};
  int? category;
  String condition = 'new';
  List<Rec> categories = [];

  TextEditingController c(String k, [String init = '']) => f.putIfAbsent(k, () => TextEditingController(text: init));

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    c('name', '${p?['name'] ?? ''}');
    c('brand', '${p?['brand'] ?? ''}');
    c('sku', '${p?['sku'] ?? ''}');
    c('hsn', '${p?['hsn'] ?? ''}');
    c('gst', p == null ? '18' : '${asInt(p['gst_bp']) / 100}');
    c('price', p == null ? '' : Money.edit(asInt(p['price'])));
    c('low', '${p?['low_stock'] ?? 2}');
    c('qty');
    c('cost');
    category = p?['category_id'] as int?;
    condition = (p?['condition'] as String?) ?? 'new';
    Books.query('SELECT * FROM categories ORDER BY name').then((r) => setState(() => categories = r));
  }

  @override
  void dispose() {
    for (final x in f.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final gst = Money.parse(f['gst']!.text); // percent × 100 = basis points
      await Books.saveProduct({
        'name': f['name']!.text,
        'brand': f['brand']!.text.trim().isEmpty ? null : f['brand']!.text.trim(),
        'sku': f['sku']!.text,
        'hsn': f['hsn']!.text.trim().isEmpty ? null : f['hsn']!.text.trim(),
        'gst_bp': gst,
        'price': Money.parse(f['price']!.text),
        'low_stock': int.tryParse(f['low']!.text) ?? 0,
        'category_id': category,
        'condition': condition,
      },
          id: widget.product == null ? null : asInt(widget.product!['id']),
          openingQty: int.tryParse(f['qty']!.text) ?? 0,
          openingCost: Money.parse(f['cost']!.text));
      if (!mounted) return;
      toast(context, 'Product saved');
      Navigator.of(context).pop();
    } catch (e) {
      toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;
    return PageShell(
      title: isNew ? 'New product' : 'Edit product',
      children: [
        CardBox(
          child: Column(children: [
            field(f['name']!, 'Product name *'),
            Row(children: [
              Expanded(child: field(f['brand']!, 'Brand')),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('${categories.length}-$category'),
                    value: categories.any((c) => asInt(c['id']) == category) ? category : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('—')),
                      for (final c in categories)
                        DropdownMenuItem<int?>(value: asInt(c['id']), child: Text(c['name'] as String)),
                    ],
                    onChanged: (v) => setState(() => category = v),
                  ),
                ),
              ),
            ]),
            Row(children: [
              Expanded(child: field(f['price']!, 'Selling price ₹', number: true)),
              const SizedBox(width: 10),
              Expanded(child: field(f['gst']!, 'GST %', number: true)),
            ]),
            Row(children: [
              Expanded(child: field(f['sku']!, 'SKU / Barcode')),
              const SizedBox(width: 10),
              Expanded(child: field(f['hsn']!, 'HSN code')),
            ]),
            Row(children: [
              Expanded(child: field(f['low']!, 'Low-stock alert', number: true)),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: condition,
                    decoration: const InputDecoration(labelText: 'Condition'),
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(value: 'used', child: Text('Used')),
                      DropdownMenuItem(value: 'refurbished', child: Text('Refurbished')),
                    ],
                    onChanged: (v) => setState(() => condition = v ?? 'new'),
                  ),
                ),
              ),
            ]),
          ]),
        ),
        if (isNew)
          CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Opening stock', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Stock you already have. New stock should come through a Purchase.',
                  style: TextStyle(color: C.muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: field(f['qty']!, 'Quantity', number: true)),
                const SizedBox(width: 10),
                Expanded(child: field(f['cost']!, 'Cost per unit ₹', number: true)),
              ]),
            ]),
          ),
        const SizedBox(height: 16),
        GradientButton(label: 'Save product', expand: true, fontSize: 16, onTap: _save),
      ],
    );
  }
}
