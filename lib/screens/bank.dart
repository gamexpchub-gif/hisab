import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarms.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'ledgers.dart';

// =============================================================================
// Bank & Cards — every money account as a 3D liquid-glass card (bank, debit,
// credit, UPI, wallet, cash). Credit cards track limit, available credit and
// a bill due [bill_days] (default 40) after each spend, with a phone reminder.
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

TextStyle _j(double size, FontWeight w, Color c, {double? height, double? spacing}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
      letterSpacing: spacing,
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

/// Brand colours for common Indian banks and wallets.
class BankPreset {
  final String name, short;
  final Color a, b;
  const BankPreset(this.name, this.short, this.a, this.b);
}

const bankPresets = [
  BankPreset('State Bank of India', 'SBI', Color(0xFF1C9BE6), Color(0xFF0A3D8F)),
  BankPreset('HDFC Bank', 'HDFC', Color(0xFF2B4FB8), Color(0xFF0B1F5C)),
  BankPreset('ICICI Bank', 'ICICI', Color(0xFFF07A2A), Color(0xFF9C1F2E)),
  BankPreset('Axis Bank', 'Axis', Color(0xFFB0256B), Color(0xFF5E0B37)),
  BankPreset('Kotak Mahindra Bank', 'Kotak', Color(0xFFE9373F), Color(0xFF1E2A6E)),
  BankPreset('Punjab National Bank', 'PNB', Color(0xFFC2185B), Color(0xFFF9A825)),
  BankPreset('Bank of Baroda', 'BoB', Color(0xFFF26B21), Color(0xFF8A2A0A)),
  BankPreset('Canara Bank', 'Canara', Color(0xFF1E88E5), Color(0xFFF6B518)),
  BankPreset('Union Bank of India', 'Union', Color(0xFFD32F2F), Color(0xFF0D3C84)),
  BankPreset('IDFC FIRST Bank', 'IDFC', Color(0xFF9E1B32), Color(0xFF3B0A14)),
  BankPreset('Yes Bank', 'YES', Color(0xFF1565C0), Color(0xFF0B2F6B)),
  BankPreset('IndusInd Bank', 'IndusInd', Color(0xFF8D2E2E), Color(0xFF3E1212)),
  BankPreset('Paytm Payments Bank', 'Paytm', Color(0xFF00BAF2), Color(0xFF002E6E)),
  BankPreset('Airtel Payments Bank', 'Airtel', Color(0xFFE40000), Color(0xFF6B0000)),
];

BankPreset? presetFor(String? bank) {
  final b = (bank ?? '').toLowerCase();
  if (b.isEmpty) return null;
  for (final p in bankPresets) {
    if (b == p.name.toLowerCase() || b == p.short.toLowerCase() || b.contains(p.short.toLowerCase())) return p;
  }
  return null;
}

const _types = [
  ('savings', 'Savings', Icons.account_balance_rounded),
  ('current', 'Current', Icons.business_center_rounded),
  ('debit', 'Debit card', Icons.credit_card_rounded),
  ('credit', 'Credit card', Icons.credit_score_rounded),
  ('upi', 'UPI', Icons.qr_code_2_rounded),
  ('wallet', 'Wallet', Icons.account_balance_wallet_rounded),
  ('cash', 'Cash', Icons.payments_rounded),
];

String typeLabel(String? t) => _types.firstWhere((e) => e.$1 == t, orElse: () => _types.first).$2;

/// Colours of the card face.
List<Color> cardColors(Rec a) {
  final t = a['card_type'] as String?;
  if (t == 'cash') return const [Color(0xFF22C38E), Color(0xFF0B7A55)];
  final p = presetFor(a['bank_name'] as String?);
  if (p != null) return [p.a, p.b];
  final c = a['color'] == null ? null : Color(asInt(a['color']));
  if (c != null) {
    final h = HSLColor.fromColor(c);
    return [c, h.withLightness((h.lightness * .45).clamp(0, 1).toDouble()).toColor()];
  }
  return switch (t) {
    'credit' => const [Color(0xFF3A3F55), Color(0xFF0E1020)],
    'upi' => const [Color(0xFF7B4DFF), Color(0xFF3410B8)],
    'wallet' => const [Color(0xFF00B4D8), Color(0xFF024C8F)],
    _ => const [Color(0xFF6B35EE), Color(0xFF2F55E8)],
  };
}

String _last4(String? n) {
  final d = (n ?? '').replaceAll(RegExp(r'\s'), '');
  return d.length <= 4 ? d : d.substring(d.length - 4);
}

int _daysTo(String date) {
  final now = DateTime.now();
  return DateTime.parse(date).difference(DateTime(now.year, now.month, now.day)).inDays;
}

String dueIn(String date) {
  final d = _daysTo(date);
  return d < 0 ? 'Overdue ${-d}d' : d == 0 ? 'Due today' : d == 1 ? 'Due tomorrow' : 'Due in ${d}d';
}

class _Acc {
  final Rec r;
  final int balance; // money held, or for a credit card what you owe
  final CardStatus? card;
  _Acc(this.r, this.balance, this.card);
  bool get credit => card != null;
  int get id => asInt(r['id']);
}

// =============================================================================
class BankScreen extends StatefulWidget {
  const BankScreen({super.key});
  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  final pager = PageController(viewportFraction: .86);
  int page = 0;
  static final _scheduled = <int, String>{};

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  Future<(List<_Acc>, List<Rec>)> _load() async {
    final out = <_Acc>[];
    for (final a in await Books.moneyAccounts(withCards: true)) {
      final credit = a['kind'] == 'card';
      out.add(_Acc(a, await Books.moneyBalance(a), credit ? await Books.cardStatus(a) : null));
    }
    const order = ['credit', 'debit', 'savings', 'current', 'upi', 'wallet', 'cash'];
    int rank(_Acc a) {
      final i = order.indexOf('${a.r['card_type'] ?? (a.credit ? 'credit' : 'savings')}');
      return i < 0 ? 2 : i;
    }
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    final transfers = await Books.query(
        'SELECT t.*, f.name AS from_name, d.name AS to_name FROM transfers t JOIN accounts f ON f.id = t.from_id '
        'JOIN accounts d ON d.id = t.to_id ORDER BY t.id DESC LIMIT 15');
    _remind(out);
    return (out, transfers);
  }

  /// Keeps one phone reminder per credit card for its next bill.
  void _remind(List<_Acc> accs) {
    for (final a in accs.where((a) => a.credit)) {
      final next = a.card!.next;
      final key = next == null ? '' : '${next.key}:${next.value}';
      if (_scheduled[a.id] == key) continue;
      _scheduled[a.id] = key;
      final dueId = 1000000 + a.id;
      if (next == null) {
        Alarms.cancelDue(dueId);
      } else {
        Alarms.scheduleDue(
          dueId: dueId,
          dueDate: DateTime.parse(next.key),
          title: '${a.r['name']} bill ${Money.rs(next.value)}',
          body: 'Deposit ${Money.rs(next.value)} to ${a.r['name']} by ${prettyDate(next.key)} to avoid interest.',
        );
      }
    }
  }

  void _add([Rec? edit]) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AccountSheet(edit: edit),
      );

  void _transfer({int? from, int? to, int? amount, String? title}) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => TransferSheet(from: from, to: to, amount: amount, title: title),
      );

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<(List<_Acc>, List<Rec>)>(
          load: _load,
          builder: (context, d) {
            final accs = d.$1;
            if (page >= accs.length && accs.isNotEmpty) page = accs.length - 1;
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    if (canPop) ...[
                      _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Bank & Cards', style: _j(22, FontWeight.w800, _navy)),
                        Text('Accounts · cards · bills', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                      ]),
                    ),
                    _round(Icons.swap_horiz_rounded, () => _transfer()),
                    const SizedBox(width: 8),
                    _pill('Add', Icons.add_card_rounded, () => _add()),
                  ]),
                ),
                const SizedBox(height: 14),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _hero(accs)),
                const SizedBox(height: 18),
                if (accs.isNotEmpty) ...[
                  SizedBox(
                    height: 210,
                    child: PageView.builder(
                      controller: pager,
                      itemCount: accs.length,
                      onPageChanged: (i) {
                        HapticFeedback.selectionClick();
                        setState(() => page = i);
                      },
                      itemBuilder: (context, i) => AnimatedBuilder(
                        animation: pager,
                        builder: (context, child) {
                          var delta = (i - page).toDouble();
                          if (pager.hasClients && pager.position.haveDimensions) delta = i - (pager.page ?? 0);
                          delta = delta.clamp(-1.0, 1.0).toDouble();
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, .0012)
                              ..rotateY(-delta * .45),
                            child: Transform.scale(scale: 1 - delta.abs() * .08, child: child),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: GestureDetector(
                            onTap: () => open(context, AccountLedgerScreen(accountId: accs[i].id)),
                            onLongPress: () => _add(accs[i].r),
                            child: BankCard(a: accs[i].r, balance: accs[i].balance, card: accs[i].card),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < accs.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == page ? 20 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: i == page ? _purple : const Color(0xFFD5D8EA),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _detail(accs[page], accs)),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ..._bills(accs),
                    const SizedBox(height: 14),
                    _allAccounts(accs),
                    const SizedBox(height: 14),
                    _transfers(d.$2),
                  ]),
                ),
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

  Widget _pill(String label, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
            boxShadow: const [BoxShadow(color: Color(0x664A17C9), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -4)],
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: _j(13, FontWeight.w800, Colors.white)),
          ]),
        ),
      );

  // ---------------------------------------------------------------- hero
  Widget _hero(List<_Acc> accs) {
    final bank = accs.where((a) => !a.credit && a.r['kind'] == 'bank').fold<int>(0, (s, a) => s + a.balance);
    final cash = accs.where((a) => !a.credit && a.r['kind'] != 'bank').fold<int>(0, (s, a) => s + a.balance);
    final owed = accs.where((a) => a.credit).fold<int>(0, (s, a) => s + a.balance);
    final limit = accs.where((a) => a.credit).fold<int>(0, (s, a) => s + a.card!.limit);
    final net = bank + cash - owed;
    Widget cell(String l, int v, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: _j(11, FontWeight.w600, const Color(0xCCFFFFFF))),
            const SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(v), style: _j(15.5, FontWeight.w800, c))),
          ]),
        );
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
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Net money', style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Text('${accs.length} accounts', style: _j(11, FontWeight.w700, Colors.white)),
              ),
            ]),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(net), style: _j(30, FontWeight.w800, Colors.white))),
            const SizedBox(height: 12),
            Row(children: [
              cell('In bank', bank, Colors.white),
              Container(width: 1, height: 34, color: const Color(0x40FFFFFF), margin: const EdgeInsets.symmetric(horizontal: 10)),
              cell('Cash & UPI', cash, Colors.white),
              Container(width: 1, height: 34, color: const Color(0x40FFFFFF), margin: const EdgeInsets.symmetric(horizontal: 10)),
              cell('Card dues', owed, owed > 0 ? const Color(0xFFFFC2C2) : const Color(0xFF9CF5C4)),
            ]),
            if (limit > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (owed / limit).clamp(0, 1).toDouble(),
                  minHeight: 7,
                  backgroundColor: const Color(0x33FFFFFF),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD66B)),
                ),
              ),
              const SizedBox(height: 5),
              Text('Credit used ${Money.compact(owed)} of ${Money.compact(limit)} · available ${Money.compact(limit - owed)}',
                  style: _j(11, FontWeight.w600, const Color(0xDDFFFFFF))),
            ],
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- detail of the selected card
  Widget _detail(_Acc a, List<_Acc> all) {
    final r = a.r;
    final banks = all.where((x) => !x.credit && x.id != a.id).toList();
    final payFrom = banks.isEmpty ? null : (banks.firstWhere((x) => x.r['kind'] == 'bank', orElse: () => banks.first)).id;
    Widget action(IconData i, String l, Color c, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              height: 64,
              decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(18)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(i, color: c, size: 22),
                const SizedBox(height: 4),
                Text(l, style: _j(11.5, FontWeight.w700, c)),
              ]),
            ),
          ),
        );
    final rows = <Widget>[];
    if (a.credit) {
      final c = a.card!;
      final next = c.next;
      final days = next == null ? 999 : _daysTo(next.key);
      final tone = days < 0 ? _red : days <= 5 ? _amber : _green;
      rows.addAll([
        Row(children: [
          Expanded(child: _stat('Outstanding', Money.rs(c.outstanding), c.outstanding > 0 ? _red : _green)),
          Expanded(child: _stat('Available', c.limit > 0 ? Money.rs(c.available) : '—', _ink)),
          Expanded(child: _stat('Limit', c.limit > 0 ? Money.rs(c.limit) : 'Not set', _muted)),
        ]),
        if (c.limit > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.used,
              minHeight: 8,
              backgroundColor: const Color(0xFFEDEFF8),
              valueColor: AlwaysStoppedAnimation(c.used > .8 ? _red : c.used > .5 ? _amber : _purple),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(c.used * 100).round()}% of limit used', style: _j(11, FontWeight.w600, _muted)),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: next == null ? const Color(0xFFEAF8F1) : tone.withAlpha(0x14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (next == null ? _green : tone).withAlpha(0x40)),
          ),
          child: Row(children: [
            Icon(next == null ? Icons.verified_rounded : Icons.alarm_rounded, color: next == null ? _green : tone),
            const SizedBox(width: 10),
            Expanded(
              child: next == null
                  ? Text('No bill due — card is clear', style: _j(13, FontWeight.w700, _green))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${dueIn(next.key)} · ${Money.rs(next.value)}', style: _j(13.5, FontWeight.w800, tone)),
                      Text('Deposit by ${prettyDate(next.key)} · ${c.billDays}-day bill cycle · phone reminder on',
                          style: _j(11, FontWeight.w600, _muted)),
                    ]),
            ),
          ]),
        ),
        if (c.dues.length > 1) ...[
          const SizedBox(height: 8),
          for (final e in c.dues.skip(1).take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, size: 15, color: _muted),
                const SizedBox(width: 6),
                Expanded(child: Text('${prettyDate(e.key)} · ${dueIn(e.key)}', style: _j(12, FontWeight.w600, _ink))),
                Text(Money.rs(e.value), style: _j(12, FontWeight.w800, _ink)),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          action(Icons.payments_rounded, 'Pay bill', _green, () {
            _transfer(from: payFrom, to: a.id, amount: next?.value ?? c.outstanding, title: 'Pay card bill');
          }),
          const SizedBox(width: 8),
          action(Icons.atm_rounded, 'Withdraw', _amber, () {
            final cash = all.where((x) => x.r['kind'] == 'cash').map((x) => x.id).firstOrNull;
            _transfer(from: a.id, to: cash, title: 'Cash from card');
          }),
          const SizedBox(width: 8),
          action(Icons.receipt_long_rounded, 'Statement', _purple, () => open(context, AccountLedgerScreen(accountId: a.id))),
          const SizedBox(width: 8),
          action(Icons.edit_rounded, 'Edit', _navy, () => _add(r)),
        ]),
      ]);
    } else {
      rows.addAll([
        Row(children: [
          Expanded(child: _stat('Balance', Money.rs(a.balance), a.balance < 0 ? _red : _ink)),
          Expanded(child: _stat('Type', typeLabel(r['card_type'] as String?), _muted)),
          if ((r['ifsc'] ?? '').toString().isNotEmpty) Expanded(child: _stat('IFSC', '${r['ifsc']}', _muted)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          action(Icons.south_west_rounded, 'Deposit', _green, () {
            final cash = all.where((x) => x.r['kind'] == 'cash' && x.id != a.id).map((x) => x.id).firstOrNull;
            _transfer(from: cash, to: a.id, title: 'Deposit');
          }),
          const SizedBox(width: 8),
          action(Icons.north_east_rounded, 'Withdraw', _amber, () {
            final cash = all.where((x) => x.r['kind'] == 'cash' && x.id != a.id).map((x) => x.id).firstOrNull;
            _transfer(from: a.id, to: cash, title: 'Withdraw');
          }),
          const SizedBox(width: 8),
          action(Icons.receipt_long_rounded, 'Passbook', _purple, () => open(context, AccountLedgerScreen(accountId: a.id))),
          const SizedBox(width: 8),
          action(Icons.edit_rounded, 'Edit', _navy, () => _add(r)),
        ]),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(r: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: cardColors(r))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(15, FontWeight.w800, _ink))),
          Text(typeLabel(r['card_type'] as String?), style: _j(11.5, FontWeight.w700, _muted)),
        ]),
        const SizedBox(height: 12),
        ...rows,
      ]),
    );
  }

  Widget _stat(String l, String v, Color c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: _j(11, FontWeight.w600, _muted)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _j(15, FontWeight.w800, c))),
      ]);

  // ---------------------------------------------------------------- upcoming card bills
  List<Widget> _bills(List<_Acc> accs) {
    final bills = [
      for (final a in accs.where((a) => a.credit && a.card!.next != null)) (a, a.card!.next!),
    ]..sort((x, y) => x.$2.key.compareTo(y.$2.key));
    if (bills.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(r: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.notifications_active_rounded, color: _purple, size: 20),
            const SizedBox(width: 8),
            Text('Upcoming card bills', style: _j(15, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 8),
          for (final b in bills)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 44, height: 30, child: _MiniCard(a: b.$1.r)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.$1.r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w700, _ink)),
                    Text('${prettyDate(b.$2.key)} · ${dueIn(b.$2.key)}',
                        style: _j(11, FontWeight.w700, _daysTo(b.$2.key) < 0 ? _red : _daysTo(b.$2.key) <= 5 ? _amber : _muted)),
                  ]),
                ),
                Text(Money.rs(b.$2.value), style: _j(13.5, FontWeight.w800, _ink)),
              ]),
            ),
        ]),
      ),
    ];
  }

  Widget _allAccounts(List<_Acc> accs) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: _card(r: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('All accounts', style: _j(15, FontWeight.w800, _ink)),
          const SizedBox(height: 6),
          for (var i = 0; i < accs.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                pager.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 44, height: 30, child: _MiniCard(a: accs[i].r)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${accs[i].r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w700, _ink)),
                      Text(
                        [
                          typeLabel(accs[i].r['card_type'] as String?),
                          if (_last4(accs[i].r['acc_no'] as String?).isNotEmpty) '•• ${_last4(accs[i].r['acc_no'] as String?)}',
                        ].join(' · '),
                        style: _j(11, FontWeight.w600, _muted),
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(Money.rs(accs[i].balance),
                        style: _j(13.5, FontWeight.w800, accs[i].credit ? (accs[i].balance > 0 ? _red : _green) : _ink)),
                    if (accs[i].credit) Text('owed', style: _j(10, FontWeight.w600, _muted)),
                  ]),
                ]),
              ),
            ),
        ]),
      );

  Widget _transfers(List<Rec> rows) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: _card(r: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Recent transfers', style: _j(15, FontWeight.w800, _ink)),
          if (rows.isEmpty) const EmptyState('No transfers yet'),
          for (final t in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFF0ECFF), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.swap_horiz_rounded, color: _purple, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['from_name']} → ${t['to_name']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w700, _ink)),
                    Text('${t['number']} · ${prettyDate(t['date'] as String)}', style: _j(11, FontWeight.w600, _muted)),
                  ]),
                ),
                Text(Money.rs(asInt(t['amount'])), style: _j(13.5, FontWeight.w800, _ink)),
              ]),
            ),
        ]),
      );
}

