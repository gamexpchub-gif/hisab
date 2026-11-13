import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'purchase_form.dart';
import 'sales.dart' show PurchaseView, deletePurchaseFlow;
import 'sales_book.dart' show matchDoc, SaleMatch;
import 'scanner.dart';

// =============================================================================
// Purchases book — supplier bills and stock-in. Search by supplier, mobile,
// bill no., IMEI / serial, amount, product, address or GSTIN. Supplier
// strip opens each supplier's super profile; bill cards show the bill photo.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _orange = Color(0xFFF0601A);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);

TextStyle _j(double size, FontWeight w, Color c, {double? height}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
    );

BoxDecoration _card({double r = 22}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [
        BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
        BoxShadow(color: Color(0x0A2A2F7A), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();

const _supplierGrad = [Color(0xFFFFA24A), Color(0xFFF06A1A)];

class _BookData {
  final List<Rec> bills, suppliers;
  final Map<int, int> payable;
  _BookData(this.bills, this.suppliers, this.payable);
}

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final search = TextEditingController();
  String q = '';
  String period = 'all';
  String status = 'all'; // all | paid | partial | unpaid

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<_BookData> _load() async => _BookData(
        await Books.purchasesBook(),
        await Books.query('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE'),
        await Books.partyBalances('supplier'),
      );

  String? get _from {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (period) {
      'today' => ymd(today),
      'week' => ymd(today.subtract(Duration(days: today.weekday - 1))),
      'month' => ymd(DateTime(n.year, n.month)),
      'year' => ymd(DateTime(n.year)),
      _ => null,
    };
  }

  String _status(Rec s) {
    final total = asInt(s['total']), paid = asInt(s['paid']);
    return paid >= total ? 'paid' : paid > 0 ? 'partial' : 'unpaid';
  }

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI / barcode');
    if (code == null || !mounted) return;
    search.text = code;
    setState(() => q = code);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          open(context, const PurchaseForm());
        },
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: _supplierGrad),
            border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x774A17C9), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inventory_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text('Stock in', style: _j(15, FontWeight.w800, Colors.white)),
          ]),
        ),
      ),
      body: SafeArea(
        child: Live<_BookData>(
          load: _load,
          builder: (context, d) {
            final from = _from;
            final periodRows = from == null ? d.bills : d.bills.where((s) => '${s['date']}'.compareTo(from) >= 0).toList();
            final matches = <(Rec, SaleMatch)>[];
            for (final s in periodRows) {
              if (status != 'all' && _status(s) != status) continue;
              final m = matchDoc(s, q, party: 'supplier', accounts: 'account');
              if (m != null) matches.add((s, m));
            }
            final counts = {
              for (final k in ['all', 'paid', 'partial', 'unpaid'])
                k: k == 'all' ? periodRows.length : periodRows.where((s) => _status(s) == k).length,
            };
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Row(children: [
                  if (canPop) ...[
                    _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Purchases', style: _j(22, FontWeight.w800, _navy)),
                      Text('Supplier bills · stock in', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                    ]),
                  ),
                  _round(Icons.local_shipping_rounded, () => open(context, const PartiesScreen(type: 'supplier'))),
                ]),
                const SizedBox(height: 14),
                _searchBox(),
                const SizedBox(height: 12),
                _hero(matches.map((m) => m.$1).toList(), d),
                const SizedBox(height: 14),
                _suppliers(d),
                const SizedBox(height: 14),
                _chips([
                  for (final p in [('today', 'Today'), ('week', 'This week'), ('month', 'This month'), ('year', 'This year'), ('all', 'All time')])
                    (p.$1, p.$2, null),
                ], period, (v) => setState(() => period = v)),
                const SizedBox(height: 8),
                _chips([
                  ('all', 'All', counts['all']),
                  ('paid', 'Paid', counts['paid']),
                  ('partial', 'Partial', counts['partial']),
                  ('unpaid', 'Unpaid', counts['unpaid']),
                ], status, (v) => setState(() => status = v)),
                const SizedBox(height: 12),
                if (q.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${matches.length} result${matches.length == 1 ? '' : 's'} for "$q"',
                        style: _j(12, FontWeight.w700, _muted)),
                  ),
                if (matches.isEmpty)
                  Container(
                    decoration: _card(),
                    padding: const EdgeInsets.all(20),
                    child: EmptyState(q.isEmpty ? 'No purchase bills in this period' : 'Nothing matches "$q"'),
                  ),
                ..._grouped(matches),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
          ),
          child: Icon(icon, color: _ink, size: 21),
        ),
      );

  Widget _searchBox() => Container(
        height: 56,
        padding: const EdgeInsets.only(left: 16, right: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFFFE0CC), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0x2AF0601A), blurRadius: 22, offset: Offset(0, 8), spreadRadius: -8)],
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: _orange, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: search,
              onChanged: (v) => setState(() => q = v.trim()),
              textInputAction: TextInputAction.search,
              style: _j(14.5, FontWeight.w600, _ink),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Supplier, mobile, bill no., IMEI, ₹ amount…',
                hintStyle: _j(13, FontWeight.w500, const Color(0xFF8A8FAD)),
              ),
            ),
          ),
          if (q.isNotEmpty)
            IconButton(
              onPressed: () {
                search.clear();
                setState(() => q = '');
              },
              icon: const Icon(Icons.close_rounded, color: _muted),
            ),
          GestureDetector(
            onTap: _scan,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: _supplierGrad),
                boxShadow: [BoxShadow(color: Color(0x66F0601A), blurRadius: 10, offset: Offset(0, 4), spreadRadius: -4)],
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 21),
            ),
          ),
        ]),
      );

  Widget _hero(List<Rec> rows, _BookData d) {
    final total = rows.fold<int>(0, (a, s) => a + asInt(s['total']));
    final paid = rows.fold<int>(0, (a, s) => a + asInt(s['paid']).clamp(0, asInt(s['total'])).toInt());
    final units = rows.fold<int>(0, (a, s) => a + asInt(s['qty']));
    final payable = d.payable.values.where((v) => v > 0).fold<int>(0, (a, v) => a + v);
    Widget cell(String l, String v, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: _j(11, FontWeight.w600, const Color(0xCCFFFFFF))),
            const SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _j(15.5, FontWeight.w800, c))),
          ]),
        );
    Widget sep() => Container(width: 1, height: 34, color: const Color(0x40FFFFFF), margin: const EdgeInsets.symmetric(horizontal: 10));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF8A3D), Color(0xFFF0601A), Color(0xFFD9480F)]),
        boxShadow: const [BoxShadow(color: Color(0x66F0601A), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: Stack(children: [
        Positioned(
          right: -30,
          top: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Total purchases', style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Text('${rows.length} bills · $units units in', style: _j(11, FontWeight.w700, Colors.white)),
              ),
            ]),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(total), style: _j(28, FontWeight.w800, Colors.white))),
            const SizedBox(height: 12),
            Row(children: [
              cell('Paid', Money.rs(paid), Colors.white),
              sep(),
              cell('Unpaid bills', Money.rs(total - paid), Colors.white),
              sep(),
              cell('You owe now', Money.rs(payable), const Color(0xFFFFF1B8)),
            ]),
            if (total > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: paid / total,
                  minHeight: 7,
                  backgroundColor: const Color(0x33FFFFFF),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(height: 5),
              Text('${(paid * 100 / total).round()}% of bills paid', style: _j(11, FontWeight.w600, const Color(0xDDFFFFFF))),
            ],
          ]),
        ),
      ]),
    );
  }

  /// Supplier avatars, highest payable first; each opens the super profile.
  Widget _suppliers(_BookData d) {
    if (d.suppliers.isEmpty) return const SizedBox.shrink();
    final list = [...d.suppliers]..sort((a, b) => (d.payable[asInt(b['id'])] ?? 0).compareTo(d.payable[asInt(a['id'])] ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Suppliers', style: _j(15, FontWeight.w800, _ink)),
        const Spacer(),
        GestureDetector(
          onTap: () => open(context, const PartiesScreen(type: 'supplier')),
          child: Text('See all ›', style: _j(12.5, FontWeight.w700, _purple)),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            if (i == list.length) {
              return GestureDetector(
                onTap: () => open(context, const PartyForm(type: 'supplier')),
                child: Container(
                  width: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFFFD2B5), width: 1.4),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_business_rounded, color: _orange, size: 28),
                    const SizedBox(height: 6),
                    Text('Add\nsupplier', textAlign: TextAlign.center, style: _j(11.5, FontWeight.w700, _orange)),
                  ]),
                ),
              );
            }
            final s = list[i];
            final bal = d.payable[asInt(s['id'])] ?? 0;
            return GestureDetector(
              onTap: () => open(context, PartyView(type: 'supplier', id: asInt(s['id']))),
              child: Container(
                width: 112,
                padding: const EdgeInsets.all(10),
                decoration: _card(r: 22),
                child: Column(children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      gradient: const LinearGradient(colors: _supplierGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x55F06A1A), blurRadius: 10, offset: Offset(0, 4), spreadRadius: -3)],
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: storedImage(s['photo'] as String?,
                        fallback: Text(_initials('${s['name']}'), style: _j(16, FontWeight.w800, Colors.white))),
                  ),
                  const SizedBox(height: 6),
                  Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w800, _ink)),
                  const SizedBox(height: 2),
                  Text(bal > 0 ? Money.rs(bal) : 'Settled', style: _j(11, FontWeight.w800, bal > 0 ? _amber : _green)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _chips(List<(String, String, int?)> items, String value, ValueChanged<String> onTap) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in items) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(f.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: value == f.$1 ? const LinearGradient(colors: _supplierGrad) : null,
                  color: value == f.$1 ? null : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: value == f.$1 ? null : Border.all(color: _line),
                ),
                child: Text(f.$3 == null ? f.$2 : '${f.$2} (${f.$3})',
                    style: _j(12, FontWeight.w700, value == f.$1 ? Colors.white : _ink)),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      );

  List<Widget> _grouped(List<(Rec, SaleMatch)> rows) {
    final out = <Widget>[];
    String? last;
    final today = ymd(DateTime.now());
    final yesterday = ymd(DateTime.now().subtract(const Duration(days: 1)));
    for (final (s, m) in rows) {
      final d = '${s['date']}';
      if (d != last) {
        last = d;
        final dayTotal = rows.where((r) => '${r.$1['date']}' == d).fold<int>(0, (a, r) => a + asInt(r.$1['total']));
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(children: [
            Text(d == today ? 'Today' : d == yesterday ? 'Yesterday' : prettyDate(d), style: _j(13, FontWeight.w800, _navy)),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: _line)),
            const SizedBox(width: 8),
            Text(Money.rs(dayTotal), style: _j(12, FontWeight.w700, _muted)),
          ]),
        ));
      }
      out.add(PurchaseCard(p: s, match: q.isEmpty ? null : m));
    }
    return out;
  }
}

