import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'product_form.dart';
import 'products.dart';
import 'sales.dart';
import 'scanner.dart';

// =============================================================================
// New Purchase — supplier bill entry.
// Supplier search with payable · duplicate bill-no guard · bill photo ·
// product search / barcode scan · IMEI-by-IMEI device intake (one line per
// unit) · purchase-rate intelligence (last rate, price change, margin at the
// current selling price) · CGST/SGST or IGST · paid now / credit ·
// success summary with stock movement.
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

InputDecoration _bare(String hint) => InputDecoration(
      isCollapsed: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      hintText: hint,
      hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
    );

class _PLine {
  final Rec p;
  int qty;
  int rate; // purchase rate per unit, before GST (paise)
  final serial = TextEditingController();
  final int? lastRate;
  _PLine(this.p, {this.qty = 1, required this.rate, this.lastRate});
  int get id => asInt(p['id']);
  int get gstBp => asInt(p['gst_bp']);
  int get amount => rate * qty;
  int get tax => Money.percent(amount, gstBp);
  int get sellPrice => asInt(p['price']);
  double get marginPct => sellPrice == 0 ? 0 : (sellPrice - rate) * 100 / sellPrice;
  double? get changePct => (lastRate == null || lastRate == 0) ? null : (rate - lastRate!) * 100 / lastRate!;
  bool get isDevice => (p['category'] as String? ?? '').toLowerCase().contains(RegExp('mobile|laptop|tablet|desktop'));
}