// =============================================================================
// The card face
// =============================================================================
class BankCard extends StatelessWidget {
  final Rec a;
  final int balance;
  final CardStatus? card;
  const BankCard({super.key, required this.a, this.balance = 0, this.card});

  @override
  Widget build(BuildContext context) {
    final colors = cardColors(a);
    final type = (a['card_type'] as String?) ?? 'savings';
    final isCard = type == 'credit' || type == 'debit';
    final bank = (a['bank_name'] as String?)?.trim();
    final last4 = _last4(a['acc_no'] as String?);
    final holder = ((a['holder'] as String?) ?? '').trim();
    final number = switch (type) {
      'cash' => 'CASH IN HAND',
      'upi' => (a['acc_no'] as String?)?.isNotEmpty == true ? '${a['acc_no']}' : 'UPI',
      _ when isCard => '••••  ••••  ••••  ${last4.isEmpty ? '••••' : last4}',
      _ => 'A/C  ••••  ${last4.isEmpty ? '••••' : last4}',
    };
    return LayoutBuilder(builder: (context, c) {
      final s = (c.maxWidth / 320).clamp(.7, 1.3).toDouble();
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22 * s),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          boxShadow: [
            BoxShadow(color: colors.last.withAlpha(0x66), blurRadius: 22, offset: const Offset(0, 12), spreadRadius: -6),
            const BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22 * s),
          child: Stack(children: [
            // liquid glass: soft orbs and a diagonal gloss
            Positioned(
              right: -40 * s,
              top: -60 * s,
              child: Container(
                width: 200 * s,
                height: 200 * s,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
              ),
            ),
            Positioned(
              left: -50 * s,
              bottom: -90 * s,
              child: Container(
                width: 220 * s,
                height: 220 * s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(0x12)),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22 * s),
                  border: Border.all(color: const Color(0x55FFFFFF), width: 1.2),
                  gradient: const LinearGradient(
                    begin: Alignment(-1, -1),
                    end: Alignment(1, 1),
                    colors: [Color(0x38FFFFFF), Color(0x08FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF)],
                    stops: [0, .38, .62, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 14 * s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      (bank == null || bank.isEmpty) ? '${a['name']}' : (presetFor(bank)?.short ?? bank),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _j(17 * s, FontWeight.w800, Colors.white, spacing: .3),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 9 * s, vertical: 4 * s),
                    decoration: BoxDecoration(
                      color: const Color(0x2EFFFFFF),
                      borderRadius: BorderRadius.circular(10 * s),
                      border: Border.all(color: const Color(0x40FFFFFF)),
                    ),
                    child: Text(typeLabel(type).toUpperCase(), style: _j(9.5 * s, FontWeight.w800, Colors.white, spacing: .8)),
                  ),
                ]),
                SizedBox(height: 2 * s),
                Text(
                  bank == null || bank.isEmpty ? typeLabel(type) : '${a['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _j(11 * s, FontWeight.w600, const Color(0xCCFFFFFF)),
                ),
                const Spacer(),
                Row(children: [
                  if (type == 'cash')
                    Icon(Icons.payments_rounded, color: Colors.white, size: 30 * s)
                  else if (type == 'upi')
                    Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 30 * s)
                  else if (type == 'wallet')
                    Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30 * s)
                  else
                    _Chip(s: s),
                  SizedBox(width: 10 * s),
                  if (isCard) Icon(Icons.contactless_rounded, color: const Color(0xDDFFFFFF), size: 24 * s),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(card != null ? 'OUTSTANDING' : 'BALANCE', style: _j(8.5 * s, FontWeight.w700, const Color(0xBBFFFFFF), spacing: 1)),
                    Text(Money.rs(balance), style: _j(16 * s, FontWeight.w800, Colors.white)),
                  ]),
                ]),
                SizedBox(height: 10 * s),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(number, style: _j(16 * s, FontWeight.w700, Colors.white, spacing: 1.6)),
                ),
                SizedBox(height: 8 * s),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        card != null ? (card!.next == null ? 'NO BILL DUE' : dueIn(card!.next!.key).toUpperCase()) : 'HOLDER',
                        style: _j(8 * s, FontWeight.w700, card?.next != null && _daysTo(card!.next!.key) <= 5 ? const Color(0xFFFFD66B) : const Color(0xBBFFFFFF), spacing: 1),
                      ),
                      Text(
                        holder.isEmpty ? 'GAMEX PC HUB' : holder.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _j(11.5 * s, FontWeight.w700, Colors.white, spacing: .8),
                      ),
                    ]),
                  ),
                  _Network(network: a['network'] as String?, s: s),
                ]),
              ]),
            ),
          ]),
        ),
      );
    });
  }
}

