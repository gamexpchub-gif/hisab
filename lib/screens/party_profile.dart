import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'ledgers.dart';
import 'lend_sheet.dart';
import 'parties.dart';
import 'products.dart';
import 'purchase_form.dart';
import 'sale_form.dart';
import 'sales.dart';

// =============================================================================
// Customer / supplier profile: liquid-glass profile card, balance & credit
// usage, quick actions (call · WhatsApp · remind · statement), due ageing,
// smart WhatsApp reminder (EN / বাংলা, tone picked from the age of dues),
// lifetime stats and the full transaction timeline.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
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

class _ProfileData {
  final Rec party;
  final int balance;
  final List<Rec> rows;
  final Ageing ageing;
  final PartyStats stats;
  final Map<String, String> settings;
  final CreditSplit split;
  final List<Rec> dues, bought;
  _ProfileData(this.party, this.balance, this.rows, this.ageing, this.stats, this.settings, this.split, this.dues, this.bought);
}

class PartyView extends StatefulWidget {
  final String type; // customer | supplier
  final int id;
  const PartyView({super.key, required this.type, required this.id});
  @override
  State<PartyView> createState() => _PartyViewState();
}

class _PartyViewState extends State<PartyView> {
  String filter = 'all'; // all | bills | payments
  bool bangla = false;
  ReminderTone? tone;

  bool get isC => widget.type == 'customer';

  Future<_ProfileData?> _load() async {
    final r = await Books.query('SELECT * FROM ${isC ? 'customers' : 'suppliers'} WHERE id = ?', [widget.id]);
    if (r.isEmpty) return null;
    final ageing = (await Books.ageing(widget.type))[widget.id] ?? Ageing([0, 0, 0, 0], 0, null);
    return _ProfileData(
      r.first,
      await Books.partyBalance(widget.type, widget.id),
      await Books.ledger(partyType: widget.type, partyId: widget.id),
      ageing,
      await Books.partyStats(widget.type, widget.id),
      await Books.settings(),
      await Books.creditSplit(widget.type, widget.id),
      await Books.dues(partyType: widget.type, partyId: widget.id, openOnly: false),
      isC ? await Books.boughtBy(widget.id) : const [],
    );
  }

