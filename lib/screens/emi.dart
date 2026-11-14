import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarms.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'parties.dart';
import 'sales.dart' show SaleView;

// =============================================================================
// EMI / Kisti tracker — monthly instalments for phones sold on finance
// (Bajaj, HDB, Home Credit…) or on the shop's own kisti. Dashboard of what
// is due this month and overdue, plan cards with progress, collection with
// receipts, WhatsApp reminders and a phone alarm before each due date.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);
const _grad = [Color(0xFF14B8A6), Color(0xFF0E7490)];

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

const financers = ['Bajaj Finserv', 'HDB Financial', 'Home Credit', 'TVS Credit', 'IDFC FIRST', 'Samsung Finance+', 'Kotak', 'Other'];

int _daysTo(String date) {
  final now = DateTime.now();
  return DateTime.parse(date).difference(DateTime(now.year, now.month, now.day)).inDays;
}

String _dueText(String date) {
  final d = _daysTo(date);
  return d < 0 ? 'Overdue ${-d}d' : d == 0 ? 'Due today' : d == 1 ? 'Due tomorrow' : 'Due in ${d}d';
}

Color _dueColor(String date) {
  final d = _daysTo(date);
  return d < 0 ? _red : d <= 3 ? _amber : _green;
}

String _initials(String n) => n.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();

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

Widget _avatar(Rec p, {double size = 48}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .34),
        gradient: const LinearGradient(colors: _grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x550E7490), blurRadius: 10, offset: Offset(0, 4), spreadRadius: -3)],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: storedImage(p['photo'] as String?,
          fallback: Text(_initials('${p['customer']}'), style: _j(size * .34, FontWeight.w800, Colors.white))),
    );

String reminderText(Rec p, Map<String, String> settings) {
  final shop = (settings['business_name'] ?? '').trim().isEmpty ? 'our shop' : settings['business_name']!.trim();
  final upi = (settings['upi_id'] ?? '').trim();
  final due = p['next_due'] == null ? '' : prettyDate('${p['next_due']}');
  return 'Hi ${p['customer']},\nYour EMI of ${Money.rs(asInt(p['next_amount']))}'
      '${p['product'] == null ? '' : ' for ${p['product']}'} is due on $due'
      '${p['financer'] == null ? '' : ' (${p['financer']})'}.'
      '${p['kind'] == 'shop' && upi.isNotEmpty ? '\nPay by UPI: $upi' : ''}'
      '\nPlease pay on time to avoid late charges. Thank you! — $shop';
}

/// Keeps one phone alarm per plan for its next instalment.
class EmiAlarms {
  static final _done = <int, String>{};
  static void sync(List<Rec> plans) {
    for (final p in plans) {
      final id = asInt(p['id']);
      final key = '${p['status']}|${p['next_id']}|${p['next_due']}';
      if (_done[id] == key) continue;
      _done[id] = key;
      final next = p['next_id'];
      if (next == null || p['status'] != 'active') continue;
      Alarms.scheduleDue(
        dueId: 2000000 + asInt(next),
        dueDate: DateTime.parse('${p['next_due']}'),
        title: 'EMI ${Money.rs(asInt(p['next_amount']))} — ${p['customer']}',
        body: '${p['financer'] ?? 'Shop kisti'} · ${p['product'] ?? ''} · instalment due',
      );
    }
  }
}

// =============================================================================
class EmiScreen extends StatefulWidget {
  const EmiScreen({super.key});
  @override
  State<EmiScreen> createState() => _EmiScreenState();
}

class _EmiScreenState extends State<EmiScreen> {
  String q = '';
  String filter = 'active'; // active | overdue | week | closed | all

  Future<(List<Rec>, Map<String, String>)> _load() async {
    final plans = await Books.emiPlans();
    EmiAlarms.sync(plans);
    return (plans, await Books.settings());
  }

  bool _match(Rec p) {
    if (q.isEmpty) return true;
    final l = q.toLowerCase();
    return [p['customer'], p['phone'], p['product'], p['imei'], p['opp_id'], p['loan_no'], p['financer']]
        .any((v) => v != null && '$v'.toLowerCase().contains(l));
  }

