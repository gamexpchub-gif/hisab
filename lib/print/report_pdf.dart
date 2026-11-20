import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/books.dart';
import '../core/daily_report.dart';
import '../core/money.dart';

/// The Daily AI Report as a one-page PDF (to share on WhatsApp / print).
Future<Uint8List> dailyReportPdf(DailyReport r, String shop) async {
  Future<pw.Font> f(String n) async => pw.Font.ttf(await rootBundle.load('assets/pdf/$n.ttf'));
  final reg = await f('Jakarta-Regular'), semi = await f('Jakarta-SemiBold'), bold = await f('Jakarta-ExtraBold');
  const ink = PdfColor.fromInt(0xFF0A0E26), muted = PdfColor.fromInt(0xFF6B7094), brand = PdfColor.fromInt(0xFF4318D2);
  const green = PdfColor.fromInt(0xFF0BA360), red = PdfColor.fromInt(0xFFE0245E), soft = PdfColor.fromInt(0xFFF4F5FB);
  pw.TextStyle t(double s, pw.Font font, PdfColor c) => pw.TextStyle(font: font, fontSize: s, color: c);

  pw.Widget kpi(String label, String value, {PdfColor color = ink}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.all(4),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: t(9, semi, muted)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: t(14, bold, color)),
          ]),
        ),
      );

  pw.Widget section(String title, List<List<String>> rows, List<String> head) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          pw.Text(title, style: t(12, bold, ink)),
          pw.SizedBox(height: 6),
          if (rows.isEmpty)
            pw.Text('Nothing', style: t(10, reg, muted))
          else
            pw.TableHelper.fromTextArray(
              headers: head,
              data: rows,
              headerStyle: t(9, bold, PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: brand),
              cellStyle: t(9.5, reg, ink),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: soft))),
              cellAlignments: {for (var i = 1; i < head.length; i++) i: pw.Alignment.centerRight},
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
      );

  final doc = pw.Document(title: '$shop daily report ${r.day}', author: 'Hisab AI');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(14),
          gradient: const pw.LinearGradient(colors: [PdfColor.fromInt(0xFF1B1F6B), PdfColor.fromInt(0xFF4318D2)]),
        ),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(shop, style: t(18, bold, PdfColors.white)),
              pw.Text('Daily AI Report · ${prettyDate(r.day)}', style: t(10.5, semi, const PdfColor.fromInt(0xD9FFFFFF))),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(Money.rs(r.sales), style: t(20, bold, PdfColors.white)),
            pw.Text('${r.change >= 0 ? '+' : '-'}${r.change.abs()}% vs yesterday', style: t(9.5, semi, const PdfColor.fromInt(0xD9FFFFFF))),
          ]),
        ]),
      ),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        kpi('Bills', '${r.invoices} · ${r.items} items'),
        kpi('Profit', '${Money.rs(r.profit)} (${r.margin}%)', color: r.profit >= 0 ? green : red),
        kpi('Collected', Money.rs(r.collected), color: green),
      ]),
      pw.Row(children: [
        kpi('Expenses', Money.rs(r.expenses), color: red),
        kpi('Purchases', Money.rs(r.purchases)),
        kpi('Dues (total)', Money.rs(r.totalDue), color: red),
      ]),
      if (r.best != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 8, left: 4), child: pw.Text('Best seller: ${r.best}', style: t(10.5, semi, ink))),
      if (r.cash.isNotEmpty)
        section('Money now', [for (final e in r.cash.entries) [e.key, Money.rs(e.value)]], ['Account', 'Balance']),
      section('Due tomorrow', [
        for (final x in r.tomorrow.take(15)) ['${x['name']}${x['late'] == true ? ' (late)' : ''}', '${x['what']}', Money.rs(asInt(x['amount']))]
      ], [
        'Name',
        'For',
        'Amount'
      ]),
      section('To re-order', [
        for (final x in r.reorder.take(15)) ['${x['name']}', '${x['stock']}', '${x['need']} pcs']
      ], [
        'Product',
        'Stock',
        'Order'
      ]),
      pw.Spacer(),
      pw.Text('Made by Hisab AI', textAlign: pw.TextAlign.center, style: t(8.5, reg, muted)),
    ]),
  ));
  return doc.save();
}
