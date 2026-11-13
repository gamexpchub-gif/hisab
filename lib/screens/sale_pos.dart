import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/books.dart';
import '../core/imei_smart.dart';
import '../core/money.dart';
import '../print/print_screen.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'product_form.dart';
import 'products.dart';
import 'sales.dart';
import 'scanner.dart';

// =============================================================================
// New Sale — point-of-sale billing screen.
// Customer search with dues/credit limit · product search, barcode scan and
// quick picks · cart with qty, rate, IMEI scan, swipe to remove · discount
// (₹ or %), CGST/SGST split, round-off · cash/UPI/bank with change & due ·
// UPI QR for exact amount · success screen with WhatsApp invoice.
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

TextStyle _j(double size, FontWeight w, Color c, {double? height, TextDecoration? deco}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
      decoration: deco,
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

class _Line {
  final Rec p;
  int qty;
  int rate; // paise, before GST
  final serial = TextEditingController();
  final opp = TextEditingController(); // opportunity / finance ID
  String? imeiWarn; // Smart IMEI warning for the typed / scanned number
  String? imeiInfo; // Smart IMEI note (recognised model)
  _Line(this.p, {this.qty = 1}) : rate = asInt(p['price']);
  int get id => asInt(p['id']);
  int get stock => asInt(p['stock']);
  int get gstBp => asInt(p['gst_bp']);
  int get amount => rate * qty;
  int get tax => Money.percent(amount, gstBp);
  int get cost => asInt(p['cost']) * qty;
}

class _Split {
  int? account;
  final ctrl = TextEditingController();
}

class SaleForm extends StatefulWidget {
  final int? customerId;
  final int? editSaleId; // edit an existing sale in place
  const SaleForm({super.key, this.customerId, this.editSaleId});
  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  List<Rec> products = [], customers = [], accounts = [], quick = [];
  Map<int, int> dues = {};
  Map<String, String> settings = {};
  final cart = <_Line>[];
  Rec? customer;
  int? account;
  String date = ymd(DateTime.now());
  final search = TextEditingController();
  final received = TextEditingController();
  final discountCtrl = TextEditingController();
  final note = TextEditingController();
  bool discountPct = false;
  bool roundOff = true;
  bool receivedTouched = false;
  String payMode = 'full'; // full | due | split
  int advancePct = 0; // due mode: 0 / 25 / 50 / 75, or -1 for a custom advance
  final advanceCtrl = TextEditingController();
  final splits = <_Split>[];
  bool showProfit = false;
  String? cat; // category filter of the product strip
  bool saving = false;
  String nextNo = '';

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
    discountCtrl.addListener(_recalc);
    _load();
  }

  Future<void> _load() async {
    products = await Books.query(
        'SELECT p.*, c.name AS category, (SELECT COALESCE(SUM(qty),0) FROM sale_items WHERE product_id = p.id) AS sold '
        'FROM products p LEFT JOIN categories c ON c.id = p.category_id ORDER BY p.name COLLATE NOCASE');
    quick = [...products.where((p) => asInt(p['stock']) > 0)]..sort((a, b) => asInt(b['sold']).compareTo(asInt(a['sold'])));
    if (quick.length > 10) quick = quick.sublist(0, 10);
    customers = await Books.query('SELECT * FROM customers ORDER BY name COLLATE NOCASE');
    dues = await Books.partyBalances('customer');
    accounts = await Books.moneyAccounts();
    settings = await Books.settings();
    final n = asInt((await Books.query('SELECT COUNT(*) AS c FROM sales')).first['c']) + 1;
    nextNo = 'INV-${n.toString().padLeft(5, '0')}';
    final last = int.tryParse(settings['last_pay_account'] ?? '');
    if (account == null && last != null && accounts.any((a) => asInt(a['id']) == last)) account = last;
    account ??= accounts.isNotEmpty ? asInt(accounts.first['id']) : null;
    if (widget.customerId != null) {
      for (final c in customers) {
        if (asInt(c['id']) == widget.customerId) customer = c;
      }
    }
    if (widget.editSaleId != null && !_editLoaded) await _loadEdit(widget.editSaleId!);
    if (mounted) setState(() {});
  }

  bool _editLoaded = false;

  /// Fills the form from an existing sale. Its units count as in stock again.
  Future<void> _loadEdit(int id) async {
    final s = await Books.query('SELECT * FROM sales WHERE id = ?', [id]);
    if (s.isEmpty) return;
    _editLoaded = true;
    final sale = s.first;
    nextNo = '${sale['number']}';
    date = '${sale['date']}';
    note.text = '${sale['note'] ?? ''}';
    roundOff = false;
    discountPct = false;
    discountCtrl.text = asInt(sale['discount']) > 0 ? Money.edit(asInt(sale['discount'])) : '';
    final cid = sale['customer_id'];
    customer = cid == null ? null : customers.where((c) => asInt(c['id']) == asInt(cid)).firstOrNull;
    final items = await Books.query('SELECT * FROM sale_items WHERE sale_id = ? ORDER BY id', [id]);
    final back = <int, int>{};
    for (final i in items) {
      back[asInt(i['product_id'])] = (back[asInt(i['product_id'])] ?? 0) + asInt(i['qty']);
    }
    products = [
      for (final p in products) back.containsKey(asInt(p['id'])) ? {...p, 'stock': asInt(p['stock']) + back[asInt(p['id'])]!} : p,
    ];
    for (final i in items) {
      final p = products.where((p) => asInt(p['id']) == asInt(i['product_id'])).firstOrNull;
      if (p == null) continue;
      final l = _Line(p, qty: asInt(i['qty']))..rate = asInt(i['rate']);
      l.serial.text = '${i['serial'] ?? ''}';
      l.opp.text = '${i['opp_id'] ?? ''}';
      cart.add(l);
    }
    final pays = await Books.query('SELECT account_id, amount FROM sale_payments WHERE sale_id = ? ORDER BY id', [id]);
    final total = asInt(sale['total']), paid = asInt(sale['paid']);
    if (pays.length > 1) {
      payMode = 'split';
      for (final p in pays) {
        final sp = _Split()..account = asInt(p['account_id']);
        sp.ctrl.text = Money.edit(asInt(p['amount']));
        splits.add(sp);
      }
    } else {
      if (pays.isNotEmpty) account = asInt(pays.first['account_id']);
      if (paid >= total) {
        payMode = 'full';
      } else {
        payMode = 'due';
        advancePct = -1;
        advanceCtrl.text = paid > 0 ? Money.edit(paid) : '';
      }
    }
  }

  bool get editing => widget.editSaleId != null;
  bool get oppEnabled => settings['opp_id_enabled'] == '1';

  @override
  void dispose() {
    for (final l in cart) {
      l.serial.dispose();
      l.opp.dispose();
    }
    search.dispose();
    received.dispose();
    advanceCtrl.dispose();
    for (final sp in splits) {
      sp.ctrl.dispose();
    }
    discountCtrl.dispose();
    note.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- totals
  int get subtotal => cart.fold(0, (a, l) => a + l.amount);
  int get tax => cart.fold(0, (a, l) => a + l.tax);
  int get _discountInput {
    try {
      final v = Money.parse(discountCtrl.text);
      return discountPct ? Money.percent(subtotal, v) : v; // "10" % → 1000 basis points
    } catch (_) {
      return 0;
    }
  }

  int get _disc => math.min(math.max(_discountInput, 0), subtotal);
  int get _gross => subtotal + tax - _disc;
  int get roundAmount => roundOff ? _gross % 100 : 0; // drop the paise
  int get discount => _disc + roundAmount;
  int get total => subtotal + tax - discount;
  int get profit => subtotal - discount - cart.fold(0, (a, l) => a + l.cost);
  int get qtyTotal => cart.fold(0, (a, l) => a + l.qty);

  int _parse(TextEditingController c) {
    try {
      return Money.parse(c.text);
    } catch (_) {
      return 0;
    }
  }

  bool get _cashSelected => _account?['kind'] == 'cash';
  int get splitSum => splits.fold(0, (a, sp) => a + _parse(sp.ctrl));

  /// Amount collected now, by payment mode.
  int get paid {
    switch (payMode) {
      case 'due':
        if (advancePct < 0) return math.min(math.max(_parse(advanceCtrl), 0), total);
        return (total * advancePct ~/ 100) ~/ 100 * 100; // whole rupees
      case 'split':
        return math.min(splitSum, total);
      default:
        return total;
    }
  }

  /// Change to hand back when cash tendered exceeds the bill (full mode, cash).
  int get change => payMode == 'full' && _cashSelected && receivedTouched ? math.max(0, _parse(received) - total) : 0;
  int get due => total - paid;

  void _recalc() => setState(() {});

  // ---------------------------------------------------------------- cart
  void _add(Rec p, {String? serial}) {
    HapticFeedback.selectionClick();
    final existing = cart.where((l) => l.id == asInt(p['id']) && serial == null).toList();
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.qty++;
      } else {
        final l = _Line(p);
        if (serial != null) l.serial.text = serial;
        cart.add(l);
      }
      search.clear();
    });
    final inCart = cart.where((l) => l.id == asInt(p['id'])).fold<int>(0, (a, l) => a + l.qty);
    if (inCart > asInt(p['stock'])) toast(context, 'Only ${p['stock']} × ${p['name']} in stock', error: true);
  }

  /// Continuous scanning: every barcode / IMEI goes straight into the cart.
  Future<void> _scan() async {
    final n = await BarcodeScannerScreen.scanMany(context, title: 'Scan items · batch', onCode: _useCode);
    if (n > 0 && mounted) toast(context, '$n item${n == 1 ? '' : 's'} added by scan');
  }

  /// A scanned or typed code: product SKU, label code (P000123) or IMEI.
  Future<String?> _useCode(String code) async {
    code = code.trim();
    final c = SmartImei.clean(code);
    if (!SmartImei.looksLikeImei(c)) {
      final pid = RegExp(r'^P(\d{6})$').firstMatch(code.toUpperCase());
      for (final p in products) {
        final sku = (p['sku'] as String?)?.trim() ?? '';
        if ((sku.isNotEmpty && sku.toUpperCase() == code.toUpperCase()) || (pid != null && asInt(p['id']) == int.parse(pid.group(1)!))) {
          _add(p);
          return '${p['name']} added';
        }
      }
    }
    final before = cart.length;
    await _addByImei(c.isEmpty ? code : c);
    if (cart.length > before) return '${cart.last.p['name']} · ${cart.last.serial.text}';
    return null;
  }

  /// Smart IMEI: recognise the device from its IMEI and add it to the cart.
  Future<void> _addByImei(String code) async {
    final m = await SmartImei.match(code);
    if (!mounted) return;
    final warn = m.warning();
    if (warn != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: const Icon(Icons.warning_amber_rounded, color: _amber, size: 40),
          title: Text(m.isImei ? 'Check this IMEI' : 'Check this serial'),
          content: Text('${m.code}\n\n$warn'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    Rec? product = m.product == null ? null : products.where((p) => asInt(p['id']) == asInt(m.product!['id'])).firstOrNull;
    if (product == null) {
      product = await showModalBottomSheet<Rec>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PickProductSheet(products: products, code: m.code, hint: m.suggestName),
      );
      if (product == null || !mounted) return;
      await SmartImei.learn(m.code, productId: asInt(product['id']), name: '${product['name']}', brand: '${product['brand'] ?? ''}');
      if (!mounted) return;
    }
    _add(product, serial: m.code);
    final l = cart.lastWhere((x) => x.serial.text == m.code, orElse: () => cart.last);
    l.imeiWarn = warn;
    l.imeiInfo = switch (m.how) {
      'exact' => 'Smart IMEI · from purchase ${m.boughtOn?['number'] ?? ''}',
      'tac' => 'Smart IMEI · recognised model (seen ${m.tacSeen}×)',
      'learned' => 'Smart IMEI · recognised model',
      _ => m.isImei ? 'Smart IMEI · new model learned' : null,
    };
    HapticFeedback.mediumImpact();
    if (m.how != 'none') toast(context, '${product['name']} added · ${m.how == 'exact' ? 'exact device' : 'recognised by IMEI'}');
    setState(() {});
  }

  /// Checks an IMEI typed into a cart line.
  Future<void> _checkLineImei(_Line l) async {
    final c = SmartImei.clean(l.serial.text);
    if (c.isEmpty) {
      setState(() => l.imeiWarn = l.imeiInfo = null);
      return;
    }
    if (!SmartImei.looksLikeImei(c)) {
      if (l.imeiWarn != null) setState(() => l.imeiWarn = null);
      return;
    }
    final m = await SmartImei.match(c);
    if (!mounted || SmartImei.clean(l.serial.text) != c) return;
    setState(() {
      l.imeiWarn = m.warning();
      if (m.product != null && asInt(m.product!['id']) != l.id) {
        l.imeiWarn ??= 'This IMEI belongs to ${m.product!['name']}';
      }
      l.imeiInfo = m.warning() == null && m.valid ? 'IMEI verified ✓' : null;
    });
  }

  Future<void> _editRate(_Line l) async {
    final c = TextEditingController(text: Money.edit(l.rate));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Price for ${l.p['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Rate per unit (before GST)'),
          ),
          const SizedBox(height: 8),
          Text('MRP ${Money.rs(asInt(l.p['mrp']))} · list price ${Money.rs(asInt(l.p['price']))}',
              style: _j(12, FontWeight.w500, _muted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Set price')),
        ],
      ),
    );
    if (r == null) return;
    try {
      setState(() => l.rate = Money.parse(r));
    } catch (_) {
      if (mounted) toast(context, 'Enter a valid amount', error: true);
    }
  }

  Future<void> _scanSerial(_Line l) async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI / serial');
    if (code != null) setState(() => l.serial.text = code);
  }

  // ---------------------------------------------------------------- customer
  Future<void> _pickCustomer() async {
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerSheet(customers: customers, dues: dues),
    );
    if (r == 'walkin') {
      setState(() => customer = null);
    } else if (r == 'new') {
      await open(context, const PartyForm(type: 'customer'));
      await _load();
      if (customers.isNotEmpty) {
        final newest = [...customers]..sort((a, b) => asInt(b['id']).compareTo(asInt(a['id'])));
        setState(() => customer = newest.first);
      }
    } else if (r is Map<String, Object?>) {
      setState(() => customer = r);
    }
  }

  // ---------------------------------------------------------------- charge
  Future<void> _charge() async {
    if (saving) return;
    if (cart.isEmpty) {
      toast(context, 'Add at least one product', error: true);
      return;
    }
    if (payMode == 'split' && splitSum > total) {
      toast(context, 'Split amounts are ₹${Money.inr(splitSum - total)} more than the bill', error: true);
      return;
    }
    if (payMode == 'split' && splits.any((sp) => sp.account == null && _parse(sp.ctrl) > 0)) {
      toast(context, 'Choose an account for every split amount', error: true);
      return;
    }
    if (due > 0 && customer == null) {
      toast(context, 'Select a customer to give credit (₹${Money.inr(due)} due)', error: true);
      return;
    }
    if (customer != null && due > 0) {
      final limit = asInt(customer!['credit_limit']);
      final after = (dues[asInt(customer!['id'])] ?? 0) + due;
      if (limit > 0 && after > limit) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Credit limit crossed'),
            content: Text('${customer!['name']} will owe ${Money.rs(after)}, above the limit of ${Money.rs(limit)}. Continue?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    setState(() => saving = true);
    try {
      final id = await Books.createSale(
        editId: widget.editSaleId,
        items: [for (final l in cart) ItemIn(l.id, l.qty, l.rate, l.serial.text, oppEnabled ? l.opp.text : null)],
        customerId: customer == null ? null : asInt(customer!['id']),
        paid: paid,
        accountId: account,
        discount: discount,
        date: date,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        splits: payMode == 'split'
            ? [for (final sp in splits) if (sp.account != null && _parse(sp.ctrl) > 0) MapEntry(sp.account!, _parse(sp.ctrl))]
            : null,
      );
      if (account != null) await Books.setSetting('last_pay_account', '$account');
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      if (editing) {
        toast(context, 'Sale $nextNo updated');
        Navigator.of(context).pop(true);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SaleSuccessScreen(saleId: id, change: change)));
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  Rec? get _account {
    for (final a in accounts) {
      if (asInt(a['id']) == account) return a;
    }
    return null;
  }

  // ================================================================== UI
  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 150 + safe),
            children: [
              _header(),
              const SizedBox(height: 14),
              _customerCard(),
              const SizedBox(height: 14),
              _searchBar(),
              if (search.text.trim().isNotEmpty) _results() else _quickPicks(),
              const SizedBox(height: 14),
              _cartCard(),
              if (cart.isNotEmpty) ...[
                const SizedBox(height: 14),
                _billCard(),
                const SizedBox(height: 14),
                _paymentCard(),
                const SizedBox(height: 14),
                _noteField(),
              ],
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _checkoutBar(safe)),
      ]),
    );
  }

  Widget _header() => Row(children: [
        _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editing ? 'Edit Sale' : 'New Sale', style: _j(21, FontWeight.w800, _navy)),
            Row(children: [
              Text(nextNo.isEmpty ? 'Tax invoice' : '$nextNo · tax invoice', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
            ]),
          ]),
        ),
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.parse(date),
              firstDate: DateTime(2015),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (d != null) setState(() => date = ymd(d));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: _card(r: 16),
            child: Row(children: [
              const Icon(Icons.event_rounded, size: 16, color: _purple),
              const SizedBox(width: 6),
              Text(date == ymd(DateTime.now()) ? 'Today' : prettyDate(date), style: _j(12.5, FontWeight.w700, _ink)),
            ]),
          ),
        ),
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
          child: Icon(icon, color: _ink, size: 22),
        ),
      );

  // ---------------------------------------------------------------- customer card
  Widget _customerCard() {
    final c = customer;
    final cDue = c == null ? 0 : dues[asInt(c['id'])] ?? 0;
    final limit = c == null ? 0 : asInt(c['credit_limit']);
    return GestureDetector(
      onTap: _pickCustomer,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _card(),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  colors: c == null ? const [Color(0xFFE2E8F0), Color(0xFFCBD5E1)] : const [Color(0xFF4FD8E0), Color(0xFF139DB0)]),
            ),
            alignment: Alignment.center,
            child: c == null
                ? const Icon(Icons.storefront_rounded, color: Color(0xFF475569))
                : Text((c['name'] as String).isEmpty ? '?' : (c['name'] as String)[0].toUpperCase(),
                    style: _j(20, FontWeight.w800, Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c == null ? 'Walk-in customer' : c['name'] as String, style: _j(15, FontWeight.w800, _ink)),
              const SizedBox(height: 2),
              Text(
                c == null
                    ? 'Cash sale · tap to choose a customer'
                    : [c['phone'] ?? '', if (limit > 0) 'limit ${Money.compact(limit)}'].where((e) => '$e'.isNotEmpty).join(' · '),
                style: _j(11.5, FontWeight.w500, _muted),
              ),
            ]),
          ),
          if (c != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cDue > 0 ? const Color(0xFFFDE4EA) : const Color(0xFFE3F7EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(cDue > 0 ? 'Due ${Money.compact(cDue)}' : 'No dues',
                  style: _j(11, FontWeight.w800, cDue > 0 ? const Color(0xFFC8102E) : const Color(0xFF0E6E47))),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.unfold_more_rounded, color: Color(0xFFB9BCD6)),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- search + quick picks
  Widget _searchBar() => Row(children: [
        Expanded(
          child: Container(
            height: 52,
            decoration: _card(r: 26),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              const Icon(Icons.search_rounded, color: Color(0xFF2C3B8F)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: search,
                  style: _j(14, FontWeight.w600, _ink),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Search product, brand or barcode',
                    hintStyle: _j(13.5, FontWeight.w400, const Color(0xFF8A8FAD)),
                  ),
                ),
              ),
              if (search.text.isNotEmpty)
                GestureDetector(onTap: search.clear, child: const Icon(Icons.close_rounded, color: _muted, size: 20)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _scan,
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF7B4DFF), Color(0xFF4318D2)]),
              boxShadow: [BoxShadow(color: Color(0x664A17C9), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
          ),
        ),
      ]);

  Widget _results() {
    final q = search.text.trim().toLowerCase();
    final r = products
        .where((p) => [p['name'], p['brand'], p['sku'], p['variant'], p['category']]
            .any((v) => v != null && '$v'.toLowerCase().contains(q)))
        .take(8)
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: _card(),
      child: r.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(child: Text('No product matches “${search.text}”', style: _j(13, FontWeight.w500, _muted))),
                TextButton(
                  onPressed: () async {
                    await open(context, const ProductForm());
                    _load();
                  },
                  child: const Text('Add product'),
                ),
              ]),
            )
          : Column(children: [
              for (var i = 0; i < r.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 72, color: Color(0xFFEEF0F8)),
                InkWell(
                  onTap: () => _add(r[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      ProductThumb(r[i], width: 46, height: 50),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r[i]['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w700, _ink)),
                          Text(
                            [r[i]['variant'], 'Stock ${r[i]['stock']}'].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                            style: _j(11, FontWeight.w500, asInt(r[i]['stock']) <= 0 ? _red : _muted),
                          ),
                        ]),
                      ),
                      Text(Money.rs(asInt(r[i]['price'])), style: _j(13.5, FontWeight.w800, const Color(0xFF1C1CA0))),
                      const SizedBox(width: 8),
                      const Icon(Icons.add_circle_rounded, color: _purple),
                    ]),
                  ),
                ),
              ],
            ]),
    );
  }

  /// Inline category chips + a sideways product strip (best sellers for "All").
  Widget _quickPicks() {
    final cats = <String>{for (final p in products) if ((p['category'] as String?)?.isNotEmpty == true) p['category'] as String}.toList()..sort();
    final list = cat == null
        ? (quick.isEmpty ? products.take(12).toList() : quick)
        : (products.where((p) => p['category'] == cat).toList()..sort((a, b) => asInt(b['stock']).compareTo(asInt(a['stock']))));
    IconData icon(String c) {
      final l = c.toLowerCase();
      if (l.contains('mobile')) return Icons.smartphone_rounded;
      if (l.contains('laptop')) return Icons.laptop_mac_rounded;
      if (l.contains('tablet')) return Icons.tablet_mac_rounded;
      if (l.contains('desktop') || l.contains('pc')) return Icons.desktop_windows_rounded;
      if (l.contains('access')) return Icons.headphones_rounded;
      return Icons.category_rounded;
    }

    Widget chip(String? c, String label, IconData i) {
      final on = cat == c;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => cat = c);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: on ? null : Border.all(color: const Color(0xFFE9EAF5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 14, color: on ? Colors.white : _purple),
            const SizedBox(width: 5),
            Text(label, style: _j(11.5, FontWeight.w700, on ? Colors.white : _ink)),
          ]),
        ),
      );
    }

    if (products.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            chip(null, 'Best sellers', Icons.bolt_rounded),
            for (final c in cats) chip(c, c, icon(c)),
          ]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: list.isEmpty
              ? Center(child: Text('No products in $cat', style: _j(12, FontWeight.w600, _muted)))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final stock = asInt(p['stock']);
                    return GestureDetector(
                      onTap: () => _add(p),
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                        decoration: _card(r: 16),
                        child: Column(children: [
                          Stack(children: [
                            ProductThumb(p, width: 50, height: 50),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: stock <= 0 ? _red : stock <= asInt(p['low_stock']) ? _amber : _green,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('$stock', style: _j(9, FontWeight.w800, Colors.white)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 5),
                          Text(p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w700, _ink)),
                          Text(Money.compact(asInt(p['price'])), style: _j(11, FontWeight.w800, _purple)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- cart
  Widget _cartCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.shopping_cart_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Cart', style: _j(15, FontWeight.w800, _ink))),
          if (cart.isNotEmpty)
            Text('$qtyTotal item${qtyTotal == 1 ? '' : 's'}', style: _j(12, FontWeight.w700, _muted)),
          if (cart.isNotEmpty)
            IconButton(
              tooltip: 'Clear cart',
              icon: const Icon(Icons.delete_sweep_rounded, color: _red, size: 22),
              onPressed: () => setState(cart.clear),
            ),
        ]),
        if (cart.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Column(children: [
                Image.asset('assets/home/cart.png', width: 64, height: 60),
                const SizedBox(height: 8),
                Text('Cart is empty', style: _j(14, FontWeight.w800, _ink)),
                Text('Search, scan a barcode or tap a best seller', style: _j(12, FontWeight.w500, _muted)),
              ]),
            ),
          ),
        for (final l in cart) _cartLine(l),
      ]),
    );
  }

  Widget _cartLine(_Line l) {
    final over = l.qty > l.stock;
    final isDevice = (l.p['category'] as String? ?? '').toLowerCase().contains(RegExp('mobile|laptop|tablet|desktop'));
    return Dismissible(
      key: ObjectKey(l),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(color: const Color(0xFFFDE4EA), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_rounded, color: _red),
      ),
      onDismissed: (_) => setState(() => cart.remove(l)),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: over ? const Color(0xFFF5B5C2) : const Color(0xFFEEF0F8)),
        ),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProductThumb(l.p, width: 54, height: 60),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
                if ((l.p['variant'] as String? ?? '').isNotEmpty)
                  Text(l.p['variant'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w500, _muted)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _editRate(l),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(Money.rs(l.rate), style: _j(13, FontWeight.w800, const Color(0xFF1C1CA0))),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_rounded, size: 13, color: _purple),
                    const SizedBox(width: 6),
                    Text('+${l.gstBp ~/ 100}% GST', style: _j(10.5, FontWeight.w600, _muted)),
                  ]),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.rs(l.amount + l.tax), style: _j(14, FontWeight.w800, _ink)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _qtyBtn(Icons.remove_rounded, () {
                    setState(() {
                      if (l.qty > 1) {
                        l.qty--;
                      } else {
                        cart.remove(l);
                      }
                    });
                  }),
                  SizedBox(width: 30, child: Text('${l.qty}', textAlign: TextAlign.center, style: _j(14, FontWeight.w800, _ink))),
                  _qtyBtn(Icons.add_rounded, () => setState(() => l.qty++)),
                ]),
              ),
            ]),
          ]),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: _red, size: 15),
                const SizedBox(width: 4),
                Text('Only ${l.stock} in stock', style: _j(11, FontWeight.w700, _red)),
              ]),
            ),
          if (isDevice || l.serial.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: 40,
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                child: Row(children: [
                  const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFF8B7FD6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: l.serial,
                      onChanged: (_) => _checkLineImei(l),
                      keyboardType: TextInputType.text,
                      style: _j(12.5, FontWeight.w600, _ink),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'IMEI / serial number',
                        hintStyle: _j(12, FontWeight.w400, const Color(0xFFA3A7C2)),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: _purple, size: 20),
                    onPressed: () => _scanSerial(l),
                  ),
                ]),
              ),
            ),
          if (l.imeiWarn != null || l.imeiInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 4),
              child: Row(children: [
                Icon(l.imeiWarn != null ? Icons.warning_amber_rounded : Icons.verified_rounded,
                    size: 14, color: l.imeiWarn != null ? _red : _green),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(l.imeiWarn ?? l.imeiInfo!,
                      style: _j(11, FontWeight.w700, l.imeiWarn != null ? _red : _green)),
                ),
              ]),
            ),
          if (oppEnabled && (isDevice || l.serial.text.isNotEmpty || l.opp.text.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFF2FBF6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCDEEDB))),
                child: Row(children: [
                  const Icon(Icons.badge_rounded, size: 18, color: _green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: l.opp,
                      style: _j(12.5, FontWeight.w600, _ink),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Opportunity ID (finance / EMI)',
                        hintStyle: _j(12, FontWeight.w400, const Color(0xFFA3A7C2)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 30, height: 30, child: Icon(icon, size: 18, color: _purple)),
      );

  // ---------------------------------------------------------------- bill
  Widget _billCard() {
    Widget row(String l, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(l, style: _j(13, bold ? FontWeight.w800 : FontWeight.w500, bold ? _ink : const Color(0xFF3A4155)))),
            Text(v, style: _j(bold ? 18 : 13, FontWeight.w800, color ?? _ink)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line),
              ),
              child: Row(children: [
                const Icon(Icons.discount_rounded, size: 18, color: Color(0xFF8B7FD6)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: discountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: _j(14, FontWeight.w700, _ink),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Discount',
                      hintStyle: _j(13, FontWeight.w500, const Color(0xFFA3A7C2)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          _seg(['₹', '%'], discountPct ? 1 : 0, (i) => setState(() => discountPct = i == 1)),
        ]),
        const SizedBox(height: 10),
        row('Subtotal ($qtyTotal item${qtyTotal == 1 ? '' : 's'})', Money.rs(subtotal)),
        if (_disc > 0) row('Discount', '− ${Money.rs(_disc)}', color: _green),
        row('CGST', Money.rs(tax ~/ 2)),
        row('SGST', Money.rs(tax - tax ~/ 2)),
        Row(children: [
          Expanded(child: Text('Round off', style: _j(13, FontWeight.w500, const Color(0xFF3A4155)))),
          if (roundOff && roundAmount > 0) Text('− ${Money.rs(roundAmount)}  ', style: _j(12.5, FontWeight.w700, _muted)),
          Switch(value: roundOff, onChanged: (v) => setState(() => roundOff = v)),
        ]),
        const Divider(color: Color(0xFFEEF0F8)),
        row('Total', Money.rs(total), color: _navy, bold: true),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => showProfit = !showProfit),
          child: Row(children: [
            Icon(showProfit ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 16, color: _muted),
            const SizedBox(width: 6),
            Text(showProfit ? 'Profit on this bill: ${Money.rs(profit)}' : 'Show profit (owner only)',
                style: _j(11.5, FontWeight.w700, showProfit ? (profit >= 0 ? _green : _red) : _muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _seg(List<String> labels, int sel, ValueChanged<int> on) => Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFF1F2FA), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => on(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: i == sel ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(labels[i], style: _j(14, FontWeight.w800, i == sel ? Colors.white : _ink)),
              ),
            ),
        ]),
      );

  // ---------------------------------------------------------------- payment
  IconData _accIcon(String? k) =>
      k == 'cash' ? Icons.payments_rounded : k == 'upi' ? Icons.qr_code_2_rounded : Icons.account_balance_rounded;

  void _setMode(String m) {
    HapticFeedback.selectionClick();
    setState(() {
      payMode = m;
      if (m == 'split' && splits.isEmpty) _initSplits();
    });
  }

  /// Two rows by default: cash + the first non-cash account, 50/50.
  void _initSplits() {
    Rec? cash, other;
    for (final a in accounts) {
      if (a['kind'] == 'cash') cash ??= a;
      if (a['kind'] != 'cash') other ??= a;
    }
    final first = cash ?? (accounts.isNotEmpty ? accounts.first : null);
    final second = other ?? (accounts.length > 1 ? accounts[1] : null);
    for (final a in [first, second]) {
      splits.add(_Split()..account = a == null ? null : asInt(a['id']));
    }
    _splitPreset(50);
  }

  /// Puts [pct]% of the bill on the first row (whole rupees) and the rest on the second.
  void _splitPreset(int pct) {
    if (splits.length < 2) return;
    final firstAmt = (total * pct ~/ 100) ~/ 100 * 100;
    splits[0].ctrl.text = Money.edit(firstAmt);
    splits[1].ctrl.text = Money.edit(total - firstAmt);
    for (var i = 2; i < splits.length; i++) {
      splits[i].ctrl.text = '';
    }
  }

  /// Smart split: cash in round ₹500 notes, the remainder digitally.
  void _smartSplit() {
    if (splits.length < 2) return;
    final half = total ~/ 2;
    final cash = (half ~/ 50000) * 50000;
    splits[0].ctrl.text = Money.edit(cash == 0 ? half ~/ 100 * 100 : cash);
    splits[1].ctrl.text = Money.edit(total - _parse(splits[0].ctrl));
  }

  /// Editing one of two rows auto-fills the other with the remainder.
  void _balanceFrom(int i) {
    if (splits.length != 2) return;
    final other = splits[1 - i];
    final rest = math.max(0, total - _parse(splits[i].ctrl));
    final text = Money.edit(rest);
    if (other.ctrl.text != text) other.ctrl.text = text;
  }

  Widget _paymentCard() {
    final acc = _account;
    final upiId = (settings['upi_id'] ?? '').trim();
    const modes = [
      ('full', 'Full paid', Icons.verified_rounded),
      ('due', 'Due', Icons.schedule_rounded),
      ('split', 'Split', Icons.call_split_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Payment', style: _j(15, FontWeight.w800, _ink)),
          const Spacer(),
          if (payMode != 'full')
            Text(customer == null ? 'Needs a customer' : 'On ${customer!['name']}\'s account',
                style: _j(11, FontWeight.w700, customer == null ? _red : _muted)),
        ]),
        const SizedBox(height: 10),
        // ---- mode selector
        Container(
          height: 54,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFFF1F2FA), borderRadius: BorderRadius.circular(18)),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth / 3;
            final i = modes.indexWhere((m) => m.$1 == payMode);
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                left: i * w,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: payMode == 'full'
                          ? const [Color(0xFF1BB574), Color(0xFF0F8C58)]
                          : payMode == 'due'
                              ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                              : const [Color(0xFF6B35EE), Color(0xFF4318D2)],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x332A2F7A), blurRadius: 10, offset: Offset(0, 4), spreadRadius: -4)],
                  ),
                ),
              ),
              Row(children: [
                for (final m in modes)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setMode(m.$1),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(m.$3, size: 17, color: m.$1 == payMode ? Colors.white : _muted),
                        const SizedBox(width: 5),
                        Text(m.$2, style: _j(12.5, FontWeight.w800, m.$1 == payMode ? Colors.white : _ink)),
                      ]),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
        const SizedBox(height: 14),
        if (payMode == 'full') ..._fullMode(),
        if (payMode == 'due') ..._dueMode(),
        if (payMode == 'split') ..._splitMode(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _stat(change > 0 ? 'Change to return' : 'Collected now', Money.rs(change > 0 ? change : paid),
                change > 0 ? _amber : _green),
          ),
          const SizedBox(width: 10),
          Expanded(child: _stat(due > 0 ? 'Goes to due' : 'Balance due', Money.rs(due), due > 0 ? _red : _muted)),
        ]),
        if (payMode != 'split' && paid > 0 && acc != null && acc['kind'] == 'upi' && upiId.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showUpiQr(upiId),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)]),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.qr_code_2_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text('Show UPI QR for ${Money.rs(paid)}', style: _j(13.5, FontWeight.w800, Colors.white)),
              ]),
            ),
          ),
        ] else if (payMode != 'split' && acc != null && acc['kind'] == 'upi' && upiId.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Tip: add your UPI ID in Settings to show a payment QR here.', style: _j(11, FontWeight.w500, _muted)),
          ),
      ]),
    );
  }

  /// Account chips — every cash / bank / UPI / wallet account in the books.
  Widget _accountChips(int? selected, ValueChanged<int> onPick) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in accounts)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onPick(asInt(a['id']));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: selected == asInt(a['id']) ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                color: selected == asInt(a['id']) ? null : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: selected == asInt(a['id']) ? null : Border.all(color: _line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_accIcon(a['kind'] as String?), size: 17, color: selected == asInt(a['id']) ? Colors.white : _purple),
                const SizedBox(width: 6),
                Text(a['name'] as String, style: _j(12.5, FontWeight.w700, selected == asInt(a['id']) ? Colors.white : _ink)),
              ]),
            ),
          ),
      ]);

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
      );

  Widget _amountBox(TextEditingController c, String label, {ValueChanged<String>? onChanged, String? hint}) => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCFC4FF), width: 1.4),
        ),
        child: Row(children: [
          Text(label, style: _j(12.5, FontWeight.w600, _muted)),
          const SizedBox(width: 8),
          Text('₹', style: _j(17, FontWeight.w800, _ink)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: _j(17, FontWeight.w800, _ink),
              onChanged: (v) {
                onChanged?.call(v);
                setState(() {});
              },
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint ?? '0',
                hintStyle: _j(17, FontWeight.w800, const Color(0xFFB9BCD6)),
              ),
            ),
          ),
        ]),
      );

  // ---- FULL PAID: pick the account; for cash, optional tendered amount → change
  List<Widget> _fullMode() => [
        _label('Received in'),
        _accountChips(account, (id) => setState(() => account = id)),
        if (_cashSelected) ...[
          const SizedBox(height: 12),
          _amountBox(received, 'Cash given', hint: Money.inr(total), onChanged: (_) => receivedTouched = true),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _quickAmt('Exact', total),
            for (final n in [50000, 100000, 200000, 500000])
              if (n >= total ~/ 4 && n < total * 3) _quickAmt('₹${Money.inr(n)}', n),
            _quickAmt('Next ₹500', ((total + 49999) ~/ 50000) * 50000),
          ]),
        ],
      ];

  // ---- DUE: advance presets, advance account
  List<Widget> _dueMode() {
    const presets = [(0, 'Nothing'), (25, '25%'), (50, 'Half'), (75, '75%'), (-1, 'Custom')];
    return [
      _label('Advance / deposit now'),
      Row(children: [
        for (final p in presets) ...[
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => advancePct = p.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 52,
                decoration: BoxDecoration(
                  gradient: advancePct == p.$1 ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]) : null,
                  color: advancePct == p.$1 ? null : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: advancePct == p.$1 ? null : Border.all(color: _line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(p.$2, style: _j(12, FontWeight.w800, advancePct == p.$1 ? Colors.white : _ink)),
                  if (p.$1 > 0)
                    Text(Money.compact((total * p.$1 ~/ 100) ~/ 100 * 100),
                        style: _j(9.5, FontWeight.w600, advancePct == p.$1 ? const Color(0xE6FFFFFF) : _muted)),
                ]),
              ),
            ),
          ),
          if (p != presets.last) const SizedBox(width: 6),
        ],
      ]),
      if (advancePct < 0) ...[
        const SizedBox(height: 10),
        _amountBox(advanceCtrl, 'Advance'),
      ],
      if (paid > 0) ...[
        const SizedBox(height: 12),
        _label('Advance received in'),
        _accountChips(account, (id) => setState(() => account = id)),
      ],
      if (customer != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: _muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${customer!['name']} will owe ${Money.rs((dues[asInt(customer!['id'])] ?? 0) + due)} in total after this bill',
              style: _j(11.5, FontWeight.w600, _muted),
            ),
          ),
        ]),
      ],
    ];
  }

  // ---- SPLIT: several accounts, auto-balancing, presets
  List<Widget> _splitMode() {
    final diff = total - splitSum;
    return [
      Row(children: [
        _label('Split between accounts'),
        const Spacer(),
        for (final p in const [(50, '50/50'), (70, '70/30')]) ...[
          GestureDetector(
            onTap: () => setState(() => _splitPreset(p.$1)),
            child: Container(
              margin: const EdgeInsets.only(left: 6, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF1F2FA), borderRadius: BorderRadius.circular(10)),
              child: Text(p.$2, style: _j(11.5, FontWeight.w800, _ink)),
            ),
          ),
        ],
        GestureDetector(
          onTap: () => setState(_smartSplit),
          child: Container(
            margin: const EdgeInsets.only(left: 6, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF5B2EE0)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text('Smart', style: _j(11.5, FontWeight.w800, Colors.white)),
            ]),
          ),
        ),
      ]),
      for (var i = 0; i < splits.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEF0F8)),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final a in accounts)
                      GestureDetector(
                        onTap: () => setState(() => splits[i].account = asInt(a['id'])),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: splits[i].account == asInt(a['id'])
                                ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)])
                                : null,
                            color: splits[i].account == asInt(a['id']) ? null : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: splits[i].account == asInt(a['id']) ? null : Border.all(color: _line),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_accIcon(a['kind'] as String?), size: 15,
                                color: splits[i].account == asInt(a['id']) ? Colors.white : _purple),
                            const SizedBox(width: 4),
                            Text(a['name'] as String,
                                style: _j(11.5, FontWeight.w700, splits[i].account == asInt(a['id']) ? Colors.white : _ink)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
              if (splits.length > 2)
                GestureDetector(
                  onTap: () => setState(() => splits.removeAt(i)),
                  child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.close_rounded, color: _red, size: 20)),
                ),
            ]),
            const SizedBox(height: 8),
            _amountBox(splits[i].ctrl, 'Amount', onChanged: (_) => _balanceFrom(i)),
            if (total > 0 && _parse(splits[i].ctrl) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_parse(splits[i].ctrl) / total).clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: const Color(0xFFEDEBFA),
                    valueColor: const AlwaysStoppedAnimation(_purple),
                  ),
                ),
              ),
          ]),
        ),
      if (splits.length < accounts.length)
        TextButton.icon(
          onPressed: () => setState(() {
            final used = splits.map((sp) => sp.account).toSet();
            final next = accounts.firstWhere((a) => !used.contains(asInt(a['id'])), orElse: () => accounts.first);
            splits.add(_Split()..account = asInt(next['id']));
          }),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add another account'),
        ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: diff == 0 ? const Color(0xFFE3F7EC) : diff > 0 ? const Color(0xFFFFF1DC) : const Color(0xFFFDE4EA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(diff == 0 ? Icons.check_circle_rounded : diff > 0 ? Icons.info_rounded : Icons.error_rounded,
              size: 17, color: diff == 0 ? _green : diff > 0 ? _amber : _red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              diff == 0
                  ? 'Split matches the bill exactly'
                  : diff > 0
                      ? '${Money.rs(diff)} left — it will go to the customer\'s due'
                      : '${Money.rs(-diff)} more than the bill — reduce an amount',
              style: _j(12, FontWeight.w700, diff == 0 ? const Color(0xFF0E6E47) : diff > 0 ? const Color(0xFF9A5B00) : _red),
            ),
          ),
        ]),
      ),
    ];
  }

  Widget _quickAmt(String label, int v) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            receivedTouched = true;
            received.text = Money.edit(v);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFF1F2FA), borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: _j(12, FontWeight.w700, _ink)),
        ),
      );

  Widget _stat(String l, String v, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: _j(11, FontWeight.w600, c)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _j(16, FontWeight.w800, _ink))),
        ]),
      );

  void _showUpiQr(String upiId) {
    final name = settings['business_name'] ?? 'GameX PC Hub';
    final amt = (paid / 100).toStringAsFixed(2);
    final data = 'upi://pay?pa=${Uri.encodeComponent(upiId)}&pn=${Uri.encodeComponent(name)}&am=$amt&cu=INR'
        '&tn=${Uri.encodeComponent('Invoice $nextNo')}';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Scan to pay', style: _j(18, FontWeight.w800, _navy)),
            const SizedBox(height: 4),
            Text('$name · $upiId', style: _j(12, FontWeight.w500, _muted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: _card(),
              child: QrImageView(data: data, size: 220),
            ),
            const SizedBox(height: 14),
            Text(Money.rs(paid), style: _j(26, FontWeight.w800, _ink)),
            Text('Any UPI app — GPay, PhonePe, Paytm, BHIM', style: _j(12, FontWeight.w500, _muted)),
          ]),
        ),
      ),
    );
  }

  Widget _noteField() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _card(r: 18),
        child: TextField(
          controller: note,
          style: _j(13.5, FontWeight.w500, _ink),
          decoration: InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            icon: const Icon(Icons.sticky_note_2_rounded, color: Color(0xFF8B7FD6)),
            hintText: 'Note (warranty, delivery, exchange details…)',
            hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
          ),
        ),
      );

  // ---------------------------------------------------------------- checkout
  Widget _checkoutBar(double safe) {
    final ready = cart.isNotEmpty && !saving;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safe),
      decoration: const BoxDecoration(
        color: Color(0xF7FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 24, offset: Offset(0, -6), spreadRadius: -8)],
      ),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cart.isEmpty ? 'No items' : '$qtyTotal item${qtyTotal == 1 ? '' : 's'} · ${due > 0 ? 'due ${Money.compact(due)}' : 'fully paid'}',
                style: _j(11.5, FontWeight.w600, due > 0 ? _red : _muted)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(total), style: _j(22, FontWeight.w800, _navy))),
          ]),
        ),
        GestureDetector(
          onTap: ready ? _charge : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: ready ? 1 : .5,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [Color(0xFF1BB574), Color(0xFF0F8C58)]),
                boxShadow: const [BoxShadow(color: Color(0x8016A36A), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
              ),
              alignment: Alignment.center,
              child: saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(editing ? 'Update sale' : 'Complete sale', style: _j(15, FontWeight.w800, Colors.white)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Customer picker sheet
// =============================================================================
class _CustomerSheet extends StatefulWidget {
  final List<Rec> customers;
  final Map<int, int> dues;
  const _CustomerSheet({required this.customers, required this.dues});
  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.customers
        .where((c) => q.isEmpty || '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: .75,
      maxChildSize: .95,
      minChildSize: .4,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(color: _bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Expanded(child: Text('Choose customer', style: _j(18, FontWeight.w800, _navy))),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, 'new'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('New'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(hintText: 'Search name or phone', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              _tile(
                leading: const Icon(Icons.storefront_rounded, color: Color(0xFF475569)),
                title: 'Walk-in customer',
                sub: 'Cash sale, no account',
                onTap: () => Navigator.pop(context, 'walkin'),
              ),
              for (final c in list)
                _tile(
                  leading: Text((c['name'] as String).isEmpty ? '?' : (c['name'] as String)[0].toUpperCase(),
                      style: _j(17, FontWeight.w800, const Color(0xFF139DB0))),
                  title: c['name'] as String,
                  sub: '${c['phone'] ?? ''}',
                  due: widget.dues[asInt(c['id'])] ?? 0,
                  onTap: () => Navigator.pop(context, c),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile({required Widget leading, required String title, required String sub, int due = 0, required VoidCallback onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: const Color(0xFFE2FAFA), borderRadius: BorderRadius.circular(13)),
                  alignment: Alignment.center,
                  child: leading,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: _j(14, FontWeight.w700, _ink)),
                    if (sub.isNotEmpty) Text(sub, style: _j(11.5, FontWeight.w500, _muted)),
                  ]),
                ),
                if (due > 0) Text('Due ${Money.compact(due)}', style: _j(11.5, FontWeight.w800, _red)),
              ]),
            ),
          ),
        ),
      );
}

