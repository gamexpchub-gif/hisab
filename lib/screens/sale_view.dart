import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../print/print_screen.dart';
import '../ui/contact.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'products.dart' show ProductThumb;
import 'sale_form.dart';
import 'sale_return.dart';
import 'sales.dart' show invoiceText;

// =============================================================================
// Invoice page — opened from any sale. Glass hero with status and customer,
// one-tap Print, Custom print (paper sizes, live preview), PDF share and
// WhatsApp, item cards with IMEI, payment split, profit and returns.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);

TextStyle _j(double size, FontWeight w, Color c, {double? height, double? spacing}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
      letterSpacing: spacing,
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

class _ViewData {
  final Rec sale;
  final List<Rec> items, payments, returns;
  final Map<String, String> settings;
  _ViewData(this.sale, this.items, this.payments, this.returns, this.settings);
}

class SaleView extends StatelessWidget {
  final int id;
  const SaleView({super.key, required this.id});

  Future<_ViewData?> _load() async {
    final s = await Books.query(
        'SELECT s.*, c.name AS customer, c.phone AS phone, c.address AS address, c.gstin AS gstin, c.photo AS photo '
        'FROM sales s LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id = ?',
        [id]);
    if (s.isEmpty) return null;
    return _ViewData(
      s.first,
      await Books.query(
          'SELECT i.*, p.image AS image, p.hsn AS hsn, c.name AS category FROM sale_items i '
          'LEFT JOIN products p ON p.id = i.product_id LEFT JOIN categories c ON c.id = p.category_id '
          'WHERE i.sale_id = ? ORDER BY i.id',
          [id]),
      await Books.query(
          'SELECT a.name AS name, p.amount AS amount FROM sale_payments p JOIN accounts a ON a.id = p.account_id WHERE p.sale_id = ?',
          [id]),
      await Books.query('SELECT * FROM sale_returns WHERE sale_id = ? ORDER BY id', [id]),
      await Books.settings(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<_ViewData?>(
          load: _load,
          builder: (context, d) {
            if (d == null) return const EmptyState('Invoice not found');
            final s = d.sale;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _topBar(context, d),
                const SizedBox(height: 12),
                _hero(context, d),
                const SizedBox(height: 14),
                _actions(context, d),
                const SizedBox(height: 14),
                _items(d),
                const SizedBox(height: 14),
                _summary(d),
                if (d.returns.isNotEmpty) ...[const SizedBox(height: 14), _returns(d)],
                if ('${s['note'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: _card(),
                    child: Row(children: [
                      const Icon(Icons.sticky_note_2_rounded, color: _amber),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${s['note']}', style: _j(13, FontWeight.w600, _ink))),
                    ]),
                  ),
                ],
                const SizedBox(height: 14),
                if (d.returns.isEmpty) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: const Color(0xFF4318D2),
                      side: const BorderSide(color: Color(0xFFD5CCFF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    onPressed: () => open(context, SaleForm(editSaleId: id)),
                    icon: const Icon(Icons.edit_rounded),
                    label: Text('Edit this sale', style: _j(13.5, FontWeight.w800, const Color(0xFF4318D2))),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: const Color(0xFFE0245E),
                    side: const BorderSide(color: Color(0xFFFFC2D0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: () => open(context, SaleReturnForm(saleId: id)),
                  icon: const Icon(Icons.assignment_return_rounded),
                  label: Text('Return items from this sale', style: _j(13.5, FontWeight.w800, const Color(0xFFE0245E))),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

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

  Widget _topBar(BuildContext context, _ViewData d) => Row(children: [
        _round(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Invoice', style: _j(22, FontWeight.w800, _navy)),
            Text('${d.sale['number']} · ${prettyDate('${d.sale['date']}')}', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
          ]),
        ),
        if (d.returns.isEmpty) ...[
          _round(Icons.edit_rounded, () => open(context, SaleForm(editSaleId: id))),
          const SizedBox(width: 8),
        ],
        _round(Icons.copy_rounded, () {
          Clipboard.setData(ClipboardData(text: invoiceText(d.settings, d.sale, d.items)));
          toast(context, 'Invoice copied');
        }),
      ]);

  Widget _hero(BuildContext context, _ViewData d) {
    final s = d.sale;
    final total = asInt(s['total']), paid = asInt(s['paid']);
    final due = total - paid;
    final (label, color) = paid >= total ? ('FULLY PAID', const Color(0xFF9CF5C4)) : paid > 0 ? ('PART PAID', const Color(0xFFFFE08A)) : ('UNPAID', const Color(0xFFFFB4B4));
    final name = (s['customer'] as String?) ?? 'Walk-in customer';
    final phone = s['phone'] as String?;
    final time = DateTime.tryParse('${s['created_at']}');
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B2163), Color(0xFF3A2BC9), Color(0xFF3F5BEA)]),
        boxShadow: const [BoxShadow(color: Color(0x663A2BC9), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      child: Stack(children: [
        Positioned(
          right: -40,
          top: -50,
          child: Container(
            width: 170,
            height: 170,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x40FFFFFF)),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x22FFFFFF), Color(0x00FFFFFF)]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Text('TAX INVOICE', style: _j(10.5, FontWeight.w800, Colors.white, spacing: 1.2)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color.withAlpha(0x33), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withAlpha(0x99))),
                child: Text(label, style: _j(10.5, FontWeight.w800, color, spacing: .8)),
              ),
            ]),
            const SizedBox(height: 12),
            Text('${s['number']}', style: _j(14, FontWeight.w700, const Color(0xCCFFFFFF))),
            FittedBox(fit: BoxFit.scaleDown, child: Text(Money.rs(total), style: _j(32, FontWeight.w800, Colors.white))),
            Text(
              '${prettyDate('${s['date']}')}${time == null ? '' : ' · ${two(time.hour)}:${two(time.minute)}'}'
              '${due > 0 ? ' · Due ${Money.rs(due)}' : ''}',
              style: _j(12, FontWeight.w600, const Color(0xDDFFFFFF)),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: s['customer_id'] == null ? null : () => open(context, PartyView(type: 'customer', id: asInt(s['customer_id']))),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: const Color(0x33FFFFFF),
                      border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: storedImage(s['photo'] as String?,
                        fallback: s['customer'] == null
                            ? const Icon(Icons.person_rounded, color: Colors.white)
                            : Text(initials, style: _j(15, FontWeight.w800, Colors.white))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14, FontWeight.w800, Colors.white)),
                      Text(
                        [if (phone != null && phone.isNotEmpty) phone, if ('${s['address'] ?? ''}'.isNotEmpty) '${s['address']}'].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _j(11, FontWeight.w600, const Color(0xCCFFFFFF)),
                      ),
                    ]),
                  ),
                  if (phone != null && phone.isNotEmpty) ...[
                    _glassMini(Icons.call_rounded, () => Contact.call(phone)),
                    const SizedBox(width: 6),
                    _glassMini(Icons.chat_rounded, () => Contact.whatsapp(phone, invoiceText(d.settings, s, d.items))),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _glassMini(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(11)),
          child: Icon(i, color: Colors.white, size: 17),
        ),
      );

  Widget _actions(BuildContext context, _ViewData d) {
    Widget tile(IconData icon, String label, List<Color> colors, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              height: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: const Color(0x55FFFFFF)),
                boxShadow: [BoxShadow(color: colors.last.withAlpha(0x66), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 6),
                Text(label, style: _j(11.5, FontWeight.w800, Colors.white)),
              ]),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.print_rounded, 'Print', const [Color(0xFF6B35EE), Color(0xFF4318D2)], () => quickPrint(context, id)),
      const SizedBox(width: 8),
      tile(Icons.tune_rounded, 'Custom', const [Color(0xFF38BDF8), Color(0xFF2563EB)], () => open(context, PrintStudio(saleId: id))),
      const SizedBox(width: 8),
      tile(Icons.picture_as_pdf_rounded, 'PDF', const [Color(0xFFFF6B8B), Color(0xFFE0245E)], () => shareInvoicePdf(context, id)),
      const SizedBox(width: 8),
      tile(Icons.send_rounded, 'WhatsApp', const [Color(0xFF25D366), Color(0xFF128C7E)],
          () => Contact.whatsapp(d.sale['phone'] as String?, invoiceText(d.settings, d.sale, d.items))),
    ]);
  }

  Widget _items(_ViewData d) {
    final units = d.items.fold<int>(0, (a, i) => a + asInt(i['qty']));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Items', style: _j(15, FontWeight.w800, _ink)),
          const Spacer(),
          Text('$units unit${units == 1 ? '' : 's'}', style: _j(12, FontWeight.w700, _muted)),
        ]),
        const SizedBox(height: 6),
        for (final it in d.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ProductThumb({'image': it['image'], 'category': it['category']}, width: 46, height: 50),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${it['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
                  const SizedBox(height: 2),
                  Text(
                    '${it['qty']} × ${Money.rs(asInt(it['rate']))} · GST ${(asInt(it['gst_bp']) / 100).toStringAsFixed(asInt(it['gst_bp']) % 100 == 0 ? 0 : 1)}%'
                    '${'${it['hsn'] ?? ''}'.isEmpty ? '' : ' · HSN ${it['hsn']}'}',
                    style: _j(11.5, FontWeight.w600, _muted),
                  ),
                  if ('${it['serial'] ?? ''}'.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFEEF1FF), borderRadius: BorderRadius.circular(8)),
                      child: Text('IMEI ${it['serial']}', style: _j(10.5, FontWeight.w800, const Color(0xFF2440C8))),
                    ),
                  if ('${it['opp_id'] ?? ''}'.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFE6F6EC), borderRadius: BorderRadius.circular(8)),
                      child: Text('Opportunity ID ${it['opp_id']}', style: _j(10.5, FontWeight.w800, _green)),
                    ),
                ]),
              ),
              Text(Money.rs(asInt(it['amount']) + asInt(it['tax'])), style: _j(13.5, FontWeight.w800, _ink)),
            ]),
          ),
      ]),
    );
  }

  Widget _summary(_ViewData d) {
    final s = d.sale;
    final subtotal = asInt(s['subtotal']), discount = asInt(s['discount']), tax = asInt(s['tax']);
    final total = asInt(s['total']), paid = asInt(s['paid']);
    final due = total - paid;
    final profit = subtotal - discount - asInt(s['cogs']);
    Widget row(String k, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: _j(13, bold ? FontWeight.w800 : FontWeight.w600, bold ? _ink : _muted))),
            Text(v, style: _j(bold ? 15 : 13.5, FontWeight.w800, color ?? _ink)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(children: [
        row('Subtotal', Money.rs(subtotal)),
        if (discount > 0) row('Discount', '− ${Money.rs(discount)}', color: _amber),
        row('GST', Money.rs(tax)),
        const Divider(height: 16),
        row('Total', Money.rs(total), bold: true),
        for (final p in d.payments) row('Paid · ${p['name']}', Money.rs(asInt(p['amount'])), color: _green),
        if (due > 0) row('Balance due', Money.rs(due), color: _red, bold: true),
        const Divider(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (profit >= 0 ? _green : _red).withAlpha(0x14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(profit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: profit >= 0 ? _green : _red),
            const SizedBox(width: 8),
            Expanded(child: Text('Profit on this invoice', style: _j(13, FontWeight.w700, _ink))),
            Text(Money.rs(profit), style: _j(14.5, FontWeight.w800, profit >= 0 ? _green : _red)),
          ]),
        ),
      ]),
    );
  }

  Widget _returns(_ViewData d) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Returns', style: _j(15, FontWeight.w800, _ink)),
          const SizedBox(height: 6),
          for (final r in d.returns)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                const Icon(Icons.assignment_return_rounded, color: Color(0xFFE0245E), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${r['number']} · ${prettyDate('${r['date']}')}'
                      '${asInt(r['deduction']) > 0 ? ' · kept ${Money.rs(asInt(r['deduction']))}' : ''}',
                      style: _j(12, FontWeight.w600, _muted)),
                ),
                Text('− ${Money.rs(asInt(r['refund']))}', style: _j(13, FontWeight.w800, _red)),
              ]),
            ),
        ]),
      );
}
