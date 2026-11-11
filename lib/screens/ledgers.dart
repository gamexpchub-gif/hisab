import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'parties.dart';

// =============================================================================
// Ledgers — customers (receivable), suppliers (payable) and accounts.
// Summary card, sliding tabs, search, filters (due / overdue / settled),
// sorting, party cards with ageing, call & WhatsApp, and bulk reminders.
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

class _LedgerData {
  final List<Rec> customers, suppliers;
  final Map<int, int> cBal, sBal;
  final Map<int, Ageing> cAge, sAge;
  final List<(Rec, int)> accounts;
  final Map<String, String> settings;
  _LedgerData(this.customers, this.suppliers, this.cBal, this.sBal, this.cAge, this.sAge, this.accounts, this.settings);
  int get receivable => cBal.values.where((v) => v > 0).fold(0, (a, b) => a + b);
  int get payable => sBal.values.where((v) => v > 0).fold(0, (a, b) => a + b);
}

class LedgersScreen extends StatefulWidget {
  final int initialTab; // 0 customers · 1 suppliers · 2 accounts
  const LedgersScreen({super.key, this.initialTab = 0});
  @override
  State<LedgersScreen> createState() => _LedgersScreenState();
}

class _LedgersScreenState extends State<LedgersScreen> {
  late int tab = widget.initialTab;
  String q = '';
  String filter = 'all'; // all | due | overdue | settled
  String sort = 'due'; // due | name | recent

  Future<_LedgerData> _load() async {
    final accts = <(Rec, int)>[];
    for (final a in await Books.accounts()) {
      accts.add((a, await Books.balance(asInt(a['id']), a['type'] as String)));
    }
    return _LedgerData(
      await Books.query('SELECT * FROM customers ORDER BY name COLLATE NOCASE'),
      await Books.query('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE'),
      await Books.partyBalances('customer'),
      await Books.partyBalances('supplier'),
      await Books.ageing('customer'),
      await Books.ageing('supplier'),
      accts,
      await Books.settings(),
    );
  }