// =============================================================================
// Sale complete
// =============================================================================
class SaleSuccessScreen extends StatelessWidget {
  final int saleId;
  final int change;
  const SaleSuccessScreen({super.key, required this.saleId, this.change = 0});

  Future<(Rec, List<Rec>, Map<String, String>)> _load() async {
    final s = (await Books.query(
            'SELECT s.*, c.name AS customer, c.phone AS phone FROM sales s LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id = ?',
            [saleId]))
        .first;
    return (s, await Books.query('SELECT * FROM sale_items WHERE sale_id = ?', [saleId]), await Books.settings());
  }

  Future<void> _whatsApp(BuildContext context, Rec s, List<Rec> items, Map<String, String> st) async {
    final text = invoiceText(st, s, items);
    var phone = (s['phone'] as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 10) phone = '91$phone';
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) toast(context, 'WhatsApp not available — invoice copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<(Rec, List<Rec>, Map<String, String>)>(
          load: _load,
          builder: (context, d) {
            final s = d.$1;
            final due = asInt(s['total']) - asInt(s['paid']);
            return ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 30), children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF34D399), Color(0xFF0F8C58)]),
                      boxShadow: [BoxShadow(color: Color(0x8016A36A), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -6)],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 64),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(child: Text('Sale completed!', style: _j(22, FontWeight.w800, _navy))),
              const SizedBox(height: 4),
              Center(
                child: Text('${s['number']} · ${(s['customer'] as String?) ?? 'Walk-in customer'}',
                    style: _j(13, FontWeight.w600, _muted)),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: _card(),
                child: Column(children: [
                  Text(Money.rs(asInt(s['total'])), style: _j(32, FontWeight.w800, _ink)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _pill('Paid', Money.rs(asInt(s['paid'])), _green)),
                    const SizedBox(width: 10),
                    Expanded(child: _pill('Due', Money.rs(due), due > 0 ? _red : _muted)),
                  ]),
                  if (change > 0) ...[
                    const SizedBox(height: 10),
                    _pill('Return change', Money.rs(change), _amber),
                  ],
                ]),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: _action(Icons.print_rounded, 'Print bill', const [Color(0xFF6B35EE), Color(0xFF4318D2)],
                      () => quickPrint(context, saleId)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _action(Icons.tune_rounded, 'Custom print', const [Color(0xFFFF8A3D), Color(0xFFE0245E)],
                      () => open(context, PrintStudio(saleId: saleId))),
                ),
              ]),
              const SizedBox(height: 10),
              _action(Icons.picture_as_pdf_rounded, 'Share PDF bill', const [Color(0xFF38BDF8), Color(0xFF0E7490)],
                  () => shareInvoicePdf(context, saleId)),
              const SizedBox(height: 10),
              _action(Icons.send_rounded, 'Send invoice on WhatsApp', const [Color(0xFF25D366), Color(0xFF128C7E)],
                  () => _whatsApp(context, s, d.$2, d.$3)),
              const SizedBox(height: 10),
              _action(Icons.receipt_long_rounded, 'View invoice', const [Color(0xFF1B2163), Color(0xFF3F5BEA)],
                  () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SaleView(id: saleId)))),
              const SizedBox(height: 10),
              _action(Icons.add_shopping_cart_rounded, 'Start a new sale', const [Color(0xFF38BDF8), Color(0xFF2563EB)],
                  () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SaleForm()))),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Done', style: _j(15, FontWeight.w800, _purple)),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _pill(String l, String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(child: Text(l, style: _j(12, FontWeight.w700, c))),
          Text(v, style: _j(14, FontWeight.w800, _ink)),
        ]),
      );

  Widget _action(IconData icon, String label, List<Color> colors, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withAlpha(0x66), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -6)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Text(label, style: _j(14.5, FontWeight.w800, Colors.white)),
          ]),
        ),
      );
}