  bool _filter(Rec p) {
    final active = p['status'] == 'active';
    return switch (filter) {
      'active' => active,
      'overdue' => active && asInt(p['overdue_n']) > 0,
      'week' => active && p['next_due'] != null && _daysTo('${p['next_due']}') <= 7,
      'closed' => !active,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: GestureDetector(
        onTap: () => open(context, const EmiForm()),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: _grad),
            border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x770E7490), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_card_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text('New EMI plan', style: _j(15, FontWeight.w800, Colors.white)),
          ]),
        ),
      ),
      body: SafeArea(
        child: Live<(List<Rec>, Map<String, String>)>(
          load: _load,
          builder: (context, d) {
            final all = d.$1;
            final rows = all.where(_filter).where(_match).toList();
            final active = all.where((p) => p['status'] == 'active').toList();
            final now = DateTime.now();
            final monthEnd = ymd(DateTime(now.year, now.month + 1, 0));
            final dueMonth = active
                .where((p) => p['next_due'] != null && '${p['next_due']}'.compareTo(monthEnd) <= 0)
                .fold<int>(0, (a, p) => a + asInt(p['next_amount']));
            final overdue = active.fold<int>(0, (a, p) => a + asInt(p['overdue_sum']));
            final overdueN = active.where((p) => asInt(p['overdue_n']) > 0).length;
            final collected = all.fold<int>(0, (a, p) => a + asInt(p['paid_sum']));
            final counts = {
              'active': active.length,
              'overdue': overdueN,
              'week': active.where((p) => p['next_due'] != null && _daysTo('${p['next_due']}') <= 7).length,
              'closed': all.length - active.length,
              'all': all.length,
            };
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
              Row(children: [
                if (canPop) ...[_round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()), const SizedBox(width: 12)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('EMI / Kisti', style: _j(22, FontWeight.w800, _navy)),
                    Text('Finance & shop instalments', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              _hero(dueMonth, overdue, overdueN, active.length, collected),
              const SizedBox(height: 14),
              Container(
                height: 52,
                decoration: _card(r: 26),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF0E7490)),
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
                        hintText: 'Name, mobile, IMEI, opportunity ID, loan no…',
                        hintStyle: _j(13, FontWeight.w500, const Color(0xFF8A8FAD)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in [('active', 'Active'), ('overdue', 'Overdue'), ('week', 'Due this week'), ('closed', 'Closed'), ('all', 'All')]) ...[
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => filter = f.$1);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: filter == f.$1 ? const LinearGradient(colors: _grad) : null,
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
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Container(
                  decoration: _card(),
                  padding: const EdgeInsets.all(20),
                  child: EmptyState(all.isEmpty ? 'No EMI plans yet — tap New EMI plan' : 'Nothing here'),
                ),
              for (final p in rows) _PlanCard(p: p, settings: d.$2),
            ]);
          },
        ),
      ),
    );
  }

  Widget _hero(int dueMonth, int overdue, int overdueN, int active, int collected) {
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
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14B8A6), Color(0xFF0E7490), Color(0xFF1E3A8A)]),
        boxShadow: const [BoxShadow(color: Color(0x660E7490), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: Stack(children: [
        Positioned(
          right: -30,
          top: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('To collect this month', style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Text('$active active plans', style: _j(11, FontWeight.w700, Colors.white)),
              ),
            ]),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(dueMonth), style: _j(28, FontWeight.w800, Colors.white))),
            const SizedBox(height: 12),
            Row(children: [
              cell('Overdue', Money.rs(overdue), overdue > 0 ? const Color(0xFFFFC2C2) : Colors.white),
              sep(),
              cell('Late customers', '$overdueN', overdueN > 0 ? const Color(0xFFFFC2C2) : Colors.white),
              sep(),
              cell('Collected', Money.rs(collected), const Color(0xFFB8FFE4)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Rec p;
  final Map<String, String> settings;
  const _PlanCard({required this.p, required this.settings});

  @override
  Widget build(BuildContext context) {
    final months = asInt(p['months']), paidN = asInt(p['paid_n']);
    final active = p['status'] == 'active';
    final next = p['next_due'] as String?;
    final phone = p['phone'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => open(context, EmiPlanView(id: asInt(p['id']))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _avatar(p),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['customer']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14.5, FontWeight.w800, _ink)),
                    Text(
                      [p['product'], p['financer'] ?? 'Shop kisti'].whereType<Object>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _j(11.5, FontWeight.w600, _muted),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${Money.rs(asInt(p['emi']))}/mo', style: _j(14.5, FontWeight.w800, _ink)),
                  const SizedBox(height: 3),
                  if (!active)
                    _chip(p['status'] == 'closed' ? 'COMPLETED' : 'CLOSED', _green)
                  else if (next != null)
                    _chip(_dueText(next).toUpperCase(), _dueColor(next)),
                ]),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: months == 0 ? 0 : paidN / months,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE7F6F4),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF14B8A6)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$paidN/$months paid', style: _j(11.5, FontWeight.w800, const Color(0xFF0E7490))),
              ]),
              if (asInt(p['overdue_n']) > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: _red, size: 16),
                  const SizedBox(width: 6),
                  Text('${asInt(p['overdue_n'])} instalment${asInt(p['overdue_n']) == 1 ? '' : 's'} late · ${Money.rs(asInt(p['overdue_sum']))}',
                      style: _j(11.5, FontWeight.w800, _red)),
                ]),
              ],
              if (active && phone != null && phone.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _action(Icons.call_rounded, 'Call', const Color(0xFF2F6BFF), () => Contact.call(phone))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _action(Icons.chat_rounded, 'Remind', const Color(0xFF25D366),
                        () => Contact.whatsapp(phone, reminderText(p, settings))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _action(Icons.payments_rounded, 'Collect', const Color(0xFF0E7490), () {
                      if (p['next_id'] == null) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => CollectSheet(
                            installmentId: asInt(p['next_id']), amount: asInt(p['next_amount']), shop: p['kind'] == 'shop'),
                      );
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

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: _j(9.5, FontWeight.w800, c)),
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

// =============================================================================
// Collect an instalment
// =============================================================================
class CollectSheet extends StatefulWidget {
  final int installmentId, amount;
  final bool shop;
  const CollectSheet({super.key, required this.installmentId, required this.amount, required this.shop});
  @override
  State<CollectSheet> createState() => _CollectSheetState();
}

class _CollectSheetState extends State<CollectSheet> {
  late final amount = TextEditingController(text: Money.edit(widget.amount));
  List<Rec> accounts = [];
  int? account;
  String date = ymd(DateTime.now());
  bool busy = false;

  @override
  void initState() {
    super.initState();
    Books.moneyAccounts().then((a) {
      if (!mounted) return;
      setState(() {
        accounts = a;
        account = a.isEmpty ? null : asInt(a.first['id']);
      });
    });
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.shop ? 'Collect instalment' : 'Mark instalment paid', style: _j(19, FontWeight.w800, _navy)),
        Text(
          widget.shop
              ? 'Received from the customer — posts a receipt against their due'
              : 'Customer paid the finance company — for tracking only',
          style: _j(12, FontWeight.w600, _muted),
        ),
        const SizedBox(height: 14),
        field(amount, 'Amount ₹', number: true),
        if (widget.shop) ...[
          Text('Received in', style: _j(12.5, FontWeight.w800, const Color(0xFF323B60))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in accounts)
              ChoiceChip(
                label: Text('${a['name']}'),
                selected: account == asInt(a['id']),
                onSelected: (_) => setState(() => account = asInt(a['id'])),
              ),
          ]),
          const SizedBox(height: 12),
        ],
        DateField(value: date, onChanged: (v) => setState(() => date = v)),
        GradientButton(
          label: busy ? 'Saving…' : 'Save',
          expand: true,
          fontSize: 16,
          onTap: () async {
            if (busy) return;
            setState(() => busy = true);
            try {
              await Books.payEmi(widget.installmentId,
                  amount: Money.parse(amount.text), accountId: widget.shop ? account : null, date: date);
              if (!context.mounted) return;
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop();
              toast(context, 'Instalment saved');
            } catch (e) {
              setState(() => busy = false);
              toast(context, '$e', error: true);
            }
          },
        ),
      ]),
    );
  }
}

