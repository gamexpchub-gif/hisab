import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/imei_smart.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'emi.dart';
import 'sale_pos.dart';
import 'sale_view.dart';
import 'scanner.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF0BA360);
const _red = Color(0xFFE0245E);
const _amber = Color(0xFFF97316);
const _purple = Color(0xFF4318D2);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

BoxDecoration _card() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x0F1B2163), blurRadius: 16, offset: Offset(0, 6))],
    );

Widget _hero(String title, String sub, IconData icon, List<Color> colors) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(colors: colors)),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _j(17, FontWeight.w800, Colors.white)),
            const SizedBox(height: 3),
            Text(sub, style: _j(12, FontWeight.w500, const Color(0xD9FFFFFF))),
          ]),
        ),
      ]),
    );

Future<int?> _pickAccount(BuildContext context, {String title = 'Paid from / into'}) async {
  final accounts = await Books.moneyAccounts();
  if (!context.mounted) return null;
  if (accounts.length == 1) return asInt(accounts.first['id']);
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: _j(16, FontWeight.w800, _ink))),
        for (final a in accounts)
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_rounded, color: _purple),
            title: Text('${a['name']}'),
            onTap: () => Navigator.pop(c, asInt(a['id'])),
          ),
      ]),
    ),
  );
}

InputDecoration _dec(String label, {String? prefix, Widget? suffix}) => InputDecoration(labelText: label, prefixText: prefix, suffixIcon: suffix);

// =============================================================================
// Repairs
// =============================================================================
class RepairsScreen extends StatefulWidget {
  const RepairsScreen({super.key});
  @override
  State<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends State<RepairsScreen> {
  String filter = 'open';

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Repair jobs',
      subtitle: 'Job cards · status · ready message · billing',
      fab: FloatingActionButton.extended(
        backgroundColor: _purple,
        onPressed: () => open(context, const RepairForm()),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New job', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      children: [
        Live<(List<Rec>, Map<String, String>)>(
          reloadKey: filter,
          load: () async => (await Shop.repairs(status: filter == 'all' ? null : filter), await Books.settings()),
          builder: (context, d) {
            final (list, settings) = d;
            final ready = list.where((r) => r['status'] == 'ready').length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              _hero(
                filter == 'open' ? '${list.length} job${list.length == 1 ? '' : 's'} in the shop' : '${list.length} job${list.length == 1 ? '' : 's'}',
                ready > 0 ? '$ready ready for pickup — send the "ready" message' : 'Take in a device, update the status, deliver and bill',
                Icons.build_circle_rounded,
                const [Color(0xFF0E7490), Color(0xFF4318D2)],
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: [
                for (final f in const [('open', 'In shop'), ('ready', 'Ready'), ('delivered', 'Delivered'), ('all', 'All')])
                  ChoiceChip(label: Text(f.$2), selected: filter == f.$1, onSelected: (_) => setState(() => filter = f.$1)),
              ]),
              for (final r in list) _jobCard(r, settings),
              if (list.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('No repair jobs here — tap New job')),
              const SizedBox(height: 80),
            ]);
          },
        ),
      ],
    );
  }

  Widget _jobCard(Rec r, Map<String, String> settings) {
    final st = '${r['status']}';
    final color = switch (st) { 'ready' => _green, 'delivered' => _muted, 'cancelled' => _red, 'waiting_parts' => _amber, _ => _purple };
    final late = r['promised'] != null && st != 'delivered' && '${r['promised']}'.compareTo(ymd(DateTime.now())) < 0;
    return GestureDetector(
      onTap: () => open(context, RepairView(id: asInt(r['id']))),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: _card(),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withAlpha(0x1F), borderRadius: BorderRadius.circular(14)),
            child: Icon(st == 'ready' ? Icons.check_circle_rounded : Icons.phonelink_setup_rounded, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['device']} · ${r['customer'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
              Text('${r['number']} · ${r['problem']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w500, _muted)),
              if (late) Text('Promised ${prettyDate('${r['promised']}')} — late', style: _j(11, FontWeight.w700, _red)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withAlpha(0x1F), borderRadius: BorderRadius.circular(10)),
            child: Text(Shop.repairLabels[st] ?? st, style: _j(11, FontWeight.w800, color)),
          ),
        ]),
      ),
    );
  }
}

