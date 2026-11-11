import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../core/smart.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'products.dart';
import 'scanner.dart';

// =============================================================================
// Add / Edit Product — photo, Smart Assist, barcode scanning, variant builder,
// live pricing & GST calculator, stock & warranty, live preview.
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

const _ramChips = ['4GB', '6GB', '8GB', '12GB', '16GB', '32GB'];
const _phoneStorage = ['64GB', '128GB', '256GB', '512GB', '1TB'];
const _pcStorage = ['256GB SSD', '512GB SSD', '1TB SSD', '1TB HDD', '2TB SSD'];
const _colorChips = {
  'Black': Color(0xFF1F2937),
  'White': Color(0xFFF8FAFC),
  'Silver': Color(0xFFC0C4CC),
  'Space Grey': Color(0xFF6B7280),
  'Blue': Color(0xFF3B82F6),
  'Purple': Color(0xFF8B5CF6),
  'Deep Purple': Color(0xFF5B21B6),
  'Gold': Color(0xFFD4A84B),
  'Green': Color(0xFF22C55E),
  'Red': Color(0xFFEF4444),
  'Pink': Color(0xFFF472B6),
  'Titanium': Color(0xFFA8A29E),
};
const _gstRates = [0, 500, 1200, 1800, 2800];
const _warranty = [0, 3, 6, 12, 24];

class ProductForm extends StatefulWidget {
  final Rec? product;
  const ProductForm({super.key, this.product});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final name = TextEditingController();
  final brand = TextEditingController();
  final variant = TextEditingController();
  final sku = TextEditingController();
  final hsn = TextEditingController();
  final price = TextEditingController();
  final mrp = TextEditingController();
  final cost = TextEditingController();
  int qty = 0;
  int low = 2;
  int gstBp = 1800;
  int warrantyMonths = 0;
  String condition = 'new';
  int? category;
  String? image;
  List<Rec> categories = [];
  SmartGuess guess = const SmartGuess();
  Rec? duplicate;
  bool saving = false;
  String? ram, storage, colour;

