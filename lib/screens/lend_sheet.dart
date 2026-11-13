import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarms.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';

// =============================================================================
// Khata entry sheets:
//   LendSheet — "You gave" (cash given on credit) / "You got" (cash received)
//               with reason chips, account, date and an optional due date
//               that rings the phone.
//   DueSheet  — set a payment due date for a party, with notification.
// =============================================================================

const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);

TextStyle _j(double size, FontWeight w, Color c, {double? height}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
    );

BoxDecoration _card({double r = 18}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -4)],
    );

Widget _handle() => Center(
      child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
    );

Widget _amountField(TextEditingController c, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: _card(r: 20),
      child: Row(children: [
        Text('₹', style: _j(30, FontWeight.w800, color)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: _j(30, FontWeight.w800, _ink),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '0',
              hintStyle: _j(30, FontWeight.w800, const Color(0xFFD5D8EA)),
            ),
          ),
        ),
      ]),
    );

Future<String?> _pickDate(BuildContext context, String? current, {bool future = false}) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: current == null ? (future ? now.add(const Duration(days: 7)) : now) : DateTime.parse(current),
    firstDate: future ? DateTime(now.year, now.month, now.day) : DateTime(2015),
    lastDate: DateTime(now.year + 5),
  );
  return d == null ? null : ymd(d);
}

/// Saves a due date and schedules its phone reminders.
Future<int> saveDueWithAlarm({
  required String partyType,
  required int partyId,
  required String partyName,
  required int amount,
  required String dueDate,
  String? note,
  int hour = 10,
  int minute = 0,
}) async {
  final id = await Books.addDue(partyType, partyId, amount, dueDate, note);
  final isC = partyType == 'customer';
  await Alarms.scheduleDue(
    dueId: id,
    dueDate: DateTime.parse(dueDate),
    title: isC ? 'Collect ${Money.rs(amount)} from $partyName' : 'Pay ${Money.rs(amount)} to $partyName',
    body: (note ?? '').isEmpty ? 'Payment due ${prettyDate(dueDate)} · GameX Hisab' : '$note · due ${prettyDate(dueDate)}',
    hour: hour,
    minute: minute,
  );
  return id;
}

// =============================================================================
class LendSheet extends StatefulWidget {
  final String kind; // gave | got
  final String? partyType;
  final int? partyId;
  const LendSheet({super.key, required this.kind, this.partyType, this.partyId});
  @override
  State<LendSheet> createState() => _LendSheetState();
}

class _LendSheetState extends State<LendSheet> {
  final amount = TextEditingController();
  final reason = TextEditingController();
  late String partyType = widget.partyType ?? 'customer';
  int? partyId;
  List<Rec> customers = [], suppliers = [], accounts = [];
  Map<int, int> cBal = {}, sBal = {};
  int? account;
  String date = ymd(DateTime.now());
  String? dueDate;
  String q = '';
  bool saving = false;

  bool get gave => widget.kind == 'gave';
  Color get _color => gave ? _red : _green;

  @override
  void initState() {
    super.initState();
    partyId = widget.partyId;
    _load();
  }