  String get _type => tab == 0 ? 'customer' : 'supplier';

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<_LedgerData>(
          load: _load,
          builder: (context, d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Row(children: [
                if (canPop) ...[
                  _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ledgers', style: _j(22, FontWeight.w800, _navy)),
                    Text('Khata · dues · payments · reminders', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                  ]),
                ),
                if (tab < 2)
                  GestureDetector(
                    onTap: () => open(context, PartyForm(type: _type)),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(21),
                        gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
                        boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -4)],
                      ),
                      child: Row(children: [
                        const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text('Add', style: _j(13, FontWeight.w800, Colors.white)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              _summary(d),
              const SizedBox(height: 14),
              _tabs(),
              const SizedBox(height: 14),
              if (tab < 2) ..._partyList(d) else _accounts(d),
            ],
          ),
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

  // ---------------------------------------------------------------- summary
  Widget _summary(_LedgerData d) {
    final overdue = d.cAge.entries.where((e) => (d.cBal[e.key] ?? 0) > 0 && e.value.oldestDays > 30).toList();
    final overdueAmt = overdue.fold<int>(0, (a, e) => a + e.value.buckets[1] + e.value.buckets[2] + e.value.buckets[3]);
    final net = d.receivable - d.payable;
    Widget cell(String l, int v, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: _j(11, FontWeight.w600, const Color(0xCCFFFFFF))),
            const SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(v), style: _j(17, FontWeight.w800, c))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)]),
        boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: Column(children: [
        Row(children: [
          cell('To receive', d.receivable, Colors.white),
          Container(width: 1, height: 36, color: const Color(0x40FFFFFF), margin: const EdgeInsets.symmetric(horizontal: 12)),
          cell('To pay', d.payable, Colors.white),
          Container(width: 1, height: 36, color: const Color(0x40FFFFFF), margin: const EdgeInsets.symmetric(horizontal: 12)),
          cell('Net', net, net >= 0 ? const Color(0xFF9CF5C4) : const Color(0xFFFFB4B4)),
        ]),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD66B), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${Money.rs(overdueAmt)} overdue 30+ days from ${overdue.length} customer${overdue.length == 1 ? '' : 's'}',
                    style: _j(12, FontWeight.w700, Colors.white)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- tabs
  Widget _tabs() {
    const labels = ['Customers', 'Suppliers', 'Accounts'];
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
                    setState(() {
                      tab = i;
                      filter = 'all';
                    });
                  },
                  child: Center(child: Text(labels[i], style: _j(13, FontWeight.w700, i == tab ? Colors.white : const Color(0xFF3A4155)))),
                ),
              ),
          ]),
        ]);
      }),
    );
  }

  // ---------------------------------------------------------------- party list
  List<Widget> _partyList(_LedgerData d) {
    final isC = tab == 0;
    final all = isC ? d.customers : d.suppliers;
    final bal = isC ? d.cBal : d.sBal;
    final age = isC ? d.cAge : d.sAge;
    int b(Rec r) => bal[asInt(r['id'])] ?? 0;
    int old(Rec r) => b(r) > 0 ? (age[asInt(r['id'])]?.oldestDays ?? 0) : 0;
    final counts = {
      'all': all.length,
      'due': all.where((r) => b(r) > 0).length,
      'overdue': all.where((r) => old(r) > 30).length,
      'settled': all.where((r) => b(r) <= 0).length,
    };
    var rows = all.where((r) {
      if (q.isNotEmpty && !'${r['name']} ${r['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase())) return false;
      return switch (filter) { 'due' => b(r) > 0, 'overdue' => old(r) > 30, 'settled' => b(r) <= 0, _ => true };
    }).toList();
    rows.sort((x, y) => switch (sort) {
          'name' => '${x['name']}'.toLowerCase().compareTo('${y['name']}'.toLowerCase()),
          'recent' => (age[asInt(y['id'])]?.lastActivity ?? '').compareTo(age[asInt(x['id'])]?.lastActivity ?? ''),
          _ => b(y).compareTo(b(x)),
        });
    final dueCustomers = isC ? d.customers.where((r) => b(r) > 0).toList() : <Rec>[];
    return [
      Row(children: [
        Expanded(
          child: Container(
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
                    hintText: 'Search ${isC ? 'customers' : 'suppliers'}',
                    hintStyle: _j(13.5, FontWeight.w400, const Color(0xFF8A8FAD)),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          initialValue: sort,
          onSelected: (v) => setState(() => sort = v),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'due', child: Text('Highest balance')),
            PopupMenuItem(value: 'recent', child: Text('Recent activity')),
            PopupMenuItem(value: 'name', child: Text('Name A–Z')),
          ],
          child: Container(
            width: 48,
            height: 48,
            decoration: _card(r: 24),
            child: const Icon(Icons.sort_rounded, color: _purple),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in [
            ('all', 'All'),
            ('due', isC ? 'With due' : 'To pay'),
            ('overdue', '30+ days'),
            ('settled', 'Settled'),
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
                child: Text('${f.$2} (${counts[f.$1]})', style: _j(12, FontWeight.w700, filter == f.$1 ? Colors.white : _ink)),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      if (dueCustomers.isNotEmpty) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _BulkReminderSheet(customers: dueCustomers, balances: d.cBal, ageing: d.cAge, settings: d.settings),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
              boxShadow: const [BoxShadow(color: Color(0x5525D366), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -5)],
            ),
            child: Row(children: [
              const Icon(Icons.campaign_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Send WhatsApp reminders to ${dueCustomers.length} customer${dueCustomers.length == 1 ? '' : 's'}',
                    style: _j(13, FontWeight.w800, Colors.white)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (rows.isEmpty)
        Container(decoration: _card(), padding: const EdgeInsets.all(20), child: EmptyState(isC ? 'No customers here' : 'No suppliers here')),
      for (final r in rows) _PartyCard(type: _type, r: r, balance: b(r), ageing: age[asInt(r['id'])]),
    ];
  }

  // ---------------------------------------------------------------- accounts
  Widget _accounts(_LedgerData d) {
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

class _PartyCard extends StatelessWidget {
  final String type;
  final Rec r;
  final int balance;
  final Ageing? ageing;
  const _PartyCard({required this.type, required this.r, required this.balance, this.ageing});

  @override
  Widget build(BuildContext context) {
    final isC = type == 'customer';
    final name = r['name'] as String;
    final phone = r['phone'] as String?;
    final days = balance > 0 ? ageing?.oldestDays ?? 0 : 0;
    final ageColor = days > 60 ? _red : days > 30 ? _amber : _green;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    final grad = isC ? const [Color(0xFF8B5CF6), Color(0xFF4F46E5)] : const [Color(0xFFFFA24A), Color(0xFFF06A1A)];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card(r: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => open(context, PartyView(type: type, id: asInt(r['id']))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: grad.last.withAlpha(0x55), blurRadius: 10, offset: const Offset(0, 4), spreadRadius: -3)],
                ),
                alignment: Alignment.center,
                child: Text(initials.isEmpty ? '?' : initials, style: _j(16, FontWeight.w800, Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14, FontWeight.w800, _ink)),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (balance > 0) ...[
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: ageColor, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(days == 0 ? 'Due today' : '${days}d old', style: _j(11, FontWeight.w700, ageColor)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        ageing?.lastActivity == null ? (phone ?? 'No activity') : 'Last · ${timeAgoDate(ageing!.lastActivity!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _j(11, FontWeight.w500, _muted),
                      ),
                    ),
                  ]),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(Money.rs(balance.abs()),
                    style: _j(14.5, FontWeight.w800, balance > 0 ? (isC ? _red : _amber) : _green)),
                Text(balance > 0 ? (isC ? 'to receive' : 'to pay') : balance < 0 ? 'advance' : 'settled',
                    style: _j(10.5, FontWeight.w600, _muted)),
              ]),
              const SizedBox(width: 6),
              Column(children: [
                _mini(Icons.call_rounded, const Color(0xFF2F6BFF), () => Contact.call(phone)),
                const SizedBox(height: 6),
                _mini(Icons.chat_rounded, const Color(0xFF25D366), () => Contact.whatsapp(phone, 'Hi $name,')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _mini(IconData i, Color c, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(10)),
          child: Icon(i, size: 16, color: c),
        ),
      );
}

/// Sends a smart reminder to each customer with dues, one tap each.
class _BulkReminderSheet extends StatefulWidget {
  final List<Rec> customers;
  final Map<int, int> balances;
  final Map<int, Ageing> ageing;
  final Map<String, String> settings;
  const _BulkReminderSheet({required this.customers, required this.balances, required this.ageing, required this.settings});
  @override
  State<_BulkReminderSheet> createState() => _BulkReminderSheetState();
}

class _BulkReminderSheetState extends State<_BulkReminderSheet> {
  final sent = <int>{};
  bool bangla = false;

  @override
  Widget build(BuildContext context) {
    final list = [...widget.customers]
      ..sort((a, b) => (widget.balances[asInt(b['id'])] ?? 0).compareTo(widget.balances[asInt(a['id'])] ?? 0));
    return DraggableScrollableSheet(
      initialChildSize: .8,
      maxChildSize: .95,
      minChildSize: .4,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(color: _bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Payment reminders', style: _j(18, FontWeight.w800, _navy)),
                  Text('${sent.length} of ${list.length} sent · tone picked by due age', style: _j(12, FontWeight.w500, _muted)),
                ]),
              ),
              GestureDetector(
                onTap: () => setState(() => bangla = !bangla),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFE7F8EE), borderRadius: BorderRadius.circular(12)),
                  child: Text(bangla ? 'বাংলা' : 'English', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF075E54))),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('WhatsApp opens with the message ready — just tap Send there.', style: _j(11.5, FontWeight.w500, _muted)),
          ),
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              for (final c in list) _row(c),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(Rec c) {
    final id = asInt(c['id']);
    final due = widget.balances[id] ?? 0;
    final days = widget.ageing[id]?.oldestDays ?? 0;
    final tone = Reminders.suggest(days);
    final done = sent.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: _card(r: 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'] as String, style: _j(13.5, FontWeight.w800, _ink)),
            Text('${Money.rs(due)} · ${days}d · ${Reminders.label(tone, bangla: bangla)}',
                style: _j(11.5, FontWeight.w600, days > 60 ? _red : days > 30 ? _amber : _muted)),
          ]),
        ),
        GestureDetector(
          onTap: () async {
            final msg = Reminders.message(
                tone: tone, bangla: bangla, name: c['name'] as String, due: due, days: days, settings: widget.settings);
            await Contact.whatsapp(c['phone'] as String?, msg);
            await Books.logReminder('customer', id, c['name'] as String, 'WhatsApp');
            if (mounted) setState(() => sent.add(id));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: done ? const Color(0xFFE3F7EC) : const Color(0xFF25D366),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(done ? Icons.check_rounded : Icons.send_rounded, size: 16, color: done ? _green : Colors.white),
              const SizedBox(width: 5),
              Text(done ? 'Sent' : 'Send', style: _j(12.5, FontWeight.w800, done ? _green : Colors.white)),
            ]),
          ),
        ),
      ]),
    );
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