// =============================================================================
// Plan details
// =============================================================================
class EmiPlanView extends StatelessWidget {
  final int id;
  const EmiPlanView({super.key, required this.id});

  Future<(Rec?, List<Rec>, Map<String, String>)> _load() async {
    final plans = await Books.emiPlans();
    final p = plans.where((x) => asInt(x['id']) == id).firstOrNull;
    return (p, p == null ? <Rec>[] : await Books.emiInstallments(id), await Books.settings());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<(Rec?, List<Rec>, Map<String, String>)>(
          load: _load,
          builder: (context, d) {
            final p = d.$1;
            if (p == null) return const EmptyState('Plan not found');
            final months = asInt(p['months']), paidN = asInt(p['paid_n']);
            final total = asInt(p['emi']) * months;
            final phone = p['phone'] as String?;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Row(children: [
                _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('EMI plan', style: _j(22, FontWeight.w800, _navy)),
                    Text('${p['financer'] ?? 'Shop kisti'} · $months months', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                  ]),
                ),
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (v) async {
                    try {
                      if (v == 'close') await Books.setEmiStatus(id, 'cancelled');
                      if (v == 'reopen') await Books.setEmiStatus(id, 'active');
                      if (v == 'delete') {
                        await Books.deleteEmiPlan(id);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    } catch (e) {
                      if (context.mounted) toast(context, '$e', error: true);
                    }
                  },
                  itemBuilder: (_) => [
                    if (p['status'] == 'active') const PopupMenuItem(value: 'close', child: Text('Close plan'))
                    else const PopupMenuItem(value: 'reopen', child: Text('Reopen plan')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete plan', style: TextStyle(color: _red))),
                  ],
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14B8A6), Color(0xFF0E7490), Color(0xFF1E3A8A)]),
                  boxShadow: const [BoxShadow(color: Color(0x660E7490), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
                ),
                child: Row(children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: months == 0 ? 0 : paidN / months,
                          strokeWidth: 9,
                          backgroundColor: const Color(0x33FFFFFF),
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$paidN/$months', style: _j(18, FontWeight.w800, Colors.white)),
                        Text('paid', style: _j(10.5, FontWeight.w600, const Color(0xDDFFFFFF))),
                      ]),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(
                        onTap: () => open(context, PartyView(type: 'customer', id: asInt(p['customer_id']))),
                        child: Text('${p['customer']}', style: _j(17, FontWeight.w800, Colors.white)),
                      ),
                      if (p['product'] != null) Text('${p['product']}', style: _j(12, FontWeight.w600, const Color(0xDDFFFFFF))),
                      const SizedBox(height: 8),
                      Text('${Money.rs(asInt(p['emi']))} × $months = ${Money.rs(total)}', style: _j(13, FontWeight.w800, Colors.white)),
                      Text('Collected ${Money.rs(asInt(p['paid_sum']))} · left ${Money.rs(total - asInt(p['paid_sum']))}',
                          style: _j(11.5, FontWeight.w600, const Color(0xDDFFFFFF))),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _card(),
                child: Column(children: [
                  _kv('Type', p['kind'] == 'shop' ? 'Shop kisti (we collect)' : 'Finance company'),
                  if (p['financer'] != null) _kv('Financer', '${p['financer']}'),
                  if (p['opp_id'] != null) _kv('Opportunity ID', '${p['opp_id']}'),
                  if (p['loan_no'] != null) _kv('Loan / agreement no.', '${p['loan_no']}'),
                  if (p['imei'] != null) _kv('IMEI', '${p['imei']}'),
                  if (asInt(p['price']) > 0) _kv('Price', Money.rs(asInt(p['price']))),
                  if (asInt(p['down_payment']) > 0) _kv('Down payment', Money.rs(asInt(p['down_payment']))),
                  _kv('First EMI', prettyDate('${p['start_date']}')),
                  if (p['note'] != null) _kv('Note', '${p['note']}'),
                ]),
              ),
              if (p['sale_id'] != null || (phone != null && phone.isNotEmpty)) ...[
                const SizedBox(height: 10),
                Row(children: [
                  if (p['sale_id'] != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => open(context, SaleView(id: asInt(p['sale_id']))),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Invoice'),
                      ),
                    ),
                  if (p['sale_id'] != null && phone != null && phone.isNotEmpty) const SizedBox(width: 8),
                  if (phone != null && phone.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Contact.whatsapp(phone, reminderText(p, d.$3)),
                        icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                        label: const Text('Remind'),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                decoration: _card(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Instalment schedule', style: _j(15, FontWeight.w800, _ink)),
                  const SizedBox(height: 6),
                  for (final i in d.$2) _instRow(context, i, p['kind'] == 'shop'),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: _j(12.5, FontWeight.w600, _muted))),
          Expanded(child: Text(v, style: _j(13, FontWeight.w700, _ink))),
        ]),
      );