class _Chip extends StatelessWidget {
  final double s;
  const _Chip({required this.s});
  @override
  Widget build(BuildContext context) => Container(
        width: 40 * s,
        height: 30 * s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6 * s),
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE9A8), Color(0xFFD9A440), Color(0xFFF6D77E)]),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: CustomPaint(painter: _ChipLines()),
      );
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x66855A12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(0, h * .35), Offset(w, h * .35), p);
    canvas.drawLine(Offset(0, h * .65), Offset(w, h * .65), p);
    canvas.drawLine(Offset(w * .38, 0), Offset(w * .38, h), p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .38, h * .35, w * .3, h * .3), const Radius.circular(2)), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Network extends StatelessWidget {
  final String? network;
  final double s;
  const _Network({this.network, required this.s});
  @override
  Widget build(BuildContext context) {
    switch (network) {
      case 'mastercard':
        return SizedBox(
          width: 44 * s,
          height: 28 * s,
          child: Stack(children: [
            Positioned(left: 0, child: _dot(const Color(0xFFEB001B))),
            Positioned(right: 0, child: _dot(const Color(0xDDF79E1B))),
          ]),
        );
      case 'visa':
        return Text('VISA', style: _j(22 * s, FontWeight.w900, Colors.white, spacing: 1).copyWith(fontStyle: FontStyle.italic));
      case 'rupay':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Text('RuPay', style: _j(16 * s, FontWeight.w900, Colors.white).copyWith(fontStyle: FontStyle.italic)),
          Icon(Icons.play_arrow_rounded, color: const Color(0xFFF7941D), size: 16 * s),
        ]);
      case 'amex':
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
          decoration: BoxDecoration(border: Border.all(color: Colors.white), borderRadius: BorderRadius.circular(4)),
          child: Text('AMEX', style: _j(11 * s, FontWeight.w900, Colors.white, spacing: 1)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _dot(Color c) => Container(width: 28 * s, height: 28 * s, decoration: BoxDecoration(shape: BoxShape.circle, color: c));
}

class _MiniCard extends StatelessWidget {
  final Rec a;
  const _MiniCard({required this.a});
  @override
  Widget build(BuildContext context) {
    final type = a['card_type'] as String?;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cardColors(a)),
        boxShadow: const [BoxShadow(color: Color(0x332A2F7A), blurRadius: 6, offset: Offset(0, 3), spreadRadius: -2)],
      ),
      alignment: Alignment.center,
      child: Icon(_types.firstWhere((e) => e.$1 == type, orElse: () => _types.first).$3, color: Colors.white, size: 16),
    );
  }
}

