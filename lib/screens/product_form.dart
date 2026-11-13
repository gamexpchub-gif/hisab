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
              const SizedBox(height: 14),
              _topCard(),
              if (!guess.isEmpty) ...[const SizedBox(height: 12), _smartStrip()],
              const SizedBox(height: 12),
              _priceCard(),
              const SizedBox(height: 12),
              _variantCard(),
              const SizedBox(height: 12),
              _codesCard(),
              const SizedBox(height: 12),
              _stockCard(),
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(safeBottom)),
      ]),
    );
  }

  Widget _header() {
    final (pct, _) = _score;
    final color = pct >= 80 ? _green : pct >= 50 ? _amber : _red;
    return Row(children: [
      _circle(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isNew ? 'New Product' : 'Edit Product', style: _j(20, FontWeight.w800, _navy)),
          Text(isNew ? 'Listing ${pct >= 80 ? 'ready to sell' : '$pct% complete'}' : '${widget.product!['name']}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
        ]),
      ),
      SizedBox(
        width: 44,
        height: 44,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: pct / 100),
          duration: const Duration(milliseconds: 500),
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(v, color),
            child: Center(child: Text('$pct', style: _j(12, FontWeight.w800, _ink))),
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _scanSku,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFF7B4DFF), Color(0xFF4318D2)]),
            boxShadow: [BoxShadow(color: Color(0x664A17C9), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
          ),
          child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 21),
        ),
      ),
    ]);
  }

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

  // ---------------------------------------------------------------- top: photo + name + inline categories
  Widget _topCard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () async {
                final r = await pickPhoto(context, folder: 'product_images', allowRemove: image != null);
                if (r != null) setState(() => image = r.isEmpty ? null : r);
              },
              child: Container(
                width: 96,
                height: 108,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [Color(0xFFF3EFFF), Color(0xFFE9F0FF)]),
                  border: Border.all(color: const Color(0xFFD6CCFF), width: 1.4),
                ),
                clipBehavior: Clip.antiAlias,
                child: image == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF5B2EE0)]),
                          ),
                          child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(height: 6),
                        Text('Photo', style: _j(11.5, FontWeight.w800, _purple)),
                      ])
                    : Stack(fit: StackFit.expand, children: [
                        ProductThumb({'image': image, 'category': _categoryName}, width: 96, height: 108),
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
                            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                          ),
                        ),
                      ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                _field(name, 'Product name *', hint: 'iPhone 15 Pro 8GB 256GB', big: true),
                _field(brand, 'Brand', hint: 'Apple, Samsung, HP…'),
              ]),
            ),
          ]),
          const SizedBox(height: 2),
          _label('Category'),
          SizedBox(
            height: 38,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in categories) ...[
                _pill(c['name'] as String, category == asInt(c['id']), () => setState(() => category = asInt(c['id'])),
                    icon: _catIcon(c['name'] as String)),
                const SizedBox(width: 6),
              ],
              _pill('New', false, _newCategory, icon: Icons.add_rounded, dashed: true),
            ]),
          ),
        ]),
      );

  Widget _label(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 7),
        child: Row(children: [
          Text(t.toUpperCase(), style: _j(10.5, FontWeight.w800, const Color(0xFF7A80A3)).copyWith(letterSpacing: .8)),
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );

  /// A labelled single-line row of chips that scrolls sideways.
  Widget _inline(String label, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(width: 62, child: Text(label, style: _j(11.5, FontWeight.w800, const Color(0xFF3A4155)))),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in chips) ...[c, const SizedBox(width: 6)],
              ]),
            ),
          ),
        ]),
      );

  // ---------------------------------------------------------------- smart assist (slim)
  Widget _smartStrip() {
    final g = guess;
    final suggest = Smart.suggestPrice(_m(cost), _categoryName ?? g.category);
    final parts = [g.category, g.brand, if (g.hsn != null) 'HSN ${g.hsn}', if (g.variant.isNotEmpty) g.variant].whereType<String>().join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF6A2FF0), Color(0xFF2F55E8)]),
        boxShadow: const [BoxShadow(color: Color(0x554A17C9), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(parts.isEmpty ? 'Smart Assist' : parts,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w700, Colors.white)),
          ),
          GestureDetector(
            onTap: () => _applyGuess(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Text('Apply', style: _j(11.5, FontWeight.w800, _purple)),
            ),
          ),
        ]),
        if (suggest > 0)
          GestureDetector(
            onTap: () => setState(() => price.text = Money.edit(suggest)),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('💡 Suggested price ${Money.rs(suggest)} — tap to use', style: _j(11, FontWeight.w600, const Color(0xE6FFFFFF))),
            ),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- price (compact)
  Widget _priceCard() {
    final p = _m(price), m = _m(mrp), c = _m(cost);
    final margin = p - c;
    final marginPct = p == 0 ? 0.0 : margin * 100 / p;
    final gst = Money.percent(p, gstBp);
    final off = m > p && m > 0 ? (m - p) * 100 / m : 0.0;
    Widget metric(String l, String v, Color col) => Expanded(
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _j(13, FontWeight.w800, col))),
            Text(l, style: _j(9.5, FontWeight.w600, const Color(0xB3FFFFFF))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Price & tax'),
        Row(children: [
          Expanded(child: _field(price, 'Sell *', number: true, prefix: '₹')),
          const SizedBox(width: 8),
          Expanded(child: _field(mrp, 'MRP', number: true, prefix: '₹')),
          const SizedBox(width: 8),
          Expanded(child: _field(cost, isNew ? 'Cost' : 'Avg cost', number: true, prefix: '₹', enabled: isNew)),
        ]),
        _inline('GST', [
          for (final g in _gstRates) _pill('${g ~/ 100}%', gstBp == g, () => setState(() => gstBp = g)),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [Color(0xFF14164A), Color(0xFF26238A)]),
          ),
          child: Row(children: [
            metric('Profit', Money.rs(margin), margin >= 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFF8A8A)),
            metric('Margin', '${marginPct.toStringAsFixed(1)}%', Colors.white),
            metric('With GST', Money.rs(p + gst), Colors.white),
            metric('Off MRP', '${off.toStringAsFixed(0)}%', const Color(0xFFFFD66B)),
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- variant (inline rows)
  Widget _variantCard() => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label('Variant', trailing: variant.text.isEmpty ? null : Text(variant.text, style: _j(11, FontWeight.w700, _purple))),
          _inline('RAM', [
            for (final it in _ramChips)
              _pill(it, ram == it, () {
                setState(() => ram = ram == it ? null : it);
                _composeVariant();
              }),
          ]),
          _inline('Storage', [
            for (final it in _isPc ? _pcStorage : _phoneStorage)
              _pill(it, storage == it, () {
                setState(() => storage = storage == it ? null : it);
                _composeVariant();
              }),
          ]),
          _inline('Colour', [
            for (final e in _colorChips.entries)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => colour = colour == e.key ? null : e.key);
                  _composeVariant();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                  decoration: BoxDecoration(
                    color: colour == e.key ? const Color(0xFFEFEBFF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colour == e.key ? _purple : _line, width: colour == e.key ? 1.5 : 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(color: e.value, shape: BoxShape.circle, border: Border.all(color: const Color(0x33000000))),
                    ),
                    const SizedBox(width: 5),
                    Text(e.key, style: _j(11.5, FontWeight.w700, _ink)),
                  ]),
                ),
              ),
          ]),
        ]),
      );

  // ---------------------------------------------------------------- codes
  Widget _codesCard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label('Barcode & HSN'),
          Row(children: [
            Expanded(
              flex: 3,
              child: _field(sku, 'Barcode / SKU', onChanged: (_) => _checkDuplicate(), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _iconBtn(Icons.qr_code_scanner_rounded, _scanSku),
                _iconBtn(Icons.auto_fix_high_rounded, _autoSku),
                const SizedBox(width: 4),
              ])),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field(hsn, 'HSN', number: true)),
          ]),
          if (duplicate != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFFDE4EA), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.error_rounded, color: _red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Used by “${duplicate!['name']}”', style: _j(11.5, FontWeight.w700, const Color(0xFF7A0A1E))),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute(builder: (_) => ProductView(id: asInt(duplicate!['id'])))),
                  child: const Text('Open'),
                ),
              ]),
            ),
        ]),
      );

  Widget _iconBtn(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
          child: Icon(i, size: 17, color: _purple),
        ),
      );

  // ---------------------------------------------------------------- stock (compact)
  Widget _stockCard() {
    Widget stepper(String label, int v, ValueChanged<int> set) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(color: const Color(0xFFF8F7FF), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: Text(label, style: _j(11.5, FontWeight.w700, _ink))),
              _stepBtn(Icons.remove_rounded, () => set(math.max(0, v - 1))),
              SizedBox(width: 30, child: Text('$v', textAlign: TextAlign.center, style: _j(15, FontWeight.w800, _ink))),
              _stepBtn(Icons.add_rounded, () => set(v + 1)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Stock & warranty'),
        Row(children: [
          if (isNew) ...[stepper('Opening', qty, (v) => setState(() => qty = v)), const SizedBox(width: 8)],
          stepper('Alert at', low, (v) => setState(() => low = v)),
        ]),
        const SizedBox(height: 10),
        _inline('Condition', [
          for (final c in const [('new', 'New', Icons.fiber_new_rounded), ('used', 'Used', Icons.recycling_rounded), ('refurbished', 'Refurb', Icons.build_circle_rounded)])
            _pill(c.$2, condition == c.$1, () => setState(() => condition = c.$1), icon: c.$3),
        ]),
        _inline('Warranty', [
          for (final w in _warranty)
            _pill(w == 0 ? 'None' : w < 12 ? '$w mo' : '${w ~/ 12} yr', warrantyMonths == w, () => setState(() => warrantyMonths = w)),
        ]),
      ]),
    );
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

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _line),
          ),
          child: Icon(icon, color: _purple, size: 18),
        ),
      );

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
      padding: const EdgeInsets.only(bottom: 10),
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
          prefixText: prefix == null ? null : '$prefix ',
          prefixIcon: icon == null ? null : Icon(icon, color: const Color(0xFF8B7FD6), size: 20),
          suffixIcon: trailing,
          suffixIconConstraints: const BoxConstraints(minHeight: 36),
          filled: true,
          fillColor: enabled ? const Color(0xFFFBFBFE) : const Color(0xFFF2F3F8),
          labelStyle: _j(13, FontWeight.w500, const Color(0xFF6B7094)),
          hintStyle: _j(13, FontWeight.w400, const Color(0xFFA3A7C2)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
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
