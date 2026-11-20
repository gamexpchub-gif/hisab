import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/books.dart';
import '../core/money.dart';

// =============================================================================
// Barcode labels — price stickers with a Code 128 barcode of the product's
// SKU (or a stable P-number when it has none): product name, variant, price
// and MRP. Roll sizes for label printers and an A4 sheet of 24 labels.
// =============================================================================

class LabelSize {
  final String id, label;
  final double w, h; // millimetres
  const LabelSize(this.id, this.label, this.w, this.h);
}

const labelSizes = [
  LabelSize('50x25', '50 × 25 mm', 50, 25),
  LabelSize('38x25', '38 × 25 mm', 38, 25),
  LabelSize('50x30', '50 × 30 mm', 50, 30),
  LabelSize('a4', 'A4 sheet (3 × 8)', 70, 37),
];

/// The code printed on a product's label.
String labelCode(Rec p) {
  final sku = '${p['sku'] ?? ''}'.trim();
  return sku.isNotEmpty ? sku : 'P${asInt(p['id']).toString().padLeft(6, '0')}';
}

class _Fonts {
  final pw.Font regular, bold, black;
  _Fonts(this.regular, this.bold, this.black);
  static _Fonts? cache;
  static Future<_Fonts> load() async {
    Future<pw.Font> f(String n) async => pw.Font.ttf(await rootBundle.load('assets/pdf/$n.ttf'));
    return cache ??= _Fonts(await f('Jakarta-Regular'), await f('Jakarta-Bold'), await f('Montserrat-Black'));
  }
}

Future<Uint8List> buildLabels(
  List<(Rec, int)> items, {
  required LabelSize size,
  required String shop,
  bool price = true,
  bool mrp = true,
  bool name = true,
}) async {
  final f = await _Fonts.load();
  final doc = pw.Document(title: 'Barcode labels', theme: pw.ThemeData.withFont(base: f.regular, bold: f.bold));
  final labels = [for (final (p, n) in items) for (var i = 0; i < n; i++) p];
  final s = size.h / 25; // text scale

  pw.Widget label(Rec p) {
    final pr = asInt(p['price']), m = asInt(p['mrp']);
    final variant = '${p['variant'] ?? ''}'.trim();
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 1.6 * PdfPageFormat.mm, vertical: 1.2 * PdfPageFormat.mm),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if (name)
          pw.Text('${p['name']}',
              maxLines: 1, overflow: pw.TextOverflow.clip, style: pw.TextStyle(font: f.bold, fontSize: 7.2 * s)),
        if (name && variant.isNotEmpty)
          pw.Text(variant, maxLines: 1, overflow: pw.TextOverflow.clip, style: pw.TextStyle(font: f.regular, fontSize: 5.6 * s)),
        pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
        pw.Expanded(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: labelCode(p),
            drawText: true,
            textStyle: pw.TextStyle(font: f.regular, fontSize: 5.6 * s, letterSpacing: .6),
          ),
        ),
        if (price)
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(shop, maxLines: 1, style: pw.TextStyle(font: f.regular, fontSize: 5 * s)),
            pw.Row(children: [
              if (mrp && m > pr)
                pw.Text('MRP ₹${Money.inr(m)}  ',
                    style: pw.TextStyle(font: f.regular, fontSize: 5.4 * s, decoration: pw.TextDecoration.lineThrough)),
              pw.Text('₹${Money.inr(pr)}', style: pw.TextStyle(font: f.black, fontSize: 9 * s)),
            ]),
          ]),
      ]),
    );
  }

  if (size.id == 'a4') {
    const cols = 3, rows = 8;
    final fmt = PdfPageFormat.a4.copyWith(
        marginLeft: 0, marginRight: 0, marginTop: 4 * PdfPageFormat.mm, marginBottom: 4 * PdfPageFormat.mm);
    for (var start = 0; start < labels.length; start += cols * rows) {
      final page = labels.skip(start).take(cols * rows).toList();
      doc.addPage(pw.Page(
        pageFormat: fmt,
        build: (_) => pw.Column(children: [
          for (var r = 0; r < rows; r++)
            pw.Expanded(
              child: pw.Row(children: [
                for (var c = 0; c < cols; c++)
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.all(2),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300, width: .4),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: r * cols + c < page.length ? label(page[r * cols + c]) : pw.SizedBox(),
                    ),
                  ),
              ]),
            ),
        ]),
      ));
    }
  } else {
    final fmt = PdfPageFormat(size.w * PdfPageFormat.mm, size.h * PdfPageFormat.mm, marginAll: 0);
    for (final p in labels) {
      doc.addPage(pw.Page(pageFormat: fmt, build: (_) => label(p)));
    }
  }
  if (labels.isEmpty) doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('No labels'))));
  return doc.save();
}

/// Choose size, copies and what to show, with a live preview; print or share.
class LabelStudio extends StatefulWidget {
  final List<Rec> products;
  const LabelStudio({super.key, required this.products});
  @override
  State<LabelStudio> createState() => _LabelStudioState();
}

class _LabelStudioState extends State<LabelStudio> {
  LabelSize size = labelSizes.first;
  late final copies = {for (final p in widget.products) asInt(p['id']): asInt(p['stock']) > 0 ? asInt(p['stock']).clamp(1, 50).toInt() : 1};
  bool price = true, mrp = true, name = true;
  String shop = '';
  int version = 0;

  @override
  void initState() {
    super.initState();
    Books.settings().then((s) {
      if (mounted) setState(() {
        final n = (s['business_name'] ?? '').trim();
        shop = n.isEmpty ? 'GameX Pc Hub' : n;
      });
    });
  }

  void _set(VoidCallback f) => setState(() {
        f();
        version++;
      });

  Widget _chip(String l, bool on, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: on ? null : Border.all(color: const Color(0xFFE9EAF5)),
          ),
          child: Text(l, style: TextStyle(fontFamily: 'Jakarta', fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : const Color(0xFF0A0E26))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final total = copies.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FC),
        title: Text('Barcode labels · $total', style: const TextStyle(fontFamily: 'Jakarta', fontWeight: FontWeight.w800, color: Color(0xFF0B0F5E))),
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final z in labelSizes) _chip(z.label, size.id == z.id, () => _set(() => size = z))]),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('Name', name, () => _set(() => name = !name)),
                _chip('Price', price, () => _set(() => price = !price)),
                _chip('MRP', mrp, () => _set(() => mrp = !mrp)),
              ]),
            ),
            for (final p in widget.products)
              Row(children: [
                Expanded(
                  child: Text('${p['name']} · ${labelCode(p)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Jakarta', fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: () => _set(() => copies[asInt(p['id'])] = ((copies[asInt(p['id'])] ?? 1) - 1).clamp(0, 999).toInt()),
                ),
                Text('${copies[asInt(p['id'])]}', style: const TextStyle(fontFamily: 'Jakarta', fontWeight: FontWeight.w800)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF5B2EE0)),
                  onPressed: () => _set(() => copies[asInt(p['id'])] = (copies[asInt(p['id'])] ?? 0) + 1),
                ),
              ]),
          ]),
        ),
        Expanded(
          child: PdfPreview(
            key: ValueKey(version),
            build: (_) => buildLabels([for (final p in widget.products) (p, copies[asInt(p['id'])] ?? 0)],
                size: size, shop: shop, price: price, mrp: mrp, name: name),
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: 'barcode-labels.pdf',
          ),
        ),
      ]),
    );
  }
}
