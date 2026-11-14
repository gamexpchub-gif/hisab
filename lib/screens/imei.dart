import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../print/print_screen.dart' show quickPrint;
import '../ui/contact.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'sales.dart' show SaleView, PurchaseView;
import 'scanner.dart';

// =============================================================================
// IMEI & Warranty — scan or type any IMEI / serial to see the device's whole
// life: bought from which supplier, sold to which customer, returned, and a
// warranty countdown. Also lists warranties ending soon.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);
const _orange = Color(0xFFF0601A);
const _grad = [Color(0xFF6366F1), Color(0xFF312E81)];

TextStyle _j(double size, FontWeight w, Color c, {double? spacing}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
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

(String, Color, IconData) _status(ImeiRecord r) => switch (r.status) {
      'sold' => ('SOLD', _green, Icons.verified_rounded),
      'returned' => ('RETURNED', const Color(0xFFE0245E), Icons.assignment_return_rounded),
      'in_stock' => ('IN STOCK', const Color(0xFF2563EB), Icons.inventory_2_rounded),
      _ => ('UNKNOWN', _muted, Icons.help_outline_rounded),
    };

class ImeiScreen extends StatefulWidget {
  final String? initial;
  const ImeiScreen({super.key, this.initial});
  @override
  State<ImeiScreen> createState() => _ImeiScreenState();
}

class _ImeiScreenState extends State<ImeiScreen> {
  late final search = TextEditingController(text: widget.initial ?? '');
  late String q = widget.initial ?? '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<(List<ImeiRecord>, List<ImeiRecord>, Map<String, String>)> _load() async => (
        q.length >= 3 ? await Books.imeiLookup(q) : <ImeiRecord>[],
        q.isEmpty ? await Books.warrantyEndingSoon() : <ImeiRecord>[],
        await Books.settings(),
      );

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.scan(context, title: 'Scan IMEI / serial');
    if (code == null || !mounted) return;
    HapticFeedback.mediumImpact();
    search.text = code;
    setState(() => q = code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Live<(List<ImeiRecord>, List<ImeiRecord>, Map<String, String>)>(
          reloadKey: q,
          load: _load,
          builder: (context, d) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            Row(children: [
              if (canPop) ...[
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: _ink),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('IMEI & Warranty', style: _j(22, FontWeight.w800, _navy)),
                  Text('Device history · warranty check', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _scanCard(),
            const SizedBox(height: 14),
            if (q.isNotEmpty && q.length < 3)
              Text('Type at least 3 digits', style: _j(12.5, FontWeight.w600, _muted)),
            if (q.length >= 3) ...[
              Text('${d.$1.length} device${d.$1.length == 1 ? '' : 's'} found', style: _j(12.5, FontWeight.w700, _muted)),
              const SizedBox(height: 8),
              if (d.$1.isEmpty)
                Container(
                  decoration: _card(),
                  padding: const EdgeInsets.all(20),
                  child: EmptyState('No device with "$q" in purchases or sales'),
                ),
              for (final r in d.$1) _DeviceCard(r: r, settings: d.$3),
            ],
            if (q.isEmpty) ...[
              Row(children: [
                const Icon(Icons.hourglass_bottom_rounded, color: _amber, size: 20),
                const SizedBox(width: 6),
                Text('Warranty ending soon', style: _j(15, FontWeight.w800, _ink)),
                const Spacer(),
                Text('next 30 days', style: _j(11.5, FontWeight.w600, _muted)),
              ]),
              const SizedBox(height: 8),
              if (d.$2.isEmpty)
                Container(
                  decoration: _card(),
                  padding: const EdgeInsets.all(20),
                  child: const EmptyState('No warranty ends in the next 30 days'),
                ),
              for (final r in d.$2) _DeviceCard(r: r, settings: d.$3, compact: true),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _scanCard() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF6366F1), Color(0xFF4338CA), Color(0xFF1E1B4B)]),
          boxShadow: const [BoxShadow(color: Color(0x664338CA), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Check any device', style: _j(18, FontWeight.w800, Colors.white)),
                const SizedBox(height: 3),
                Text('Scan the IMEI barcode on the box or phone (*#06#)', style: _j(12, FontWeight.w600, const Color(0xDDFFFFFF))),
              ]),
            ),
            GestureDetector(
              onTap: _scan,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x33FFFFFF),
                  border: Border.all(color: const Color(0x80FFFFFF), width: 1.5),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 30),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
            child: Row(children: [
              const Icon(Icons.search_rounded, color: Color(0xFF4338CA)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: search,
                  keyboardType: TextInputType.text,
                  onChanged: (v) => setState(() => q = v.trim()),
                  style: _j(15, FontWeight.w700, _ink, spacing: .6),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Type IMEI / serial (any part)',
                    hintStyle: _j(13, FontWeight.w500, const Color(0xFF8A8FAD)),
                  ),
                ),
              ),
              if (q.isNotEmpty)
                IconButton(
                  onPressed: () {
                    search.clear();
                    setState(() => q = '');
                  },
                  icon: const Icon(Icons.close_rounded, color: _muted),
                ),
            ]),
          ),
        ]),
      );
}