// =============================================================================
// Add / edit account sheet with a live card preview
// =============================================================================
class AccountSheet extends StatefulWidget {
  final Rec? edit;
  const AccountSheet({super.key, this.edit});
  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  late final e = widget.edit;
  late String type = (e?['card_type'] as String?) ?? 'savings';
  late String? network = e?['network'] as String?;
  late final bank = TextEditingController(text: (e?['bank_name'] as String?) ?? '');
  late final name = TextEditingController(text: (e?['name'] as String?) ?? '');
  late final number = TextEditingController(text: (e?['acc_no'] as String?) ?? '');
  late final holder = TextEditingController(text: (e?['holder'] as String?) ?? '');
  late final ifsc = TextEditingController(text: (e?['ifsc'] as String?) ?? '');
  late final limit = TextEditingController(text: e == null || asInt(e!['credit_limit']) == 0 ? '' : Money.edit(asInt(e!['credit_limit'])));
  late final days = TextEditingController(text: e == null ? '40' : '${asInt(e!['bill_days']) <= 0 ? 40 : asInt(e!['bill_days'])}');
  final opening = TextEditingController();
  bool busy = false;

  bool get isCard => type == 'credit' || type == 'debit';
  bool get isBank => type == 'savings' || type == 'current' || isCard;
  bool get lockedType => e != null; // the ledger side (asset / liability) can't change later

