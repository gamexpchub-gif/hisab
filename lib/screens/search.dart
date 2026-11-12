import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'products.dart';
import 'sales.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String q = '';

  Future<List<List<Rec>>> _load() async {
    if (q.isEmpty) return [[], [], [], [], []];
    final like = '%$q%';
    return [
      await Books.query(
          'SELECT * FROM customers WHERE name LIKE ? OR IFNULL(phone,\'\') LIKE ? OR IFNULL(alt_phone,\'\') LIKE ? '
          'OR IFNULL(address,\'\') LIKE ? LIMIT 10',
          [like, like, like, like]),
      [for (final s in await Books.salesBook()) if (matchSale(s, q) != null) s].take(15).toList(),
      await Books.query(
          'SELECT * FROM products WHERE name LIKE ? OR IFNULL(brand,\'\') LIKE ? OR IFNULL(sku,\'\') LIKE ? '
          'OR IFNULL(variant,\'\') LIKE ? OR IFNULL(hsn,\'\') LIKE ? LIMIT 10',
          [like, like, like, like, like]),
      await Books.query(
          'SELECT * FROM suppliers WHERE name LIKE ? OR IFNULL(phone,\'\') LIKE ? OR IFNULL(gstin,\'\') LIKE ? LIMIT 10',
          [like, like, like]),
      await Books.query(
          'SELECT i.serial, s.id, s.number, s.date FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE i.serial LIKE ? LIMIT 10',
          [like]),
    ];
  }

  Widget _section(String title, List<Widget> rows) =>
      rows.isEmpty ? const SizedBox() : CardBox(child: Column(children: [SectionTitle(title), Divided(rows)]));

  @override
  Widget build(BuildContext context) {
    return PageShell(title: 'Search', children: [
      const SizedBox(height: 10),
      TextField(
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
            hintText: 'Customer, phone, invoice no., product, IMEI…', prefixIcon: Icon(Icons.search_rounded)),
        onChanged: (v) => setState(() => q = v.trim()),
      ),
      Live<List<List<Rec>>>(
        reloadKey: q,
        load: _load,
        builder: (context, r) {
          final none = q.isNotEmpty && r.every((l) => l.isEmpty);
          return Column(children: [
            if (none) EmptyState('No results for “$q”'),
            _section('Customers', [
              for (final c in r[0])
                ListRow(
                  leading: Avatar((c['name'] as String)[0].toUpperCase()),
                  title: c['name'] as String,
                  subtitle: c['phone'] as String?,
                  onTap: () => open(context, PartyView(type: 'customer', id: asInt(c['id']))),
                ),
            ]),
            _section('Invoices', [for (final s in r[1]) SaleRow(s)]),
            _section('IMEI / Serial', [
              for (final s in r[4])
                ListRow(
                  leading: const Avatar('', icon: Icons.smartphone_rounded),
                  title: '${s['serial']}',
                  subtitle: 'Sold on ${s['number']} · ${prettyDate(s['date'] as String)}',
                  onTap: () => open(context, SaleView(id: asInt(s['id']))),
                ),
            ]),
            _section('Products', [
              for (final p in r[2])
                ListRow(
                  leading: Avatar('${p['stock']}'),
                  title: p['name'] as String,
                  subtitle: p['brand'] as String?,
                  trailing: Money.rs(asInt(p['price'])),
                  onTap: () => open(context, ProductView(id: asInt(p['id']))),
                ),
            ]),
            _section('Suppliers', [
              for (final c in r[3])
                ListRow(
                  leading: Avatar((c['name'] as String)[0].toUpperCase(), fg: C.orange, bg: const Color(0xFFFFF1E0)),
                  title: c['name'] as String,
                  subtitle: c['phone'] as String?,
                  onTap: () => open(context, PartyView(type: 'supplier', id: asInt(c['id']))),
                ),
            ]),
          ]);
        },
      ),
    ]);
  }
}
