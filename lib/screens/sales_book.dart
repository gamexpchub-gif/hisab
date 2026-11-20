import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'sale_form.dart';
import 'sales.dart' show SaleView, deleteSaleFlow;
import 'scanner.dart';

// =============================================================================
// Sales book — one search box finds a sale by customer name, mobile,
// IMEI / serial, invoice number, amount, address, product or account.
// Liquid-glass summary, period and status filters, date-grouped sale cards
// with the customer's photo avatar.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
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

/// Which field of a sale matched the search, for the "matched" hint.
typedef SaleMatch = (String field, String value);

/// Searches a sales-book row (see [Books.salesBook]). Returns null when the
/// row does not match, otherwise what matched. Numbers match mobile numbers,
/// IMEI / serials, invoice numbers and amounts (₹1,250 / 1250 / 1250.50).
SaleMatch? matchSale(Rec s, String query) => matchDoc(s, query);

/// Shared search for sales and purchase bills. [party] is the column with
/// the customer / supplier name, [accounts] the one with the paying account.
SaleMatch? matchDoc(Rec s, String query, {String party = 'customer', String accounts = 'accounts'}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return ('', '');
  bool has(Object? v) => v != null && '$v'.toLowerCase().contains(q);
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  final numeric = digits.isNotEmpty && RegExp(r'^[₹rs.\s0-9,]+$').hasMatch(q);
  if (has(s['number'])) return ('Invoice', '${s['number']}');
  if (has(s['bill_no'])) return ('Bill no.', '${s['bill_no']}');
  if (has(s[party])) return (party == 'customer' ? 'Customer' : 'Supplier', '${s[party]}');
  String clean(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
  if (numeric && digits.length >= 3) {
    for (final k in ['phone', 'alt_phone']) {
      if (clean(s[k]).contains(digits)) return ('Mobile', '${s[k]}');
    }
  }
  if (has(s['serials']) || (numeric && digits.length >= 4 && clean(s['serials']).contains(digits))) {
    final hit = '${s['serials']}'.split(' ').firstWhere(
        (x) => x.toLowerCase().contains(q) || (digits.length >= 4 && x.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)),
        orElse: () => '${s['serials']}');
    return ('IMEI / Serial', hit);
  }
  if (numeric) {
    final total = asInt(s['total']);
    final cleanQ = q.replaceAll(RegExp(r'[₹rs,\s]'), '');
    final rupees = '${total ~/ 100}';
    if (rupees.startsWith(cleanQ) || Money.edit(total).startsWith(cleanQ)) return ('Amount', Money.rs(total));
    final due = total - asInt(s['paid']);
    if (due > 0 && '${due ~/ 100}'.startsWith(cleanQ)) return ('Due', Money.rs(due));
  }
  if (has(s['address'])) return ('Address', '${s['address']}');
  if (has(s['items'])) return ('Product', '${s['items']}');
  if (has(s[accounts])) return ('Paid via', '${s[accounts]}');
  if (has(s['gstin'])) return ('GSTIN', '${s['gstin']}');
  if (has(s['note'])) return ('Note', '${s['note']}');
  return null;
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final search = TextEditingController();
  String q = '';
  String period = 'all'; // today | week | month | year | all
  String status = 'all'; // all | paid | partial | due

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

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
    return paid >= total ? 'paid' : paid > 0 ? 'partial' : 'due';
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
          open(context, const SaleForm());
        },
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
            border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x774A17C9), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text('New sale', style: _j(15, FontWeight.w800, Colors.white)),
          ]),
        ),
      ),
      body: SafeArea(
        child: Live<List<Rec>>(
          load: Books.salesBook,
          builder: (context, all) {
            final from = _from;
            final periodRows = from == null ? all : all.where((s) => '${s['date']}'.compareTo(from) >= 0).toList();
            final matches = <(Rec, SaleMatch)>[];
            for (final s in periodRows) {
              if (status != 'all' && _status(s) != status) continue;
              final m = matchSale(s, q);
              if (m != null) matches.add((s, m));
            }
            final counts = {
              for (final k in ['all', 'paid', 'partial', 'due'])
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
                      Text('Sales', style: _j(22, FontWeight.w800, _navy)),
                      Text('${all.length} invoices · search anything', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                _searchBox(),
                const SizedBox(height: 12),
                _hero(matches.map((m) => m.$1).toList()),
                const SizedBox(height: 12),
                _chips([
                  for (final p in [('today', 'Today'), ('week', 'This week'), ('month', 'This month'), ('year', 'This year'), ('all', 'All time')])
                    (p.$1, p.$2, null),
                ], period, (v) => setState(() => period = v)),
                const SizedBox(height: 8),
                _chips([
                  ('all', 'All', counts['all']),
                  ('paid', 'Paid', counts['paid']),
                  ('partial', 'Partial', counts['partial']),
                  ('due', 'Due', counts['due']),
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
                    child: EmptyState(q.isEmpty ? 'No sales in this period' : 'Nothing matches "$q"'),
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
          border: Border.all(color: const Color(0xFFE4E0FB), width: 1.2),
          boxShadow: const [
            BoxShadow(color: Color(0x2A5B2EE0), blurRadius: 22, offset: Offset(0, 8), spreadRadius: -8),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: _purple, size: 24),
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
                hintText: 'Name, mobile, IMEI, invoice, ₹ amount, address…',
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
                boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 10, offset: Offset(0, 4), spreadRadius: -4)],
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 21),
            ),
          ),
        ]),
      );

  Widget _hero(List<Rec> rows) {
    final total = rows.fold<int>(0, (a, s) => a + asInt(s['total']));
    final paid = rows.fold<int>(0, (a, s) => a + asInt(s['paid']).clamp(0, asInt(s['total'])).toInt());
    final due = total - paid;
    final items = rows.fold<int>(0, (a, s) => a + asInt(s['qty']));
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
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)]),
        boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
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
              Text('Total sales', style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Text('${rows.length} invoices · $items items', style: _j(11, FontWeight.w700, Colors.white)),
              ),
            ]),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(total), style: _j(28, FontWeight.w800, Colors.white))),
            const SizedBox(height: 12),
            Row(children: [
              cell('Collected', Money.rs(paid), const Color(0xFF9CF5C4)),
              sep(),
              cell('Due', Money.rs(due), due > 0 ? const Color(0xFFFFC2C2) : Colors.white),
              sep(),
              cell('Avg bill', rows.isEmpty ? '—' : Money.rs(total ~/ rows.length), Colors.white),
            ]),
            if (total > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: paid / total,
                  minHeight: 7,
                  backgroundColor: const Color(0x33FFFFFF),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF9CF5C4)),
                ),
              ),
              const SizedBox(height: 5),
              Text('${(paid * 100 / total).round()}% collected', style: _j(11, FontWeight.w600, const Color(0xDDFFFFFF))),
            ],
          ]),
        ),
      ]),
    );
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
                  gradient: value == f.$1 ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
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
      out.add(SaleCard(s: s, match: q.isEmpty ? null : m));
    }
    return out;
  }
}