  @override
  void dispose() {
    for (final c in [bank, name, number, holder, ifsc, limit, days, opening]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _autoName {
    final b = presetFor(bank.text)?.short ?? bank.text.trim();
    final l4 = _last4(number.text);
    return [if (b.isNotEmpty) b, typeLabel(type), if (l4.isNotEmpty && isCard) l4].join(' ');
  }

  Rec get _preview => {
        'name': name.text.trim().isEmpty ? _autoName : name.text.trim(),
        'bank_name': isBank ? bank.text.trim() : null,
        'acc_no': number.text.trim(),
        'holder': holder.text.trim(),
        'card_type': type,
        'network': isCard ? network : null,
      };

  Future<void> _save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = <String, Object?>{
        ..._preview,
        'ifsc': isBank && !isCard ? ifsc.text.trim().toUpperCase() : null,
        'credit_limit': type == 'credit' ? Money.parse(limit.text) : 0,
        'bill_days': type == 'credit' ? (int.tryParse(days.text.trim()) ?? 40) : 40,
        'color': presetFor(bank.text)?.a.toARGB32(),
      };
      await Books.saveMoneyAccount(data, id: e == null ? null : asInt(e!['id']), opening: e == null ? Money.parse(opening.text) : 0);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, e == null ? 'Account added' : 'Account updated');
    } catch (err) {
      setState(() => busy = false);
      if (mounted) toast(context, '$err', error: true);
    }
  }

  Widget _chip(String label, bool on, VoidCallback? onTap, {Widget? lead}) => GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
            color: on ? null : (onTap == null ? const Color(0xFFF2F3F8) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: on ? null : Border.all(color: _line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (lead != null) ...[lead, const SizedBox(width: 6)],
            Text(label, style: _j(12, FontWeight.w700, on ? Colors.white : (onTap == null ? _muted : _ink))),
          ]),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(t, style: _j(12.5, FontWeight.w800, const Color(0xFF323B60))),
      );

  @override
  Widget build(BuildContext context) {
    final credit = type == 'credit';
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
      decoration: const BoxDecoration(color: _bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 12),
          Text(e == null ? 'Add account or card' : 'Edit account', style: _j(20, FontWeight.w800, _navy)),
          Text('Bank account, debit / credit card, UPI, wallet or cash', style: _j(12, FontWeight.w600, _muted)),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: AspectRatio(aspectRatio: 1.62, child: BankCard(a: _preview)),
            ),
          ),
          const SizedBox(height: 16),
          _label('Type'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _types)
              _chip(
                t.$2,
                type == t.$1,
                lockedType && ((t.$1 == 'credit') != (type == 'credit')) ? null : () => setState(() => type = t.$1),
                lead: Icon(t.$3, size: 15, color: type == t.$1 ? Colors.white : _purple),
              ),
          ]),
          if (isBank) ...[
            const SizedBox(height: 14),
            _label('Bank'),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in bankPresets) ...[
                  _chip(
                    p.short,
                    presetFor(bank.text) == p,
                    () => setState(() => bank.text = p.name),
                    lead: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [p.a, p.b])),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            field(bank, 'Bank name', onChanged: (_) => setState(() {})),
          ],
          if (type != 'cash') ...[
            const SizedBox(height: 4),
            field(
              number,
              switch (type) {
                'upi' => 'UPI ID (e.g. gamex@okicici)',
                'wallet' => 'Wallet number / mobile',
                _ when isCard => 'Card number (only last 4 shown)',
                _ => 'Account number',
              },
              number: isBank,
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (isBank) field(holder, isCard ? 'Name on card' : 'Account holder', onChanged: (_) => setState(() {})),
          if (isBank && !isCard) field(ifsc, 'IFSC code'),
          if (isCard) ...[
            _label('Network'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in [('visa', 'Visa'), ('mastercard', 'Mastercard'), ('rupay', 'RuPay'), ('amex', 'Amex')])
                _chip(n.$2, network == n.$1, () => setState(() => network = network == n.$1 ? null : n.$1)),
            ]),
            const SizedBox(height: 12),
          ],
          if (credit) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: const Color(0xFFF0ECFF), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _purple, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Every spend on this card falls due after the bill days below. The phone rings a reminder the day before and on the due date.',
                    style: _j(11.5, FontWeight.w600, const Color(0xFF3B2C8F)),
                  ),
                ),
              ]),
            ),
            Row(children: [
              Expanded(child: field(limit, 'Credit limit ₹', number: true)),
              const SizedBox(width: 10),
              Expanded(child: field(days, 'Bill days', number: true)),
            ]),
          ],
          field(name, 'Display name (optional) — ${_autoName.isEmpty ? 'auto' : _autoName}', onChanged: (_) => setState(() {})),
          if (e == null) field(opening, credit ? 'Already owed on card ₹ (optional)' : 'Opening balance ₹ (optional)', number: true),
          const SizedBox(height: 6),
          GradientButton(label: busy ? 'Saving…' : (e == null ? 'Add account' : 'Save changes'), expand: true, fontSize: 16, onTap: _save),
        ]),
      ),
    );
  }
}

