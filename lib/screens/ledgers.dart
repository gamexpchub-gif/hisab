import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarms.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'lend_sheet.dart';
import 'parties.dart';
import 'sales.dart';

// =============================================================================
// Ledgers — the Khata book.
//   Khata    : who you will get from / give to, goods-on-credit vs cash lent
//              vs received, upcoming payment dates (with phone reminders),
//              and a feed of every credit entry: whom, when, how much, why.
//              "You gave" / "You got" buttons for cash udhar.
//   Balances : everyone you will get from and give to, ranked.
//   Accounts : chart of accounts with balances.
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

/// Presentation of each khata entry kind.
class _Kind {
  final String label;
  final IconData icon;
  final Color color;
  final bool raises; // true = raises what they owe you (or what you owe a supplier)
  const _Kind(this.label, this.icon, this.color, this.raises);
}

const _kinds = {
  'goods': _Kind('Goods on credit', Icons.shopping_bag_rounded, Color(0xFF7B3FF2), true),
  'cash_gave': _Kind('Cash given', Icons.north_east_rounded, _red, true),
  'receipt': _Kind('Payment received', Icons.south_west_rounded, _green, false),
  'cash_got': _Kind('Cash received', Icons.south_west_rounded, _green, false),
  'bill': _Kind('Goods taken on credit', Icons.inventory_2_rounded, _amber, true),
  'payment': _Kind('Paid to supplier', Icons.north_east_rounded, Color(0xFF2F6BFF), false),
};

class _KhataData {
  final KhataTotals totals;
  final List<Rec> feed, dues, customers, suppliers;
  final Map<int, int> cBal, sBal;
  final List<(Rec, int)> accounts;
  _KhataData(this.totals, this.feed, this.dues, this.customers, this.suppliers, this.cBal, this.sBal, this.accounts);
}

class LedgersScreen extends StatefulWidget {
  final int initialTab; // 0 khata · 1 balances · 2 accounts
  const LedgersScreen({super.key, this.initialTab = 0});
  @override
  State<LedgersScreen> createState() => _LedgersScreenState();
}

class _LedgersScreenState extends State<LedgersScreen> {
  late int tab = widget.initialTab;
  String filter = 'all'; // all | goods | cash | received | suppliers
  String q = '';

  Future<_KhataData> _load() async {
    final accts = <(Rec, int)>[];
    for (final a in await Books.accounts()) {
      accts.add((a, await Books.balance(asInt(a['id']), a['type'] as String)));
    }
    return _KhataData(
      await Books.khataTotals(),
      await Books.khataFeed(),
      await Books.dues(),
      await Books.query('SELECT * FROM customers ORDER BY name COLLATE NOCASE'),
      await Books.query('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE'),
      await Books.partyBalances('customer'),
      await Books.partyBalances('supplier'),
      accts,
    );
  }

