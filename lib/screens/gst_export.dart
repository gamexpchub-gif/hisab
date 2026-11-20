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
        rows: [
          for (final r in rows) DataRow(cells: [for (final c in r) DataCell(Text(c))])
        ],
      ),
    );

Future<void> _export(BuildContext context, String kind, String from, String to) async {
  toast(context, 'Creating the Excel file…');
  try {
    await ExportBook.share(kind, from, to);
  } catch (e) {
    if (context.mounted) toast(context, 'Export failed: $e', error: true);
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
  int tab = 0;
  bool busy = false;

  Future<void> _json() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ExportBook.shareGstr1Json(from, to);
    } catch (e) {
      if (mounted) toast(context, 'Could not make the JSON: $e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Live<GstReport>(
      key: ValueKey('$from$to'),
      load: () => GstReport.load(from, to),
      builder: (context, g) {
        final rs = Money.rs;
        final so = g.setOff;
        final (oi, oc, os) = g.outHeads;
        final (ci, cc, cs) = g.itcHeads;
        final noHsn = g.hsn.values.where((h) => h.hsn == '—').fold<int>(0, (a, h) => a + h.qty);
        final oneMonth = from.substring(0, 7) == to.substring(0, 7);
        return PageShell(
          title: 'GST Returns',
          subtitle: 'GSTR-1 · GSTR-3B · GSTR-2 · HSN',
          children: [
            _PeriodBar(
                from,
                to,
                (f, t) => setState(() {
                      from = f;
                      to = t;
                    })),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient:
                    LinearGradient(colors: g.cashPayable > 0 ? const [Color(0xFFFF5C7A), Color(0xFFB4123E)] : const [Color(0xFF3EE08F), Color(0xFF0E7F4C)]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.cashPayable > 0 ? 'GST to pay in cash' : 'Nothing to pay', style: _j(13, FontWeight.w600, const Color(0xE6FFFFFF))),
                const SizedBox(height: 4),
                Text(rs(g.cashPayable), style: _j(30, FontWeight.w800, Colors.white)),
                const SizedBox(height: 4),
                Text('Output ${rs(g.netOutTax)} − ITC ${rs(g.itc)} · ${g.invoices} invoices', style: _j(12, FontWeight.w600, const Color(0xE6FFFFFF))),
              ]),
            ),
            if (g.gstin.isEmpty || noHsn > 0)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (g.gstin.isEmpty) Text('• Add your shop GSTIN in Settings', style: _j(12, FontWeight.w700, const Color(0xFF8A5300))),
                  if (noHsn > 0)
                    Text('• $noHsn items sold without an HSN code — add HSN to those products', style: _j(12, FontWeight.w700, const Color(0xFF8A5300))),
                ]),
              ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (k, l) in const [(0, 'GSTR-1'), (1, 'GSTR-3B'), (2, 'GSTR-2'), (3, 'HSN')])
                  GestureDetector(
                    onTap: () => setState(() => tab = k),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: tab == k ? const LinearGradient(colors: [Color(0xFFF472B6), Color(0xFFDB2777)]) : null,
                        color: tab == k ? null : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: tab == k ? null : Border.all(color: _line),
                      ),
                      child: Text(l, style: _j(13, FontWeight.w800, tab == k ? Colors.white : _ink)),
                    ),
                  ),
              ]),
            ),
            if (tab == 0) ...[
              _card('B2B invoices · ${g.b2bDocs.length}', [
                if (g.b2bDocs.isEmpty)
                  Text('No bills to customers with a GSTIN.', style: _j(12, FontWeight.w500, _muted))
                else
                  _table([
                    'Invoice',
                    'Date',
                    'Customer',
                    'GSTIN',
                    'POS',
                    'Taxable',
                    'IGST',
                    'CGST+SGST'
                  ], [
                    for (final d in g.b2bDocs) [d.number, prettyDate(d.date), d.party, d.gstin, d.pos, rs(d.taxable), rs(d.igst), rs(d.tax - d.igst)],
                  ]),
              ]),
              _card('B2C small (by rate)', [
                _table([
                  'State',
                  'Rate',
                  'Taxable',
                  'IGST',
                  'CGST',
                  'SGST'
                ], [
                  for (final e in g.b2cs.entries)
                    if (e.value.taxable != 0) [e.key.split('|').first, e.value.rate, rs(e.value.taxable), rs(e.value.igst), rs(e.value.cgst), rs(e.value.sgst)],
                ]),
              ]),
              _card('Credit notes · ${g.creditNotes.length}', [
                if (g.creditNotes.isEmpty)
                  Text('No sale returns in this period.', style: _j(12, FontWeight.w500, _muted))
                else
                  _table([
                    'Note',
                    'Date',
                    'Invoice',
                    'Customer',
                    'Taxable',
                    'Tax'
                  ], [
                    for (final c in g.creditNotes)
                      [
                        '${c['number']}',
                        prettyDate('${c['date']}'),
                        '${c['invoice']}',
                        '${c['customer'] ?? 'Walk-in'}',
                        rs(asInt(c['taxable'])),
                        rs(asInt(c['tax']))
                      ],
                  ]),
              ]),
              _card('Documents issued', [
                _row('Invoices', g.invoices == 0 ? '—' : '${g.firstInvoice} → ${g.lastInvoice} (${g.invoices})'),
                _row('Credit notes', g.creditNotes.isEmpty ? '—' : '${g.firstCn} → ${g.lastCn} (${g.creditNotes.length})'),
              ]),
            ],
            if (tab == 1) ...[
              _card('3.1 Outward supplies', [
                _row('(a) Taxable value', rs(g.outTaxable - g.creditTaxable - g.nilRated)),
                _row('IGST', rs(oi)),
                _row('CGST', rs(oc)),
                _row('SGST', rs(os)),
                if (g.nilRated > 0) _row('(c) Nil rated / exempt', rs(g.nilRated)),
                if (g.creditTax > 0) _row('Credit notes taken off', '− ${rs(g.creditTax)}', color: _green),
              ]),
              _card('4 Input tax credit', [
                _row('Purchases (taxable)', rs(g.itcTaxable)),
                _row('IGST', rs(ci), color: _green),
                _row('CGST', rs(cc), color: _green),
                _row('SGST', rs(cs), color: _green),
                if (g.itcBlocked > 0) _row('No ITC (supplier without GSTIN)', rs(g.itcBlocked), color: _red),
              ]),
              _card('6.1 Payment of tax', [
                _row('IGST in cash', rs(so.cash.$1)),
                _row('CGST in cash', rs(so.cash.$2)),
                _row('SGST in cash', rs(so.cash.$3)),
                const Divider(color: _line),
                _row('Total to pay', rs(g.cashPayable), bold: true, color: g.cashPayable > 0 ? _red : _green),
                _row('ITC carried forward', rs(so.left.$1 + so.left.$2 + so.left.$3), color: _green),
              ]),
            ],
            if (tab == 2)
              _card('Purchases with ITC · ${g.purchaseDocs.length}', [
                if (g.purchaseDocs.isEmpty)
                  Text('No purchases from suppliers with a GSTIN.', style: _j(12, FontWeight.w500, _muted))
                else
                  _table([
                    'Bill',
                    'Date',
                    'Supplier',
                    'GSTIN',
                    'Taxable',
                    'ITC'
                  ], [
                    for (final d in g.purchaseDocs) [d.number, prettyDate(d.date), d.party, d.gstin, rs(d.taxable), rs(d.tax)],
                  ]),
                if (g.itcBlocked > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('GST of ${rs(g.itcBlocked)} on bills from suppliers without a GSTIN cannot be claimed — add their GSTIN.',
                        style: _j(11.5, FontWeight.w600, _red)),
                  ),
              ]),
            if (tab == 3)
              _card('HSN summary', [
                _table([
                  'HSN',
                  'Type',
                  'Rate',
                  'Qty',
                  'Taxable',
                  'IGST',
                  'CGST',
                  'SGST'
                ], [
                  for (final h in (g.hsn.values.toList()..sort((a, b) => a.hsn.compareTo(b.hsn))))
                    [h.hsn, h.b2b ? 'B2B' : 'B2C', GstRateRow(h.rateBp).rate, '${h.qty}', rs(h.taxable), rs(h.igst), rs(h.cgst), rs(h.sgst)],
                ]),
              ]),
            const SizedBox(height: 14),
            _BigButton(
              icon: Icons.table_view_rounded,
              label: 'Excel · all returns',
              onTap: () => _export(context, 'gst', from, to),
            ),
            const SizedBox(height: 8),
            _BigButton(
              icon: Icons.data_object_rounded,
              label: busy ? 'Making JSON…' : 'GSTR-1 JSON (portal)',
              colors: const [Color(0xFF6B35EE), Color(0xFF4318D2)],
              onTap: () {
                if (!oneMonth) {
                  toast(context, 'Choose one month for the GSTR-1 JSON', error: true);
                  return;
                }
                _json();
              },
            ),
            const SizedBox(height: 8),
            Text('Import the JSON in the GST offline tool, check, then upload. Check with your CA before filing.',
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
  final List<Color> colors;
  const _BigButton({required this.icon, required this.label, required this.onTap, this.colors = const [Color(0xFF21A366), Color(0xFF107C41)]});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withAlpha(0x40), blurRadius: 16, offset: const Offset(0, 8), spreadRadius: -6)],
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
    'all': (Icons.workspaces_rounded, [Color(0xFF21A366), Color(0xFF107C41)], 'Every sheet in one file: sales, purchases, stock, parties, day book, GST'),
    'sales': (Icons.receipt_long_rounded, [Color(0xFF8B5CF6), Color(0xFF5B2EE0)], 'Every bill plus item-wise profit, with IMEI'),
    'purchases': (Icons.shopping_bag_rounded, [Color(0xFFB58CFF), Color(0xFF7B3FF2)], 'Supplier bills, GSTIN, payables'),
    'stock': (Icons.inventory_2_rounded, [Color(0xFF6AA5FF), Color(0xFF1A47C8)], 'Products, stock, cost, stock value'),
    'parties': (Icons.groups_rounded, [Color(0xFF4FD8E0), Color(0xFF139DB0)], 'Customer dues and supplier payables'),
    'expenses': (Icons.sell_rounded, [Color(0xFFFF7A7A), Color(0xFFDC4545)], 'Expenses by category'),
    'daybook': (Icons.event_note_rounded, [Color(0xFF5EEAD4), Color(0xFF0D9488)], 'Tally-style journal: debit / credit'),
    'gst': (Icons.request_quote_rounded, [Color(0xFFF472B6), Color(0xFFDB2777)], 'GSTR-1, GSTR-3B, GSTR-2, HSN, credit notes'),
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
      subtitle: 'Real .xlsx files · open in Excel, Google Sheets or WPS',
      children: [
        _PeriodBar(
            from,
            to,
            (f, t) => setState(() {
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
        Text('Stock and party sheets show today\'s position; other sheets cover the chosen period.',
            textAlign: TextAlign.center, style: _j(11, FontWeight.w500, _muted)),
      ],
    );
  }
}