class RepairForm extends StatefulWidget {
  const RepairForm({super.key});
  @override
  State<RepairForm> createState() => _RepairFormState();
}

class _RepairFormState extends State<RepairForm> {
  final name = TextEditingController(), phone = TextEditingController(), device = TextEditingController(), imei = TextEditingController();
  final problem = TextEditingController(), condition = TextEditingController(), lock = TextEditingController();
  final estimate = TextEditingController(), advance = TextEditingController(), tech = TextEditingController();
  String? promised = ymd(DateTime.now().add(const Duration(days: 2)));
  bool saving = false;
  static const problems = ['Screen broken', 'Battery', 'Charging port', 'Not switching on', 'Speaker / mic', 'Water damage', 'Software / FRP', 'Camera'];

  @override
  void dispose() {
    for (final c in [name, phone, device, imei, problem, condition, lock, estimate, advance, tech]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanImei() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI');
    if (code == null || !mounted) return;
    imei.text = SmartImei.clean(code);
    final m = await SmartImei.match(imei.text);
    if (!mounted) return;
    if (device.text.trim().isEmpty) device.text = m.product?['name'] as String? ?? m.suggestName ?? '';
    final sold = m.soldOn;
    if (sold != null) {
      toast(context, 'Sold by you on ${prettyDate('${sold['date']}')} (${sold['number']}) — check the warranty');
      final c = await Books.query('SELECT c.name, c.phone FROM sales s JOIN customers c ON c.id = s.customer_id WHERE s.id = ?', [sold['doc_id']]);
      if (c.isNotEmpty && mounted) {
        setState(() {
          if (name.text.isEmpty) name.text = '${c.first['name']}';
          if (phone.text.isEmpty) phone.text = '${c.first['phone'] ?? ''}';
        });
      }
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final cid = await Shop.customerFor(name.text, phone.text);
      final adv = Money.tryParse(advance.text) ?? 0;
      int? acc;
      if (adv > 0) {
        acc = await _pickAccount(context, title: 'Advance received in');
        if (acc == null) {
          setState(() => saving = false);
          return;
        }
      }
      final id = await Shop.createRepair(
        customerId: cid,
        device: device.text,
        imei: imei.text,
        problem: problem.text,
        condition: condition.text,
        lockCode: lock.text,
        estimate: Money.tryParse(estimate.text) ?? 0,
        advance: adv,
        accountId: acc,
        promised: promised,
        technician: tech.text,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      open(context, RepairView(id: id, justCreated: true));
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'New repair job',
      subtitle: 'Customer, device and problem — a job number is given',
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _card(),
          child: Column(children: [
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: _dec('Customer phone')),
            const SizedBox(height: 8),
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: _dec('Customer name')),
            const SizedBox(height: 8),
            TextField(
              controller: imei,
              decoration: _dec('IMEI / serial (optional)',
                  suffix: IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: _purple), onPressed: _scanImei)),
            ),
            const SizedBox(height: 8),
            TextField(controller: device, textCapitalization: TextCapitalization.words, decoration: _dec('Device (e.g. Redmi Note 12)')),
            const SizedBox(height: 8),
            TextField(controller: problem, maxLines: 2, decoration: _dec('Problem')),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final p in problems)
                ActionChip(
                  label: Text(p, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => setState(() => problem.text = problem.text.trim().isEmpty ? p : '${problem.text.trim()}, $p'),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: condition, decoration: _dec('Condition on receipt (scratches, missing parts…)')),
            const SizedBox(height: 8),
            TextField(controller: lock, decoration: _dec('Screen lock / pattern (optional)')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: estimate, keyboardType: TextInputType.number, decoration: _dec('Estimate', prefix: '₹ '))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: advance, keyboardType: TextInputType.number, decoration: _dec('Advance', prefix: '₹ '))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: tech, textCapitalization: TextCapitalization.words, decoration: _dec('Technician (optional)')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_rounded, color: _purple),
              title: Text(promised == null ? 'Ready by — not set' : 'Ready by ${prettyDate(promised!)}'),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: DateTime.now().add(const Duration(days: 2)), firstDate: DateTime.now(), lastDate: DateTime(2100));
                if (d != null) setState(() => promised = ymd(d));
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: _purple),
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.assignment_turned_in_rounded),
          label: Text(saving ? 'Saving…' : 'Create job card'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class RepairView extends StatefulWidget {
  final int id;
  final bool justCreated;
  const RepairView({super.key, required this.id, this.justCreated = false});
  @override
  State<RepairView> createState() => _RepairViewState();
}

class _RepairViewState extends State<RepairView> {
  int _reload = 0;

  Future<(Rec, Map<String, String>)> _load() async => (
        (await Books.query('SELECT r.*, c.name AS customer, c.phone FROM repairs r LEFT JOIN customers c ON c.id = r.customer_id WHERE r.id = ?',
                [widget.id]))
            .first,
        await Books.settings(),
      );

  Future<void> _status(String s) async {
    await Shop.repairStatus(widget.id, s);
    HapticFeedback.selectionClick();
    setState(() => _reload++);
  }

  Future<void> _deliver(Rec r) async {
    final charge = TextEditingController(text: Money.edit(asInt(r['charge']) > 0 ? asInt(r['charge']) : asInt(r['estimate'])));
    final parts = TextEditingController(text: asInt(r['parts_cost']) > 0 ? Money.edit(asInt(r['parts_cost'])) : '');
    final paid = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final due = (Money.tryParse(charge.text) ?? 0) - asInt(r['advance']);
          if (paid.text.isEmpty && due > 0) paid.text = Money.edit(due);
          return AlertDialog(
            title: const Text('Deliver & bill'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: charge, keyboardType: TextInputType.number, onChanged: (_) => set(() {}), decoration: _dec('Repair charge', prefix: '₹ ')),
              TextField(controller: parts, keyboardType: TextInputType.number, decoration: _dec('Parts cost (for profit)', prefix: '₹ ')),
              const SizedBox(height: 8),
              Text('Advance paid ${Money.rs(asInt(r['advance']))} · balance ${Money.rs(due < 0 ? 0 : due)}', style: _j(12, FontWeight.w700, _muted)),
              TextField(controller: paid, keyboardType: TextInputType.number, decoration: _dec('Paid now', prefix: '₹ ')),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Deliver')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final now = Money.tryParse(paid.text) ?? 0;
    int? acc;
    if (now > 0) {
      acc = await _pickAccount(context, title: 'Payment received in');
      if (acc == null) return;
    }
    try {
      final left = await Shop.deliverRepair(widget.id,
          charge: Money.tryParse(charge.text) ?? 0, partsCost: Money.tryParse(parts.text) ?? 0, paidNow: now, accountId: acc);
      if (!mounted) return;
      toast(context, left > 0 ? 'Delivered · ${Money.rs(left)} on the customer\'s account' : 'Delivered and paid ✓');
      setState(() => _reload++);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Live<(Rec, Map<String, String>)>(
      reloadKey: _reload,
      load: _load,
      builder: (context, d) {
        final (r, s) = d;
        final st = '${r['status']}';
        final steps = Shop.repairSteps;
        final at = steps.indexOf(st);
        return PageShell(
          title: '${r['number']}',
          subtitle: '${r['device']} · ${r['customer'] ?? ''}',
          children: [
            const SizedBox(height: 8),
            if (widget.justCreated)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFE3F7EC), borderRadius: BorderRadius.circular(16)),
                child: Text('Job created ✓ — send the job number to the customer on WhatsApp', style: _j(12.5, FontWeight.w700, _green)),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Status', style: _j(14, FontWeight.w800, _ink)),
                const SizedBox(height: 10),
                for (var i = 0; i < steps.length; i++)
                  InkWell(
                    onTap: st == 'delivered' || steps[i] == 'delivered' ? null : () => _status(steps[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Icon(i < at || st == 'delivered' ? Icons.check_circle_rounded : i == at ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: i <= at || st == 'delivered' ? _green : const Color(0xFFCBD5E1), size: 22),
                        const SizedBox(width: 10),
                        Text(Shop.repairLabels[steps[i]]!, style: _j(13.5, i == at ? FontWeight.w800 : FontWeight.w600, i <= at ? _ink : _muted)),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (l, v) in [
                  ('Customer', '${r['customer'] ?? ''}${(r['phone'] ?? '').toString().isEmpty ? '' : ' · ${r['phone']}'}'),
                  ('Problem', '${r['problem']}'),
                  if ((r['imei'] ?? '').toString().isNotEmpty) ('IMEI', '${r['imei']}'),
                  if ((r['condition'] ?? '').toString().isNotEmpty) ('Condition', '${r['condition']}'),
                  if ((r['lock_code'] ?? '').toString().isNotEmpty) ('Lock', '${r['lock_code']}'),
                  ('Received', prettyDate('${r['date']}')),
                  if (r['promised'] != null) ('Ready by', prettyDate('${r['promised']}')),
                  ('Estimate', Money.rs(asInt(r['estimate']))),
                  ('Advance', Money.rs(asInt(r['advance']))),
                  if (asInt(r['charge']) > 0) ('Charge', Money.rs(asInt(r['charge']))),
                  if (asInt(r['parts_cost']) > 0) ('Profit', Money.rs(asInt(r['charge']) - asInt(r['parts_cost']))),
                  if ((r['technician'] ?? '').toString().isNotEmpty) ('Technician', '${r['technician']}'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 92, child: Text(l, style: _j(12, FontWeight.w600, _muted))),
                      Expanded(child: Text(v, style: _j(13, FontWeight.w700, _ink))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => Contact.whatsapp(r['phone'] as String?, Shop.repairMessage(s, r)),
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF128C7E)),
                  label: Text(st == 'ready' ? 'Send "ready"' : 'Send job slip'),
                ),
              ),
              const SizedBox(width: 8),
              if (st != 'delivered' && st != 'cancelled')
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _green),
                    onPressed: () => _deliver(r),
                    icon: const Icon(Icons.handshake_rounded),
                    label: const Text('Deliver & bill'),
                  ),
                ),
            ]),
            if (st != 'delivered' && st != 'cancelled')
              TextButton(onPressed: () => _status('cancelled'), child: const Text('Cancel job', style: TextStyle(color: _red))),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Exchange / used phones
// =============================================================================
class ExchangeScreen extends StatelessWidget {
  const ExchangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Exchange & used phones',
      subtitle: 'Buy old phones, resell them, see the profit',
      fab: FloatingActionButton.extended(
        backgroundColor: _purple,
        onPressed: () => open(context, const ExchangeForm()),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Buy used phone', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      children: [
        Live<List<Rec>>(
          load: Shop.exchanges,
          builder: (context, list) {
            final inStock = list.where((e) => asInt(e['stock']) > 0).toList();
            final value = inStock.fold<int>(0, (a, e) => a + asInt(e['price']));
            final sold = list.where((e) => e['sold_for'] != null && asInt(e['stock']) <= 0).toList();
            final profit = sold.fold<int>(0, (a, e) => a + asInt(e['sold_for']) - asInt(e['price']));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              _hero('${inStock.length} used phone${inStock.length == 1 ? '' : 's'} in stock', 'Bought for ${Money.rs(value)} · profit on resold phones ${Money.rs(profit)}',
                  Icons.swap_horizontal_circle_rounded, const [Color(0xFFF97316), Color(0xFFE0245E)]),
              for (final e in list)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: _card(),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.phone_android_rounded, color: _amber),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${e['model']}${e['grade'] == null ? '' : ' · Grade ${e['grade']}'}', style: _j(13.5, FontWeight.w800, _ink)),
                        Text(
                          '${e['number']} · from ${e['customer'] ?? '—'} · ${prettyDate('${e['date']}')}'
                          '${e['battery'] == null ? '' : ' · battery ${e['battery']}%'}',
                          style: _j(11.5, FontWeight.w500, _muted),
                        ),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(Money.rs(asInt(e['price'])), style: _j(13.5, FontWeight.w800, _ink)),
                      Text(
                        asInt(e['stock']) > 0
                            ? 'In stock'
                            : e['sold_for'] == null
                                ? 'Out'
                                : 'Sold +${Money.compact(asInt(e['sold_for']) - asInt(e['price']))}',
                        style: _j(11, FontWeight.w800, asInt(e['stock']) > 0 ? _purple : _green),
                      ),
                    ]),
                  ]),
                ),
              if (list.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('No used phones yet — tap Buy used phone')),
              const SizedBox(height: 80),
            ]);
          },
        ),
      ],
    );
  }
}