  List<Color> get _gradient => isC
      ? const [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)]
      : const [Color(0xFFFF8A3D), Color(0xFFF0601A), Color(0xFFD9480F)];

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _bg,
      body: Live<_ProfileData?>(
        load: _load,
        builder: (context, d) {
          if (d == null) return const SafeArea(child: EmptyState('Not found'));
          return Stack(children: [
            SafeArea(
              bottom: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 110 + safe),
                children: [
                  _topBar(d),
                  const SizedBox(height: 12),
                  _profileCard(d),
                  const SizedBox(height: 14),
                  _creditCard(d),
                  const SizedBox(height: 14),
                  _statsGrid(d),
                  const SizedBox(height: 14),
                  _duesCard(d),
                  if (d.balance > 0) ...[const SizedBox(height: 14), _ageingCard(d)],
                  if (isC && d.balance > 0) ...[const SizedBox(height: 14), _reminderCard(d)],
                  const SizedBox(height: 14),
                  if (isC && d.bought.isNotEmpty) ...[_boughtCard(d), const SizedBox(height: 14)],
                  _detailsCard(d),
                  const SizedBox(height: 14),
                  _timeline(d),
                ],
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(d, safe)),
          ]);
        },
      ),
    );
  }

  // ---------------------------------------------------------------- top bar
  Widget _topBar(_ProfileData d) => Row(children: [
        _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isC ? 'Customer profile' : 'Supplier profile', style: _j(19, FontWeight.w800, _navy)),
            Text('Ledger · payments · reminders', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
          ]),
        ),
        _round(Icons.edit_rounded, () => open(context, PartyForm(type: widget.type, party: d.party))),
      ]);

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

  // ---------------------------------------------------------------- liquid profile card
  Widget _profileCard(_ProfileData d) {
    final p = d.party;
    final name = p['name'] as String;
    final phone = (p['phone'] as String?) ?? '';
    final limit = asInt(p['credit_limit']);
    final used = limit > 0 ? (d.balance / limit).clamp(0.0, 1.0).toDouble() : 0.0;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: _gradient.last.withAlpha(0x66), blurRadius: 30, offset: const Offset(0, 14), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _gradient),
              ),
            ),
          ),
          Positioned(right: -50, top: -60, child: _blob(200, 0x33)),
          Positioned(left: -40, bottom: -70, child: _blob(180, 0x22)),
          Positioned(right: 40, bottom: 30, child: _blob(80, 0x1F)),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => _changePhoto(d),
                  child: Stack(children: [
                    _glass(
                      radius: 26,
                      child: SizedBox(
                        width: 74,
                        height: 74,
                        child: storedImage(
                          p['photo'] as String?,
                          fallback: Center(child: Text(initials.isEmpty ? '?' : initials, style: _j(26, FontWeight.w800, Colors.white))),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(Icons.photo_camera_rounded, size: 12, color: _gradient.first),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(20, FontWeight.w800, Colors.white, height: 1.15)),
                    const SizedBox(height: 4),
                    if (phone.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.phone_rounded, size: 13, color: Color(0xCCFFFFFF)),
                        const SizedBox(width: 4),
                        Text(phone, style: _j(12.5, FontWeight.w600, const Color(0xE6FFFFFF))),
                      ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _chip(isC ? 'Customer' : 'Supplier', Icons.verified_rounded),
                      if (d.stats.firstDoc != null) _chip('Since ${monthName(DateTime.parse(d.stats.firstDoc!).month)} ${DateTime.parse(d.stats.firstDoc!).year}', Icons.history_rounded),
                      if ((p['gstin'] as String? ?? '').isNotEmpty) _chip('GST', Icons.receipt_rounded),
                      if ((p['aadhaar'] as String? ?? '').isNotEmpty || (p['aadhaar_img'] as String? ?? '').isNotEmpty)
                        _chip('Aadhaar', Icons.fingerprint_rounded),
                      if ((p['pan'] as String? ?? '').isNotEmpty || (p['pan_img'] as String? ?? '').isNotEmpty) _chip('PAN', Icons.credit_card_rounded),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              _glass(
                radius: 20,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      isC
                          ? (d.balance > 0 ? 'Outstanding — you will receive' : d.balance < 0 ? 'Advance paid by customer' : 'All settled')
                          : (d.balance > 0 ? 'Payable — you will pay' : d.balance < 0 ? 'Advance paid to supplier' : 'All settled'),
                      style: _j(12, FontWeight.w600, const Color(0xD9FFFFFF)),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(Money.rs(d.balance.abs()),
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            fontVariations: [FontVariation('wght', 800)],
                            color: Colors.white,
                            letterSpacing: -0.5,
                          )),
                    ),
                    if (limit > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: used,
                          minHeight: 7,
                          backgroundColor: const Color(0x33FFFFFF),
                          valueColor: AlwaysStoppedAnimation(used > .9 ? const Color(0xFFFF8A8A) : Colors.white),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text('Credit used ${(used * 100).round()}% of ${Money.rs(limit)}',
                          style: _j(11, FontWeight.w600, const Color(0xD9FFFFFF))),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                _action(Icons.call_rounded, 'Call', () async {
                  if (!await Contact.call(phone) && mounted) toast(context, 'No phone number saved', error: true);
                }),
                _action(Icons.chat_rounded, 'WhatsApp', () async {
                  await Contact.whatsapp(phone, isC ? 'Hi ${p['name']},' : 'Hello ${p['name']},');
                }),
                if (isC) _action(Icons.notifications_active_rounded, 'Remind', () => _sendReminder(d)),
                _action(Icons.description_rounded, 'Statement', () => _sendStatement(d)),
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

  Widget _glass({required Widget child, double radius = 18}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x40FFFFFF), Color(0x1AFFFFFF)],
              ),
              border: Border.all(color: const Color(0x59FFFFFF), width: 1.2),
            ),
            child: child,
          ),
        ),
      );

  Widget _chip(String l, IconData i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(l, style: _j(10, FontWeight.w700, Colors.white)),
        ]),
      );

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _glass(
              radius: 18,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(height: 4),
                  Text(label, style: _j(11, FontWeight.w700, Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      );

  // ---------------------------------------------------------------- photo
  Future<void> _changePhoto(_ProfileData d) async {
    final r = await pickPhoto(context, folder: 'people', allowRemove: (d.party['photo'] as String? ?? '').isNotEmpty);
    if (r == null) return;
    await Books.saveParty(widget.type, {'name': d.party['name'], 'photo': r.isEmpty ? null : r}, id: widget.id);
  }

  // ---------------------------------------------------------------- credit breakdown
  Widget _creditCard(_ProfileData d) {
    final s = d.split;
    final got = s.payments + s.cashGot;
    Widget tile(String l, String sub, int v, Color c, IconData i) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [c.withAlpha(0x1A), c.withAlpha(0x08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: c.withAlpha(0x33)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(i, size: 16, color: c),
                const SizedBox(width: 5),
                Flexible(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w800, c))),
              ]),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(v), style: _j(16, FontWeight.w800, _ink))),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10, FontWeight.w500, _muted)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.account_balance_wallet_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(isC ? 'Udhar breakdown' : 'Account breakdown', style: _j(15, FontWeight.w800, _ink))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          tile(isC ? 'Goods udhar' : 'Goods taken', isC ? 'Unpaid part of bills' : 'Unpaid part of bills', s.goods, const Color(0xFF7B3FF2), Icons.shopping_bag_rounded),
          const SizedBox(width: 10),
          tile(isC ? 'Cash udhar' : 'Cash given', isC ? 'Cash you gave' : 'Advance you gave', s.cashGave, _red, Icons.north_east_rounded),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(isC ? 'Received' : 'Paid / got', isC ? 'Payments + cash back' : 'Payments made', got, _green, Icons.south_west_rounded),
          const SizedBox(width: 10),
          tile(isC ? 'Total due' : 'Payable', 'Right now', d.balance.abs(), d.balance > 0 ? (isC ? _red : _amber) : _green, Icons.summarize_rounded),
        ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- payment schedule
  Widget _duesCard(_ProfileData d) {
    final today = ymd(DateTime.now());
    final open = d.dues.where((x) => x['status'] == 'open').toList();
    final done = d.dues.where((x) => x['status'] != 'open').take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.alarm_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Payment schedule', style: _j(15, FontWeight.w800, _ink)),
              Text('Phone reminds you on these dates', style: _j(11, FontWeight.w500, _muted)),
            ]),
          ),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => DueSheet(
                partyType: widget.type,
                partyId: widget.id,
                partyName: d.party['name'] as String,
                suggested: d.balance > 0 ? d.balance : 0,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.add_alarm_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 4),
                Text('Add date', style: _j(11.5, FontWeight.w800, Colors.white)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (open.isEmpty && done.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No due dates. Add one and your phone will ring a day before and on the day.',
                style: _j(12, FontWeight.w500, _muted)),
          ),
        for (final x in open) _dueRow(x, today),
        for (final x in done) _dueRow(x, today),
      ]),
    );
  }

  Widget _dueRow(Rec x, String today) {
    final date = x['due_date'] as String;
    final paid = x['status'] != 'open';
    final overdue = !paid && date.compareTo(today) < 0;
    final c = paid ? _green : overdue ? _red : date == today ? _amber : _purple;
    final id = asInt(x['id']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: c.withAlpha(0x1A), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('${DateTime.parse(date).day}', style: _j(15, FontWeight.w800, c, height: 1)),
            Text(monthName(DateTime.parse(date).month), style: _j(10, FontWeight.w700, c)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Money.rs(asInt(x['amount'])),
                style: _j(14, FontWeight.w800, paid ? _muted : _ink).copyWith(decoration: paid ? TextDecoration.lineThrough : null)),
            Text(
              [paid ? 'Paid' : overdue ? 'Overdue' : timeUntil(date), if ((x['note'] as String? ?? '').isNotEmpty) x['note']].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _j(11, FontWeight.w600, c),
            ),
          ]),
        ),
        if (!paid)
          GestureDetector(
            onTap: () async {
              await closeDue(id);
              if (mounted) toast(context, 'Marked as paid — reminder cancelled');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFE3F7EC), borderRadius: BorderRadius.circular(10)),
              child: Text('Paid', style: _j(11.5, FontWeight.w800, _green)),
            ),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFB9BCD6)),
          onPressed: () => closeDue(id, delete: true),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- products bought
  Widget _boughtCard(_ProfileData d) {
    final units = d.bought.fold<int>(0, (a, r) => a + asInt(r['qty']));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.shopping_bag_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Products bought', style: _j(15, FontWeight.w800, _ink))),
          Text('$units unit${units == 1 ? '' : 's'}', style: _j(12, FontWeight.w700, _muted)),
        ]),
        const SizedBox(height: 6),
        for (final r in d.bought.take(12))
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => open(context, SaleView(id: asInt(r['sale_id']))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                ProductThumb({'image': r['image'], 'category': r['category']}, width: 44, height: 48),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w700, _ink)),
                    Text(
                      [prettyDate(r['date'] as String), '${r['qty']} × ${Money.rs(asInt(r['rate']))}', '${r['number']}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _j(10.5, FontWeight.w600, _muted),
                    ),
                    if ((r['serial'] as String? ?? '').isNotEmpty)
                      Text('IMEI ${r['serial']}', style: _j(10.5, FontWeight.w700, _purple)),
                  ]),
                ),
                Text(Money.rs(asInt(r['amount']) + asInt(r['tax'])), style: _j(13, FontWeight.w800, _ink)),
              ]),
            ),
          ),
        if (d.bought.length > 12)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('+${d.bought.length - 12} more in the transactions below', style: _j(11, FontWeight.w600, _muted)),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- details & KYC
  Widget _detailsCard(_ProfileData d) {
    final p = d.party;
    String? v(String k) => (p[k] as String? ?? '').trim().isEmpty ? null : (p[k] as String).trim();
    Widget row(IconData i, String label, String value, {VoidCallback? onTap, IconData? action}) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 18, color: const Color(0xFF8B7FD6)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: _j(10.5, FontWeight.w600, _muted)),
                  Text(value, style: _j(13.5, FontWeight.w700, _ink)),
                ]),
              ),
              if (action != null) Icon(action, size: 18, color: _purple),
            ]),
          ),
        );
    Widget doc(String label, String? img) => Expanded(
          child: GestureDetector(
            onTap: img == null
                ? null
                : () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: storedImage(img, fit: BoxFit.contain),
                      ),
                    ),
            child: Container(
              height: 86,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F3FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD6CCFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (img != null) storedImage(img) else const Center(child: Icon(Icons.image_not_supported_rounded, color: Color(0xFFB9BCD6))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0x99000000),
                    child: Text(label, textAlign: TextAlign.center, style: _j(10.5, FontWeight.w700, Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
        );
    final hasDocs = v('aadhaar_img') != null || v('pan_img') != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.badge_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Details & KYC', style: _j(15, FontWeight.w800, _ink))),
          TextButton(
            onPressed: () => open(context, PartyForm(type: widget.type, party: p)),
            child: const Text('Edit'),
          ),
        ]),
        if (v('phone') != null) row(Icons.phone_rounded, 'Mobile', v('phone')!, onTap: () => Contact.call(v('phone')), action: Icons.call_rounded),
        if (v('alt_phone') != null)
          row(Icons.phone_forwarded_rounded, 'Alternate number', v('alt_phone')!, onTap: () => Contact.call(v('alt_phone')), action: Icons.call_rounded),
        if (v('email') != null) row(Icons.alternate_email_rounded, 'Email', v('email')!),
        if (v('address') != null) row(Icons.location_on_rounded, 'Address', v('address')!),
        if (v('gstin') != null) row(Icons.receipt_long_rounded, 'GSTIN', v('gstin')!),
        if (v('aadhaar') != null) row(Icons.fingerprint_rounded, 'Aadhaar', maskAadhaar(v('aadhaar'))),
        if (v('pan') != null) row(Icons.credit_card_rounded, 'PAN', maskPan(v('pan'))),
        if (hasDocs) ...[
          const SizedBox(height: 6),
          Row(children: [doc('Aadhaar', v('aadhaar_img')), const SizedBox(width: 10), doc('PAN card', v('pan_img'))]),
        ],
        if (v('notes') != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.sticky_note_2_rounded, size: 17, color: Color(0xFFB7791F)),
              const SizedBox(width: 8),
              Expanded(child: Text(v('notes')!, style: _j(12.5, FontWeight.w600, const Color(0xFF5C4400)))),
            ]),
          ),
        ],
        if ([v('phone'), v('alt_phone'), v('email'), v('address'), v('gstin'), v('aadhaar'), v('pan'), v('notes')].every((e) => e == null) && !hasDocs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No details yet — tap Edit to add phone, address, Aadhaar and PAN.', style: _j(12, FontWeight.w500, _muted)),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- stats
  Widget _statsGrid(_ProfileData d) {
    final s = d.stats;
    Widget tile(IconData i, Color c, String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: _card(r: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(9)),
                child: Icon(i, color: c, size: 17),
              ),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: _j(15, FontWeight.w800, _ink))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w600, _muted)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        tile(Icons.trending_up_rounded, _purple, isC ? 'Lifetime sales' : 'Lifetime purchases', Money.compact(s.business)),
        const SizedBox(width: 10),
        tile(Icons.receipt_long_rounded, _amber, isC ? 'Invoices' : 'Bills', '${s.docs}'),
        const SizedBox(width: 10),
        tile(Icons.shopping_bag_rounded, const Color(0xFF2F6BFF), 'Avg. bill', Money.compact(s.avgBill)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(Icons.payments_rounded, _green, isC ? 'Received' : 'Paid', Money.compact(s.paidAtBill + s.paymentsTotal)),
        const SizedBox(width: 10),
        tile(Icons.event_available_rounded, const Color(0xFF14B8A6), isC ? 'Last purchase' : 'Last bill',
            s.lastDoc == null ? '—' : timeAgoDate(s.lastDoc!)),
        const SizedBox(width: 10),
        tile(Icons.price_check_rounded, const Color(0xFFEC4899), 'Last payment', s.lastPayment == null ? '—' : timeAgoDate(s.lastPayment!)),
      ]),
    ]);
  }

  // ---------------------------------------------------------------- ageing
  Widget _ageingCard(_ProfileData d) {
    final a = d.ageing;
    final total = a.total == 0 ? 1 : a.total;
    const colors = [Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFF97316), Color(0xFFEF4444)];
    const labels = ['0–30 days', '31–60 days', '61–90 days', '90+ days'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.hourglass_bottom_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(isC ? 'Due ageing' : 'Payable ageing', style: _j(15, FontWeight.w800, _ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (a.oldestDays > 60 ? _red : a.oldestDays > 30 ? _amber : _green).withAlpha(0x1F),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Oldest ${a.oldestDays}d',
                style: _j(11, FontWeight.w800, a.oldestDays > 60 ? _red : a.oldestDays > 30 ? _amber : _green)),
          ),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (var i = 0; i < 4; i++)
                if (a.buckets[i] > 0) Expanded(flex: (a.buckets[i] * 1000 ~/ total).clamp(1, 1000).toInt(), child: Container(color: colors[i])),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(labels[i], style: _j(12.5, FontWeight.w600, const Color(0xFF3A4155)))),
              Text(Money.rs(a.buckets[i]), style: _j(12.5, FontWeight.w800, a.buckets[i] > 0 ? _ink : _muted)),
            ]),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- smart reminder
  Widget _reminderCard(_ProfileData d) {
    final suggested = Reminders.suggest(d.ageing.oldestDays);
    final t = tone ?? suggested;
    final msg = _message(d, t);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF0F3D2E), Color(0xFF075E54)]),
        boxShadow: const [BoxShadow(color: Color(0x40075E54), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: const Color(0x2625D366), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7CF0AE), size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Smart WhatsApp reminder', style: _j(14.5, FontWeight.w800, Colors.white)),
              Text(
                d.stats.lastReminder == null ? 'Never reminded' : 'Last reminded ${timeAgo(d.stats.lastReminder!)}',
                style: _j(11, FontWeight.w500, const Color(0xB3FFFFFF)),
              ),
            ]),
          ),
          _langToggle(),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final rt in ReminderTone.values) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => tone = rt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: rt == t ? const Color(0xFF25D366) : const Color(0x1FFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Text(Reminders.label(rt, bangla: bangla), style: _j(11.5, FontWeight.w800, Colors.white)),
                    if (rt == suggested) Text(bangla ? 'প্রস্তাবিত' : 'suggested', style: _j(9, FontWeight.w600, const Color(0xCCFFFFFF))),
                  ]),
                ),
              ),
            ),
            if (rt != ReminderTone.values.last) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFDCF8C6),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(msg, style: const TextStyle(fontSize: 13, height: 1.35, color: Color(0xFF111B21))),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _sendReminder(d),
          child: Container(
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(24)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.send_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(bangla ? 'WhatsApp-এ পাঠান' : 'Send on WhatsApp', style: _j(14, FontWeight.w800, Colors.white)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _langToggle() => GestureDetector(
        onTap: () => setState(() => bangla = !bangla),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (l, on) in [('EN', !bangla), ('বাং', bangla)])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                child: Text(l, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? const Color(0xFF075E54) : Colors.white)),
              ),
          ]),
        ),
      );

  String _message(_ProfileData d, ReminderTone t) => Reminders.message(
        tone: t,
        bangla: bangla,
        name: d.party['name'] as String,
        due: d.balance,
        days: d.ageing.oldestDays,
        settings: d.settings,
      );

  Future<void> _sendReminder(_ProfileData d) async {
    if (d.balance <= 0) {
      toast(context, 'No dues to remind about');
      return;
    }
    final t = tone ?? Reminders.suggest(d.ageing.oldestDays);
    final ok = await Contact.whatsapp(d.party['phone'] as String?, _message(d, t));
    await Books.logReminder(widget.type, widget.id, d.party['name'] as String, 'WhatsApp');
    if (!ok && mounted) toast(context, 'WhatsApp not available — message copied');
  }

  Future<void> _sendStatement(_ProfileData d) async {
    final text = Reminders.statement(
      name: d.party['name'] as String,
      rows: d.rows,
      balance: d.balance,
      customer: isC,
      settings: d.settings,
    );
    final ok = await Contact.whatsapp(d.party['phone'] as String?, text);
    if (!ok && mounted) toast(context, 'WhatsApp not available — statement copied');
  }

  // ---------------------------------------------------------------- timeline
  Widget _timeline(_ProfileData d) {
    // newest first, keep running balance from the ledger
    final rows = d.rows.reversed.where((r) {
      final up = isC ? asInt(r['debit']) : asInt(r['credit']);
      if (filter == 'bills') return up > 0;
      if (filter == 'payments') return up == 0;
      return true;
    }).toList();
    final groups = <String, List<Rec>>{};
    for (final r in rows) {
      final dt = DateTime.parse(r['date'] as String);
      groups.putIfAbsent('${monthName(dt.month)} ${dt.year}', () => []).add(r);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.swap_vert_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Transactions', style: _j(15, FontWeight.w800, _ink))),
          Text('${d.rows.length}', style: _j(12, FontWeight.w700, _muted)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (final f in [('all', 'All'), ('bills', isC ? 'Sales' : 'Bills'), ('payments', 'Payments')]) ...[
            GestureDetector(
              onTap: () => setState(() => filter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: filter == f.$1 ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                  color: filter == f.$1 ? null : const Color(0xFFF1F2FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(f.$2, style: _j(12, FontWeight.w700, filter == f.$1 ? Colors.white : _ink)),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ]),
        if (rows.isEmpty) const EmptyState('No transactions yet'),
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(g.key.toUpperCase(), style: _j(11, FontWeight.w800, _muted).copyWith(letterSpacing: 1)),
          ),
          for (final r in g.value) _txn(r),
        ],
      ]),
    );
  }

  Widget _txn(Rec r) {
    final up = isC ? asInt(r['debit']) : asInt(r['credit']);
    final down = isC ? asInt(r['credit']) : asInt(r['debit']);
    final bill = up > 0;
    final narr = '${r['narration'] ?? ''}';
    final docNo = RegExp(r'(INV|PUR)-\d+').firstMatch(narr)?.group(0);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: docNo == null ? null : () => _openDoc(docNo),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (bill ? (isC ? _purple : _amber) : _green).withAlpha(0x1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(bill ? Icons.receipt_long_rounded : Icons.payments_rounded,
                color: bill ? (isC ? _purple : _amber) : _green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(narr, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w700, _ink)),
              Text('${prettyDate(r['date'] as String)} · bal ${Money.rs(asInt(r['balance']))}',
                  style: _j(11, FontWeight.w500, _muted)),
            ]),
          ),
          Text(bill ? '+${Money.rs(up)}' : '−${Money.rs(down)}', style: _j(13.5, FontWeight.w800, bill ? _ink : _green)),
          if (docNo != null) const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9BCD6), size: 20),
        ]),
      ),
    );
  }

  Future<void> _openDoc(String no) async {
    final table = no.startsWith('INV') ? 'sales' : 'purchases';
    final r = await Books.query('SELECT id FROM $table WHERE number = ?', [no]);
    if (r.isEmpty || !mounted) return;
    final id = asInt(r.first['id']);
    open(context, table == 'sales' ? SaleView(id: id) : PurchaseView(id: id));
  }

  // ---------------------------------------------------------------- bottom actions
  Widget _bottomBar(_ProfileData d, double safe) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safe),
      decoration: const BoxDecoration(
        color: Color(0xF7FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 24, offset: Offset(0, -6), spreadRadius: -8)],
      ),
      child: Row(children: [
        Expanded(
          child: _bigBtn(
            isC ? 'Receive' : 'Pay',
            Icons.currency_rupee_rounded,
            const [Color(0xFF1BB574), Color(0xFF0F8C58)],
            () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => PaymentSheet(kind: isC ? 'receipt' : 'payment', partyId: widget.id, suggested: d.balance),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _bigBtn(
            isC ? 'Gave cash' : 'Got cash',
            isC ? Icons.north_east_rounded : Icons.south_west_rounded,
            const [Color(0xFFF43F5E), Color(0xFFDC2626)],
            () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => LendSheet(kind: isC ? 'gave' : 'got', partyType: widget.type, partyId: widget.id),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _bigBtn(
            isC ? 'New sale' : 'New purchase',
            isC ? Icons.add_shopping_cart_rounded : Icons.inventory_rounded,
            const [Color(0xFF6B35EE), Color(0xFF4318D2)],
            () => open(context, isC ? SaleForm(customerId: widget.id) : PurchaseForm(supplierId: widget.id)),
          ),
        ),
      ]),
    );
  }

  Widget _bigBtn(String label, IconData icon, List<Color> colors, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withAlpha(0x66), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -6)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, Colors.white))),
          ]),
        ),
      );
}

/// "Today", "Yesterday", "5d ago", "3 mo ago" for a yyyy-MM-dd date.
String timeAgoDate(String ymdDate) {
  final d = DateTime.tryParse(ymdDate);
  if (d == null) return ymdDate;
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 31) return '${days}d ago';
  if (days < 365) return '${days ~/ 30} mo ago';
  return '${days ~/ 365} yr ago';
}