  void _lend(String kind) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LendSheet(kind: kind),
      );

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: Live<_KhataData>(
            load: _load,
            builder: (context, d) => ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, (tab == 0 ? 100 : 30) + safe),
              children: [
                Row(children: [
                  if (canPop) ...[
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: _ink),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ledger · Khata', style: _j(22, FontWeight.w800, _navy)),
                      Text('Udhar given & taken — who, when, why', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                _hero(d.totals),
                const SizedBox(height: 14),
                _tabs(),
                const SizedBox(height: 14),
                if (tab == 0) ..._khata(d),
                if (tab == 1) ..._balances(d),
                if (tab == 2) _accounts(d),
              ],
            ),
          ),
        ),
        if (tab == 0)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14 + safe,
            child: Row(children: [
              Expanded(child: _bigButton('You gave ₹', Icons.north_east_rounded, const [Color(0xFFF43F5E), Color(0xFFDC2626)], () => _lend('gave'))),
              const SizedBox(width: 10),
              Expanded(child: _bigButton('You got ₹', Icons.south_west_rounded, const [Color(0xFF1BB574), Color(0xFF0F8C58)], () => _lend('got'))),
            ]),
          ),
      ]),
    );
  }

  Widget _bigButton(String label, IconData icon, List<Color> colors, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withAlpha(0x80), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -6)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: _j(15, FontWeight.w800, Colors.white)),
          ]),
        ),
      );

  // ---------------------------------------------------------------- hero (liquid glass)
  Widget _hero(KhataTotals t) {
    Widget glass(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(colors: [Color(0x40FFFFFF), Color(0x14FFFFFF)]),
                border: Border.all(color: const Color(0x55FFFFFF)),
              ),
              child: child,
            ),
          ),
        );
    Widget big(String l, int v, Color c, IconData i) => Expanded(
          child: glass(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(i, size: 15, color: c),
              const SizedBox(width: 4),
              Flexible(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w700, const Color(0xE6FFFFFF)))),
            ]),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(v), style: _j(20, FontWeight.w800, Colors.white))),
          ])),
        );
    Widget small(String l, int v) => Expanded(
          child: Column(children: [
            Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w500, const Color(0xB3FFFFFF))),
            const SizedBox(height: 2),
            Text(Money.compact(v), style: _j(14, FontWeight.w800, Colors.white)),
          ]),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 28, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1B4B), Color(0xFF4B22D8), Color(0xFF2F55E8)]),
              ),
            ),
          ),
          Positioned(right: -60, top: -70, child: _blob(210, 0x2E)),
          Positioned(left: -50, bottom: -80, child: _blob(190, 0x1F)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                big('You will get', t.youGet, const Color(0xFF9CF5C4), Icons.south_west_rounded),
                const SizedBox(width: 10),
                big('You will give', t.youGive, const Color(0xFFFFB4B4), Icons.north_east_rounded),
              ]),
              const SizedBox(height: 12),
              glass(Row(children: [
                small('Goods on credit', t.goodsCredit),
                small('Cash lent', t.cashLent),
                small('Received back', t.received),
                small('Net', t.net),
              ])),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xCCFFFFFF)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${t.customersWithDue} customer${t.customersWithDue == 1 ? '' : 's'} owe you · you owe ${t.suppliersToPay} supplier${t.suppliersToPay == 1 ? '' : 's'}',
                    style: _j(11.5, FontWeight.w600, const Color(0xCCFFFFFF)),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _blob(double s, int a) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color.fromARGB(a, 255, 255, 255), const Color(0x00FFFFFF)]),
        ),
      );

  Widget _tabs() {
    const labels = ['Khata', 'Balances', 'Accounts'];
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: _card(r: 24),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / 3;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            left: tab * w,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => tab = i);
                  },
                  child: Center(child: Text(labels[i], style: _j(13, FontWeight.w700, i == tab ? Colors.white : const Color(0xFF3A4155)))),
                ),
              ),
          ]),
        ]);
      }),
    );
  }

  // ---------------------------------------------------------------- khata tab
  List<Widget> _khata(_KhataData d) {
    final feed = d.feed.where((e) {
      final k = e['kind'] as String;
      final ok = switch (filter) {
        'goods' => k == 'goods',
        'cash' => k == 'cash_gave' || k == 'cash_got',
        'received' => k == 'receipt' || (k == 'cash_got' && e['party_type'] == 'customer'),
        'suppliers' => e['party_type'] == 'supplier',
        _ => true,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      return '${e['party']} ${e['reason'] ?? ''} ${e['ref']}'.toLowerCase().contains(q.toLowerCase());
    }).toList();
    final groups = <String, List<Rec>>{};
    for (final e in feed) {
      final dt = DateTime.parse(e['date'] as String);
      groups.putIfAbsent('${monthName(dt.month)} ${dt.year}', () => []).add(e);
    }
    return [
      if (d.dues.isNotEmpty) ...[_duesStrip(d.dues), const SizedBox(height: 14)],
      Container(
        height: 48,
        decoration: _card(r: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: Color(0xFF2C3B8F)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => q = v.trim()),
              style: _j(14, FontWeight.w600, _ink),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search name, reason, product, invoice',
                hintStyle: _j(13.5, FontWeight.w400, const Color(0xFF8A8FAD)),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in const [
            ('all', 'All entries'),
            ('goods', 'Goods udhar'),
            ('cash', 'Cash udhar'),
            ('received', 'Received'),
            ('suppliers', 'Suppliers'),
          ]) ...[
            GestureDetector(
              onTap: () => setState(() => filter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: filter == f.$1 ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                  color: filter == f.$1 ? null : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: filter == f.$1 ? null : Border.all(color: _line),
                ),
                child: Text(f.$2, style: _j(12, FontWeight.w700, filter == f.$1 ? Colors.white : _ink)),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      if (feed.isEmpty)
        Container(
          decoration: _card(),
          padding: const EdgeInsets.all(20),
          child: const EmptyState('No entries yet — tap “You gave” or make a credit sale'),
        ),
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: Row(children: [
            Text(g.key.toUpperCase(), style: _j(11, FontWeight.w800, _muted).copyWith(letterSpacing: 1)),
            const Spacer(),
            Text('${g.value.length} entr${g.value.length == 1 ? 'y' : 'ies'}', style: _j(11, FontWeight.w600, _muted)),
          ]),
        ),
        for (final e in g.value) _entry(e),
      ],
    ];
  }

  Widget _duesStrip(List<Rec> dues) {
    final today = ymd(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.alarm_rounded, size: 17, color: _purple),
        const SizedBox(width: 6),
        Text('Payment dates', style: _j(13, FontWeight.w800, _ink)),
        const Spacer(),
        Text('${dues.length} open', style: _j(11.5, FontWeight.w700, _muted)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 118,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: dues.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final d = dues[i];
            final date = d['due_date'] as String;
            final overdue = date.compareTo(today) < 0;
            final isToday = date == today;
            final c = overdue ? _red : isToday ? _amber : _purple;
            final isC = d['party_type'] == 'customer';
            return GestureDetector(
              onTap: () => open(context, PartyView(type: d['party_type'] as String, id: asInt(d['party_id']))),
              child: Container(
                width: 168,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.withAlpha(0x66), width: 1.4),
                  boxShadow: [BoxShadow(color: c.withAlpha(0x26), blurRadius: 14, offset: const Offset(0, 5), spreadRadius: -6)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(8)),
                      child: Text(overdue ? 'Overdue' : isToday ? 'Today' : timeUntil(date), style: _j(10.5, FontWeight.w800, c)),
                    ),
                    const Spacer(),
                    Icon(isC ? Icons.south_west_rounded : Icons.north_east_rounded, size: 16, color: isC ? _green : _red),
                  ]),
                  const SizedBox(height: 8),
                  Text('${d['party'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w800, _ink)),
                  Text(Money.rs(asInt(d['amount'])), style: _j(15, FontWeight.w800, c)),
                  Text(prettyDate(date), style: _j(10.5, FontWeight.w600, _muted)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _entry(Rec e) {
    final k = _kinds[e['kind']] ?? _kinds['goods']!;
    final isC = e['party_type'] == 'customer';
    final amount = asInt(e['amount']);
    final credit = asInt(e['credit']);
    final name = '${e['party'] ?? ''}';
    final reason = (e['reason'] as String?) ?? '';
    final isDoc = e['kind'] == 'goods' || e['kind'] == 'bill';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card(r: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => open(context, PartyView(type: e['party_type'] as String, id: asInt(e['party_id']))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(colors: isC ? const [Color(0xFF8B5CF6), Color(0xFF4F46E5)] : const [Color(0xFFFFA24A), Color(0xFFF06A1A)]),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: storedImage(e['photo'] as String?,
                      fallback: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: _j(17, FontWeight.w800, Colors.white))),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: k.color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: Icon(k.icon, size: 11, color: Colors.white),
                  ),
                ),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14, FontWeight.w800, _ink))),
                    Text(
                      '${k.raises ? '+' : '−'}${Money.rs(amount)}',
                      style: _j(14, FontWeight.w800, k.raises ? (isC ? _red : _amber) : _green),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: k.color.withAlpha(0x1A), borderRadius: BorderRadius.circular(6)),
                      child: Text(k.label, style: _j(10, FontWeight.w800, k.color)),
                    ),
                    const SizedBox(width: 6),
                    Text('${prettyDate(e['date'] as String)} · ${e['ref']}', style: _j(10.5, FontWeight.w600, _muted)),
                  ]),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(isDoc ? Icons.inventory_2_outlined : Icons.notes_rounded, size: 14, color: _muted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w600, const Color(0xFF3A4155))),
                      ),
                    ]),
                  ],
                  if (isDoc && credit < amount) ...[
                    const SizedBox(height: 4),
                    Text('Paid ${Money.rs(amount - credit)} at the time · ${Money.rs(credit)} on credit',
                        style: _j(10.5, FontWeight.w600, _muted)),
                  ],
                  if (isDoc)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        onPressed: () => open(context, e['kind'] == 'goods' ? SaleView(id: asInt(e['doc_id'])) : PurchaseView(id: asInt(e['doc_id']))),
                        icon: const Icon(Icons.receipt_long_rounded, size: 15),
                        label: Text(e['kind'] == 'goods' ? 'Open invoice' : 'Open bill', style: _j(11.5, FontWeight.w700, _purple)),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- balances tab
  List<Widget> _balances(_KhataData d) {
    final get = <(Rec, String, int)>[];
    final give = <(Rec, String, int)>[];
    for (final c in d.customers) {
      final b = d.cBal[asInt(c['id'])] ?? 0;
      if (b > 0) get.add((c, 'customer', b));
      if (b < 0) give.add((c, 'customer', -b));
    }
    for (final s in d.suppliers) {
      final b = d.sBal[asInt(s['id'])] ?? 0;
      if (b > 0) give.add((s, 'supplier', b));
      if (b < 0) get.add((s, 'supplier', -b));
    }
    get.sort((a, b) => b.$3.compareTo(a.$3));
    give.sort((a, b) => b.$3.compareTo(a.$3));
    Widget section(String title, String sub, List<(Rec, String, int)> rows, Color c, IconData icon) {
      final total = rows.fold<int>(0, (a, r) => a + r.$3);
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: c, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _j(15, FontWeight.w800, _ink)),
                Text(sub, style: _j(11, FontWeight.w500, _muted)),
              ]),
            ),
            Text(Money.rs(total), style: _j(15, FontWeight.w800, c)),
          ]),
          const SizedBox(height: 8),
          if (rows.isEmpty) const EmptyState('Nobody here'),
          for (final r in rows)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => open(context, PartyView(type: r.$2, id: asInt(r.$1['id']))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: r.$2 == 'customer' ? const Color(0xFFEFEBFF) : const Color(0xFFFFF1E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: storedImage(r.$1['photo'] as String?,
                        fallback: Text('${r.$1['name']}'.isEmpty ? '?' : '${r.$1['name']}'[0].toUpperCase(),
                            style: _j(14, FontWeight.w800, r.$2 == 'customer' ? _purple : const Color(0xFFF06A1A)))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.$1['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w700, _ink)),
                      Text(r.$2 == 'customer' ? 'Customer' : 'Supplier', style: _j(10.5, FontWeight.w600, _muted)),
                    ]),
                  ),
                  Text(Money.rs(r.$3), style: _j(13.5, FontWeight.w800, c)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Contact.call(r.$1['phone'] as String?),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: const Color(0x1F2F6BFF), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.call_rounded, size: 16, color: Color(0xFF2F6BFF)),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      );
    }

    return [
      section('You will get', 'People who owe you', get, _green, Icons.south_west_rounded),
      section('You will give', 'People you owe', give, _red, Icons.north_east_rounded),
    ];
  }

  // ---------------------------------------------------------------- accounts tab
  Widget _accounts(_KhataData d) {
    const groups = [('asset', 'Assets'), ('liability', 'Liabilities'), ('equity', 'Equity'), ('income', 'Income'), ('expense', 'Expenses')];
    const colors = {
      'asset': Color(0xFF2F6BFF),
      'liability': Color(0xFFF06A1A),
      'equity': Color(0xFF7B3FF2),
      'income': Color(0xFF16A36A),
      'expense': Color(0xFFDC4545),
    };
    return Column(children: [
      for (final g in groups)
        if (d.accounts.any((e) => e.$1['type'] == g.$1))
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            decoration: _card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.$2.toUpperCase(), style: _j(11, FontWeight.w800, colors[g.$1]!).copyWith(letterSpacing: 1)),
              for (final e in d.accounts.where((e) => e.$1['type'] == g.$1))
                InkWell(
                  onTap: () => open(context, AccountLedgerScreen(accountId: asInt(e.$1['id']))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: colors[g.$1]!.withAlpha(0x1A), borderRadius: BorderRadius.circular(11)),
                        alignment: Alignment.center,
                        child: Text('${e.$1['code']}'.substring(0, 2), style: _j(11, FontWeight.w800, colors[g.$1]!)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(e.$1['name'] as String, style: _j(13.5, FontWeight.w700, _ink))),
                      Text(Money.rs(e.$2), style: _j(13.5, FontWeight.w800, e.$2 < 0 ? _red : _ink)),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9BCD6)),
                    ]),
                  ),
                ),
            ]),
          ),
    ]);
  }
}

