import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/export_book.dart';
import '../core/gst_report.dart';
import '../core/money.dart';
import '../ui/widgets.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

/// Common periods: this month, last month, this quarter, financial year.
List<(String, String, String)> periods([DateTime? today]) {
  final t = today ?? DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final ms = DateTime(d.year, d.month, 1);
  final lmEnd = ms.subtract(const Duration(days: 1));
  final q = ((d.month - 1) ~/ 3) * 3 + 1;
  final fyStart = DateTime(d.month >= 4 ? d.year : d.year - 1, 4, 1);
  return [
    ('This month', ymd(ms), ymd(d)),
    ('Last month', ymd(DateTime(lmEnd.year, lmEnd.month, 1)), ymd(lmEnd)),
    ('This quarter', ymd(DateTime(d.year, q, 1)), ymd(d)),
    ('FY ${fyStart.year}-${(fyStart.year + 1) % 100}', ymd(fyStart), ymd(d)),
  ];
}

class _PeriodBar extends StatelessWidget {
  final String from, to;
  final void Function(String, String) onChanged;
  const _PeriodBar(this.from, this.to, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final ps = periods();
    final custom = !ps.any((p) => p.$2 == from && p.$3 == to);
    Widget chip(String l, bool on, VoidCallback tap) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            tap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
              color: on ? null : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: on ? null : Border.all(color: _line),
            ),
            child: Text(l, style: _j(12, FontWeight.w700, on ? Colors.white : _ink)),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        for (final p in ps) chip(p.$1, p.$2 == from && p.$3 == to, () => onChanged(p.$2, p.$3)),
        chip(custom ? '${prettyDate(from)} – ${prettyDate(to)}' : 'Custom', custom, () async {
          final r = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2015),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            initialDateRange: DateTimeRange(start: DateTime.parse(from), end: DateTime.parse(to)),
          );
          if (r != null) onChanged(ymd(r.start), ymd(r.end));
        }),
      ]),
    );
  }
}

Widget _card(String title, List<Widget> children, {Widget? trailing}) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F2F9)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text(title, style: _j(15, FontWeight.w800, _ink))), if (trailing != null) trailing]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );

Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(l, style: _j(13, bold ? FontWeight.w800 : FontWeight.w500, bold ? _ink : _muted))),
        Text(v, style: _j(13.5, bold ? FontWeight.w800 : FontWeight.w700, color ?? _ink)),
      ]),
    );

Widget _table(List<String> head, List<List<String>> rows) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        columnSpacing: 18,
        horizontalMargin: 4,
        headingTextStyle: _j(11.5, FontWeight.w800, _muted),
        dataTextStyle: _j(12.5, FontWeight.w600, _ink),
        columns: [for (final h in head) DataColumn(label: Text(h))],
        rows: [for (final r in rows) DataRow(cells: [for (final c in r) DataCell(Text(c))])],
      ),
    );

Future<void> _export(BuildContext context, String kind, String from, String to) async {
  toast(context, 'Excel file banano hocche…');
  try {
    await ExportBook.share(kind, from, to);
  } catch (e) {
    if (context.mounted) toast(context, 'Export hoyni: $e', error: true);
  }
}

/// GST returns: GSTR-3B summary, rate-wise outward and ITC, B2B invoices,
/// HSN summary and credit notes — exported to Excel for the CA.
class GstScreen extends StatefulWidget {
  final String? from, to;
  const GstScreen({super.key, this.from, this.to});
  @override
  State<GstScreen> createState() => _GstScreenState();
}

class _GstScreenState extends State<GstScreen> {
  late String from = widget.from ?? periods().first.$2;
  late String to = widget.to ?? periods().first.$3;