// =============================================================================
class TransferSheet extends StatefulWidget {
  final int? from, to, amount;
  final String? title;
  const TransferSheet({super.key, this.from, this.to, this.amount, this.title});
  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  late final amount = TextEditingController(text: (widget.amount ?? 0) > 0 ? Money.edit(widget.amount!) : '');
  final note = TextEditingController();
  List<Rec> accounts = [];
  int? from, to;
  String date = ymd(DateTime.now());

  @override
  void initState() {
    super.initState();
    Books.moneyAccounts(withCards: true).then((a) {
      if (!mounted) return;
      setState(() {
        accounts = a;
        from = widget.from ?? (a.isNotEmpty ? asInt(a[0]['id']) : null);
        to = widget.to ?? (a.length > 1 ? asInt(a.firstWhere((r) => asInt(r['id']) != from, orElse: () => a[1])['id']) : null);
      });
    });
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title ?? 'Transfer money', style: _j(19, FontWeight.w800, _navy)),
        Text('Cash deposit, withdrawal, UPI settlement or card bill payment', style: _j(12, FontWeight.w600, _muted)),
        const SizedBox(height: 14),
        RowPicker(label: 'From', rows: accounts, value: from, onChanged: (v) => setState(() => from = v)),
        RowPicker(label: 'To', rows: accounts, value: to, onChanged: (v) => setState(() => to = v)),
        field(amount, 'Amount ₹', number: true),
        DateField(value: date, onChanged: (v) => setState(() => date = v)),
        field(note, 'Note'),
        GradientButton(
          label: 'Save transfer',
          expand: true,
          fontSize: 16,
          onTap: () async {
            try {
              await Books.createTransfer(
                  fromId: from ?? 0, toId: to ?? 0, amount: Money.parse(amount.text), date: date, note: note.text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              toast(context, 'Transfer recorded');
            } catch (err) {
              toast(context, '$err', error: true);
            }
          },
        ),
      ]),
    );
  }
}
