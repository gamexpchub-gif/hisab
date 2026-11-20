import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/imei_smart.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'sale_pos.dart';
import 'sale_view.dart';
import 'scanner.dart';
import 'shop_work.dart' show DeviceTimeline;

// =============================================================================
// Exchange & used phones
//   · Exchanges  — who gave which old phone and took which new phone
//   · Used stock — old phones in stock (grade, battery, days, resale)
//   · Sellers    — customers who sold / exchanged phones (add like parties)
//   ExchangeForm — seller (pick or add customer), old phone (IMEI scan,
//   brand, model, storage, colour, grade, battery), checks, accessories,
//   photos + ID, price → only buy, or open the bill for the new phone.
//   ExchangeView — everything about one exchange.
// =============================================================================

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _green = Color(0xFF0BA360);
const _red = Color(0xFFE0245E);
const _amber = Color(0xFFF97316);
const _purple = Color(0xFF4318D2);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

BoxDecoration _card({Color? border}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border ?? const Color(0xFFF0F1F8)),
      boxShadow: const [BoxShadow(color: Color(0x0F1B2163), blurRadius: 16, offset: Offset(0, 6))],
    );

const _brands = [
  'Apple',
  'Samsung',
  'Vivo',
  'Oppo',
  'Realme',
  'Xiaomi',
  'OnePlus',
  'iQOO',
  'Poco',
  'Motorola',
  'Nothing',
  'Google',
  'Infinix',
  'Tecno',
  'Nokia'
];
const _storages = ['3/32', '4/64', '4/128', '6/128', '8/128', '8/256', '12/256', '12/512', '64GB', '128GB', '256GB', '512GB'];
const _checks = [
  'Screen OK',
  'Touch OK',
  'Body OK',
  'Camera OK',
  'Face / finger lock OK',
  'Charging OK',
  'Speaker & mic OK',
  'Network / SIM OK',
  'No iCloud / Google lock',
  'Not stolen (IMEI OK)',
];
const _accessories = ['Box', 'Charger', 'Cable', 'Bill', 'Earphones', 'Cover'];
const _grades = {
  'A': 'Like new · no marks',
  'B': 'Light marks · all working',
  'C': 'Visible wear · small issues',
  'D': 'Faulty · for parts / repair',
};

Color _gradeColor(String? g) => switch (g) {
      'A' => _green,
      'B' => const Color(0xFF2563EB),
      'C' => _amber,
      _ => _red,
    };

Widget _gradeBadge(String? g) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: _gradeColor(g).withAlpha(0x1F), borderRadius: BorderRadius.circular(8)),
      child: Text('Grade ${g ?? '—'}', style: _j(10.5, FontWeight.w800, _gradeColor(g))),
    );