  Future<void> _load() async {
    customers = await Books.query('SELECT * FROM customers ORDER BY name COLLATE NOCASE');
    suppliers = await Books.query('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE');
    cBal = await Books.partyBalances('customer');
    sBal = await Books.partyBalances('supplier');
    accounts = await Books.moneyAccounts();
    account ??= accounts.isNotEmpty ? asInt(accounts.first['id']) : null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  Rec? get _party {
    for (final p in partyType == 'customer' ? customers : suppliers) {
      if (asInt(p['id']) == partyId) return p;
    }
    return null;
  }

  Future<void> _save() async {
    if (saving) return;
    final p = _party;
    if (p == null) {
      toast(context, 'Choose who this is with', error: true);
      return;
    }
    int amt;
    try {
      amt = Money.parse(amount.text);
    } catch (_) {
      amt = 0;
    }
    if (amt <= 0) {
      toast(context, 'Enter the amount', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await Books.createLend(
        kind: widget.kind,
        partyType: partyType,
        partyId: asInt(p['id']),
        amount: amt,
        accountId: account ?? 0,
        date: date,
        reason: reason.text,
      );
      if (dueDate != null) {
        await saveDueWithAlarm(
          partyType: partyType,
          partyId: asInt(p['id']),
          partyName: p['name'] as String,
          amount: amt,
          dueDate: dueDate!,
          note: reason.text.trim().isEmpty ? null : reason.text.trim(),
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
      toast(context, gave ? 'Saved — ${p['name']} owes ${Money.rs(amt)} more' : 'Saved — received ${Money.rs(amt)}');
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (partyType == 'customer' ? customers : suppliers)
        .where((p) => q.isEmpty || '${p['name']} ${p['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    final bal = partyType == 'customer' ? cBal : sBal;
    final reasons = gave
        ? const ['Cash loan', 'Advance', 'Repair charge', 'EMI paid for them', 'Recharge / bill', 'Other']
        : const ['Due payment', 'Loan returned', 'Advance taken', 'Deposit', 'Other'];
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF6F7FC), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _handle(),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _color.withAlpha(0x1F), borderRadius: BorderRadius.circular(12)),
                child: Icon(gave ? Icons.north_east_rounded : Icons.south_west_rounded, color: _color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(gave ? 'You gave' : 'You got', style: _j(19, FontWeight.w800, _navy)),
                  Text(gave ? 'Cash given on credit — they will owe you' : 'Cash received — their due goes down',
                      style: _j(11.5, FontWeight.w500, _muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _amountField(amount, _color),
            const SizedBox(height: 14),
            if (widget.partyId == null) ...[
              Row(children: [
                for (final t in const [('customer', 'Customer'), ('supplier', 'Supplier')]) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        partyType = t.$1;
                        partyId = null;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: partyType == t.$1 ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                          color: partyType == t.$1 ? null : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: partyType == t.$1 ? null : Border.all(color: _line),
                        ),
                        child: Text(t.$2, style: _j(12.5, FontWeight.w800, partyType == t.$1 ? Colors.white : _ink)),
                      ),
                    ),
                  ),
                  if (t.$1 == 'customer') const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 10),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: _card(r: 22),
                child: Row(children: [
                  const Icon(Icons.search_rounded, color: _muted, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => q = v.trim()),
                      style: _j(13.5, FontWeight.w600, _ink),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Search name or phone',
                        hintStyle: _j(13, FontWeight.w400, const Color(0xFF8A8FAD)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: list.isEmpty
                    ? Center(child: Text('No ${partyType}s yet — add one first', style: _j(12.5, FontWeight.w500, _muted)))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final p = list[i];
                          final on = asInt(p['id']) == partyId;
                          final b = bal[asInt(p['id'])] ?? 0;
                          final name = p['name'] as String;
                          return GestureDetector(
                            onTap: () => setState(() => partyId = asInt(p['id'])),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 88,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: on ? const Color(0xFFEFEBFF) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: on ? _purple : _line, width: on ? 1.6 : 1),
                              ),
                              child: Column(children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF4F46E5)]),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  alignment: Alignment.center,
                                  child: storedImage(p['photo'] as String?,
                                      fallback: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: _j(15, FontWeight.w800, Colors.white))),
                                ),
                                const SizedBox(height: 4),
                                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w700, _ink)),
                                Text(b == 0 ? 'Settled' : Money.compact(b.abs()),
                                    style: _j(10, FontWeight.w700, b > 0 ? (partyType == 'customer' ? _red : const Color(0xFFE39A0F)) : _green)),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
            ] else if (_party != null) ...[
              Text('With ${_party!['name']}', style: _j(14, FontWeight.w800, _ink)),
              const SizedBox(height: 12),
            ],
            Text('Reason', style: _j(12.5, FontWeight.w700, const Color(0xFF3A4155))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in reasons)
                GestureDetector(
                  onTap: () => setState(() => reason.text = r == 'Other' ? '' : r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: reason.text == r ? _color.withAlpha(0x1F) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: reason.text == r ? _color : _line),
                    ),
                    child: Text(r, style: _j(11.5, FontWeight.w700, reason.text == r ? _color : _ink)),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _card(r: 16),
              child: TextField(
                controller: reason,
                onChanged: (_) => setState(() {}),
                style: _j(13.5, FontWeight.w600, _ink),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Details (optional)',
                  hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(gave ? 'Paid from' : 'Received in', style: _j(12.5, FontWeight.w700, const Color(0xFF3A4155))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in accounts)
                GestureDetector(
                  onTap: () => setState(() => account = asInt(a['id'])),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: account == asInt(a['id']) ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                      color: account == asInt(a['id']) ? null : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: account == asInt(a['id']) ? null : Border.all(color: _line),
                    ),
                    child: Text(a['name'] as String, style: _j(12.5, FontWeight.w700, account == asInt(a['id']) ? Colors.white : _ink)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _dateChip(Icons.event_rounded, date == ymd(DateTime.now()) ? 'Today' : prettyDate(date), () async {
                final d = await _pickDate(context, date);
                if (d != null) setState(() => date = d);
              })),
              if (gave) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _dateChip(
                    dueDate == null ? Icons.alarm_add_rounded : Icons.alarm_on_rounded,
                    dueDate == null ? 'Set return date' : 'Due ${prettyDate(dueDate!)}',
                    () async {
                      final d = await _pickDate(context, dueDate, future: true);
                      setState(() => dueDate = d);
                    },
                    highlight: dueDate != null,
                  ),
                ),
              ],
            ]),
            if (dueDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.notifications_active_rounded, size: 15, color: _purple),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Your phone will remind you a day before and on the date at 10 AM', style: _j(11, FontWeight.w600, _purple))),
                ]),
              ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _save,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: LinearGradient(colors: gave ? const [Color(0xFFF43F5E), Color(0xFFDC2626)] : const [Color(0xFF1BB574), Color(0xFF0F8C58)]),
                  boxShadow: [BoxShadow(color: _color.withAlpha(0x80), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -6)],
                ),
                alignment: Alignment.center,
                child: saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(gave ? 'Save — you gave' : 'Save — you got', style: _j(15, FontWeight.w800, Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dateChip(IconData icon, String label, VoidCallback onTap, {bool highlight = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: highlight ? const Color(0xFFEFEBFF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: highlight ? _purple : _line),
          ),
          child: Row(children: [
            Icon(icon, color: _purple, size: 19),
            const SizedBox(width: 8),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w700, _ink))),
          ]),
        ),
      );
}