/// "Which product is this device?" — shown for an IMEI the app hasn't seen.
class _PickProductSheet extends StatefulWidget {
  final List<Rec> products;
  final String code;
  final String? hint; // model name found from the IMEI, if any
  const _PickProductSheet({required this.products, required this.code, this.hint});
  @override
  State<_PickProductSheet> createState() => _PickProductSheetState();
}

class _PickProductSheetState extends State<_PickProductSheet> {
  late String q = _hintWords();

  /// First two words of the model name ("Galaxy A15") make a good search.
  String _hintWords() {
    final h = (widget.hint ?? '').trim();
    if (h.isEmpty) return '';
    final w = h.split(RegExp(r'\s+'));
    return w.length > 2 ? w.sublist(w.length - 2).join(' ') : h;
  }

  @override
  Widget build(BuildContext context) {
    final l = q.toLowerCase();
    final rows = widget.products
        .where((p) => q.isEmpty || [p['name'], p['brand'], p['variant'], p['category']].any((v) => v != null && '$v'.toLowerCase().contains(l)))
        .take(40)
        .toList();
    return Container(
      height: MediaQuery.of(context).size.height * .78,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.smartphone_rounded, color: _purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Which product is this?', style: _j(17, FontWeight.w800, _navy)),
                Text(widget.hint == null ? 'New model for ${widget.code} — the app will remember it' : 'IMEI says: ${widget.hint}',
                    style: _j(11.5, FontWeight.w600, _muted)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: TextFormField(
            initialValue: q,
            autofocus: true,
            onChanged: (v) => setState(() => q = v.trim()),
            decoration: const InputDecoration(hintText: 'Search product', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final p in rows)
              ListTile(
                leading: ProductThumb(p, width: 40, height: 44),
                title: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w700, _ink)),
                subtitle: Text([p['variant'], 'Stock ${p['stock']}'].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                    style: _j(11, FontWeight.w500, _muted)),
                trailing: Text(Money.rs(asInt(p['price'])), style: _j(13, FontWeight.w800, _purple)),
                onTap: () => Navigator.pop(context, p),
              ),
          ]),
        ),
      ]),
    );
  }
}