  @override
  Widget build(BuildContext context) {
    return Live<GstReport>(
      key: ValueKey('$from$to'),
      load: () => GstReport.load(from, to),
      builder: (context, g) {
        final rs = Money.rs;
        return PageShell(
          title: 'GST Report',
          subtitle: 'GSTR-1 · GSTR-3B · HSN — CA-ke Excel pathan',
          children: [
            _PeriodBar(from, to, (f, t) => setState(() {
                  from = f;
                  to = t;
                })),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                    colors: g.payable > 0 ? const [Color(0xFFFF5C7A), Color(0xFFB4123E)] : const [Color(0xFF3EE08F), Color(0xFF0E7F4C)]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.payable >= 0 ? 'Net GST payable' : 'ITC carried forward', style: _j(13, FontWeight.w600, const Color(0xE6FFFFFF))),
                const SizedBox(height: 4),
                Text(rs(g.payable.abs()), style: _j(30, FontWeight.w800, Colors.white)),
                const SizedBox(height: 4),
                Text('Output ${rs(g.netOutTax)} − ITC ${rs(g.itc)} · ${g.invoices} invoice', style: _j(12, FontWeight.w600, const Color(0xE6FFFFFF))),
              ]),
            ),
            _card('GSTR-3B summary', [
              _row('3.1(a) Outward taxable value', rs(g.outTaxable)),
              _row('Output tax (CGST + SGST)', rs(g.outTax)),
              if (g.creditTax > 0) _row('Less: credit notes (${g.creditNotes.length} return)', '− ${rs(g.creditTax)}', color: _green),
              _row('CGST', rs(g.netOutTax ~/ 2)),
              _row('SGST', rs(g.netOutTax - g.netOutTax ~/ 2)),
              const Divider(color: _line),
              _row('4(A) Input tax credit (purchases ${rs(g.itcTaxable)})', rs(g.itc), color: _green),
              const Divider(color: _line),
              _row(g.payable >= 0 ? 'Net payable' : 'ITC carried forward', rs(g.payable.abs()), bold: true, color: g.payable > 0 ? _red : _green),
              if (g.discount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Bill discount ${rs(g.discount)} dewa hoyeche — taxable value-te kome dekhano hoyni, CA-ke jante din.',
                      style: _j(11, FontWeight.w500, _muted)),
                ),
            ]),
            _card('Rate-wise outward (GSTR-1)', [
              _table(['Rate', 'Qty', 'Taxable', 'CGST', 'SGST'], [
                for (final r in g.sorted(g.outward)) [r.rate, '${r.qty}', rs(r.taxable), rs(r.cgst), rs(r.sgst)],
              ]),
            ]),
            _card('B2B invoices · ${g.b2b.length}', [
              if (g.b2b.isEmpty)
                Text('GSTIN-wala customer-ke kono bill nei. Customer profile-e GSTIN dile B2B-te ashbe.', style: _j(12, FontWeight.w500, _muted))
              else
                _table(['Invoice', 'Date', 'Customer', 'GSTIN', 'Taxable', 'Tax'], [
                  for (final b in g.b2b)
                    ['${b['number']}', prettyDate('${b['date']}'), '${b['customer']}', '${b['gstin']}', rs(asInt(b['taxable'])), rs(asInt(b['tax']))],
                ]),
            ]),
            _card('HSN summary', [
              _table(['HSN', 'Rate', 'Qty', 'Taxable', 'Tax'], [
                for (final h in (g.hsn.values.toList()..sort((a, b) => a.hsn.compareTo(b.hsn))))
                  [h.hsn, GstRateRow(h.rateBp).rate, '${h.qty}', rs(h.taxable), rs(h.tax)],
              ]),
            ]),
            _card('Input tax credit by rate', [
              _table(['Rate', 'Qty', 'Taxable', 'ITC'], [
                for (final r in g.sorted(g.inward)) [r.rate, '${r.qty}', rs(r.taxable), rs(r.tax)],
              ]),
            ]),
            const SizedBox(height: 14),
            _BigButton(
              icon: Icons.table_view_rounded,
              label: 'Excel download · GSTR-1 + 3B + HSN',
              onTap: () => _export(context, 'gst', from, to),
            ),
            const SizedBox(height: 8),
            Text('Sob supply intra-state (CGST + SGST) dhora hoyeche. File korar age CA-ke dekhiye nin.',
                textAlign: TextAlign.center, style: _j(11, FontWeight.w500, _muted)),
          ],
        );
      },
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: const LinearGradient(colors: [Color(0xFF21A366), Color(0xFF107C41)]),
            boxShadow: const [BoxShadow(color: Color(0x40107C41), blurRadius: 16, offset: Offset(0, 8), spreadRadius: -6)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Text(label, style: _j(14.5, FontWeight.w800, Colors.white)),
          ]),
        ),
      );
}

/// Excel export of any register for any period.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late String from = periods().first.$2;
  late String to = periods().first.$3;
  String? busy;

  static const _icons = <String, (IconData, List<Color>, String)>{
    'all': (Icons.workspaces_rounded, [Color(0xFF21A366), Color(0xFF107C41)], 'Shob sheet ek file-e: sale, purchase, stock, party, day book, GST'),
    'sales': (Icons.receipt_long_rounded, [Color(0xFF8B5CF6), Color(0xFF5B2EE0)], 'Protiti bill + item-wise lav, IMEI soho'),
    'purchases': (Icons.shopping_bag_rounded, [Color(0xFFB58CFF), Color(0xFF7B3FF2)], 'Supplier bill, GSTIN, payable'),
    'stock': (Icons.inventory_2_rounded, [Color(0xFF6AA5FF), Color(0xFF1A47C8)], 'Product, stock, kena dam, stock value'),
    'parties': (Icons.groups_rounded, [Color(0xFF4FD8E0), Color(0xFF139DB0)], 'Customer baki ar supplier payable'),
    'expenses': (Icons.sell_rounded, [Color(0xFFFF7A7A), Color(0xFFDC4545)], 'Category-wise khoroch'),
    'daybook': (Icons.event_note_rounded, [Color(0xFF5EEAD4), Color(0xFF0D9488)], 'Tally-r moto journal: debit / credit'),
    'gst': (Icons.request_quote_rounded, [Color(0xFFF472B6), Color(0xFFDB2777)], 'GSTR-1, GSTR-3B, HSN, credit note'),
  };

  Future<void> _go(String kind) async {
    if (busy != null) return;
    setState(() => busy = kind);
    await _export(context, kind, from, to);
    if (mounted) setState(() => busy = null);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Excel Export',
      subtitle: 'Asol .xlsx file · Excel, Google Sheets, WPS-e khulbe',
      children: [
        _PeriodBar(from, to, (f, t) => setState(() {
              from = f;
              to = t;
            })),
        const SizedBox(height: 6),
        for (final k in ExportBook.kinds)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: k.$1 == 'all' ? const Color(0xFF21A366) : const Color(0xFFF1F2F9), width: k.$1 == 'all' ? 1.5 : 1),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _go(k.$1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: _icons[k.$1]!.$2)),
                      child: Icon(_icons[k.$1]!.$1, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(k.$2, style: _j(14.5, FontWeight.w800, _ink)),
                        const SizedBox(height: 2),
                        Text(_icons[k.$1]!.$3, style: _j(11.5, FontWeight.w500, _muted)),
                      ]),
                    ),
                    busy == k.$1
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Icon(Icons.download_rounded, color: Color(0xFF107C41)),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text('Stock ar party sheet aajker hisab dekhay; baki sob sheet upore bacha somoy-er.',
            textAlign: TextAlign.center, style: _j(11, FontWeight.w500, _muted)),
      ],
    );
  }
}