Future<int?> _pickAccount(BuildContext context, {String title = 'Paid from'}) async {
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

// =============================================================================
// Main screen
// =============================================================================
class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});
  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeData {
  final List<Rec> all, sellers;
  _ExchangeData(this.all, this.sellers);
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  int tab = 0;
  String q = '';

  bool _match(Rec e) {
    if (q.isEmpty) return true;
    final hay =
        '${e['model']} ${e['brand'] ?? ''} ${e['imei'] ?? ''} ${e['customer'] ?? ''} ${e['phone'] ?? ''} ${e['number']} ${e['new_phone'] ?? ''}'.toLowerCase();
    return q.toLowerCase().split(' ').every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Exchange & used phones',
      subtitle: 'Old phone in · new phone out · resale profit',
      fab: FloatingActionButton.extended(
        backgroundColor: _purple,
        onPressed: () => open(context, const ExchangeForm()),
        icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
        label: const Text('New exchange', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      children: [
        Live<_ExchangeData>(
          load: () async => _ExchangeData(await Shop.exchanges(), await Shop.sellers()),
          builder: (context, d) {
            final inStock = d.all.where((e) => asInt(e['stock']) > 0).toList();
            final stockValue = inStock.fold<int>(0, (a, e) => a + asInt(e['price']));
            final sold = d.all.where((e) => e['sold_for'] != null && asInt(e['stock']) <= 0).toList();
            final profit = sold.fold<int>(0, (a, e) => a + asInt(e['sold_for']) - asInt(e['price']));
            final month = ymd(DateTime.now()).substring(0, 7);
            final thisMonth = d.all.where((e) => '${e['date']}'.startsWith(month)).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(colors: [Color(0xFFFFA24A), Color(0xFFE0245E)]),
                  boxShadow: const [BoxShadow(color: Color(0x55E0245E), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -10)],
                ),
                child: Row(children: [
                  for (final (v, l) in [
                    ('${inStock.length}', 'In stock'),
                    (Money.compact(stockValue), 'Stock value'),
                    ('$thisMonth', 'This month'),
                    (Money.compact(profit), 'Resale profit'),
                  ])
                    Expanded(
                      child: Column(children: [
                        Text(v, style: _j(18, FontWeight.w800, Colors.white)),
                        const SizedBox(height: 2),
                        Text(l, style: _j(10.5, FontWeight.w600, const Color(0xE6FFFFFF))),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23), border: Border.all(color: _line)),
                child: Row(children: [
                  for (final (k, l) in [(0, 'Exchanges · ${d.all.length}'), (1, 'Used stock · ${inStock.length}'), (2, 'Sellers · ${d.sellers.length}')])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => tab = k),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(19),
                            gradient: tab == k ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                          ),
                          child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w800, tab == k ? Colors.white : _ink)),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => q = v.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tab == 2 ? 'Search seller' : 'Search model, IMEI, customer',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
                ),
              ),
              if (tab == 0) ...[
                for (final e in d.all.where(_match)) _ExchangeTile(e),
                if (d.all.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('No exchanges yet — tap New exchange')),
              ],
              if (tab == 1) ...[
                for (final e in inStock.where(_match)) _StockTile(e),
                if (inStock.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('No used phones in stock')),
              ],
              if (tab == 2) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => open(context, const PartyForm(type: 'customer')),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add seller / customer'),
                ),
                for (final c in d.sellers.where((c) => q.isEmpty || '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase())))
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    decoration: _card(),
                    child: ListTile(
                      onTap: () => open(context, PartyView(type: 'customer', id: asInt(c['id']))),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFFFF1E6),
                        child: ClipOval(
                          child: storedImage(c['photo'] as String?,
                              fallback: Text('${c['name']}'.isEmpty ? '?' : '${c['name']}'[0].toUpperCase(), style: _j(16, FontWeight.w800, _amber))),
                        ),
                      ),
                      title: Text('${c['name']}', style: _j(14, FontWeight.w800, _ink)),
                      subtitle: Text(
                          '${c['phone'] ?? 'No phone'} · ${c['phones']} phone${asInt(c['phones']) == 1 ? '' : 's'} · ${(c['aadhaar'] ?? '').toString().isEmpty ? 'no ID on file' : 'ID ✓'}',
                          style: _j(11.5, FontWeight.w500, _muted)),
                      trailing: Text(Money.rs(asInt(c['paid'])), style: _j(13, FontWeight.w800, _ink)),
                    ),
                  ),
                if (d.sellers.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('Sellers appear here after the first exchange')),
              ],
              const SizedBox(height: 90),
            ]);
          },
        ),
      ],
    );
  }
}

class _ExchangeTile extends StatelessWidget {
  final Rec e;
  const _ExchangeTile(this.e);

  @override
  Widget build(BuildContext context) {
    final took = e['new_phone'] as String?;
    return GestureDetector(
      onTap: () => open(context, ExchangeView(id: asInt(e['id']))),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('${e['number']}', style: _j(11.5, FontWeight.w800, _purple)),
            Text('  ·  ${prettyDate('${e['date']}')}', style: _j(11.5, FontWeight.w600, _muted)),
            const Spacer(),
            Text('${e['customer'] ?? '—'}', style: _j(12, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _phoneBox('GAVE', '${e['model']}', Money.rs(asInt(e['price'])), const Color(0xFFFFF1E6), _amber, e['photo'] as String?)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, color: _muted, size: 20)),
            Expanded(
              child: took == null
                  ? _phoneBox('TOOK', 'Only bought', 'no new phone', const Color(0xFFF4F5FB), _muted, null)
                  : _phoneBox('TOOK', took, '${e['new_bill'] ?? ''}', const Color(0xFFEAF8F1), _green, null),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _phoneBox(String tag, String title, String sub, Color bg, Color fg, String? photo) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
            width: 34,
            height: 40,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
            clipBehavior: Clip.antiAlias,
            child: storedImage(photo, fallback: Icon(Icons.phone_android_rounded, color: fg, size: 20)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tag, style: _j(9.5, FontWeight.w800, fg).copyWith(letterSpacing: 1)),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w800, _ink)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w600, _muted)),
            ]),
          ),
        ]),
      );
}