class SaleCard extends StatelessWidget {
  final Rec s;
  final SaleMatch? match;
  const SaleCard({super.key, required this.s, this.match});

  @override
  Widget build(BuildContext context) {
    final name = (s['customer'] as String?) ?? 'Walk-in customer';
    final walkIn = s['customer'] == null;
    final phone = s['phone'] as String?;
    final total = asInt(s['total']), paid = asInt(s['paid']);
    final due = total - paid;
    final (label, color) = paid >= total ? ('PAID', _green) : paid > 0 ? ('PARTIAL', _amber) : ('DUE', _red);
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    final grad = walkIn ? const [Color(0xFF9AA3C7), Color(0xFF5E6790)] : const [Color(0xFF8B5CF6), Color(0xFF4F46E5)];
    final serials = '${s['serials'] ?? ''}'.trim();
    final accounts = '${s['accounts'] ?? ''}'.trim();
    final time = DateTime.tryParse('${s['created_at']}');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card(r: 22),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => open(context, SaleView(id: asInt(s['id']))),
          onLongPress: () => _options(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: grad.last.withAlpha(0x66), blurRadius: 12, offset: const Offset(0, 5), spreadRadius: -3)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: storedImage(
                    s['photo'] as String?,
                    fallback: walkIn
                        ? const Icon(Icons.person_rounded, color: Colors.white)
                        : Text(initials.isEmpty ? '?' : initials, style: _j(17, FontWeight.w800, Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14.5, FontWeight.w800, _ink)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${s['number']}',
                        if (time != null) '${two(time.hour)}:${two(time.minute)}',
                        if (phone != null && phone.isNotEmpty) phone,
                      ].join(' · '),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF6F5FF), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.inventory_2_rounded, size: 16, color: _purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${s['items'] ?? 'No items'}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                  ),
                  Text('×${asInt(s['qty'])}', style: _j(12, FontWeight.w800, _purple)),
                ]),
              ),
              if (serials.isNotEmpty || accounts.isNotEmpty || due > 0) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (serials.isNotEmpty) _tag(Icons.qr_code_rounded, 'IMEI ${serials.split(' ').first}${serials.contains(' ') ? ' +' : ''}', _navy),
                  if (accounts.isNotEmpty) _tag(Icons.account_balance_wallet_rounded, accounts, _green),
                  if (due > 0) _tag(Icons.schedule_rounded, 'Due ${Money.rs(due)}', _red),
                ]),
              ],
              if (match != null && match!.$1.isNotEmpty && match!.$1 != 'Customer' && match!.$1 != 'Invoice') ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.manage_search_rounded, size: 15, color: _purple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Matched ${match!.$1}: ${match!.$2}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w700, _purple)),
                  ),
                ]),
              ],
              if (!walkIn && phone != null && phone.isNotEmpty && due > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _action(Icons.call_rounded, 'Call', const Color(0xFF2F6BFF), () => Contact.call(phone))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _action(Icons.chat_rounded, 'Remind', const Color(0xFF25D366), () {
                      Contact.whatsapp(phone,
                          'Hi $name, a reminder for invoice ${s['number']} — ${Money.rs(due)} is pending. Thank you!');
                    }),
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
          ListTile(title: Text('${s['number']}', style: _j(15, FontWeight.w800, _ink)), subtitle: Text(Money.rs(asInt(s['total'])))),
          ListTile(
            leading: const Icon(Icons.receipt_long_rounded),
            title: const Text('Open invoice'),
            onTap: () {
              Navigator.pop(c);
              open(context, SaleView(id: asInt(s['id'])));
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Edit sale'),
            onTap: () {
              Navigator.pop(c);
              open(context, SaleForm(editSaleId: asInt(s['id'])));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: _red),
            title: const Text('Delete sale', style: TextStyle(color: _red)),
            onTap: () {
              Navigator.pop(c);
              deleteSaleFlow(context, s, popAfter: false);
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