class PurchaseForm extends StatefulWidget {
  final int? supplierId;
  final int? editPurchaseId; // edit an existing purchase in place
  const PurchaseForm({super.key, this.supplierId, this.editPurchaseId});
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  List<Rec> products = [], suppliers = [], accounts = [];
  Map<int, int> payables = {};
  Map<int, int> lastRates = {};
  final lines = <_PLine>[];
  Rec? supplier;
  int? account;
  String date = ymd(DateTime.now());
  String? billImage;
  bool interState = false;
  bool duplicateBill = false;
  bool saving = false;
  String payMode = 'credit'; // full | partial | credit
  final billNo = TextEditingController();
  final search = TextEditingController();
  final paidCtrl = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
    billNo.addListener(_checkBill);
    _load();
  }

  @override
  void dispose() {
    for (final l in lines) {
      l.serial.dispose();
    }
    billNo.dispose();
    search.dispose();
    paidCtrl.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    products = await Books.query(
        'SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id ORDER BY p.name COLLATE NOCASE');
    suppliers = await Books.query('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE');
    payables = await Books.partyBalances('supplier');
    accounts = await Books.moneyAccounts(withCards: true);
    final rates = await Books.query('SELECT i.product_id AS pid, i.rate AS rate FROM purchase_items i '
        'JOIN purchases p ON p.id = i.purchase_id ORDER BY p.date DESC, p.id DESC');
    lastRates = {};
    for (final r in rates) {
      lastRates.putIfAbsent(asInt(r['pid']), () => asInt(r['rate']));
    }
    account ??= accounts.isNotEmpty ? asInt(accounts.first['id']) : null;
    if (widget.supplierId != null && supplier == null) {
      for (final s in suppliers) {
        if (asInt(s['id']) == widget.supplierId) supplier = s;
      }
    }
    if (widget.editPurchaseId != null && !_editLoaded) await _loadEdit(widget.editPurchaseId!);
    if (mounted) setState(() {});
  }

  bool _editLoaded = false;
  String editNumber = '';
  bool get editing => widget.editPurchaseId != null;

  Future<void> _loadEdit(int id) async {
    final b = await Books.query('SELECT * FROM purchases WHERE id = ?', [id]);
    if (b.isEmpty) return;
    _editLoaded = true;
    final bill = b.first;
    editNumber = '${bill['number']}';
    supplier = suppliers.where((s) => asInt(s['id']) == asInt(bill['supplier_id'])).firstOrNull;
    date = '${bill['date']}';
    billNo.text = '${bill['bill_no'] ?? ''}';
    billImage = bill['bill_image'] as String?;
    var n = '${bill['note'] ?? ''}';
    if (n.startsWith('IGST (inter-state)')) {
      interState = true;
      n = n.replaceFirst('IGST (inter-state)', '').replaceFirst(RegExp(r'^\s*·\s*'), '');
    }
    note.text = n;
    if (bill['account_id'] != null) account = asInt(bill['account_id']);
    final total = asInt(bill['total']), paid = asInt(bill['paid']);
    payMode = paid >= total ? 'full' : paid > 0 ? 'partial' : 'credit';
    if (payMode == 'partial') paidCtrl.text = Money.edit(paid);
    for (final i in await Books.query('SELECT * FROM purchase_items WHERE purchase_id = ? ORDER BY id', [id])) {
      final p = products.where((p) => asInt(p['id']) == asInt(i['product_id'])).firstOrNull;
      if (p == null) continue;
      final l = _PLine(p, qty: asInt(i['qty']), rate: asInt(i['rate']), lastRate: lastRates[asInt(i['product_id'])]);
      l.serial.text = '${i['serial'] ?? ''}';
      lines.add(l);
    }
  }

  Future<void> _checkBill() async {
    final s = supplier, b = billNo.text.trim();
    var dup = false;
    if (s != null && b.isNotEmpty) {
      final r = await Books.query('SELECT id FROM purchases WHERE supplier_id = ? AND bill_no = ? AND id != ?',
          [asInt(s['id']), b, widget.editPurchaseId ?? -1]);
      dup = r.isNotEmpty;
    }
    if (mounted && dup != duplicateBill) setState(() => duplicateBill = dup);
  }

  // ---------------------------------------------------------------- totals
  int get subtotal => lines.fold(0, (a, l) => a + l.amount);
  int get tax => lines.fold(0, (a, l) => a + l.tax);
  int get total => subtotal + tax;
  int get units => lines.fold(0, (a, l) => a + l.qty);
  int get paid {
    switch (payMode) {
      case 'full':
        return total;
      case 'partial':
        try {
          return math.min(Money.parse(paidCtrl.text), total);
        } catch (_) {
          return 0;
        }
      default:
        return 0;
    }
  }

  int get payableNow => (supplier == null ? 0 : payables[asInt(supplier!['id'])] ?? 0) + total - paid;

  // ---------------------------------------------------------------- lines
  void _add(Rec p, {String? serial}) {
    HapticFeedback.selectionClick();
    final pid = asInt(p['id']);
    final last = lastRates[pid];
    final rate = last ?? asInt(p['cost']);
    setState(() {
      final same = lines.where((l) => l.id == pid && l.serial.text.isEmpty && serial == null).toList();
      if (same.isNotEmpty) {
        same.first.qty++;
      } else {
        final l = _PLine(p, rate: rate, lastRate: last);
        if (serial != null) l.serial.text = serial;
        lines.add(l);
      }
      search.clear();
    });
  }

  Future<void> _scanProduct() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan product barcode');
    if (code == null || !mounted) return;
    for (final p in products) {
      if ((p['sku'] as String?)?.trim() == code) {
        _add(p);
        return;
      }
    }
    final create = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New product?'),
        content: Text('No product has barcode “$code”. Create it now?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
        ],
      ),
    );
    if (create == true && mounted) {
      await open(context, const ProductForm());
      await _load();
    }
  }

  /// Scans IMEIs one after another; each becomes its own line of qty 1.
  Future<void> _scanUnits(_PLine l) async {
    var added = 0;
    while (mounted) {
      final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI / serial #${added + 1}');
      if (code == null || !mounted) break;
      final dupe = lines.any((x) => x.serial.text.trim() == code.trim());
      if (dupe) {
        toast(context, 'IMEI $code is already on this bill', error: true);
        continue;
      }
      setState(() {
        if (l.serial.text.isEmpty && l.qty == 1 && added == 0) {
          l.serial.text = code;
        } else {
          final n = _PLine(l.p, rate: l.rate, lastRate: l.lastRate);
          n.serial.text = code;
          lines.insert(lines.indexOf(l) + 1 + added, n);
          if (l.serial.text.isEmpty && l.qty > 1) l.qty--;
        }
      });
      added++;
      final more = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$added unit${added == 1 ? '' : 's'} scanned'),
          content: Text('Last: $code'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Done')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Scan next')),
          ],
        ),
      );
      if (more != true) break;
    }
  }

  Future<void> _editRate(_PLine l) async {
    final c = TextEditingController(text: Money.edit(l.rate));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Purchase rate · ${l.p['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Rate per unit (before GST)'),
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (l.lastRate != null) 'Last bought at ${Money.rs(l.lastRate!)}',
              'Avg cost ${Money.rs(asInt(l.p['cost']))}',
              'Selling ${Money.rs(l.sellPrice)}',
            ].join(' · '),
            style: _j(12, FontWeight.w500, _muted),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Set rate')),
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

  // ---------------------------------------------------------------- supplier
  Future<void> _pickSupplier() async {
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierSheet(suppliers: suppliers, payables: payables),
    );
    if (r == 'new') {
      await open(context, const PartyForm(type: 'supplier'));
      await _load();
      if (suppliers.isNotEmpty) {
        final newest = [...suppliers]..sort((a, b) => asInt(b['id']).compareTo(asInt(a['id'])));
        setState(() => supplier = newest.first);
      }
    } else if (r is Map<String, Object?>) {
      setState(() => supplier = r);
    }
    _checkBill();
  }

  // ---------------------------------------------------------------- save
  Future<void> _save() async {
    if (saving) return;
    if (supplier == null) {
      toast(context, 'Choose the supplier', error: true);
      return;
    }
    if (lines.isEmpty) {
      toast(context, 'Add at least one product', error: true);
      return;
    }
    if (lines.any((l) => l.rate <= 0)) {
      toast(context, 'Every item needs a purchase rate', error: true);
      return;
    }
    if (duplicateBill) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Duplicate bill number'),
          content: Text('Bill “${billNo.text}” from ${supplier!['name']} is already entered. Save it again?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final before = {for (final l in lines) l.id: asInt(l.p['stock'])};
    final noteText = [if (interState) 'IGST (inter-state)', if (note.text.trim().isNotEmpty) note.text.trim()].join(' · ');
    setState(() => saving = true);
    try {
      final id = await Books.createPurchase(
        editId: widget.editPurchaseId,
        items: [for (final l in lines) ItemIn(l.id, l.qty, l.rate, l.serial.text)],
        supplierId: asInt(supplier!['id']),
        paid: paid,
        accountId: account,
        date: date,
        billNo: billNo.text.trim().isEmpty ? null : billNo.text.trim(),
        note: noteText.isEmpty ? null : noteText,
        billImage: billImage,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      if (editing) {
        toast(context, 'Purchase $editNumber updated');
        Navigator.of(context).pop(true);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PurchaseSuccessScreen(purchaseId: id, before: before)));
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
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
              _supplierCard(),
              const SizedBox(height: 14),
              _billCard(),
              const SizedBox(height: 14),
              _searchBar(),
              if (search.text.trim().isNotEmpty) _results(),
              const SizedBox(height: 14),
              _itemsCard(),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 14),
                _insights(),
                const SizedBox(height: 14),
                _summary(),
                const SizedBox(height: 14),
                _payment(),
              ],
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _saveBar(safe)),
      ]),
    );
  }

  Widget _header() => Row(children: [
        _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editing ? 'Edit Purchase $editNumber' : 'New Purchase', style: _j(21, FontWeight.w800, _navy)),
            Text('Supplier bill · stock in · payable', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
          ]),
        ),
        GestureDetector(
          onTap: _scanProduct,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFB58CFF), Color(0xFF7B3FF2)]),
              boxShadow: [BoxShadow(color: Color(0x664A17C9), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
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

  Widget _supplierCard() {
    final s = supplier;
    final pay = s == null ? 0 : payables[asInt(s['id'])] ?? 0;
    return GestureDetector(
      onTap: _pickSupplier,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  colors: s == null ? const [Color(0xFFE2E8F0), Color(0xFFCBD5E1)] : const [Color(0xFFFFA24A), Color(0xFFF06A1A)]),
            ),
            child: Icon(Icons.local_shipping_rounded, color: s == null ? const Color(0xFF475569) : Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s == null ? 'Choose supplier *' : s['name'] as String,
                  style: _j(15, FontWeight.w800, s == null ? _purple : _ink)),
              const SizedBox(height: 2),
              Text(
                s == null
                    ? 'Distributor / wholesaler you are buying from'
                    : [s['phone'], if (s['gstin'] != null) 'GSTIN ${s['gstin']}'].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                style: _j(11.5, FontWeight.w500, _muted),
              ),
            ]),
          ),
          if (s != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pay > 0 ? const Color(0xFFFFF1DC) : const Color(0xFFE3F7EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(pay > 0 ? 'To pay ${Money.compact(pay)}' : 'Settled',
                  style: _j(11, FontWeight.w800, pay > 0 ? const Color(0xFF9A5B00) : const Color(0xFF0E6E47))),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.unfold_more_rounded, color: Color(0xFFB9BCD6)),
        ]),
      ),
    );
  }

  Widget _billCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: duplicateBill ? const Color(0xFFF5B5C2) : _line),
              ),
              child: Row(children: [
                const Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF8B7FD6)),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: billNo, style: _j(14, FontWeight.w700, _ink), decoration: _bare('Supplier bill no.'))),
              ]),
            ),
          ),
          const SizedBox(width: 10),
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
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line),
              ),
              child: Row(children: [
                const Icon(Icons.event_rounded, size: 18, color: _purple),
                const SizedBox(width: 6),
                Text(date == ymd(DateTime.now()) ? 'Today' : prettyDate(date), style: _j(13, FontWeight.w700, _ink)),
              ]),
            ),
          ),
        ]),
        if (duplicateBill)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.error_rounded, color: _red, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text('This bill no. is already entered for this supplier', style: _j(11.5, FontWeight.w700, _red)),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          GestureDetector(
            onTap: () async {
              final r = await pickPhoto(context, folder: 'bills', allowRemove: billImage != null);
              if (r != null) setState(() => billImage = r.isEmpty ? null : r);
            },
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F3FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6CCFF), width: 1.4),
              ),
              clipBehavior: Clip.antiAlias,
              child: billImage == null
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.document_scanner_rounded, color: _purple),
                      const SizedBox(height: 4),
                      Text('Bill photo', style: _j(10, FontWeight.w700, _purple)),
                    ])
                  : storedImage(billImage),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tax type', style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
              const SizedBox(height: 6),
              Row(children: [
                _toggle('CGST + SGST', !interState, () => setState(() => interState = false)),
                const SizedBox(width: 6),
                _toggle('IGST', interState, () => setState(() => interState = true)),
              ]),
              const SizedBox(height: 6),
              Text(interState ? 'Supplier is in another state' : 'Supplier is in your state', style: _j(10.5, FontWeight.w500, _muted)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _toggle(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
              color: on ? null : const Color(0xFFF1F2FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(label, style: _j(11.5, FontWeight.w800, on ? Colors.white : _ink)),
          ),
        ),
      );

  Widget _searchBar() => Container(
        height: 52,
        decoration: _card(r: 26),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          const Icon(Icons.add_box_rounded, color: _purple),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: search, style: _j(14, FontWeight.w600, _ink), decoration: _bare('Add product — search name, brand, barcode'))),
          if (search.text.isNotEmpty) GestureDetector(onTap: search.clear, child: const Icon(Icons.close_rounded, color: _muted, size: 20)),
        ]),
      );

  Widget _results() {
    final q = search.text.trim().toLowerCase();
    final r = products
        .where((p) => [p['name'], p['brand'], p['sku'], p['variant'], p['category']].any((v) => v != null && '$v'.toLowerCase().contains(q)))
        .take(8)
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: _card(),
      child: Column(children: [
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
                      'Stock ${r[i]['stock']} · last ${lastRates[asInt(r[i]['id'])] == null ? '—' : Money.rs(lastRates[asInt(r[i]['id'])]!)}',
                      style: _j(11, FontWeight.w500, _muted),
                    ),
                  ]),
                ),
                const Icon(Icons.add_circle_rounded, color: _purple),
              ]),
            ),
          ),
        ],
        InkWell(
          onTap: () async {
            await open(context, const ProductForm());
            await _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.add_rounded, color: _purple),
              const SizedBox(width: 8),
              Text('Create a new product', style: _j(13, FontWeight.w800, _purple)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _itemsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.inventory_2_rounded, color: _purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Items received', style: _j(15, FontWeight.w800, _ink))),
          if (lines.isNotEmpty) Text('$units unit${units == 1 ? '' : 's'}', style: _j(12, FontWeight.w700, _muted)),
        ]),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Column(children: [
                Image.asset('assets/home/box.png', width: 90, height: 90),
                const SizedBox(height: 8),
                Text('No items yet', style: _j(14, FontWeight.w800, _ink)),
                Text('Search above or scan the product barcode', style: _j(12, FontWeight.w500, _muted)),
              ]),
            ),
          ),
        for (final l in lines) _lineTile(l),
      ]),
    );
  }

  Widget _lineTile(_PLine l) {
    final ch = l.changePct;
    final m = l.marginPct;
    return Dismissible(
      key: ObjectKey(l),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(color: const Color(0xFFFDE4EA), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_rounded, color: _red),
      ),
      onDismissed: (_) => setState(() => lines.remove(l)),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: m < 0 ? const Color(0xFFF5B5C2) : const Color(0xFFEEF0F8)),
        ),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProductThumb(l.p, width: 54, height: 60),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
                Text('Stock ${l.p['stock']} → ${asInt(l.p['stock']) + l.qty}', style: _j(11, FontWeight.w600, _green)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _editRate(l),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(Money.rs(l.rate), style: _j(13, FontWeight.w800, const Color(0xFF1C1CA0))),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_rounded, size: 13, color: _purple),
                    if (ch != null && ch.abs() >= 0.5) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (ch > 0 ? _red : _green).withAlpha(0x1F),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${ch > 0 ? '▲' : '▼'} ${ch.abs().toStringAsFixed(1)}%',
                            style: _j(10, FontWeight.w800, ch > 0 ? _red : _green)),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.rs(l.amount + l.tax), style: _j(14, FontWeight.w800, _ink)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _qtyBtn(Icons.remove_rounded, () {
                    setState(() {
                      if (l.qty > 1) {
                        l.qty--;
                      } else {
                        lines.remove(l);
                      }
                    });
                  }),
                  SizedBox(width: 30, child: Text('${l.qty}', textAlign: TextAlign.center, style: _j(14, FontWeight.w800, _ink))),
                  _qtyBtn(Icons.add_rounded, () => setState(() => l.qty++)),
                ]),
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(m < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded, size: 15, color: m < 0 ? _red : _green),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                l.sellPrice == 0
                    ? 'No selling price set'
                    : 'Sells at ${Money.rs(l.sellPrice)} · margin ${m.toStringAsFixed(1)}%${m < 0 ? ' — buying above selling price!' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _j(11, FontWeight.w600, m < 0 ? _red : const Color(0xFF3A4155)),
              ),
            ),
          ]),
          if (l.isDevice)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                    child: Row(children: [
                      const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFF8B7FD6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: l.serial,
                          style: _j(12.5, FontWeight.w600, _ink),
                          decoration: _bare(l.qty > 1 ? 'IMEI (or scan units)' : 'IMEI / serial number'),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _scanUnits(l),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.qr_code_scanner_rounded, size: 17, color: _purple),
                      const SizedBox(width: 4),
                      Text('Scan units', style: _j(11.5, FontWeight.w800, _purple)),
                    ]),
                  ),
                ),
              ]),
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

  Widget _insights() {
    final up = lines.where((l) => (l.changePct ?? 0) >= 0.5).length;
    final down = lines.where((l) => (l.changePct ?? 0) <= -0.5).length;
    final loss = lines.where((l) => l.marginPct < 0).length;
    final sellValue = lines.fold<int>(0, (a, l) => a + l.sellPrice * l.qty);
    final expected = sellValue - subtotal;
    final avgMargin = sellValue == 0 ? 0.0 : expected * 100 / sellValue;
    Widget tile(IconData i, String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, color: c, size: 18),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: _j(15, FontWeight.w800, Colors.white))),
              Text(label, style: _j(10, FontWeight.w500, const Color(0xB3FFFFFF))),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF14164A), Color(0xFF2A1B6B)]),
        boxShadow: const [BoxShadow(color: Color(0x4014164A), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFFB9A5FF), size: 18),
          const SizedBox(width: 8),
          Text('Purchase insights', style: _j(14, FontWeight.w800, Colors.white)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          tile(Icons.savings_rounded, 'Expected profit', Money.compact(expected), const Color(0xFF6EE7B7)),
          const SizedBox(width: 8),
          tile(Icons.percent_rounded, 'Avg margin', '${avgMargin.toStringAsFixed(1)}%', const Color(0xFFB9A5FF)),
          const SizedBox(width: 8),
          tile(Icons.trending_up_rounded, 'Costlier', '$up', const Color(0xFFFF8A8A)),
          const SizedBox(width: 8),
          tile(Icons.trending_down_rounded, 'Cheaper', '$down', const Color(0xFF6EE7B7)),
        ]),
        if (loss > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8A8A), size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$loss item${loss == 1 ? ' is' : 's are'} bought above the selling price — update the price after saving.',
                  style: _j(11.5, FontWeight.w600, const Color(0xFFFFB4B4))),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _summary() {
    Widget row(String l, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(l, style: _j(13, bold ? FontWeight.w800 : FontWeight.w500, bold ? _ink : const Color(0xFF3A4155)))),
            Text(v, style: _j(bold ? 18 : 13, FontWeight.w800, bold ? _navy : _ink)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(children: [
        row('Taxable value ($units unit${units == 1 ? '' : 's'})', Money.rs(subtotal)),
        if (interState) row('IGST (input credit)', Money.rs(tax)) else ...[
          row('CGST (input credit)', Money.rs(tax ~/ 2)),
          row('SGST (input credit)', Money.rs(tax - tax ~/ 2)),
        ],
        const Divider(color: Color(0xFFEEF0F8)),
        row('Bill total', Money.rs(total), bold: true),
      ]),
    );
  }

  Widget _payment() {
    IconData icon(String? k) =>
        k == 'cash' ? Icons.payments_rounded : k == 'upi' ? Icons.qr_code_2_rounded : Icons.account_balance_rounded;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Payment to supplier', style: _j(15, FontWeight.w800, _ink)),
        const SizedBox(height: 10),
        Row(children: [
          _toggle('Pay in full', payMode == 'full', () => setState(() => payMode = 'full')),
          const SizedBox(width: 6),
          _toggle('Part pay', payMode == 'partial', () => setState(() => payMode = 'partial')),
          const SizedBox(width: 6),
          _toggle('On credit', payMode == 'credit', () => setState(() => payMode = 'credit')),
        ]),
        if (payMode == 'partial') ...[
          const SizedBox(height: 10),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCFC4FF), width: 1.4),
            ),
            child: Row(children: [
              Text('Paying ₹', style: _j(14, FontWeight.w700, _muted)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: paidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: _j(17, FontWeight.w800, _ink),
                  decoration: _bare('0'),
                ),
              ),
            ]),
          ),
        ],
        if (payMode != 'credit') ...[
          const SizedBox(height: 10),
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon(a['kind'] as String?), size: 17, color: account == asInt(a['id']) ? Colors.white : _purple),
                    const SizedBox(width: 6),
                    Text(a['name'] as String, style: _j(12.5, FontWeight.w700, account == asInt(a['id']) ? Colors.white : _ink)),
                  ]),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _stat('Paying now', Money.rs(paid), _green)),
          const SizedBox(width: 10),
          Expanded(child: _stat('Supplier payable after', Money.rs(payableNow), payableNow > 0 ? _amber : _muted)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFFFAFAFE), borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
          child: TextField(
            controller: note,
            style: _j(13, FontWeight.w500, _ink),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              icon: const Icon(Icons.sticky_note_2_rounded, color: Color(0xFF8B7FD6)),
              hintText: 'Note (transport, scheme, credit days…)',
              hintStyle: _j(12.5, FontWeight.w400, const Color(0xFFA3A7C2)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String l, String v, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w600, c)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _j(16, FontWeight.w800, _ink))),
        ]),
      );

  Widget _saveBar(double safe) {
    final ready = lines.isNotEmpty && supplier != null && !saving;
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
            Text(lines.isEmpty ? 'No items' : '$units unit${units == 1 ? '' : 's'} · ${paid == total ? 'paid' : 'credit ${Money.compact(total - paid)}'}',
                style: _j(11.5, FontWeight.w600, _muted)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(total), style: _j(22, FontWeight.w800, _navy))),
          ]),
        ),
        GestureDetector(
          onTap: ready ? _save : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: ready ? 1 : .5,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [Color(0xFF7B3FF2), Color(0xFF4318D2)]),
                boxShadow: const [BoxShadow(color: Color(0x804A17C9), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
              ),
              alignment: Alignment.center,
              child: saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.inventory_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(editing ? 'Update purchase' : 'Save & stock in', style: _j(15, FontWeight.w800, Colors.white)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Supplier picker
// =============================================================================
class _SupplierSheet extends StatefulWidget {
  final List<Rec> suppliers;
  final Map<int, int> payables;
  const _SupplierSheet({required this.suppliers, required this.payables});
  @override
  State<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<_SupplierSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.suppliers
        .where((c) => q.isEmpty || '${c['name']} ${c['phone'] ?? ''} ${c['gstin'] ?? ''}'.toLowerCase().contains(q.toLowerCase()))
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
              Expanded(child: Text('Choose supplier', style: _j(18, FontWeight.w800, _navy))),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, 'new'),
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('New'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(hintText: 'Search name, phone or GSTIN', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('No suppliers yet — tap New', style: _j(13, FontWeight.w500, _muted)))
                : ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                    for (final s in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pop(context, s),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(color: const Color(0xFFFFF1E0), borderRadius: BorderRadius.circular(13)),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.local_shipping_rounded, color: Color(0xFFF06A1A)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(s['name'] as String, style: _j(14, FontWeight.w700, _ink)),
                                    Text(
                                      [s['phone'], s['gstin']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                                      style: _j(11.5, FontWeight.w500, _muted),
                                    ),
                                  ]),
                                ),
                                if ((widget.payables[asInt(s['id'])] ?? 0) > 0)
                                  Text('Pay ${Money.compact(widget.payables[asInt(s['id'])]!)}',
                                      style: _j(11.5, FontWeight.w800, _amber)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// Purchase saved
// =============================================================================
class PurchaseSuccessScreen extends StatelessWidget {
  final int purchaseId;
  final Map<int, int> before; // product id → stock before this purchase
  const PurchaseSuccessScreen({super.key, required this.purchaseId, this.before = const {}});

  Future<(Rec, List<Rec>)> _load() async {
    final p = (await Books.query(
            'SELECT p.*, s.name AS supplier FROM purchases p JOIN suppliers s ON s.id = p.supplier_id WHERE p.id = ?',
            [purchaseId]))
        .first;
    final items = await Books.query(
        'SELECT i.product_id, i.name, SUM(i.qty) AS qty, pr.stock AS stock FROM purchase_items i '
        'JOIN products pr ON pr.id = i.product_id WHERE i.purchase_id = ? GROUP BY i.product_id',
        [purchaseId]);
    return (p, items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<(Rec, List<Rec>)>(
          load: _load,
          builder: (context, d) {
            final p = d.$1;
            final due = asInt(p['total']) - asInt(p['paid']);
            return ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 30), children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFFB58CFF), Color(0xFF5B2EE0)]),
                      boxShadow: [BoxShadow(color: Color(0x805B2EE0), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -6)],
                    ),
                    child: const Icon(Icons.inventory_rounded, color: Colors.white, size: 54),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(child: Text('Stock received!', style: _j(22, FontWeight.w800, _navy))),
              Center(
                child: Text('${p['number']}${p['bill_no'] != null ? ' · bill ${p['bill_no']}' : ''} · ${p['supplier']}',
                    textAlign: TextAlign.center, style: _j(13, FontWeight.w600, _muted)),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _card(),
                child: Column(children: [
                  Text(Money.rs(asInt(p['total'])), style: _j(30, FontWeight.w800, _ink)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _pill('Paid', Money.rs(asInt(p['paid'])), _green)),
                    const SizedBox(width: 10),
                    Expanded(child: _pill('Payable', Money.rs(due), due > 0 ? _amber : _muted)),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _card(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Stock updated', style: _j(15, FontWeight.w800, _ink)),
                  const SizedBox(height: 6),
                  for (final i in d.$2)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        const Icon(Icons.add_box_rounded, color: _green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(i['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13, FontWeight.w600, _ink))),
                        Text(
                          '${before[asInt(i['product_id'])] ?? (asInt(i['stock']) - asInt(i['qty']))} → ${i['stock']}',
                          style: _j(13, FontWeight.w800, _green),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 18),
              _action(Icons.receipt_long_rounded, 'View purchase bill', const [Color(0xFF7B4DFF), Color(0xFF4318D2)],
                  () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PurchaseView(id: purchaseId)))),
              const SizedBox(height: 10),
              _action(Icons.add_shopping_cart_rounded, 'Enter another purchase', const [Color(0xFF38BDF8), Color(0xFF2563EB)],
                  () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PurchaseForm()))),
              const SizedBox(height: 12),
              Center(
                child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Done', style: _j(15, FontWeight.w800, _purple))),
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