  Widget _instRow(BuildContext context, Rec i, bool shop) {
    final amount = asInt(i['amount']), paid = asInt(i['paid_amount']);
    final done = paid >= amount;
    final due = '${i['due_date']}';
    final c = done ? _green : _dueColor(due);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withAlpha(0x1A), shape: BoxShape.circle),
          child: done ? Icon(Icons.check_rounded, color: c, size: 20) : Text('${i['n']}', style: _j(13, FontWeight.w800, c)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prettyDate(due), style: _j(13, FontWeight.w700, _ink)),
            Text(
              done
                  ? 'Paid ${i['paid_on'] == null ? '' : prettyDate('${i['paid_on']}')}${i['account'] == null ? '' : ' · ${i['account']}'}'
                  : paid > 0
                      ? 'Part paid ${Money.rs(paid)} · ${_dueText(due)}'
                      : _dueText(due),
              style: _j(11, FontWeight.w700, c),
            ),
          ]),
        ),
        Text(Money.rs(amount), style: _j(13.5, FontWeight.w800, _ink)),
        if (!done) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => CollectSheet(installmentId: asInt(i['id']), amount: amount - paid, shop: shop),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: _grad), borderRadius: BorderRadius.circular(12)),
              child: Text(shop ? 'Collect' : 'Paid', style: _j(11.5, FontWeight.w800, Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }
}