// =============================================================================
class DueSheet extends StatefulWidget {
  final String partyType;
  final int partyId;
  final String partyName;
  final int suggested;
  const DueSheet({super.key, required this.partyType, required this.partyId, required this.partyName, this.suggested = 0});
  @override
  State<DueSheet> createState() => _DueSheetState();
}

class _DueSheetState extends State<DueSheet> {
  late final amount = TextEditingController(text: widget.suggested > 0 ? Money.edit(widget.suggested) : '');
  final note = TextEditingController();
  String? date;
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    int amt;
    try {
      amt = Money.parse(amount.text);
    } catch (_) {
      amt = 0;
    }
    if (amt <= 0 || date == null) {
      toast(context, 'Enter the amount and pick a date', error: true);
      return;
    }
    setState(() => saving = true);
    await saveDueWithAlarm(
      partyType: widget.partyType,
      partyId: widget.partyId,
      partyName: widget.partyName,
      amount: amt,
      dueDate: date!,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
    toast(context, 'Reminder set for ${prettyDate(date!)}');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final quick = [('1 week', 7), ('15 days', 15), ('1 month', 30), ('2 months', 60)];
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF6F7FC), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _handle(),
            const SizedBox(height: 14),
            Text('Payment due date', style: _j(19, FontWeight.w800, _navy)),
            Text(
              widget.partyType == 'customer' ? '${widget.partyName} promises to pay on this date' : 'You need to pay ${widget.partyName} on this date',
              style: _j(12, FontWeight.w500, _muted),
            ),
            const SizedBox(height: 14),
            _amountField(amount, _purple),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in quick)
                GestureDetector(
                  onTap: () => setState(() => date = ymd(now.add(Duration(days: q.$2)))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: date == ymd(now.add(Duration(days: q.$2))) ? const Color(0xFFEFEBFF) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: date == ymd(now.add(Duration(days: q.$2))) ? _purple : _line),
                    ),
                    child: Text(q.$1, style: _j(12, FontWeight.w700, _ink)),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  final d = await _pickDate(context, date, future: true);
                  if (d != null) setState(() => date = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_month_rounded, size: 15, color: _purple),
                    const SizedBox(width: 4),
                    Text(date == null ? 'Pick date' : prettyDate(date!), style: _j(12, FontWeight.w700, _ink)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _card(r: 16),
              child: TextField(
                controller: note,
                style: _j(13.5, FontWeight.w600, _ink),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Note (e.g. 2nd installment, after salary)',
                  hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.notifications_active_rounded, size: 15, color: _purple),
              const SizedBox(width: 6),
              Expanded(child: Text('Phone notification with sound: 1 day before and on the date, 10 AM', style: _j(11, FontWeight.w600, _purple))),
            ]),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: saving ? null : _save,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF3A10CC)]),
                ),
                alignment: Alignment.center,
                child: Text('Save due date & reminder', style: _j(15, FontWeight.w800, Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