class _StockTile extends StatelessWidget {
  final Rec e;
  const _StockTile(this.e);

  @override
  Widget build(BuildContext context) {
    final days = DateTime.now().difference(DateTime.tryParse('${e['date']}') ?? DateTime.now()).inDays;
    final resale = asInt(e['resale']) > 0 ? asInt(e['resale']) : (asInt(e['price']) * 1.15).round();
    return GestureDetector(
      onTap: () => open(context, ExchangeView(id: asInt(e['id']))),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: _card(border: days > 30 ? const Color(0xFFFFD9B8) : null),
        child: Row(children: [
          Container(
            width: 48,
            height: 56,
            decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: storedImage(e['photo'] as String?, fallback: const Icon(Icons.phone_android_rounded, color: _amber)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('${e['model']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink))),
                const SizedBox(width: 6),
                _gradeBadge(e['grade'] as String?),
              ]),
              Text(
                [
                  if ((e['storage'] ?? '').toString().isNotEmpty) '${e['storage']}',
                  if ((e['color'] ?? '').toString().isNotEmpty) '${e['color']}',
                  if (e['battery'] != null) 'battery ${e['battery']}%',
                  '$days day${days == 1 ? '' : 's'} in stock',
                ].join(' · '),
                style: _j(11, FontWeight.w500, days > 30 ? _amber : _muted),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Money.rs(resale), style: _j(14, FontWeight.w800, _ink)),
            Text('bought ${Money.compact(asInt(e['price']))}', style: _j(10.5, FontWeight.w600, _muted)),
          ]),
        ]),
      ),
    );
  }
}

// =============================================================================
// New exchange
// =============================================================================
class ExchangeForm extends StatefulWidget {
  final int? customerId;
  const ExchangeForm({super.key, this.customerId});
  @override
  State<ExchangeForm> createState() => _ExchangeFormState();
}