class _DeviceCard extends StatelessWidget {
  final ImeiRecord r;
  final Map<String, String> settings;
  final bool compact;
  const _DeviceCard({required this.r, required this.settings, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _status(r);
    final sale = r.sale, purchase = r.purchase, ret = r.returned;
    final left = r.warrantyDaysLeft;
    final months = r.warrantyMonths;
    final phone = sale?['phone'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _card(r: 24),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: _grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Icon(Icons.smartphone_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14.5, FontWeight.w800, _ink)),
              Text(r.serial, style: _j(12.5, FontWeight.w700, const Color(0xFF4338CA), spacing: .8)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withAlpha(0x1F), borderRadius: BorderRadius.circular(9)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label, style: _j(9.5, FontWeight.w800, color)),
            ]),
          ),
        ]),
        if (sale != null) ...[
          const SizedBox(height: 12),
          _warranty(left, months),
        ],
        if (!compact) ...[
          const SizedBox(height: 12),
          if (purchase != null)
            _step(
              context,
              Icons.move_to_inbox_rounded,
              _orange,
              'Bought from ${purchase['party']}',
              '${prettyDate('${purchase['date']}')} · ${Money.rs(asInt(purchase['rate']))} · '
                  '${(purchase['bill_no'] ?? '').toString().isNotEmpty ? 'Bill ${purchase['bill_no']}' : purchase['number']}',
              onTap: () => open(context, PurchaseView(id: asInt(purchase['doc_id']))),
              last: sale == null && ret == null,
            ),
          if (sale != null)
            _step(
              context,
              Icons.shopping_bag_rounded,
              _green,
              'Sold to ${sale['party'] ?? 'Walk-in customer'}',
              '${prettyDate('${sale['date']}')} · ${Money.rs(asInt(sale['rate']))} · ${sale['number']}'
                  '${(sale['opp_id'] ?? '').toString().isNotEmpty ? ' · Opp ${sale['opp_id']}' : ''}',
              onTap: () => open(context, SaleView(id: asInt(sale['doc_id']))),
              last: ret == null,
            ),
          if (ret != null)
            _step(
              context,
              Icons.assignment_return_rounded,
              const Color(0xFFE0245E),
              'Returned · ${ret['number']}',
              '${prettyDate('${ret['date']}')}${ret['reason'] == null ? '' : ' · ${ret['reason']}'}',
              last: true,
            ),
        ] else if (sale != null) ...[
          const SizedBox(height: 8),
          Text('${sale['party'] ?? 'Walk-in'} · sold ${prettyDate('${sale['date']}')} · ${sale['number']}',
              style: _j(11.5, FontWeight.w600, _muted)),
        ],
        if (sale != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            if (sale['party_id'] != null)
              Expanded(
                child: _action(Icons.person_rounded, 'Customer', const Color(0xFF5B2EE0),
                    () => open(context, PartyView(type: 'customer', id: asInt(sale['party_id'])))),
              ),
            if (sale['party_id'] != null) const SizedBox(width: 8),
            Expanded(child: _action(Icons.print_rounded, 'Invoice', const Color(0xFF2563EB), () => quickPrint(context, asInt(sale['doc_id'])))),
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _action(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366), () {
                  final end = r.warrantyEnd;
                  Contact.whatsapp(
                    phone,
                    'Hi ${sale['party']},\nYour ${r.name} (IMEI ${r.serial}) bought on ${prettyDate('${sale['date']}')}'
                    '${end == null ? '' : ' is under warranty until ${prettyDate(ymd(end))}'}.'
                    '\n— ${(settings['business_name'] ?? '').trim().isEmpty ? 'GameX Pc Hub' : settings['business_name']}',
                  );
                }),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _warranty(int? left, int months) {
    if (left == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F8), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: _muted, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('No warranty set for this product', style: _j(12, FontWeight.w600, _muted))),
        ]),
      );
    }
    final total = months * 30.4;
    final frac = (left / total).clamp(0.0, 1.0).toDouble();
    final c = left < 0 ? _red : left <= 30 ? _amber : _green;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withAlpha(0x12), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withAlpha(0x40))),
      child: Row(children: [
        SizedBox(
          width: 54,
          height: 54,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: frac,
                strokeWidth: 6,
                backgroundColor: c.withAlpha(0x26),
                valueColor: AlwaysStoppedAnimation(c),
                strokeCap: StrokeCap.round,
              ),
            ),
            Icon(left < 0 ? Icons.gpp_bad_rounded : Icons.verified_user_rounded, color: c, size: 22),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              left < 0 ? 'Warranty expired ${-left} days ago' : left == 0 ? 'Warranty ends today' : 'In warranty · $left days left',
              style: _j(13.5, FontWeight.w800, c),
            ),
            Text('$months-month warranty · ends ${prettyDate(ymd(r.warrantyEnd!))}', style: _j(11.5, FontWeight.w600, _muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _step(BuildContext context, IconData i, Color c, String title, String sub, {VoidCallback? onTap, bool last = false}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.withAlpha(0x1A), shape: BoxShape.circle),
              child: Icon(i, color: c, size: 18),
            ),
            if (!last) Container(width: 2, height: 22, color: const Color(0xFFE3E5F0)),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _j(13, FontWeight.w800, _ink)),
                Text(sub, style: _j(11.5, FontWeight.w600, _muted)),
              ]),
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9BCD6)),
        ]),
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
            Flexible(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w800, c))),
          ]),
        ),
      );
}