class ExchangeForm extends StatefulWidget {
  const ExchangeForm({super.key});
  @override
  State<ExchangeForm> createState() => _ExchangeFormState();
}

class _ExchangeFormState extends State<ExchangeForm> {
  final name = TextEditingController(), phone = TextEditingController(), model = TextEditingController(), brand = TextEditingController();
  final imei = TextEditingController(), price = TextEditingController(), resale = TextEditingController(), battery = TextEditingController();
  final accessories = TextEditingController(), idProof = TextEditingController(), note = TextEditingController();
  String grade = 'B';
  String? photo;
  bool saving = false;

  @override
  void dispose() {
    for (final c in [name, phone, model, brand, imei, price, resale, battery, accessories, idProof, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI of the old phone');
    if (code == null || !mounted) return;
    imei.text = SmartImei.clean(code);
    final m = await SmartImei.match(imei.text);
    if (!mounted) return;
    setState(() {
      if (model.text.trim().isEmpty) model.text = m.product?['name'] as String? ?? m.suggestName ?? '';
      if (brand.text.trim().isEmpty) brand.text = m.product?['brand'] as String? ?? m.suggestBrand ?? '';
    });
    if (m.soldOn != null) toast(context, 'You sold this phone on ${prettyDate('${m.soldOn!['date']}')} (${m.soldOn!['number']})');
    if (m.isImei && !m.valid) toast(context, 'IMEI check digit is wrong — check the number', error: true);
  }

  Future<void> _save({bool sellNew = false}) async {
    if (saving) return;
    final p = Money.tryParse(price.text) ?? 0;
    if (p <= 0) {
      toast(context, 'Enter the price you pay', error: true);
      return;
    }
    final acc = await _pickAccount(context, title: 'Paid from');
    if (acc == null || !mounted) return;
    setState(() => saving = true);
    try {
      final id = await Shop.buyUsed(
        sellerName: name.text,
        sellerPhone: phone.text,
        model: model.text,
        brand: brand.text,
        imei: imei.text,
        price: p,
        resale: Money.tryParse(resale.text) ?? 0,
        grade: grade,
        battery: int.tryParse(battery.text.trim()),
        accessories: accessories.text,
        idProof: idProof.text,
        photo: photo,
        note: note.text,
        accountId: acc,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final e = (await Books.query('SELECT * FROM exchanges WHERE id = ?', [id])).first;
      if (!mounted) return;
      Navigator.pop(context);
      if (sellNew) {
        open(context, SaleForm(customerId: asInt(e['customer_id'])));
        toast(context, 'Old phone bought for ${Money.rs(p)} — take ${Money.rs(p)} less cash on the new phone');
      } else {
        toast(context, '${e['model']} bought · in stock as a used phone');
      }
    } catch (err) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, '$err', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Buy used phone',
      subtitle: 'Exchange or second-hand purchase from a customer',
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _card(),
          child: Column(children: [
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: _dec('Seller phone')),
            const SizedBox(height: 8),
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: _dec('Seller name')),
            const SizedBox(height: 8),
            TextField(controller: idProof, decoration: _dec('ID proof (Aadhaar / voter ID no.)')),
            const SizedBox(height: 8),
            TextField(
              controller: imei,
              decoration: _dec('IMEI', suffix: IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: _purple), onPressed: _scan)),
            ),
            const SizedBox(height: 8),
            TextField(controller: model, textCapitalization: TextCapitalization.words, decoration: _dec('Model (e.g. iPhone 11 64GB)')),
            const SizedBox(height: 8),
            TextField(controller: brand, textCapitalization: TextCapitalization.words, decoration: _dec('Brand')),
            const SizedBox(height: 10),
            Row(children: [
              Text('Grade', style: _j(13, FontWeight.w700, _ink)),
              const SizedBox(width: 10),
              for (final g in const ['A', 'B', 'C', 'D'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(g), selected: grade == g, onSelected: (_) => setState(() => grade = g)),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: battery, keyboardType: TextInputType.number, decoration: _dec('Battery health %'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: accessories, decoration: _dec('Box / charger…'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: _dec('Price paid', prefix: '₹ '))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: resale, keyboardType: TextInputType.number, decoration: _dec('Resale price', prefix: '₹ '))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: _dec('Note (faults, repairs needed…)')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_camera_rounded, color: _purple),
              title: Text(photo == null ? 'Add a photo of the phone' : 'Photo added ✓'),
              onTap: () async {
                final p = await pickPhoto(context, folder: 'exchange');
                if (p != null) setState(() => photo = p);
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: _amber),
          onPressed: saving ? null : () => _save(sellNew: true),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Buy & sell a new phone (exchange)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: saving ? null : () => _save(),
          icon: const Icon(Icons.shopping_bag_rounded),
          label: const Text('Only buy (second-hand stock)'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// =============================================================================
// Finance companies
// =============================================================================
class FinancePayoutsScreen extends StatefulWidget {
  const FinancePayoutsScreen({super.key});
  @override
  State<FinancePayoutsScreen> createState() => _FinancePayoutsScreenState();
}

class _FinancePayoutsScreenState extends State<FinancePayoutsScreen> {
  int _reload = 0;

  Future<void> _received(Rec e) async {
    final amount = TextEditingController(text: Money.edit(asInt(e['expected'])));
    var post = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Payout from ${e['financer'] ?? 'finance company'}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: _dec('Amount received', prefix: '₹ ')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: post,
              onChanged: (v) => set(() => post = v),
              title: const Text('Book it as a receipt'),
              subtitle: Text(post ? 'Clears ${e['customer']}\'s bill' : 'Only mark it — the sale was already entered as paid'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Received')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    int? acc;
    if (post) {
      acc = await _pickAccount(context, title: 'Received in (bank)');
      if (acc == null) return;
    }
    try {
      await Shop.financeReceivedOn(asInt(e['id']), Money.tryParse(amount.text) ?? 0, accountId: acc, post: post);
      if (mounted) {
        toast(context, 'Payout recorded ✓');
        setState(() => _reload++);
      }
    } catch (err) {
      if (mounted) toast(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Finance payouts',
      subtitle: 'Bajaj, HDB, TVS Credit… money still to come',
      children: [
        Live<(List<Rec>, List<Rec>)>(
          reloadKey: _reload,
          load: () async => (await Shop.financePending(), await Shop.financeReceived()),
          builder: (context, d) {
            final (pending, done) = d;
            final groups = <String, List<Rec>>{};
            for (final e in pending) {
              groups.putIfAbsent('${e['financer'] ?? 'Finance company'}', () => []).add(e);
            }
            final total = pending.fold<int>(0, (a, e) => a + asInt(e['expected']));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              _hero(pending.isEmpty ? 'No payout pending 🎉' : '${Money.rs(total)} to receive',
                  pending.isEmpty ? 'Finance sales appear here until the company pays you' : '${pending.length} sale${pending.length == 1 ? '' : 's'} · ${groups.length} compan${groups.length == 1 ? 'y' : 'ies'}',
                  Icons.account_balance_rounded, const [Color(0xFF2DD4BF), Color(0xFF0E7490)]),
              for (final g in groups.entries)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: _card(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(g.key, style: _j(15, FontWeight.w800, _ink))),
                      Text(Money.rs(g.value.fold<int>(0, (a, e) => a + asInt(e['expected']))), style: _j(14, FontWeight.w800, _purple)),
                    ]),
                    const Divider(),
                    for (final e in g.value)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => open(context, EmiPlanView(id: asInt(e['id']))),
                        title: Text('${e['customer']} · ${e['product'] ?? ''}', style: _j(13, FontWeight.w700, _ink)),
                        subtitle: Text(
                          [
                            if (e['sale_no'] != null) '${e['sale_no']}',
                            if ((e['loan_no'] ?? e['opp_id']) != null) 'ref ${e['loan_no'] ?? e['opp_id']}',
                            'since ${prettyDate('${e['sale_date'] ?? e['start_date']}')}',
                          ].join(' · '),
                          style: _j(11, FontWeight.w500, _muted),
                        ),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _green, visualDensity: VisualDensity.compact),
                          onPressed: () => _received(e),
                          child: Text(Money.compact(asInt(e['expected']))),
                        ),
                      ),
                  ]),
                ),
              if (done.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text('Received', style: _j(15, FontWeight.w800, _ink))),
                Container(
                  decoration: _card(),
                  child: Column(children: [
                    for (final e in done.take(20))
                      ListTile(
                        dense: true,
                        title: Text('${e['customer']} · ${e['financer'] ?? ''}', style: _j(12.5, FontWeight.w700, _ink)),
                        subtitle: Text(prettyDate('${e['disbursed_on']}'), style: _j(11, FontWeight.w500, _muted)),
                        trailing: Text(Money.rs(asInt(e['disbursed_amount'])), style: _j(12.5, FontWeight.w800, _green)),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 40),
            ]);
          },
        ),
      ],
    );
  }
}

// =============================================================================
// IMEI timeline
// =============================================================================
class DeviceTimeline extends StatelessWidget {
  final String imei;
  const DeviceTimeline(this.imei, {super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<DeviceEvent>>(
      reloadKey: imei,
      load: () => Shop.imeiHistory(imei),
      builder: (context, events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.timeline_rounded, color: _purple),
              const SizedBox(width: 8),
              Text('Full history', style: _j(15, FontWeight.w800, _ink)),
            ]),
            const SizedBox(height: 10),
            for (var i = 0; i < events.length; i++) _row(context, events[i], last: i == events.length - 1),
          ]),
        );
      },
    );
  }

  Widget _row(BuildContext context, DeviceEvent e, {required bool last}) {
    final (icon, color) = switch (e.kind) {
      'bought' => (Icons.download_rounded, const Color(0xFF2563EB)),
      'sold' => (Icons.sell_rounded, _green),
      'returned' => (Icons.undo_rounded, _red),
      'exchange' => (Icons.swap_horiz_rounded, _amber),
      'repair' => (Icons.build_rounded, _purple),
      'emi' => (Icons.calendar_month_rounded, const Color(0xFF0E7490)),
      _ => (Icons.verified_user_rounded, const Color(0xFF64748B)),
    };
    return InkWell(
      onTap: e.targetId == null
          ? null
          : () {
              switch (e.target) {
                case 'sale':
                  open(context, SaleView(id: e.targetId!));
                case 'repair':
                  open(context, RepairView(id: e.targetId!));
                case 'emi':
                  open(context, EmiPlanView(id: e.targetId!));
              }
            },
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withAlpha(0x1F), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            if (!last) Expanded(child: Container(width: 2, color: const Color(0xFFE2E8F0))),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e.title} · ${prettyDate(e.date)}', style: _j(13, FontWeight.w800, _ink)),
                Text(e.detail, style: _j(11.5, FontWeight.w500, _muted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