class PurchaseCard extends StatelessWidget {
  final Rec p;
  final SaleMatch? match;
  const PurchaseCard({super.key, required this.p, this.match});

  @override
  Widget build(BuildContext context) {
    final name = '${p['supplier']}';
    final phone = p['phone'] as String?;
    final total = asInt(p['total']), paid = asInt(p['paid']);
    final due = total - paid;
    final (label, color) = paid >= total ? ('PAID', _green) : paid > 0 ? ('PARTIAL', _amber) : ('UNPAID', _red);
    final serials = '${p['serials'] ?? ''}'.trim();
    final account = '${p['account'] ?? ''}'.trim();
    final billNo = '${p['bill_no'] ?? ''}'.trim();
    final img = (p['bill_image'] as String? ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card(r: 22),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => open(context, PurchaseView(id: asInt(p['id']))),
          onLongPress: () => _options(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => open(context, PartyView(type: 'supplier', id: asInt(p['supplier_id']))),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      gradient: const LinearGradient(colors: _supplierGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x66F06A1A), blurRadius: 12, offset: Offset(0, 5), spreadRadius: -3)],
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: storedImage(p['photo'] as String?,
                        fallback: Text(_initials(name), style: _j(17, FontWeight.w800, Colors.white))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14.5, FontWeight.w800, _ink)),
                    const SizedBox(height: 2),
                    Text(
                      ['${p['number']}', if (billNo.isNotEmpty) 'Bill $billNo', if (phone != null && phone.isNotEmpty) phone].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _j(11.5, FontWeight.w600, _muted),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Money.rs(total), style: _j(15.5, FontWeight.w800, _ink)),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withAlpha(0x1F), borderRadius: BorderRadius.circular(8)),
                    child: Text(label, style: _j(9.5, FontWeight.w800, color)),
                  ),
                ]),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFFFF6EF), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.move_to_inbox_rounded, size: 16, color: _orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${p['items'] ?? 'No items'}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                      ),
                      Text('+${asInt(p['qty'])}', style: _j(12, FontWeight.w800, _green)),
                    ]),
                  ),
                ),
                if (img.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFD9BF))),
                    clipBehavior: Clip.antiAlias,
                    child: storedImage(img, fallback: const Icon(Icons.receipt_long_rounded, color: _orange)),
                  ),
                ],
              ]),
              if (serials.isNotEmpty || account.isNotEmpty || due > 0) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (serials.isNotEmpty)
                    _tag(Icons.qr_code_rounded, 'IMEI ${serials.split(' ').first}${serials.contains(' ') ? ' +' : ''}', _navy),
                  if (account.isNotEmpty && paid > 0) _tag(Icons.account_balance_wallet_rounded, account, _green),
                  if (due > 0) _tag(Icons.schedule_rounded, 'To pay ${Money.rs(due)}', _red),
                ]),
              ],
              if (match != null && match!.$1.isNotEmpty && match!.$1 != 'Supplier' && match!.$1 != 'Invoice') ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.manage_search_rounded, size: 15, color: _orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Matched ${match!.$1}: ${match!.$2}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w700, _orange)),
                  ),
                ]),
              ],
              if (phone != null && phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _action(Icons.call_rounded, 'Call', const Color(0xFF2F6BFF), () => Contact.call(phone))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _action(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366),
                        () => Contact.whatsapp(phone, 'Hello $name, regarding bill ${billNo.isEmpty ? p['number'] : billNo}')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _action(Icons.person_rounded, 'Profile', _orange,
                        () => open(context, PartyView(type: 'supplier', id: asInt(p['supplier_id'])))),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  void _options(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(title: Text('${p['number']}', style: _j(15, FontWeight.w800, _ink)), subtitle: Text(Money.rs(asInt(p['total'])))),
          ListTile(
            leading: const Icon(Icons.receipt_long_rounded),
            title: const Text('Open bill'),
            onTap: () {
              Navigator.pop(c);
              open(context, PurchaseView(id: asInt(p['id'])));
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Edit purchase'),
            onTap: () {
              Navigator.pop(c);
              open(context, PurchaseForm(editPurchaseId: asInt(p['id'])));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: _red),
            title: const Text('Delete purchase', style: TextStyle(color: _red)),
            onTap: () {
              Navigator.pop(c);
              deletePurchaseFlow(context, p, popAfter: false);
            },
          ),
        ]),
      ),
    );
  }

  Widget _tag(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: c),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w700, c)),
          ),
        ]),
      );

  Widget _action(IconData i, String l, Color c, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 36,
          decoration: BoxDecoration(color: c.withAlpha(0x1A), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 16, color: c),
            const SizedBox(width: 6),
            Text(l, style: _j(12, FontWeight.w800, c)),
          ]),
        ),
      );
}