  bool get isNew => widget.product == null;
  int? get _id => isNew ? null : asInt(widget.product!['id']);

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      name.text = '${p['name'] ?? ''}';
      brand.text = '${p['brand'] ?? ''}';
      variant.text = '${p['variant'] ?? ''}';
      sku.text = '${p['sku'] ?? ''}';
      hsn.text = '${p['hsn'] ?? ''}';
      price.text = Money.edit(asInt(p['price']));
      if (asInt(p['mrp']) > 0) mrp.text = Money.edit(asInt(p['mrp']));
      cost.text = Money.edit(asInt(p['cost']));
      low = asInt(p['low_stock']);
      gstBp = asInt(p['gst_bp']);
      warrantyMonths = asInt(p['warranty_months']);
      condition = (p['condition'] as String?) ?? 'new';
      category = p['category_id'] as int?;
      image = p['image'] as String?;
    }
    for (final c in [name, brand, variant, sku, hsn, price, mrp, cost]) {
      c.addListener(_changed);
    }
    name.addListener(_analyse);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final r = await Books.query('SELECT * FROM categories ORDER BY name');
    if (mounted) setState(() => categories = r);
  }

  @override
  void dispose() {
    for (final c in [name, brand, variant, sku, hsn, price, mrp, cost]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _analyse() => setState(() => guess = Smart.analyse(name.text));

  int _m(TextEditingController c) {
    try {
      return Money.parse(c.text);
    } catch (_) {
      return 0;
    }
  }

  String? get _categoryName {
    for (final c in categories) {
      if (asInt(c['id']) == category) return c['name'] as String;
    }
    return null;
  }

  bool get _isPc {
    final c = (_categoryName ?? '').toLowerCase();
    return c.contains('laptop') || c.contains('desktop') || c.contains('pc');
  }

  // ---------------------------------------------------------------- smart assist
  Future<void> _applyGuess({bool all = true, String? only}) async {
    final g = guess;
    HapticFeedback.lightImpact();
    if ((all || only == 'category') && g.category != null) {
      final id = await Books.addCategory(g.category!);
      await _loadCategories();
      category = id;
    }
    if ((all || only == 'brand') && g.brand != null) brand.text = g.brand!;
    if ((all || only == 'hsn') && g.hsn != null) {
      hsn.text = g.hsn!;
      if (g.gstBp != null) gstBp = g.gstBp!;
    }
    if ((all || only == 'variant') && g.variant.isNotEmpty) {
      ram = g.ram;
      storage = g.storage;
      colour = g.color;
      variant.text = g.variant;
    }
    if (mounted) setState(() {});
  }

  void _composeVariant() {
    variant.text = [ram, storage, colour].whereType<String>().join(' • ');
  }

  // ---------------------------------------------------------------- barcode
  Future<void> _scanSku() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan product barcode');
    if (code == null) return;
    sku.text = code;
    await _checkDuplicate();
  }

  Future<void> _autoSku() async {
    sku.text = await Smart.nextSku(_categoryName ?? guess.category, brand.text.isEmpty ? guess.brand : brand.text);
    HapticFeedback.selectionClick();
    await _checkDuplicate();
  }

  Future<void> _checkDuplicate() async {
    final d = await Smart.findBySku(sku.text, exceptId: _id);
    if (mounted) setState(() => duplicate = d);
  }

  // ---------------------------------------------------------------- save
  Map<String, Object?> _values() => {
        'name': name.text,
        'variant': variant.text.trim().isEmpty ? null : variant.text.trim(),
        'brand': brand.text.trim().isEmpty ? null : brand.text.trim(),
        'sku': sku.text.trim(),
        'hsn': hsn.text.trim().isEmpty ? null : hsn.text.trim(),
        'gst_bp': gstBp,
        'price': _m(price),
        'mrp': _m(mrp),
        'low_stock': low,
        'category_id': category,
        'condition': condition,
        'image': image,
        'warranty_months': warrantyMonths,
      };

  Future<void> _save({bool another = false}) async {
    if (saving) return;
    if (name.text.trim().isEmpty) {
      toast(context, 'Enter the product name', error: true);
      return;
    }
    if (_m(price) <= 0) {
      toast(context, 'Enter the selling price', error: true);
      return;
    }
    await _checkDuplicate();
    if (duplicate != null) {
      toast(context, 'Barcode/SKU already used by ${duplicate!['name']}', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await Books.saveProduct(_values(), id: _id, openingQty: isNew ? qty : 0, openingCost: isNew ? _m(cost) : 0);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      toast(context, isNew ? 'Product added' : 'Product updated');
      if (another) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProductForm()));
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  // ---------------------------------------------------------------- score
  (int, List<(String, bool)>) get _score {
    final checks = <(String, bool)>[
      ('Photo', image != null && image!.isNotEmpty),
      ('Name', name.text.trim().length > 2),
      ('Category', category != null),
      ('Brand', brand.text.trim().isNotEmpty),
      ('Barcode', sku.text.trim().isNotEmpty),
      ('Price', _m(price) > 0),
      ('MRP', _m(mrp) > 0),
      ('HSN', hsn.text.trim().isNotEmpty),
      ('Variant', variant.text.trim().isNotEmpty),
      if (isNew) ('Cost', _m(cost) > 0),
    ];
    final done = checks.where((c) => c.$2).length;
    return ((done * 100 / checks.length).round(), checks);
  }

  // ================================================================== UI
  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 120 + safeBottom),
            children: [
              _header(),
              const SizedBox(height: 16),
              _heroCard(),
              if (!guess.isEmpty) ...[const SizedBox(height: 14), _smartCard()],
              const SizedBox(height: 14),
              _section(Icons.badge_rounded, 'Basic details', [_basic()]),
              const SizedBox(height: 14),
              _section(Icons.qr_code_scanner_rounded, 'Barcode & codes', [_codes()]),
              const SizedBox(height: 14),
              _section(Icons.tune_rounded, 'Variant', [_variant()]),
              const SizedBox(height: 14),
              _section(Icons.currency_rupee_rounded, 'Pricing & tax', [_pricing()]),
              const SizedBox(height: 14),
              _calculator(),
              const SizedBox(height: 14),
              _section(Icons.inventory_2_rounded, 'Stock & warranty', [_stock()]),
              const SizedBox(height: 14),
              _preview(),
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(safeBottom)),
      ]),
    );
  }

  Widget _header() => Row(children: [
        _circle(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isNew ? 'Add New Product' : 'Edit Product', style: _j(20, FontWeight.w800, _navy)),
            Text(isNew ? 'Photo, barcode, price & stock in one place' : '${widget.product!['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w500, const Color(0xFF323B60))),
          ]),
        ),
        GestureDetector(
          onTap: _scanSku,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF7B4DFF), Color(0xFF4318D2)]),
              boxShadow: [BoxShadow(color: Color(0x664A17C9), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
          ),
        ),
      ]);

  Widget _circle(IconData icon, VoidCallback onTap) => GestureDetector(
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

  // ---------------------------------------------------------------- hero: photo + score
  Widget _heroCard() {
    final (pct, checks) = _score;
    final color = pct >= 80 ? _green : pct >= 50 ? _amber : _red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () async {
            final r = await pickPhoto(context, folder: 'product_images', allowRemove: image != null);
            if (r != null) setState(() => image = r.isEmpty ? null : r);
          },
          child: Stack(children: [
            Container(
              width: 120,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [Color(0xFFF3EFFF), Color(0xFFE9F0FF)]),
                border: Border.all(color: const Color(0xFFD6CCFF), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: image == null
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF5B2EE0)]),
                        ),
                        child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text('Add photo', style: _j(12, FontWeight.w700, _purple)),
                      Text('Camera / gallery', style: _j(10, FontWeight.w500, _muted)),
                    ])
                  : ProductThumb({'image': image, 'category': _categoryName}, width: 120, height: 140),
            ),
            if (image != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                width: 58,
                height: 58,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct / 100),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, v, _) => CustomPaint(
                    painter: _RingPainter(v, color),
                    child: Center(child: Text('$pct%', style: _j(13, FontWeight.w800, _ink))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Listing quality', style: _j(13.5, FontWeight.w800, _ink)),
                  Text(pct >= 80 ? 'Excellent — ready to sell' : pct >= 50 ? 'Good — add a few more details' : 'Fill in the basics',
                      style: _j(11, FontWeight.w500, _muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final c in checks)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.$2 ? const Color(0xFFE3F7EC) : const Color(0xFFF2F3F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(c.$2 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 11, color: c.$2 ? _green : const Color(0xFFB9BCD6)),
                    const SizedBox(width: 3),
                    Text(c.$1, style: _j(10, FontWeight.w600, c.$2 ? const Color(0xFF0E6E47) : _muted)),
                  ]),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- smart assist
  Widget _smartCard() {
    final g = guess;
    final costPaise = _m(cost);
    final suggest = Smart.suggestPrice(costPaise, _categoryName ?? g.category);
    Widget chip(String label, String value, String key) => GestureDetector(
          onTap: () => _applyGuess(all: false, only: key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x26FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$label ', style: _j(10.5, FontWeight.w500, const Color(0xCCFFFFFF))),
              Text(value, style: _j(11.5, FontWeight.w800, Colors.white)),
              const SizedBox(width: 4),
              const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 14),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x554A17C9), blurRadius: 20, offset: Offset(0, 8), spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Smart Assist', style: _j(15, FontWeight.w800, Colors.white)),
              Text('Detected from the name · ${(g.confidence * 100).round()}% match',
                  style: _j(11, FontWeight.w500, const Color(0xCCFFFFFF))),
            ]),
          ),
          GestureDetector(
            onTap: () => _applyGuess(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Text('Apply all', style: _j(12, FontWeight.w800, _purple)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (g.category != null) chip('Category', g.category!, 'category'),
          if (g.brand != null) chip('Brand', g.brand!, 'brand'),
          if (g.hsn != null) chip('HSN', '${g.hsn} · GST ${(g.gstBp ?? 0) ~/ 100}%', 'hsn'),
          if (g.variant.isNotEmpty) chip('Variant', g.variant, 'variant'),
        ]),
        if (suggest > 0) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => price.text = Money.edit(suggest)),
            child: Row(children: [
              const Icon(Icons.lightbulb_rounded, color: Color(0xFFFFD66B), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Suggested price ${Money.rs(suggest)} (${Smart.margins[_categoryName ?? g.category] ?? 15}% margin) — tap to use',
                    style: _j(11.5, FontWeight.w600, Colors.white)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        Text('Works offline on your phone. GST/HSN are suggestions — please verify.',
            style: _j(10, FontWeight.w500, const Color(0xB3FFFFFF))),
      ]),
    );
  }

  // ---------------------------------------------------------------- basic
  Widget _basic() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _field(name, 'Product name *', hint: 'e.g. iPhone 15 Pro 8GB 256GB Black', icon: Icons.label_rounded, big: true),
      _field(brand, 'Brand', hint: 'Apple, Samsung, HP…', icon: Icons.business_rounded),
      Text('Category', style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in categories)
          _pill(
            c['name'] as String,
            category == asInt(c['id']),
            () => setState(() => category = asInt(c['id'])),
            icon: _catIcon(c['name'] as String),
          ),
        _pill('New', false, _newCategory, icon: Icons.add_rounded, dashed: true),
      ]),
    ]);
  }

  IconData _catIcon(String n) {
    final c = n.toLowerCase();
    if (c.contains('mobile')) return Icons.smartphone_rounded;
    if (c.contains('laptop')) return Icons.laptop_mac_rounded;
    if (c.contains('tablet')) return Icons.tablet_mac_rounded;
    if (c.contains('desktop') || c.contains('pc')) return Icons.desktop_windows_rounded;
    if (c.contains('access')) return Icons.headphones_rounded;
    return Icons.category_rounded;
  }

  Future<void> _newCategory() async {
    final c = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Smart Watch')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    if (n == null || n.trim().isEmpty) return;
    final id = await Books.addCategory(n);
    await _loadCategories();
    setState(() => category = id);
  }

  // ---------------------------------------------------------------- codes
  Widget _codes() {
    return Column(children: [
      _field(
        sku,
        'Barcode / SKU',
        hint: 'Scan, type or auto-generate',
        icon: Icons.qr_code_rounded,
        onChanged: (_) => _checkDuplicate(),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _miniBtn(Icons.qr_code_scanner_rounded, 'Scan', _scanSku),
          const SizedBox(width: 6),
          _miniBtn(Icons.auto_fix_high_rounded, 'Auto', _autoSku),
          const SizedBox(width: 6),
        ]),
      ),
      if (duplicate != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFDE4EA), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.error_rounded, color: _red),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Already used by “${duplicate!['name']}” (stock ${duplicate!['stock']})',
                  style: _j(12, FontWeight.w600, const Color(0xFF7A0A1E))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushReplacement(MaterialPageRoute(builder: (_) => ProductView(id: asInt(duplicate!['id'])))),
              child: const Text('Open'),
            ),
          ]),
        ),
      _field(hsn, 'HSN code', hint: '8517 mobiles · 8471 laptops', icon: Icons.numbers_rounded, number: true),
    ]);
  }

  Widget _miniBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: _purple),
            const SizedBox(width: 3),
            Text(label, style: _j(11, FontWeight.w700, _purple)),
          ]),
        ),
      );

  // ---------------------------------------------------------------- variant
  Widget _variant() {
    Widget row(String title, List<String> items, String? value, ValueChanged<String?> set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final it in items) ...[
                  _pill(it, value == it, () {
                    set(value == it ? null : it);
                    _composeVariant();
                  }),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
            const SizedBox(height: 12),
          ],
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row('RAM', _ramChips, ram, (v) => setState(() => ram = v)),
      row('Storage', _isPc ? _pcStorage : _phoneStorage, storage, (v) => setState(() => storage = v)),
      Text('Colour', style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _colorChips.entries)
          GestureDetector(
            onTap: () {
              setState(() => colour = colour == e.key ? null : e.key);
              _composeVariant();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
              decoration: BoxDecoration(
                color: colour == e.key ? const Color(0xFFEFEBFF) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colour == e.key ? _purple : _line, width: colour == e.key ? 1.5 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x33000000)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(e.key, style: _j(11.5, FontWeight.w600, _ink)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      _field(variant, 'Variant text', hint: '8GB • 256GB • Black', icon: Icons.edit_note_rounded),
    ]);
  }

  // ---------------------------------------------------------------- pricing
  Widget _pricing() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _field(price, 'Selling price *', icon: Icons.sell_rounded, number: true, prefix: '₹ ')),
        const SizedBox(width: 10),
        Expanded(child: _field(mrp, 'MRP', icon: Icons.local_offer_rounded, number: true, prefix: '₹ ')),
      ]),
      _field(cost, isNew ? 'Purchase cost per unit' : 'Average cost (from purchases)',
          icon: Icons.shopping_bag_rounded, number: true, prefix: '₹ ', enabled: isNew),
      Text('GST rate', style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
      const SizedBox(height: 8),
      Row(children: [
        for (final g in _gstRates) ...[
          Expanded(child: _pill('${g ~/ 100}%', gstBp == g, () => setState(() => gstBp = g), center: true)),
          if (g != _gstRates.last) const SizedBox(width: 6),
        ],
      ]),
    ]);
  }

  Widget _calculator() {
    final p = _m(price), m = _m(mrp), c = _m(cost);
    final margin = p - c;
    final marginPct = p == 0 ? 0.0 : margin * 100 / p;
    final markup = c == 0 ? 0.0 : margin * 100 / c;
    final gst = Money.percent(p, gstBp);
    final off = m > p && m > 0 ? (m - p) * 100 / m : 0.0;
    final warn = p > 0 && c > 0 && p < c;
    Widget cell(String label, String value, {Color color = Colors.white}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _j(10.5, FontWeight.w500, const Color(0xB3FFFFFF))),
            const SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: _j(15, FontWeight.w800, color))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF14164A), Color(0xFF1E1B6B)]),
        boxShadow: const [BoxShadow(color: Color(0x4014164A), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -8)],
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.calculate_rounded, color: Color(0xFFB9A5FF), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Live price calculator', style: _j(14, FontWeight.w800, Colors.white))),
          if (warn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0x33FF6B6B), borderRadius: BorderRadius.circular(8)),
              child: Text('Below cost!', style: _j(10.5, FontWeight.w800, const Color(0xFFFF8A8A))),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          cell('Profit / unit', Money.rs(margin), color: margin >= 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFF8A8A)),
          cell('Margin', '${marginPct.toStringAsFixed(1)}%'),
          cell('Markup', '${markup.toStringAsFixed(1)}%'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          cell('GST (${gstBp ~/ 100}%)', Money.rs(gst)),
          cell('Customer pays', Money.rs(p + gst)),
          cell('Off MRP', '${off.toStringAsFixed(0)}%', color: const Color(0xFFFFD66B)),
        ]),
        if (isNew && qty > 0 && c > 0) ...[
          const Divider(color: Color(0x26FFFFFF), height: 22),
          Row(children: [
            Expanded(child: Text('Opening stock value', style: _j(11.5, FontWeight.w500, const Color(0xB3FFFFFF)))),
            Text(Money.rs(c * qty), style: _j(13, FontWeight.w800, Colors.white)),
          ]),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- stock
  Widget _stock() {
    Widget stepper(String label, String sub, int v, ValueChanged<int> set) => Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: const Color(0xFFF8F7FF), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: _j(13, FontWeight.w700, _ink)),
                Text(sub, style: _j(10.5, FontWeight.w500, _muted)),
              ]),
            ),
            _stepBtn(Icons.remove_rounded, () => set(math.max(0, v - 1))),
            SizedBox(width: 46, child: Text('$v', textAlign: TextAlign.center, style: _j(17, FontWeight.w800, _ink))),
            _stepBtn(Icons.add_rounded, () => set(v + 1)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isNew) stepper('Opening stock', 'Units you have right now', qty, (v) => setState(() => qty = v)),
      stepper('Low-stock alert', 'Warn me when stock reaches', low, (v) => setState(() => low = v)),
      Text('Condition', style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
      const SizedBox(height: 8),
      Row(children: [
        for (final c in const [('new', 'New', Icons.fiber_new_rounded), ('used', 'Used', Icons.recycling_rounded), ('refurbished', 'Refurb', Icons.build_circle_rounded)]) ...[
          Expanded(child: _pill(c.$2, condition == c.$1, () => setState(() => condition = c.$1), icon: c.$3, center: true)),
          if (c.$1 != 'refurbished') const SizedBox(width: 6),
        ],
      ]),
      const SizedBox(height: 14),
      Text('Warranty', style: _j(12, FontWeight.w700, const Color(0xFF3A4155))),
      const SizedBox(height: 8),
      Row(children: [
        for (final w in _warranty) ...[
          Expanded(
            child: _pill(w == 0 ? 'None' : w < 12 ? '${w}M' : '${w ~/ 12}Y', warrantyMonths == w,
                () => setState(() => warrantyMonths = w), center: true),
          ),
          if (w != _warranty.last) const SizedBox(width: 6),
        ],
      ]),
    ]);
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Icon(icon, color: _purple, size: 20),
        ),
      );

  // ---------------------------------------------------------------- preview
  Widget _preview() {
    final p = _m(price), m = _m(mrp);
    final off = m > p && m > 0 ? ((m - p) * 100 / m).round() : 0;
    final low0 = isNew ? qty : asInt(widget.product!['stock']);
    final status = low0 <= 0 ? ('Out of Stock', _red) : low0 <= low ? ('Low Stock', _amber) : ('In Stock', _green);
    return _section(Icons.visibility_rounded, 'Live preview', [
      Row(children: [
        ProductThumb({'image': image, 'category': _categoryName ?? guess.category}, width: 78, height: 90),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: status.$2.withAlpha(0x22), borderRadius: BorderRadius.circular(10)),
              child: Text(status.$1, style: _j(10.5, FontWeight.w700, status.$2)),
            ),
            const SizedBox(height: 4),
            Text(name.text.isEmpty ? 'Product name' : name.text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(15, FontWeight.w800, _ink)),
            Text(variant.text.isEmpty ? (brand.text.isEmpty ? 'Variant' : brand.text) : variant.text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w500, const Color(0xFF3A4156))),
            const SizedBox(height: 4),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Text(Money.rs(p), style: _j(15, FontWeight.w800, const Color(0xFF1C1CA0))),
              if (off > 0)
                Text(Money.rs(m),
                    style: _j(11.5, FontWeight.w500, const Color(0xFF7E8198)).copyWith(decoration: TextDecoration.lineThrough)),
              if (off > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFDDDE3), borderRadius: BorderRadius.circular(8)),
                  child: Text('$off% OFF', style: _j(10, FontWeight.w800, const Color(0xFF8A0818))),
                ),
            ]),
            if (warrantyMonths > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.verified_user_rounded, size: 13, color: _green),
                  const SizedBox(width: 4),
                  Text('$warrantyMonths months warranty', style: _j(10.5, FontWeight.w600, _green)),
                ]),
              ),
          ]),
        ),
      ]),
    ]);
  }

  // ---------------------------------------------------------------- bottom bar
  Widget _bottomBar(double safe) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safe),
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 24, offset: Offset(0, -6), spreadRadius: -8)],
      ),
      child: Row(children: [
        if (isNew) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => _save(another: true),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFCFC4FF), width: 1.5),
                  color: const Color(0xFFF6F3FF),
                ),
                alignment: Alignment.center,
                child: Text('Save & add another', style: _j(13.5, FontWeight.w700, _purple)),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: GestureDetector(
            onTap: () => _save(),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF3A10CC)]),
                boxShadow: const [BoxShadow(color: Color(0x804A17C9), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
              ),
              alignment: Alignment.center,
              child: saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(isNew ? 'Save product' : 'Update product', style: _j(14.5, FontWeight.w800, Colors.white)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- building blocks
  BoxDecoration _card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEEF0F8)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
          BoxShadow(color: Color(0x0A2A2F7A), blurRadius: 3, offset: Offset(0, 1)),
        ],
      );

  Widget _section(IconData icon, String title, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _purple, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: _j(15, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 14),
          ...children,
          const SizedBox(height: 10),
        ]),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    IconData? icon,
    bool number = false,
    bool big = false,
    bool enabled = true,
    String? prefix,
    Widget? trailing,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: enabled,
        onChanged: onChanged,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
        style: _j(big ? 16 : 14.5, big ? FontWeight.w700 : FontWeight.w600, _ink),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          prefixIcon: icon == null ? null : Icon(icon, color: const Color(0xFF8B7FD6), size: 20),
          suffixIcon: trailing,
          suffixIconConstraints: const BoxConstraints(minHeight: 36),
          filled: true,
          fillColor: enabled ? const Color(0xFFFBFBFE) : const Color(0xFFF2F3F8),
          labelStyle: _j(13, FontWeight.w500, const Color(0xFF6B7094)),
          hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.6)),
        ),
      ),
    );
  }

  Widget _pill(String label, bool on, VoidCallback onTap, {IconData? icon, bool center = false, bool dashed = false}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
          color: on ? null : (dashed ? const Color(0xFFF6F3FF) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: on ? null : Border.all(color: dashed ? const Color(0xFFCFC4FF) : _line),
          boxShadow: on ? const [BoxShadow(color: Color(0x554A17C9), blurRadius: 10, offset: Offset(0, 4), spreadRadius: -4)] : null,
        ),
        child: Row(mainAxisSize: center ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: on ? Colors.white : _purple), const SizedBox(width: 5)],
          if (center)
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w700, on ? Colors.white : _ink)),
            )
          else
            Text(label, maxLines: 1, style: _j(12, FontWeight.w700, on ? Colors.white : _ink)),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(r, 0, math.pi * 2, false,
        Paint()
          ..color = const Color(0xFFF0F1F8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.color != color;
}