// =============================================================================
// New EMI plan
// =============================================================================
class EmiForm extends StatefulWidget {
  final int? saleId;
  const EmiForm({super.key, this.saleId});
  @override
  State<EmiForm> createState() => _EmiFormState();
}

class _EmiFormState extends State<EmiForm> {
  List<Rec> customers = [];
  Rec? customer;
  String kind = 'finance';
  String? financer = 'Bajaj Finserv';
  int months = 6;
  final product = TextEditingController();
  final imei = TextEditingController();
  final opp = TextEditingController();
  final loan = TextEditingController();
  final price = TextEditingController();
  final down = TextEditingController();
  final emi = TextEditingController();
  final note = TextEditingController();
  bool emiTouched = false;
  late String start = ymd(addMonths(DateTime.now(), 1));
  bool busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [price, down]) {
      c.addListener(_auto);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [product, imei, opp, loan, price, down, emi, note]) {
      c.dispose();
    }
    super.dispose();
  }

  int _p(TextEditingController c) {
    try {
      return Money.parse(c.text);
    } catch (_) {
      return 0;
    }
  }

  void _auto() {
    if (emiTouched) return;
    final financed = _p(price) - _p(down);
    final v = financed <= 0 || months <= 0 ? 0 : ((financed / months) / 100).ceil() * 100;
    emi.text = v == 0 ? '' : Money.edit(v);
    setState(() {});
  }

  Future<void> _load() async {
    customers = await Books.query('SELECT * FROM customers ORDER BY name COLLATE NOCASE');
    if (widget.saleId != null) {
      final s = await Books.query('SELECT * FROM sales WHERE id = ?', [widget.saleId]);
      final items = await Books.query('SELECT * FROM sale_items WHERE sale_id = ? ORDER BY amount DESC', [widget.saleId]);
      if (s.isNotEmpty) {
        final sale = s.first;
        customer = customers.where((c) => asInt(c['id']) == asInt(sale['customer_id'] ?? -1)).firstOrNull;
        price.text = Money.edit(asInt(sale['total']));
        down.text = asInt(sale['paid']) > 0 ? Money.edit(asInt(sale['paid'])) : '';
        if (items.isNotEmpty) {
          product.text = '${items.first['name']}';
          imei.text = '${items.first['serial'] ?? ''}';
          opp.text = '${items.first['opp_id'] ?? ''}';
        }
        kind = asInt(sale['total']) > asInt(sale['paid']) ? 'shop' : 'finance';
      }
    }
    _auto();
    if (mounted) setState(() {});
  }

  Future<void> _pickCustomer() async {
    final r = await showModalBottomSheet<Rec>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, set) {
            final rows = customers
                .where((c) => q.isEmpty || '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase()))
                .toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * .75,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => set(() => q = v.trim()),
                    decoration: const InputDecoration(hintText: 'Search customer', prefixIcon: Icon(Icons.search_rounded)),
                  ),
                ),
                Expanded(
                  child: ListView(children: [
                    for (final c in rows)
                      ListTile(
                        title: Text('${c['name']}'),
                        subtitle: Text('${c['phone'] ?? ''}'),
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: const Text('New customer'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await open(context, const PartyForm(type: 'customer'));
                        await _load();
                      },
                    ),
                  ]),
                ),
              ]),
            );
          },
        );
      },
    );
    if (r != null) setState(() => customer = r);
  }

  Future<void> _save() async {
    if (busy) return;
    if (customer == null) {
      toast(context, 'Select the customer', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final id = await Books.createEmiPlan(
        customerId: asInt(customer!['id']),
        kind: kind,
        emi: _p(emi),
        months: months,
        startDate: start,
        saleId: widget.saleId,
        financer: kind == 'finance' ? financer : null,
        oppId: opp.text,
        loanNo: loan.text,
        product: product.text,
        imei: imei.text,
        price: _p(price),
        downPayment: _p(down),
        note: note.text,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => EmiPlanView(id: id)));
    } catch (e) {
      setState(() => busy = false);
      toast(context, '$e', error: true);
    }
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: _grad) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: on ? null : Border.all(color: _line),
          ),
          child: Text(label, style: _j(12, FontWeight.w700, on ? Colors.white : _ink)),
        ),
      );

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: _j(15, FontWeight.w800, _ink)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final e = _p(emi);
    final financed = _p(price) - _p(down);
    final total = e * months;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          Row(children: [
            _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New EMI plan', style: _j(22, FontWeight.w800, _navy)),
              Text('Monthly instalments with reminders', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
            ]),
          ]),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _pickCustomer,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: _card(),
              child: Row(children: [
                customer == null
                    ? Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFE7F6F4), borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.person_search_rounded, color: Color(0xFF0E7490)),
                      )
                    : _avatar({'customer': customer!['name'], 'photo': customer!['photo']}),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(customer == null ? 'Select customer' : '${customer!['name']}', style: _j(15, FontWeight.w800, _ink)),
                    Text(customer == null ? 'Who pays the EMI' : '${customer!['phone'] ?? ''}', style: _j(12, FontWeight.w500, _muted)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: _muted),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _section('EMI type', [
            Row(children: [
              Expanded(child: _chip('Finance company', kind == 'finance', () => setState(() => kind = 'finance'))),
              const SizedBox(width: 8),
              Expanded(child: _chip('Shop kisti', kind == 'shop', () => setState(() => kind = 'shop'))),
            ]),
            const SizedBox(height: 8),
            Text(
              kind == 'shop'
                  ? 'The customer pays you every month. Collections are posted as receipts against their due.'
                  : 'The customer pays the finance company. Track it here to follow up and remind on time.',
              style: _j(11.5, FontWeight.w500, _muted),
            ),
            if (kind == 'finance') ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in financers) _chip(f, financer == f, () => setState(() => financer = f)),
              ]),
            ],
          ]),
          _section('Device', [
            field(product, 'Product (e.g. Vivo Y28 8/128)'),
            field(imei, 'IMEI / serial'),
            field(opp, 'Opportunity ID'),
            if (kind == 'finance') field(loan, 'Loan / agreement number'),
          ]),
          _section('Amount', [
            Row(children: [
              Expanded(child: field(price, 'Price ₹', number: true)),
              const SizedBox(width: 10),
              Expanded(child: field(down, 'Down payment ₹', number: true)),
            ]),
            Text('Tenure', style: _j(12.5, FontWeight.w800, const Color(0xFF323B60))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [3, 4, 6, 8, 9, 10, 12, 18, 24])
                _chip('$m mo', months == m, () {
                  setState(() => months = m);
                  _auto();
                }),
            ]),
            const SizedBox(height: 12),
            field(emi, 'EMI per month ₹', number: true, onChanged: (_) => setState(() => emiTouched = true)),
            DateField(label: 'First EMI date', value: start, onChanged: (v) => setState(() => start = v)),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFE7F6F4), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${Money.rs(e)} × $months = ${Money.rs(total)}', style: _j(14, FontWeight.w800, const Color(0xFF0E7490))),
                if (financed > 0 && total > financed)
                  Text('Interest / charges ${Money.rs(total - financed)} on ${Money.rs(financed)} financed',
                      style: _j(11.5, FontWeight.w600, _muted)),
                Text(
                    'Last EMI ${prettyDate(ymd(addMonths(DateTime.parse(start), months - 1)))} · phone reminder before each due date',
                    style: _j(11.5, FontWeight.w600, _muted)),
              ]),
            ),
          ]),
          field(note, 'Note (optional)'),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _save,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: _grad),
                boxShadow: const [BoxShadow(color: Color(0x770E7490), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
              ),
              child: Text(busy ? 'Saving…' : 'Create EMI plan', style: _j(16, FontWeight.w800, Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}