/// "in 3 days", "in 2 wk" for a future yyyy-MM-dd date.
String timeUntil(String ymdDate) {
  final d = DateTime.tryParse(ymdDate);
  if (d == null) return ymdDate;
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 14) return 'in $days days';
  if (days < 60) return 'in ${days ~/ 7} wk';
  return 'in ${days ~/ 30} mo';
}

/// Keeps reminders in sync when a due is marked paid or removed.
Future<void> closeDue(int id, {bool delete = false}) async {
  await Alarms.cancelDue(id);
  if (delete) {
    await Books.deleteDue(id);
  } else {
    await Books.setDueStatus(id, 'paid');
  }
}

class AccountLedgerScreen extends StatefulWidget {
  final int accountId;
  const AccountLedgerScreen({super.key, required this.accountId});
  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  String from = ymd(DateTime(DateTime.now().year, DateTime.now().month, 1));
  String to = ymd(DateTime.now());

  Future<(Rec, int, List<Rec>)> _load() async {
    final a = (await Books.query('SELECT * FROM accounts WHERE id = ?', [widget.accountId])).first;
    final type = a['type'] as String;
    final dayBefore = ymd(DateTime.parse(from).subtract(const Duration(days: 1)));
    final opening = await Books.balance(widget.accountId, type, to: dayBefore);
    final rows = await Books.ledger(accountId: widget.accountId, accountType: type, from: from, to: to);
    return (a, opening, [for (final r in rows) {...r, 'balance': asInt(r['balance']) + opening}]);
  }

  @override
  Widget build(BuildContext context) {
    return Live<(Rec, int, List<Rec>)>(
      key: ValueKey('$from$to'),
      load: _load,
      builder: (context, d) => PageShell(
        title: d.$1['name'] as String,
        subtitle: 'Account ${d.$1['code']} · ${d.$1['type']}',
        children: [
          CardBox(
            child: Column(children: [
              Row(children: [
                Expanded(child: DateField(label: 'From', value: from, onChanged: (v) => setState(() => from = v))),
                const SizedBox(width: 10),
                Expanded(child: DateField(label: 'To', value: to, onChanged: (v) => setState(() => to = v))),
              ]),
              TotalLine('Opening balance', Money.rs(d.$2)),
              TotalLine('Closing balance', Money.rs(d.$3.isEmpty ? d.$2 : asInt(d.$3.last['balance'])), bold: true),
            ]),
          ),
          CardBox(child: d.$3.isEmpty ? const EmptyState('No entries in this period') : LedgerTable(d.$3)),
        ],
      ),
    );
  }
}
