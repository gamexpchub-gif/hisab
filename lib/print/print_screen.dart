import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../core/books.dart';
import '../ui/widgets.dart';
import 'invoice_pdf.dart';

export 'invoice_pdf.dart';

// =============================================================================
// Printing — one-tap print with the saved layout, and a custom print studio
// with paper size (A4 / A5 / Letter / Legal / 80 mm / 58 mm thermal), title,
// copy label, GST style, sections on/off, colour or black & white, margins,
// and a live preview with print / share.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);

TextStyle _j(double size, FontWeight w, Color c) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
    );

/// Prints a sale straight away with the saved print settings.
Future<void> quickPrint(BuildContext context, int saleId) async {
  try {
    final d = await InvoiceData.load(saleId);
    if (d == null) return;
    final o = PrintOptions.fromSettings(d.settings);
    await Printing.layoutPdf(
      name: '${d.sale['number']}',
      format: o.format,
      onLayout: (format) => buildInvoicePdf(d, o, format: o.thermal ? o.format : format),
    );
  } catch (e) {
    if (context.mounted) toast(context, 'Could not print: $e', error: true);
  }
}

/// Shares the invoice PDF (WhatsApp, email, Drive…).
Future<void> shareInvoicePdf(BuildContext context, int saleId) async {
  try {
    final d = await InvoiceData.load(saleId);
    if (d == null) return;
    final bytes = await buildInvoicePdf(d, PrintOptions.fromSettings(d.settings));
    await Printing.sharePdf(bytes: bytes, filename: 'Invoice-${d.sale['number']}.pdf');
  } catch (e) {
    if (context.mounted) toast(context, 'Could not share: $e', error: true);
  }
}

class PrintStudio extends StatefulWidget {
  final int saleId;
  const PrintStudio({super.key, required this.saleId});
  @override
  State<PrintStudio> createState() => _PrintStudioState();
}

class _PrintStudioState extends State<PrintStudio> {
  InvoiceData? data;
  PrintOptions o = PrintOptions();
  int version = 0;
  bool panel = true;

  @override
  void initState() {
    super.initState();
    InvoiceData.load(widget.saleId).then((d) {
      if (!mounted || d == null) return;
      setState(() {
        data = d;
        o = PrintOptions.fromSettings(d.settings);
      });
    });
  }

  void _set(VoidCallback f) {
    HapticFeedback.selectionClick();
    setState(() {
      f();
      version++;
    });
    for (final e in o.toSettings().entries) {
      Books.setSetting(e.key, e.value);
    }
  }

  Future<Uint8List> _build(_) => buildInvoicePdf(data!, o);

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text('Print ${d?.sale['number'] ?? ''}', style: _j(18, FontWeight.w800, _navy)),
        actions: [
          IconButton(
            tooltip: panel ? 'Hide options' : 'Show options',
            onPressed: () => setState(() => panel = !panel),
            icon: Icon(panel ? Icons.expand_less_rounded : Icons.tune_rounded, color: _navy),
          ),
        ],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                child: panel ? _options() : const SizedBox(width: double.infinity),
              ),
              Expanded(
                child: PdfPreview(
                  key: ValueKey(version),
                  build: _build,
                  initialPageFormat: o.format,
                  allowPrinting: true,
                  allowSharing: true,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'Invoice-${d.sale['number']}.pdf',
                  previewPageMargin: const EdgeInsets.all(10),
                  scrollViewDecoration: const BoxDecoration(color: Color(0xFFE6E8F2)),
                ),
              ),
            ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {IconData? icon}) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: on ? null : Border.all(color: _line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: on ? Colors.white : _navy), const SizedBox(width: 5)],
            Text(label, style: _j(11.5, FontWeight.w700, on ? Colors.white : _ink)),
          ]),
        ),
      );

  Widget _row(String title, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 62, child: Text(title, style: _j(11, FontWeight.w800, _muted))),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final c in chips) ...[c, const SizedBox(width: 6)]]),
            ),
          ),
        ]),
      );

  Widget _options() {
    final thermal = o.thermal;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6)],
      ),
      child: Column(children: [
        _row('Paper', [
          for (final p in [('a4', 'A4'), ('a5', 'A5'), ('letter', 'Letter'), ('legal', 'Legal'), ('80mm', '80 mm'), ('58mm', '58 mm')])
            _chip(p.$2, o.paper == p.$1, () => _set(() => o.paper = p.$1),
                icon: p.$1.endsWith('mm') ? Icons.receipt_rounded : Icons.description_rounded),
        ]),
        _row('Title', [
          for (final t in ['TAX INVOICE', 'BILL OF SUPPLY', 'CASH MEMO', 'ESTIMATE'])
            _chip(t, o.title == t, () => _set(() => o.title = t)),
        ]),
        if (!thermal) ...[
          _row('Copy', [
            for (final c in [('ORIGINAL FOR RECIPIENT', 'Original'), ('DUPLICATE FOR TRANSPORTER', 'Duplicate'), ('TRIPLICATE FOR SUPPLIER', 'Triplicate')])
              _chip(c.$2, o.copy == c.$1, () => _set(() => o.copy = c.$1)),
          ]),
          _row('GST', [
            _chip('IGST', o.tax == 'igst', () => _set(() => o.tax = 'igst')),
            _chip('CGST + SGST', o.tax == 'cgst', () => _set(() => o.tax = 'cgst')),
          ]),
          _row('Margin', [
            for (final m in ['narrow', 'normal', 'wide'])
              _chip(m[0].toUpperCase() + m.substring(1), o.margin == m, () => _set(() => o.margin = m)),
          ]),
        ],
        _row('Show', [
          _chip('Colour', o.color, () => _set(() => o.color = !o.color), icon: Icons.palette_rounded),
          _chip('IMEI', o.imei, () => _set(() => o.imei = !o.imei)),
          _chip('UPI QR', o.qr, () => _set(() => o.qr = !o.qr)),
          if (!thermal) ...[
            _chip('Brands', o.brands, () => _set(() => o.brands = !o.brands)),
            _chip('Banner', o.banner, () => _set(() => o.banner = !o.banner)),
            _chip('HSN', o.hsn, () => _set(() => o.hsn = !o.hsn)),
            _chip('Bank', o.bank, () => _set(() => o.bank = !o.bank)),
            _chip('Terms', o.terms, () => _set(() => o.terms = !o.terms)),
            _chip('Signature', o.signature, () => _set(() => o.signature = !o.signature)),
          ],
        ]),
      ]),
    );
  }
}