class _ExchangeFormState extends State<ExchangeForm> {
  Rec? seller;
  final model = TextEditingController(), brand = TextEditingController(), imei = TextEditingController(), color = TextEditingController();
  final price = TextEditingController(), resale = TextEditingController(), battery = TextEditingController();
  final idProof = TextEditingController(), note = TextEditingController();
  String grade = 'B';
  String? storage, photo, idPhoto, imeiNote;
  bool imeiBad = false;
  final checks = <String>{};
  final acc = <String>{};
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) _setSeller(widget.customerId!);
  }

  @override
  void dispose() {
    for (final c in [model, brand, imei, color, price, resale, battery, idProof, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _setSeller(int id) async {
    final r = await Books.query('SELECT * FROM customers WHERE id = ?', [id]);
    if (r.isEmpty || !mounted) return;
    setState(() {
      seller = r.first;
      if (idProof.text.isEmpty && (seller!['aadhaar'] ?? '').toString().isNotEmpty) idProof.text = 'Aadhaar ${seller!['aadhaar']}';
    });
  }

  Future<void> _chooseSeller() async {
    final all = await Books.query('SELECT * FROM customers ORDER BY name COLLATE NOCASE');
    if (!mounted) return;
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SellerSheet(customers: all),
    );
    if (r == 'new') {
      final id = await open<int>(context, const PartyForm(type: 'customer'));
      if (id != null) await _setSeller(id);
    } else if (r is int) {
      await _setSeller(r);
    }
  }

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI of the old phone');
    if (code == null || !mounted) return;
    imei.text = SmartImei.clean(code);
    await _checkImei();
  }

  Future<void> _checkImei() async {
    final c = SmartImei.clean(imei.text);
    if (c.isEmpty) {
      setState(() => imeiNote = null);
      return;
    }
    final m = await SmartImei.match(c);
    if (!mounted) return;
    setState(() {
      if (model.text.trim().isEmpty) model.text = m.product?['name'] as String? ?? m.suggestName ?? '';
      if (brand.text.trim().isEmpty) brand.text = m.product?['brand'] as String? ?? m.suggestBrand ?? '';
      imeiBad = m.isImei && !m.valid;
      imeiNote = imeiBad
          ? 'IMEI check digit is wrong — check the number'
          : m.soldOn != null
              ? 'You sold this phone on ${prettyDate('${m.soldOn!['date']}')} (${m.soldOn!['number']})'
              : m.isImei
                  ? 'IMEI valid ✓'
                  : null;
    });
  }

  Future<void> _save({required bool sellNew}) async {
    if (saving) return;
    if (seller == null) {
      toast(context, 'Choose the customer who gives the phone', error: true);
      return;
    }
    if (model.text.trim().isEmpty) {
      toast(context, 'Enter the phone model', error: true);
      return;
    }
    final p = Money.tryParse(price.text) ?? 0;
    if (p <= 0) {
      toast(context, 'Enter the price you give for the old phone', error: true);
      return;
    }
    if (imeiBad) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('IMEI looks wrong'),
          content: const Text('The check digit does not match. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fix it')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final account = await _pickAccount(context, title: sellNew ? 'Old phone value from' : 'Paid from');
    if (account == null || !mounted) return;
    setState(() => saving = true);
    try {
      final id = await Shop.buyUsed(
        customerId: asInt(seller!['id']),
        model: model.text,
        brand: brand.text,
        imei: imei.text,
        price: p,
        resale: Money.tryParse(resale.text) ?? 0,
        grade: grade,
        battery: int.tryParse(battery.text.trim()),
        storage: storage,
        color: color.text,
        checks: checks.toList(),
        accessories: acc.join(', '),
        idProof: idProof.text,
        photo: photo,
        idPhoto: idPhoto,
        note: note.text,
        accountId: account,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
      if (sellNew) {
        open(context, SaleForm(customerId: asInt(seller!['id']), exchangeId: id));
        toast(context, 'Old phone taken for ${Money.rs(p)} — now add the new phone');
      } else {
        open(context, ExchangeView(id: id));
      }
    } catch (err) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, '$err', error: true);
      }
    }
  }

  Widget _section(String n, String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)])),
              child: Text(n, style: _j(12, FontWeight.w800, Colors.white)),
            ),
            const SizedBox(width: 8),
            Text(title, style: _j(15, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _chips(List<String> items, bool Function(String) on, void Function(String) tap) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final i in items)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => tap(i));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: on(i) ? const Color(0xFFEFEAFF) : const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: on(i) ? _purple : _line),
              ),
              child: Text(i, style: _j(12, FontWeight.w700, on(i) ? _purple : _ink)),
            ),
          ),
      ]);

  InputDecoration _dec(String label, {String? prefix, Widget? suffix, String? helper}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixIcon: suffix,
        helperText: helper,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8F8FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
      );

  Widget _photoBox(String label, String? ref, IconData icon, void Function(String?) set) => Expanded(
        child: GestureDetector(
          onTap: () async {
            final p = await pickPhoto(context, folder: 'exchange', allowRemove: ref != null);
            if (!mounted) return;
            setState(() => set(p == '' ? null : p ?? ref));
          },
          child: Container(
            height: 96,
            decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
            clipBehavior: Clip.antiAlias,
            child: ref != null
                ? storedImage(ref)
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: _purple),
                    const SizedBox(height: 4),
                    Text(label, style: _j(11.5, FontWeight.w700, _muted)),
                  ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Money.tryParse(price.text) ?? 0;
    final suggest = (p * 1.15).round();
    final s = seller;
    return PageShell(
      title: 'New exchange',
      subtitle: 'Old phone in → new phone out',
      children: [
        // 1 · customer
        _section('1', 'Customer giving the phone', [
          if (s == null)
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: _chooseSeller,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Choose customer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48), backgroundColor: _purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () async {
                    final id = await open<int>(context, const PartyForm(type: 'customer'));
                    if (id != null) await _setSeller(id);
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('New customer'),
                ),
              ),
            ])
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF7F5FF), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _purple,
                  child: ClipOval(
                    child: storedImage(s['photo'] as String?,
                        fallback: Text('${s['name']}'.isEmpty ? '?' : '${s['name']}'[0].toUpperCase(), style: _j(16, FontWeight.w800, Colors.white))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['name']}', style: _j(14.5, FontWeight.w800, _ink)),
                    Text('${s['phone'] ?? 'No phone'}${(s['aadhaar'] ?? '').toString().isEmpty ? ' · no Aadhaar on file' : ' · Aadhaar ✓'}',
                        style: _j(11.5, FontWeight.w600, (s['aadhaar'] ?? '').toString().isEmpty ? _amber : _muted)),
                  ]),
                ),
                TextButton(onPressed: _chooseSeller, child: const Text('Change')),
              ]),
            ),
        ]),
        // 2 · old phone
        _section('2', 'Old phone', [
          TextField(
            controller: imei,
            keyboardType: TextInputType.number,
            onChanged: (_) {
              if (SmartImei.clean(imei.text).length == 15) _checkImei();
            },
            decoration: _dec('IMEI', suffix: IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: _purple), onPressed: _scan)),
          ),
          if (imeiNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(imeiNote!, style: _j(11.5, FontWeight.w700, imeiBad ? _red : _green)),
            ),
          const SizedBox(height: 10),
          _chips(_brands, (b) => brand.text.toLowerCase() == b.toLowerCase(), (b) => brand.text = b),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: brand, textCapitalization: TextCapitalization.words, decoration: _dec('Brand'))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: model, textCapitalization: TextCapitalization.words, decoration: _dec('Model (e.g. iPhone 11)'))),
          ]),
          const SizedBox(height: 10),
          Text('Storage (RAM / ROM)', style: _j(12.5, FontWeight.w700, _muted)),
          const SizedBox(height: 6),
          _chips(_storages, (x) => storage == x, (x) => storage = storage == x ? null : x),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: color, textCapitalization: TextCapitalization.words, decoration: _dec('Colour'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: battery, keyboardType: TextInputType.number, decoration: _dec('Battery health %'))),
          ]),
          const SizedBox(height: 10),
          Text('Condition', style: _j(12.5, FontWeight.w700, _muted)),
          const SizedBox(height: 6),
          Row(children: [
            for (final g in _grades.keys)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => grade = g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: grade == g ? _gradeColor(g) : const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(g, textAlign: TextAlign.center, style: _j(16, FontWeight.w800, grade == g ? Colors.white : _gradeColor(g))),
                  ),
                ),
              ),
          ]),
          Padding(padding: const EdgeInsets.only(top: 4, left: 2), child: Text(_grades[grade]!, style: _j(11.5, FontWeight.w600, _muted))),
        ]),
        // 3 · checks
        _section('3', 'Checks & accessories · ${checks.length}/${_checks.length}', [
          _chips(_checks, checks.contains, (c) => checks.contains(c) ? checks.remove(c) : checks.add(c)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => checks.length == _checks.length ? checks.clear() : checks.addAll(_checks)),
              child: Text(checks.length == _checks.length ? 'Clear all' : 'All OK'),
            ),
          ),
          Text('Comes with', style: _j(12.5, FontWeight.w700, _muted)),
          const SizedBox(height: 6),
          _chips(_accessories, acc.contains, (a) => acc.contains(a) ? acc.remove(a) : acc.add(a)),
        ]),
        // 4 · photos & ID
        _section('4', 'Photos & ID proof', [
          Row(children: [
            _photoBox('Phone photo', photo, Icons.photo_camera_rounded, (v) => photo = v),
            const SizedBox(width: 8),
            _photoBox('ID proof photo', idPhoto, Icons.badge_rounded, (v) => idPhoto = v),
          ]),
          const SizedBox(height: 10),
          TextField(controller: idProof, decoration: _dec('ID number (Aadhaar / voter ID)')),
        ]),
        // 5 · price
        _section('5', 'Price', [
          Row(children: [
            Expanded(
              child: TextField(
                controller: price,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: _dec('Value given to customer', prefix: '₹ '),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: resale,
                keyboardType: TextInputType.number,
                decoration: _dec('Resale price', prefix: '₹ ', helper: p > 0 ? 'Suggested ${Money.rs(suggest)}' : null),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: _dec('Note (faults, repair needed…)')),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56), backgroundColor: _amber, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          onPressed: saving ? null : () => _save(sellNew: true),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: Text(saving ? 'Saving…' : 'Exchange → choose new phone', style: _j(15, FontWeight.w800, Colors.white)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          onPressed: saving ? null : () => _save(sellNew: false),
          icon: const Icon(Icons.shopping_bag_rounded),
          label: const Text('Only buy (second-hand stock)'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _SellerSheet extends StatefulWidget {
  final List<Rec> customers;
  const _SellerSheet({required this.customers});
  @override
  State<_SellerSheet> createState() => _SellerSheetState();
}

class _SellerSheetState extends State<_SellerSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.customers.where((c) => q.isEmpty || '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase())).take(80).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => q = v.trim()),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name or phone'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: _purple),
                tooltip: 'New customer',
                onPressed: () => Navigator.pop(context, 'new'),
                icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
              ),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              for (final c in list)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEFEAFF),
                    child: ClipOval(
                      child: storedImage(c['photo'] as String?,
                          fallback: Text('${c['name']}'.isEmpty ? '?' : '${c['name']}'[0].toUpperCase(), style: _j(15, FontWeight.w800, _purple))),
                    ),
                  ),
                  title: Text('${c['name']}'),
                  subtitle: Text('${c['phone'] ?? ''}'),
                  onTap: () => Navigator.pop(context, asInt(c['id'])),
                ),
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: EmptyState('No customer — tap + to add')),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// One exchange
// =============================================================================
class ExchangeView extends StatelessWidget {
  final int id;
  const ExchangeView({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Live<Rec?>(
      load: () => Shop.exchange(id),
      builder: (context, e) {
        if (e == null) return const Scaffold(body: Center(child: Text('Not found')));
        final inStock = asInt(e['stock']) > 0;
        final soldFor = e['sold_for'] == null ? null : asInt(e['sold_for']);
        final checks = '${e['checks'] ?? ''}'.split(',').where((x) => x.isNotEmpty).toSet();
        Widget info(String l, String? v) => (v ?? '').trim().isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 120, child: Text(l, style: _j(12.5, FontWeight.w600, _muted))),
                  Expanded(child: Text(v!, style: _j(13, FontWeight.w700, _ink))),
                ]),
              );
        Widget box(String title, List<Widget> children) => Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: _j(15, FontWeight.w800, _ink)),
                const SizedBox(height: 8),
                ...children,
              ]),
            );
        return PageShell(
          title: '${e['number']}',
          subtitle: '${prettyDate('${e['date']}')} · ${e['sale_id'] == null ? 'Bought' : 'Exchanged'}',
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(colors: [Color(0xFF1B2163), Color(0xFF4318D2)]),
              ),
              child: Row(children: [
                Container(
                  width: 70,
                  height: 84,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: storedImage(e['photo'] as String?, fallback: const Icon(Icons.phone_android_rounded, color: _purple, size: 34)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e['model']}', style: _j(18, FontWeight.w800, Colors.white)),
                    const SizedBox(height: 2),
                    Text([e['brand'], e['storage'], e['color']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                        style: _j(12, FontWeight.w600, const Color(0xD9FFFFFF))),
                    const SizedBox(height: 6),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: Text('Grade ${e['grade'] ?? '—'}', style: _j(11, FontWeight.w800, _gradeColor(e['grade'] as String?))),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            inStock
                                ? 'In stock'
                                : soldFor != null
                                    ? 'Resold'
                                    : 'Out',
                            style: _j(11, FontWeight.w800, Colors.white)),
                      ),
                    ]),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Taken for', style: _j(10.5, FontWeight.w600, const Color(0xCCFFFFFF))),
                  Text(Money.rs(asInt(e['price'])), style: _j(16, FontWeight.w800, Colors.white)),
                ]),
              ]),
            ),
            box('Customer', [
              Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEFEAFF),
                  child: ClipOval(
                    child: storedImage(e['customer_photo'] as String?,
                        fallback: Text('${e['customer'] ?? '?'}'.isEmpty ? '?' : '${e['customer'] ?? '?'}'[0].toUpperCase(),
                            style: _j(15, FontWeight.w800, _purple))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e['customer'] ?? '—'}', style: _j(14, FontWeight.w800, _ink)),
                    Text('${e['phone'] ?? ''}', style: _j(12, FontWeight.w600, _muted)),
                  ]),
                ),
                if ((e['phone'] ?? '').toString().isNotEmpty) ...[
                  IconButton(onPressed: () => Contact.call(e['phone'] as String?), icon: const Icon(Icons.call_rounded, color: _purple)),
                  IconButton(
                      onPressed: () => Contact.whatsapp(e['phone'] as String?, 'Hi ${e['customer']},'), icon: const Icon(Icons.chat_rounded, color: _green)),
                ],
              ]),
              info('ID proof', e['id_proof'] as String?),
              info('Address', e['address'] as String?),
            ]),
            box('Exchange', [
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('GAVE', style: _j(10, FontWeight.w800, _amber).copyWith(letterSpacing: 1)),
                      Text('${e['model']}', style: _j(13, FontWeight.w800, _ink)),
                      Text(Money.rs(asInt(e['price'])), style: _j(12, FontWeight.w700, _muted)),
                    ]),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, color: _muted)),
                Expanded(
                  child: GestureDetector(
                    onTap: e['sale_id'] == null ? null : () => open(context, SaleView(id: asInt(e['sale_id']))),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: e['sale_id'] == null ? const Color(0xFFF4F5FB) : const Color(0xFFEAF8F1), borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('TOOK', style: _j(10, FontWeight.w800, e['sale_id'] == null ? _muted : _green).copyWith(letterSpacing: 1)),
                        Text(e['new_phone'] as String? ?? 'Only bought', maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w800, _ink)),
                        Text(e['sale_id'] == null ? '—' : '${e['new_bill']} · ${Money.rs(asInt(e['new_total']))}', style: _j(12, FontWeight.w700, _muted)),
                      ]),
                    ),
                  ),
                ),
              ]),
              if (e['sale_id'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Customer paid the difference: ${Money.rs((asInt(e['new_total']) - asInt(e['price'])).clamp(0, 1 << 40))}',
                      style: _j(12.5, FontWeight.w700, _purple)),
                ),
            ]),
            box('Phone details', [
              info('IMEI', e['imei'] as String?),
              info('Battery health', e['battery'] == null ? null : '${e['battery']}%'),
              info('Comes with', e['accessories'] as String?),
              info('Note', e['note'] as String?),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in _checks)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: checks.contains(c) ? const Color(0xFFEAF8F1) : const Color(0xFFFFEEF2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(checks.contains(c) ? Icons.check_circle_rounded : Icons.help_outline_rounded, size: 14, color: checks.contains(c) ? _green : _red),
                      const SizedBox(width: 4),
                      Text(c, style: _j(11, FontWeight.w700, _ink)),
                    ]),
                  ),
              ]),
              if (e['id_photo'] != null) ...[
                const SizedBox(height: 10),
                Text('ID proof', style: _j(12, FontWeight.w700, _muted)),
                const SizedBox(height: 4),
                ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(height: 160, child: storedImage(e['id_photo'] as String?))),
              ],
            ]),
            box('Resale', [
              info('Resale price', Money.rs(asInt(e['resale']) > 0 ? asInt(e['resale']) : asInt(e['list_price']))),
              if (soldFor != null) ...[
                info('Sold for', '${Money.rs(soldFor)} (${e['sold_on']})'),
                info('Profit', Money.rs(soldFor - asInt(e['price']))),
              ],
              if (inStock) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: _green),
                  onPressed: () => open(context, const SaleForm()),
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Sell this phone'),
                ),
              ],
            ]),
            if ((e['imei'] ?? '').toString().isNotEmpty) box('IMEI history', [DeviceTimeline('${e['imei']}')]),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}
