import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import 'sales.dart' show SaleView;
import 'sales_book.dart' show matchSale;
import 'scanner.dart';

// =============================================================================
// Sale returns — take goods back from an invoice. The refund can be less than
// the goods' value (e.g. sold ₹10,000, refund ₹9,000): the ₹1,000 kept is
// booked as "Sale Return Charges" income, so it shows up as profit.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _rose = [Color(0xFFFF6B8B), Color(0xFFE0245E)];

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

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();

Widget _round(BuildContext context, IconData icon, VoidCallback onTap) => GestureDetector(
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

Widget _avatar(String? name, String? photo, {double size = 48}) {
  final walkIn = name == null;
  final grad = walkIn ? const [Color(0xFF9AA3C7), Color(0xFF5E6790)] : const [Color(0xFF8B5CF6), Color(0xFF4F46E5)];
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .34),
      gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [BoxShadow(color: grad.last.withAlpha(0x66), blurRadius: 12, offset: const Offset(0, 5), spreadRadius: -3)],
    ),
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    child: storedImage(photo,
        fallback: walkIn
            ? const Icon(Icons.person_rounded, color: Colors.white)
            : Text(_initials(name), style: _j(size * .34, FontWeight.w800, Colors.white))),
  );
}

Widget _pill(String label, IconData icon, VoidCallback onTap, {List<Color> colors = _rose}) => GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(colors: colors),
          border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
          boxShadow: [BoxShadow(color: colors.last.withAlpha(0x77), blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Text(label, style: _j(15, FontWeight.w800, Colors.white)),
        ]),
      ),
    );

// =============================================================================
// Returns list
// =============================================================================
class SaleReturnsScreen extends StatefulWidget {
  const SaleReturnsScreen({super.key});
  @override
  State<SaleReturnsScreen> createState() => _SaleReturnsScreenState();
}

class _SaleReturnsScreenState extends State<SaleReturnsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: _pill('New return', Icons.assignment_return_rounded, () => open(context, const ReturnPickSale())),
      body: SafeArea(
        child: Live<List<Rec>>(
          load: Books.saleReturns,
          builder: (context, all) {
            final ql = q.toLowerCase();
            final rows = q.isEmpty
                ? all
                : all
                    .where((r) => [r['number'], r['sale_number'], r['customer'], r['phone'], r['items'], r['serials'], r['reason']]
                        .any((v) => v != null && '$v'.toLowerCase().contains(ql)))
                    .toList();
            final refunded = all.fold<int>(0, (a, r) => a + asInt(r['refund']));
            final kept = all.fold<int>(0, (a, r) => a + asInt(r['deduction']));
            final units = all.fold<int>(0, (a, r) => a + asInt(r['qty']));
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Row(children: [
                  if (canPop) ...[_round(context, Icons.arrow_back_rounded, () => Navigator.of(context).pop()), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Sale returns', style: _j(22, FontWeight.w800, _navy)),
                      Text('Goods back · refunds · return charges', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF6B8B), Color(0xFFE0245E), Color(0xFF9D1B6B)]),
                    boxShadow: const [BoxShadow(color: Color(0x66E0245E), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Refunded to customers', style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                        child: Text('${all.length} returns · $units units', style: _j(11, FontWeight.w700, Colors.white)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(refunded), style: _j(28, FontWeight.w800, Colors.white))),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Icon(Icons.trending_up_rounded, color: Color(0xFFB8FFD9), size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Return charges kept (profit)', style: _j(12.5, FontWeight.w700, Colors.white))),
                        Text(Money.rs(kept), style: _j(15, FontWeight.w800, const Color(0xFFB8FFD9))),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 52,
                  decoration: _card(r: 26),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Icon(Icons.search_rounded, color: Color(0xFFE0245E)),
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
                          hintText: 'Search return, invoice, customer, IMEI…',
                          hintStyle: _j(13, FontWeight.w500, const Color(0xFF8A8FAD)),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Container(
                    decoration: _card(),
                    padding: const EdgeInsets.all(20),
                    child: EmptyState(all.isEmpty ? 'No returns yet — tap New return' : 'Nothing matches "$q"'),
                  ),
                for (final r in rows) _ReturnCard(r: r),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  final Rec r;
  const _ReturnCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final kept = asInt(r['deduction']);
    final restock = asInt(r['restock']) == 1;
    final account = r['account'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => open(context, SaleView(id: asInt(r['sale_id']))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _avatar(r['customer'] as String?, r['photo'] as String?),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((r['customer'] as String?) ?? 'Walk-in customer',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14.5, FontWeight.w800, _ink)),
                    Text('${r['number']} · from ${r['sale_number']} · ${prettyDate(r['date'] as String)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w600, _muted)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('− ${Money.rs(asInt(r['refund']))}', style: _j(15, FontWeight.w800, _red)),
                  Text('refund', style: _j(10.5, FontWeight.w600, _muted)),
                ]),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFFFF1F4), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.assignment_return_rounded, size: 16, color: Color(0xFFE0245E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${r['items'] ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                  ),
                  Text('×${asInt(r['qty'])}', style: _j(12, FontWeight.w800, const Color(0xFFE0245E))),
                ]),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _tag(Icons.inventory_2_rounded, 'Goods ${Money.rs(asInt(r['value']))}', _navy),
                if (kept > 0) _tag(Icons.trending_up_rounded, 'Kept ${Money.rs(kept)} profit', _green),
                _tag(restock ? Icons.add_box_rounded : Icons.delete_outline_rounded, restock ? 'Back in stock' : 'Written off',
                    restock ? _purple : _red),
                _tag(Icons.account_balance_wallet_rounded, account ?? 'Adjusted in due', const Color(0xFF2F6BFF)),
                if ((r['reason'] as String? ?? '').isNotEmpty) _tag(Icons.info_outline_rounded, '${r['reason']}', _muted),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withAlpha(0x14), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: c),
          const SizedBox(width: 4),
          Text(t, style: _j(11, FontWeight.w700, c)),
        ]),
      );
}

// =============================================================================
// Step 1 — find the invoice
// =============================================================================
class ReturnPickSale extends StatefulWidget {
  const ReturnPickSale({super.key});
  @override
  State<ReturnPickSale> createState() => _ReturnPickSaleState();
}

class _ReturnPickSaleState extends State<ReturnPickSale> {
  final search = TextEditingController();
  String q = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<List<Rec>>(
          load: Books.salesBook,
          builder: (context, all) {
            final rows = [for (final s in all) if (matchSale(s, q) != null) s];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Row(children: [
                  _round(context, Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Which sale?', style: _j(22, FontWeight.w800, _navy)),
                      Text('Find the invoice being returned', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                Container(
                  height: 56,
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  decoration: _card(r: 28),
                  child: Row(children: [
                    const Icon(Icons.search_rounded, color: Color(0xFFE0245E)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: search,
                        autofocus: false,
                        onChanged: (v) => setState(() => q = v.trim()),
                        style: _j(14, FontWeight.w600, _ink),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Invoice, name, mobile, IMEI, ₹…',
                          hintStyle: _j(13, FontWeight.w500, const Color(0xFF8A8FAD)),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI');
                        if (code == null || !mounted) return;
                        search.text = code;
                        setState(() => q = code);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: _rose)),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 21),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty) Container(decoration: _card(), padding: const EdgeInsets.all(20), child: const EmptyState('No matching sale')),
                for (final s in rows.take(60))
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: _card(),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      leading: _avatar(s['customer'] as String?, s['photo'] as String?, size: 44),
                      title: Text((s['customer'] as String?) ?? 'Walk-in customer',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14, FontWeight.w800, _ink)),
                      subtitle: Text('${s['number']} · ${prettyDate(s['date'] as String)}\n${s['items'] ?? ''}',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w600, _muted)),
                      trailing: Text(Money.rs(asInt(s['total'])), style: _j(14, FontWeight.w800, _ink)),
                      onTap: () => Navigator.of(context)
                          .pushReplacement(MaterialPageRoute(builder: (_) => SaleReturnForm(saleId: asInt(s['id'])))),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// Step 2 — items, refund and charges
// =============================================================================
class SaleReturnForm extends StatefulWidget {
  final int saleId;
  const SaleReturnForm({super.key, required this.saleId});
  @override
  State<SaleReturnForm> createState() => _SaleReturnFormState();
}

class _SaleReturnFormState extends State<SaleReturnForm> {
  Rec? sale;
  List<ReturnLine> lines = [];
  List<Rec> accounts = [];
  final qty = <int, int>{};
  final refund = TextEditingController();
  final note = TextEditingController();
  int? accountId; // null = adjust against the customer's due
  bool restock = true;
  bool refundTouched = false;
  String reason = 'Defective';
  String date = ymd(DateTime.now());
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    refund.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Books.query(
        'SELECT s.*, c.name AS customer, c.phone AS phone, c.photo AS photo FROM sales s '
        'LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id = ?',
        [widget.saleId]);
    final l = await Books.returnable(widget.saleId);
    final a = await Books.moneyAccounts();
    if (!mounted || s.isEmpty) return;
    setState(() {
      sale = s.first;
      lines = l;
      accounts = a;
      accountId = a.isEmpty ? null : asInt(a.first['id']);
      // one line with one unit left: select it straight away
      if (l.where((x) => x.left > 0).length == 1) {
        final only = l.firstWhere((x) => x.left > 0);
        if (only.left == 1) qty[asInt(only.item['id'])] = 1;
      }
      _syncRefund();
    });
  }

  int get value {
    var v = 0;
    for (final l in lines) {
      final q = qty[asInt(l.item['id'])] ?? 0;
      if (q > 0) v += ((l.netAmount * q / l.soldQty).round() + (asInt(l.item['tax']) * q / l.soldQty).round());
    }
    return v;
  }

  int get refundAmt => Money.parse(refund.text);
  int get kept => value - refundAmt;

  void _syncRefund() {
    if (!refundTouched) refund.text = value == 0 ? '' : Money.edit(value);
  }

  void _keepPercent(int pct) {
    refundTouched = true;
    setState(() => refund.text = Money.edit(value - (value * pct / 100).round()));
  }

  Future<void> _save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final id = await Books.createSaleReturn(
        saleId: widget.saleId,
        qty: Map.of(qty),
        refund: refundAmt,
        accountId: accountId,
        restock: restock,
        reason: reason,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        date: date,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final r = (await Books.query('SELECT number, refund, deduction FROM sale_returns WHERE id = ?', [id])).first;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          icon: const Icon(Icons.check_circle_rounded, color: _green, size: 48),
          title: Text('Return ${r['number']} saved', style: _j(18, FontWeight.w800, _ink)),
          content: Text(
            'Refund ${Money.rs(asInt(r['refund']))}'
            '${asInt(r['deduction']) > 0 ? '\n${Money.rs(asInt(r['deduction']))} kept as return charge — added to profit' : ''}',
            textAlign: TextAlign.center,
            style: _j(13.5, FontWeight.w600, _muted, height: 1.4),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = sale;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  Row(children: [
                    _round(context, Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sale return', style: _j(22, FontWeight.w800, _navy)),
                        Text('Against ${s['number']}', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _saleCard(s),
                  const SizedBox(height: 14),
                  _section('Items coming back', Icons.assignment_return_rounded, [
                    for (final l in lines) _lineRow(l),
                  ]),
                  const SizedBox(height: 14),
                  _section('Reason', Icons.info_outline_rounded, [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in ['Defective', 'Changed mind', 'Wrong item', 'Exchange', 'Warranty', 'Other'])
                        _chip(r, reason == r, () => setState(() => reason = r)),
                    ]),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: restock,
                      activeColor: _purple,
                      onChanged: (v) => setState(() => restock = v),
                      title: Text(restock ? 'Put back in stock' : 'Damaged — write off', style: _j(13.5, FontWeight.w700, _ink)),
                      subtitle: Text(restock ? 'Units are added back to inventory' : 'Stock stays the same; cost stays as loss',
                          style: _j(11.5, FontWeight.w500, _muted)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _refundCard(s),
                  const SizedBox(height: 14),
                  DateField(value: date, onChanged: (v) => setState(() => date = v)),
                  field(note, 'Note (optional)'),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: _pill(busy ? 'Saving…' : 'Save return · refund ${Money.rs(refundAmt)}', Icons.check_rounded, _save),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _saleCard(Rec s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Row(children: [
          _avatar(s['customer'] as String?, s['photo'] as String?, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((s['customer'] as String?) ?? 'Walk-in customer', style: _j(15, FontWeight.w800, _ink)),
              Text('${s['number']} · ${prettyDate(s['date'] as String)}${s['phone'] == null ? '' : ' · ${s['phone']}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w600, _muted)),
            ]),
          ),
          Text(Money.rs(asInt(s['total'])), style: _j(15, FontWeight.w800, _ink)),
        ]),
      );

  Widget _section(String title, IconData icon, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: const Color(0xFFFFEDF2), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: const Color(0xFFE0245E), size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: _j(15, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _lineRow(ReturnLine l) {
    final id = asInt(l.item['id']);
    final q = qty[id] ?? 0;
    final serial = (l.item['serial'] as String? ?? '').trim();
    void set(int v) {
      HapticFeedback.selectionClick();
      setState(() {
        qty[id] = v.clamp(0, l.left).toInt();
        _syncRefund();
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l.item['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
            Text(
              l.left == 0
                  ? 'Already returned'
                  : '${Money.rs(l.unitValue)} each · sold ${l.soldQty}${l.left < l.soldQty ? ' · ${l.left} left' : ''}',
              style: _j(11.5, FontWeight.w600, l.left == 0 ? _red : _muted),
            ),
            if (serial.isNotEmpty) Text('IMEI $serial', style: _j(11, FontWeight.w700, _purple)),
          ]),
        ),
        if (l.left > 0)
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF4F2FF), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: q > 0 ? () => set(q - 1) : null,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              SizedBox(width: 22, child: Text('$q', textAlign: TextAlign.center, style: _j(15, FontWeight.w800, _ink))),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: q < l.left ? () => set(q + 1) : null,
                icon: const Icon(Icons.add_rounded, size: 18, color: _purple),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: _rose) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: on ? null : Border.all(color: _line),
          ),
          child: Text(label, style: _j(12, FontWeight.w700, on ? Colors.white : _ink)),
        ),
      );

  Widget _refundCard(Rec s) {
    final hasCustomer = s['customer_id'] != null;
    final k = kept;
    return _section('Refund', Icons.currency_rupee_rounded, [
      Row(children: [
        Expanded(child: Text('Value of goods returned', style: _j(13, FontWeight.w600, _muted))),
        Text(Money.rs(value), style: _j(15, FontWeight.w800, _ink)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _chip('Full refund', refundAmt == value, () {
          refundTouched = false;
          setState(_syncRefund);
        }),
        for (final p in [5, 10, 15, 20]) _chip('Keep $p%', value > 0 && k == (value * p / 100).round(), () => _keepPercent(p)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: refund,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() => refundTouched = true),
        style: _j(18, FontWeight.w800, _ink),
        decoration: const InputDecoration(labelText: 'Refund to customer ₹', prefixIcon: Icon(Icons.currency_rupee_rounded)),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: k < 0 ? const Color(0xFFFFEEEE) : const Color(0xFFEAF8F1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (k < 0 ? _red : _green).withAlpha(0x40)),
        ),
        child: Row(children: [
          Icon(k < 0 ? Icons.error_outline_rounded : Icons.trending_up_rounded, color: k < 0 ? _red : _green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              k < 0
                  ? 'Refund is more than the goods are worth'
                  : k == 0
                      ? 'Full refund — no return charge'
                      : 'Return charge ${Money.rs(k)} kept → added to profit',
              style: _j(12.5, FontWeight.w700, k < 0 ? _red : _green),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Refund from', style: _j(12.5, FontWeight.w800, const Color(0xFF323B60))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in accounts) _chip('${a['name']}', accountId == asInt(a['id']), () => setState(() => accountId = asInt(a['id']))),
        if (hasCustomer) _chip('Adjust in customer due', accountId == null, () => setState(() => accountId = null)),
      ]),
    ]);
  }
}
