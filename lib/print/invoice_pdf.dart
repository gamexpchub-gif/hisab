import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/books.dart';
import '../core/money.dart';

// =============================================================================
// Tax invoice PDF — the GameX Pc Hub bill design: logo + shop header with an
// authorised-dealer brand grid, banner, GSTIN / TAX INVOICE / copy label,
// customer & invoice details, GST item table (IMEI, HSN), amount in words,
// bank details, terms, summary and a UPI QR for the amount. Also a compact
// thermal receipt for 58 / 80 mm printers.
// =============================================================================

/// Everything the user can customise when printing.
class PrintOptions {
  String paper; // a4 | a5 | letter | legal | 80mm | 58mm
  String title; // TAX INVOICE | BILL OF SUPPLY | CASH MEMO | ESTIMATE
  String copy; // ORIGINAL FOR RECIPIENT | DUPLICATE … | TRIPLICATE …
  String tax; // igst | cgst
  bool brands, banner, qr, bank, terms, imei, hsn, signature, color;
  String margin; // narrow | normal | wide

  PrintOptions({
    this.paper = 'a4',
    this.title = 'TAX INVOICE',
    this.copy = 'ORIGINAL FOR RECIPIENT',
    this.tax = 'igst',
    this.brands = true,
    this.banner = true,
    this.qr = true,
    this.bank = true,
    this.terms = true,
    this.imei = true,
    this.hsn = true,
    this.signature = true,
    this.color = true,
    this.margin = 'normal',
  });

  bool get thermal => paper == '80mm' || paper == '58mm';

  PdfPageFormat get format => switch (paper) {
        'a5' => PdfPageFormat.a5,
        'letter' => PdfPageFormat.letter,
        'legal' => PdfPageFormat.legal,
        '80mm' => PdfPageFormat.roll80,
        '58mm' => PdfPageFormat.roll57,
        _ => PdfPageFormat.a4,
      };

  Map<String, String> toSettings() => {
        'print_paper': paper,
        'print_title': title,
        'print_tax': tax,
        'print_margin': margin,
        'print_flags': [
          if (brands) 'brands',
          if (banner) 'banner',
          if (qr) 'qr',
          if (bank) 'bank',
          if (terms) 'terms',
          if (imei) 'imei',
          if (hsn) 'hsn',
          if (signature) 'signature',
          if (color) 'color',
        ].join(','),
      };

  static PrintOptions fromSettings(Map<String, String> s) {
    final f = s['print_flags'];
    bool on(String k) => f == null || f.split(',').contains(k);
    return PrintOptions(
      paper: s['print_paper'] ?? 'a4',
      title: s['print_title'] ?? 'TAX INVOICE',
      tax: s['print_tax'] ?? 'igst',
      margin: s['print_margin'] ?? 'normal',
      brands: on('brands'),
      banner: on('banner'),
      qr: on('qr'),
      bank: on('bank'),
      terms: on('terms'),
      imei: on('imei'),
      hsn: on('hsn'),
      signature: on('signature'),
      color: on('color'),
    );
  }
}

/// Everything printed on the invoice.
class InvoiceData {
  final Rec sale;
  final List<Rec> items;
  final List<(String, int)> payments;
  final Map<String, String> settings;
  InvoiceData(this.sale, this.items, this.payments, this.settings);

  static Future<InvoiceData?> load(int saleId) async {
    final s = await Books.query(
        'SELECT s.*, c.name AS customer, c.phone AS phone, c.address AS address, c.gstin AS gstin FROM sales s '
        'LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id = ?',
        [saleId]);
    if (s.isEmpty) return null;
    final items = await Books.query(
        'SELECT i.*, p.hsn AS hsn, p.brand AS brand FROM sale_items i LEFT JOIN products p ON p.id = i.product_id '
        'WHERE i.sale_id = ? ORDER BY i.id',
        [saleId]);
    final pays = await Books.query(
        'SELECT a.name AS name, p.amount AS amount FROM sale_payments p JOIN accounts a ON a.id = p.account_id '
        'WHERE p.sale_id = ? ORDER BY p.id',
        [saleId]);
    return InvoiceData(s.first, items, [for (final p in pays) ('${p['name']}', asInt(p['amount']))], await Books.settings());
  }
}

/// Default shop texts used when the settings are empty.
const defaultTerms = 'Subject to Malda jurisdiction only.\n'
    'Our Responsibility Ceases as soon as goods leave our Premises.\n'
    'Goods once sold will not be taken back or exchanged.\n'
    'Warranty as per manufacturer\'s policy only.\n'
    'Delivery Ex-Premises. Customer bears transport risk.';
const defaultBanner =
    'Get All Your Desired Smart Phones, Laptops, Gaming Gear & Accessories — Best Price Guaranteed & Easy EMI Available';

/// Indian-system amount in words: "TWENTY THOUSAND RUPEES ONLY".
String amountInWords(int paise) {
  const ones = [
    '', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN', 'ELEVEN', 'TWELVE', //
    'THIRTEEN', 'FOURTEEN', 'FIFTEEN', 'SIXTEEN', 'SEVENTEEN', 'EIGHTEEN', 'NINETEEN',
  ];
  const tens = ['', '', 'TWENTY', 'THIRTY', 'FORTY', 'FIFTY', 'SIXTY', 'SEVENTY', 'EIGHTY', 'NINETY'];
  String two(int n) => n < 20 ? ones[n] : '${tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${ones[n % 10]}'}';
  String three(int n) {
    final h = n ~/ 100, r = n % 100;
    return [if (h > 0) '${ones[h]} HUNDRED', if (r > 0) two(r)].join(' ');
  }

  String words(int n) {
    if (n == 0) return 'ZERO';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;
    if (crore > 0) parts.add('${words(crore)} CRORE');
    if (lakh > 0) parts.add('${two(lakh)} LAKH');
    if (thousand > 0) parts.add('${two(thousand)} THOUSAND');
    if (n > 0) parts.add(three(n));
    return parts.join(' ');
  }

  final rupees = paise.abs() ~/ 100, p = paise.abs() % 100;
  return '${words(rupees)} RUPEES${p > 0 ? ' AND ${two(p)} PAISE' : ''} ONLY';
}

class _Fonts {
  final pw.Font regular, semi, bold, heavy, black;
  _Fonts(this.regular, this.semi, this.bold, this.heavy, this.black);
  static _Fonts? _cache;
  static Future<_Fonts> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String n) async => pw.Font.ttf(await rootBundle.load('assets/pdf/$n.ttf'));
    return _cache = _Fonts(await f('Jakarta-Regular'), await f('Jakarta-SemiBold'), await f('Jakarta-Bold'),
        await f('Jakarta-ExtraBold'), await f('Montserrat-Black'));
  }
}

Future<Uint8List?> _logo() async {
  try {
    return (await rootBundle.load('assets/home/logo.png')).buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Builds the invoice PDF for [d] with [o] on [format] (defaults to the paper in [o]).
Future<Uint8List> buildInvoicePdf(InvoiceData d, PrintOptions o, {PdfPageFormat? format}) async {
  final fonts = await _Fonts.load();
  final logo = await _logo();
  final doc = pw.Document(
    title: '${o.title} ${d.sale['number']}',
    author: d.settings['business_name'] ?? 'GameX Pc Hub',
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  final b = _Builder(d, o, fonts, logo == null ? null : pw.MemoryImage(logo));
  final fmt = format ?? o.format;
  if (o.thermal) {
    b.receipt(doc, fmt);
  } else {
    b.a4(doc, fmt);
  }
  return doc.save();
}

class _Builder {
  final InvoiceData d;
  final PrintOptions o;
  final _Fonts f;
  final pw.ImageProvider? logo;
  _Builder(this.d, this.o, this.f, this.logo);

  late double s = 1; // scale: 1 on A4, smaller on A5

  // ---------------------------------------------------------------- palette
  PdfColor c(int argb, [int? grey]) {
    if (o.color) return PdfColor.fromInt(argb);
    final col = PdfColor.fromInt(argb);
    final l = grey ?? ((col.red * .3 + col.green * .59 + col.blue * .11) * 255).round();
    return PdfColor.fromInt(0xFF000000 | (l << 16) | (l << 8) | l);
  }

  PdfColor get navy => c(0xFF1B2163, 0x22);
  PdfColor get navy2 => c(0xFF26307A, 0x33);
  PdfColor get red => c(0xFFE0262B, 0x22);
  PdfColor get ink => c(0xFF14172E, 0x14);
  PdfColor get muted => c(0xFF6A7088, 0x66);
  PdfColor get line => c(0xFFDCE0EC, 0xCC);
  PdfColor get soft => c(0xFFF3F5FB, 0xF4);
  PdfColor get blueSoft => c(0xFFE9EEFF, 0xEE);
  PdfColor get green => c(0xFF23935A, 0x33);
  PdfColor get amber => c(0xFFEFA537, 0x88);
  PdfColor get amberSoft => c(0xFFFFF7E6, 0xF6);
  PdfColor get amberInk => c(0xFFB06A00, 0x44);

  pw.TextStyle t(double size, {pw.Font? font, PdfColor? color, double spacing = 0, double? height}) => pw.TextStyle(
        font: font ?? f.regular,
        fontSize: size * s,
        color: color ?? ink,
        letterSpacing: spacing * s,
        lineSpacing: height == null ? null : height * s,
      );

  String get shop => (d.settings['business_name'] ?? '').trim().isEmpty ? 'GameX Pc Hub' : d.settings['business_name']!.trim();
  String setting(String k, [String fallback = '']) => (d.settings[k] ?? '').trim().isEmpty ? fallback : d.settings[k]!.trim();
  String rs(int p) => Money.inr(p, decimals: true);

  // ---------------------------------------------------------------- A4 / A5 / Letter
  void a4(pw.Document doc, PdfPageFormat fmt) {
    s = (fmt.width / PdfPageFormat.a4.width).clamp(.6, 1.1).toDouble();
    final m = switch (o.margin) { 'narrow' => 14.0, 'wide' => 36.0, _ => 24.0 } * s;
    doc.addPage(pw.MultiPage(
      pageFormat: fmt.copyWith(marginLeft: m, marginRight: m, marginTop: m, marginBottom: m),
      maxPages: 20,
      footer: (ctx) => pw.Container(
        margin: pw.EdgeInsets.only(top: 6 * s),
        child: pw.Row(children: [
          pw.Text('${o.title} ${d.sale['number']} — $shop', style: t(7, color: muted)),
          pw.Spacer(),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: t(7, color: muted)),
        ]),
      ),
      build: (ctx) => [
        _header(),
        if (o.banner) _banner(),
        _titleBar(),
        _parties(),
        _itemsTable(),
        pw.SizedBox(height: 10 * s),
        _bottom(),
        pw.SizedBox(height: 10 * s),
        pw.Center(child: pw.Text('Thank you for shopping with us!', style: t(8.5, font: f.bold, color: navy))),
      ],
    ));
  }

  pw.Widget _header() {
    final name = shop;
    final xi = name.indexOf('X');
    final nameStyle = t(25, font: f.black, color: navy, spacing: -.6);
    final nameWidget = xi < 0
        ? pw.Text(name, style: nameStyle)
        : pw.RichText(
            text: pw.TextSpan(style: nameStyle, children: [
            pw.TextSpan(text: name.substring(0, xi)),
            pw.TextSpan(text: 'X', style: nameStyle.copyWith(color: red)),
            pw.TextSpan(text: name.substring(xi + 1)),
          ]));
    pw.Widget info(String label, String value, {bool boldValue = false}) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: 3 * s),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              width: 9 * s,
              height: 9 * s,
              margin: pw.EdgeInsets.only(top: 1 * s, right: 5 * s),
              decoration: pw.BoxDecoration(color: navy2, borderRadius: pw.BorderRadius.circular(2 * s)),
            ),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  if (label.isNotEmpty) pw.TextSpan(text: '$label ', style: t(7.5, color: muted)),
                  pw.TextSpan(text: value, style: t(7.5, font: boldValue ? f.bold : f.regular, color: ink)),
                ]),
              ),
            ),
          ]),
        );
    final address = setting('address', 'Kaliachak Choudhary Market, Near Registry Office, Kaliachak, Malda — PIN 732201, West Bengal');
    final phone = setting('phone');
    final upi = setting('upi_id');
    final phonepe = setting('phonepe', phone);
    final left = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Container(
          width: 50 * s,
          height: 50 * s,
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(11 * s),
            gradient: pw.LinearGradient(colors: [c(0xFF2A3BB0, 0x44), c(0xFF0D1240, 0x11)], begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
          ),
          child: logo != null
              ? pw.ClipRRect(horizontalRadius: 11 * s, verticalRadius: 11 * s, child: pw.Image(logo!, fit: pw.BoxFit.cover))
              : pw.Center(child: pw.Text('GX', style: t(18, font: f.black, color: PdfColors.white))),
        ),
        pw.SizedBox(width: 12 * s),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            nameWidget,
            pw.SizedBox(height: 3 * s),
            pw.Text(setting('tagline', 'COMPUTER · GAMING · ACCESSORIES · MOBILES').toUpperCase(),
                style: t(6.6, font: f.semi, color: muted, spacing: 2.2)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 10 * s),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 11,
          child: pw.Column(children: [
            info('', address),
            if (upi.isNotEmpty) info('UPI:', upi, boldValue: true),
          ]),
        ),
        pw.SizedBox(width: 10 * s),
        pw.Expanded(
          flex: 8,
          child: pw.Column(children: [
            if (phone.isNotEmpty) info('', phone, boldValue: true),
            if (phonepe.isNotEmpty) info('PhonePe:', phonepe, boldValue: true),
          ]),
        ),
      ]),
    ]);
    if (!o.brands) return pw.Padding(padding: pw.EdgeInsets.only(bottom: 8 * s), child: left);
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 8 * s),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(flex: 66, child: left),
        pw.Container(width: .8, height: 104 * s, color: line, margin: pw.EdgeInsets.symmetric(horizontal: 10 * s)),
        pw.Expanded(flex: 34, child: _brands()),
      ]),
    );
  }

  pw.Widget _brands() {
    const brands = [
      ('APPLE', 0xFF000000, 0xFFFFFFFF),
      ('SAMSUNG', 0xFF1428A0, 0xFFFFFFFF),
      ('Mi', 0xFFFF6900, 0xFFFFFFFF),
      ('1+', 0xFFEB0029, 0xFFFFFFFF),
      ('G', 0xFF4285F4, 0xFFFFFFFF),
      ('OPPO', 0xFF1A1A1A, 0xFFB6F25C),
      ('vivo', 0xFF415FFF, 0xFFFFFFFF),
      ('NOKIA', 0xFF124191, 0xFFFFFFFF),
      ('ASUS', 0xFF0A3E8A, 0xFFFFFFFF),
      ('HONOR', 0xFFC8102E, 0xFFFFFFFF),
      ('realme', 0xFFF5C518, 0xFF1A1A1A),
      ('SONY', 0xFF000000, 0xFFFFFFFF),
    ];
    pw.Widget tile((String, int, int) b) => pw.Expanded(
          child: pw.Container(
            height: 19 * s,
            margin: pw.EdgeInsets.all(1.6 * s),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: c(b.$2), borderRadius: pw.BorderRadius.circular(3.5 * s)),
            child: pw.Text(b.$1, style: t(b.$1.length > 5 ? 5.6 : 6.6, font: f.heavy, color: c(b.$3))),
          ),
        );
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Center(child: pw.Text('AUTHORISED DEALER', style: t(6.4, font: f.bold, color: muted, spacing: 1.8))),
      pw.Container(height: .8, color: line, margin: pw.EdgeInsets.symmetric(vertical: 4 * s)),
      for (var r = 0; r < 3; r++) pw.Row(children: [for (var i = 0; i < 4; i++) tile(brands[r * 4 + i])]),
      pw.Container(
        margin: pw.EdgeInsets.only(top: 4 * s),
        padding: pw.EdgeInsets.symmetric(vertical: 3.5 * s),
        decoration: pw.BoxDecoration(color: blueSoft, borderRadius: pw.BorderRadius.circular(3 * s)),
        alignment: pw.Alignment.center,
        child: pw.Text('ALL BRANDS AVAILABLE', style: t(6.4, font: f.heavy, color: navy, spacing: 1.4)),
      ),
    ]);
  }

  pw.Widget _banner() => pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: 6 * s, horizontal: 10 * s),
        decoration: pw.BoxDecoration(gradient: pw.LinearGradient(colors: [navy, c(0xFF3F5BEA, 0x55)])),
        alignment: pw.Alignment.center,
        child: pw.Text('•   ${setting('invoice_banner', defaultBanner)}   •',
            textAlign: pw.TextAlign.center, style: t(7.2, font: f.semi, color: PdfColors.white, spacing: .3)),
      );

  pw.Widget _titleBar() => pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: 8 * s, horizontal: 10 * s),
        decoration: pw.BoxDecoration(color: soft, border: pw.Border(bottom: pw.BorderSide(color: navy, width: 2 * s))),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(text: 'GSTIN :  ', style: t(8, color: muted)),
                  pw.TextSpan(text: setting('gstin', '—'), style: t(9, font: f.heavy, color: ink)),
                ]),
              ),
              pw.SizedBox(height: 2 * s),
              pw.Text('State: ${setting('state', 'West Bengal')}  |  Pin: ${setting('pin', '732201')}', style: t(6.8, color: muted)),
            ]),
          ),
          pw.Text(o.title.split('').join(' ').replaceAll('   ', '      '), style: t(19, font: f.black, color: navy, spacing: 1)),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: navy, width: 1 * s), borderRadius: pw.BorderRadius.circular(4 * s)),
                child: pw.Text(o.copy, style: t(6.6, font: f.heavy, color: navy, spacing: .8)),
              ),
            ),
          ),
        ]),
      );

  String get _paymentMode {
    final names = d.payments.map((p) => p.$1).toList();
    if (names.isEmpty) return 'Credit';
    String short(String n) => n.toLowerCase().contains('cash')
        ? 'Cash'
        : n.toLowerCase().contains('upi')
            ? 'UPI'
            : n;
    return names.map(short).toSet().join(' + ');
  }

  pw.Widget _parties() {
    final sale = d.sale;
    final total = asInt(sale['total']), paid = asInt(sale['paid']);
    final status = paid >= total ? 'Fully Paid' : paid > 0 ? 'Partly Paid' : 'Unpaid';
    final statusColor = paid >= total ? green : paid > 0 ? amberInk : red;
    pw.Widget row(String k, String v, {pw.Font? font, PdfColor? color, double w = 64}) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 2.6 * s),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: w * s, child: pw.Text(k, style: t(7.4, font: f.heavy, color: navy))),
            pw.Expanded(child: pw.Text(v, style: t(7.8, font: font ?? f.regular, color: color ?? ink))),
          ]),
        );
    final gstin = '${sale['gstin'] ?? ''}'.trim();
    final state = setting('state', 'West Bengal');
    final stateCode = gstin.length >= 2 ? gstin.substring(0, 2) : setting('state_code', '19');
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .8))),
      padding: pw.EdgeInsets.symmetric(vertical: 8 * s),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 66,
          child: pw.Padding(
            padding: pw.EdgeInsets.only(left: 10 * s, right: 10 * s),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
                decoration: pw.BoxDecoration(
                  color: blueSoft,
                  border: pw.Border.all(color: c(0xFFC5CFF5, 0xDD), width: .8),
                  borderRadius: pw.BorderRadius.circular(3 * s),
                ),
                child: pw.Text('CUSTOMER DETAIL', style: t(7, font: f.heavy, color: navy2, spacing: 1)),
              ),
              pw.SizedBox(height: 6 * s),
              row('NAME', (sale['customer'] as String?) ?? 'Walk-in Customer'),
              row('PHONE', '${sale['phone'] ?? '—'}'),
              if ('${sale['address'] ?? ''}'.trim().isNotEmpty) row('ADDRESS', '${sale['address']}'),
              row('GSTIN', gstin.isEmpty ? '—' : gstin),
              row('PLACE OF SUPPLY', '$state ($stateCode)'),
            ]),
          ),
        ),
        pw.Container(width: .8, height: 92 * s, color: line),
        pw.Expanded(
          flex: 34,
          child: pw.Padding(
            padding: pw.EdgeInsets.only(left: 12 * s, top: 2 * s),
            child: pw.Column(children: [
              row('INVOICE NO.', '${sale['number']}', font: f.heavy, w: 66),
              row('INVOICE DATE', prettyDate('${sale['date']}'), font: f.heavy, w: 66),
              row('PAYMENT MODE', _paymentMode, font: f.heavy, w: 66),
              row('STATUS', status, font: f.heavy, color: statusColor, w: 66),
            ]),
          ),
        ),
      ]),
    );
  }

  bool get _cgst => o.tax == 'cgst';

  pw.Widget _itemsTable() {
    final sale = d.sale;
    final subtotal = asInt(sale['subtotal']), discount = asInt(sale['discount']);
    final white = PdfColors.white;
    pw.Widget h(String text, {pw.Alignment a = pw.Alignment.center}) => pw.Container(
          alignment: a,
          padding: pw.EdgeInsets.symmetric(horizontal: 4 * s, vertical: 7 * s),
          child: pw.Text(text, textAlign: pw.TextAlign.center, style: t(6.8, font: f.heavy, color: white)),
        );
    pw.Widget cell(String text, {pw.Alignment a = pw.Alignment.topRight, pw.Font? font, PdfColor? color, double size = 7.6}) =>
        pw.Container(
          alignment: a,
          padding: pw.EdgeInsets.symmetric(horizontal: 4 * s, vertical: 6 * s),
          child: pw.Text(text, style: t(size, font: font, color: color ?? ink)),
        );
    pw.Widget tag(String k, String v, PdfColor kc, PdfColor bg) => pw.Padding(
          padding: pw.EdgeInsets.only(top: 3 * s),
          child: pw.Row(children: [
            pw.Container(
              padding: pw.EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1.2 * s),
              decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(2 * s)),
              child: pw.Text(k, style: t(5.8, font: f.heavy, color: kc)),
            ),
            pw.SizedBox(width: 5 * s),
            pw.Text(v, style: t(6.8, color: muted)),
          ]),
        );

    final widths = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(22 * s),
      1: const pw.FlexColumnWidth(),
      if (o.hsn) 2: pw.FixedColumnWidth(42 * s),
    };
    var col = o.hsn ? 3 : 2;
    for (final w in [30.0, 54.0, 56.0, if (_cgst) ...[28.0, 38.0, 38.0] else ...[26.0, 38.0], 58.0]) {
      widths[col++] = pw.FixedColumnWidth(w * s);
    }

    var totalTaxable = 0, totalTax = 0, totalQty = 0, totalAll = 0;
    final rows = <pw.TableRow>[];
    for (var i = 0; i < d.items.length; i++) {
      final it = d.items[i];
      final amount = asInt(it['amount']);
      final share = subtotal == 0 ? 0 : (discount * amount / subtotal).round();
      final taxable = amount - share;
      final tax = asInt(it['tax']);
      final qty = asInt(it['qty']);
      final gstPct = asInt(it['gst_bp']) / 100;
      totalTaxable += taxable;
      totalTax += tax;
      totalQty += qty;
      totalAll += taxable + tax;
      final serial = '${it['serial'] ?? ''}'.trim();
      final hsn = '${it['hsn'] ?? ''}'.trim();
      String pct(double p) => p == p.roundToDouble() ? p.toStringAsFixed(2) : p.toStringAsFixed(2);
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .6))),
        children: [
          cell('${i + 1}', a: pw.Alignment.topCenter, color: muted),
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: 6 * s, vertical: 6 * s),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('${it['name']}'.toUpperCase(), style: t(8, font: f.heavy, color: ink)),
              if (o.imei && serial.isNotEmpty) tag('IMEI', serial, c(0xFF2440C8, 0x33), blueSoft),
              if (o.hsn && hsn.isNotEmpty) tag('HSN', hsn, green, c(0xFFE6F6EC, 0xEE)),
              if ('${it['opp_id'] ?? ''}'.trim().isNotEmpty)
                tag('Opportunity ID', '${it['opp_id']}'.trim(), green, c(0xFFE6F6EC, 0xEE)),
            ]),
          ),
          if (o.hsn) cell(hsn.isEmpty ? '—' : hsn, a: pw.Alignment.topCenter, color: muted, size: 7),
          pw.Container(
            alignment: pw.Alignment.topCenter,
            padding: pw.EdgeInsets.symmetric(vertical: 6 * s),
            child: pw.Column(children: [
              pw.Text('$qty', style: t(7.8, font: f.bold)),
              pw.Text('pcs', style: t(6, color: muted)),
            ]),
          ),
          cell(rs(asInt(it['rate']))),
          cell(rs(taxable)),
          if (_cgst) ...[
            cell(pct(gstPct)),
            cell(rs(tax ~/ 2)),
            cell(rs(tax - tax ~/ 2)),
          ] else ...[
            cell(pct(gstPct)),
            cell(rs(tax)),
          ],
          cell(rs(taxable + tax), font: f.heavy, size: 8),
        ],
      ));
    }

    final header1 = pw.TableRow(
      decoration: pw.BoxDecoration(color: navy),
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        h('SR.\nNO.'),
        h('NAME OF PRODUCT / SERVICE'),
        if (o.hsn) h('HSN /\nSAC'),
        h('QTY'),
        h('RATE (₹)'),
        h('TAXABLE\nVALUE (₹)'),
        if (_cgst) ...[h('GST\n%'), h('CGST\n(₹)'), h('SGST\n(₹)')] else ...[h('IGST\n%'), h('IGST\nAmt (₹)')],
        h('TOTAL (₹)'),
      ],
    );
    final footer = pw.TableRow(
      decoration: pw.BoxDecoration(color: soft, border: pw.Border(top: pw.BorderSide(color: navy, width: 1.6 * s))),
      children: [
        pw.SizedBox(),
        cell('TOTAL', font: f.heavy, a: pw.Alignment.centerRight),
        if (o.hsn) pw.SizedBox(),
        cell('$totalQty', font: f.heavy, a: pw.Alignment.center),
        pw.SizedBox(),
        cell(rs(totalTaxable), font: f.heavy),
        if (_cgst) ...[pw.SizedBox(), cell(rs(totalTax ~/ 2), font: f.heavy), cell(rs(totalTax - totalTax ~/ 2), font: f.heavy)] else ...[
          pw.SizedBox(),
          cell(rs(totalTax), font: f.heavy),
        ],
        cell(rs(totalAll), font: f.heavy, size: 8.2),
      ],
    );
    return pw.Table(columnWidths: widths, children: [header1, ...rows, footer]);
  }

  pw.Widget _boxHeader(String title, {PdfColor? color}) => pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: 5 * s),
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: color ?? navy,
          borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(4 * s), topRight: pw.Radius.circular(4 * s)),
        ),
        child: pw.Text(title, style: t(7, font: f.heavy, color: PdfColors.white, spacing: 1.4)),
      );

  pw.BoxDecoration _box({PdfColor? border}) => pw.BoxDecoration(
        border: pw.Border.all(color: border ?? line, width: .8),
        borderRadius: pw.BorderRadius.circular(4 * s),
      );

  pw.Widget _bottom() {
    final sale = d.sale;
    final total = asInt(sale['total']), paid = asInt(sale['paid']), discount = asInt(sale['discount']);
    final tax = asInt(sale['tax']);
    final taxable = asInt(sale['subtotal']) - discount;
    final due = total - paid;
    final upi = setting('upi_id');
    final terms = setting('terms', defaultTerms).split('\n').where((l) => l.trim().isNotEmpty).toList();

    pw.Widget kv(String k, String v, {bool shade = false}) => pw.Container(
          color: shade ? soft : null,
          padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4.2 * s),
          child: pw.Row(children: [
            pw.Text(k, style: t(7.4, color: muted)),
            pw.Spacer(),
            pw.Text(v, style: t(7.4, font: f.heavy)),
          ]),
        );

    final left = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        decoration: _box(),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _boxHeader('TOTAL AMOUNT IN WORDS'),
          pw.Container(
            color: blueSoft,
            padding: pw.EdgeInsets.symmetric(vertical: 7 * s, horizontal: 8 * s),
            alignment: pw.Alignment.center,
            child: pw.Text(amountInWords(total), textAlign: pw.TextAlign.center, style: t(8, font: f.heavy)),
          ),
        ]),
      ),
      if (o.bank) ...[
        pw.SizedBox(height: 8 * s),
        pw.Container(
          decoration: _box(),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            _boxHeader('BANK & PAYMENT DETAILS'),
            kv('Bank Name', setting('bank_name', '—'), shade: true),
            kv('Branch', setting('bank_branch', 'Kaliachak')),
            kv('Acc. Number', setting('bank_acc', '—'), shade: true),
            kv('IFSC Code', setting('bank_ifsc', '—')),
            if (upi.isNotEmpty) kv('UPI ID', upi, shade: true),
            if (setting('phonepe', setting('phone')).isNotEmpty) kv('PhonePe', setting('phonepe', setting('phone'))),
          ]),
        ),
      ],
      if (o.terms) ...[
        pw.SizedBox(height: 8 * s),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: amberSoft,
            border: pw.Border.all(color: amber, width: .8),
            borderRadius: pw.BorderRadius.circular(4 * s),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            _boxHeader('TERMS & CONDITIONS', color: amber),
            pw.Padding(
              padding: pw.EdgeInsets.fromLTRB(10 * s, 6 * s, 10 * s, 6 * s),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                for (final l in terms)
                  pw.Padding(
                    padding: pw.EdgeInsets.symmetric(vertical: 1.6 * s),
                    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('•  ', style: t(7.2, font: f.heavy, color: amber)),
                      pw.Expanded(child: pw.Text(l.trim(), style: t(7, color: amberInk))),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ],
    ]);

    final summary = pw.Container(
      decoration: _box(border: c(0xFFC5CFF5, 0xCC)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _boxHeader('SUMMARY'),
        pw.Container(
          color: blueSoft,
          padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 5 * s),
          child: pw.Column(children: [
            _sumRow('TAXABLE AMOUNT', '₹${rs(taxable)}', heavyKey: true),
            if (discount > 0) _sumRow('DISCOUNT', '− ₹${rs(discount)}'),
            if (tax > 0 && _cgst) ...[
              _sumRow('CGST', '₹${rs(tax ~/ 2)}'),
              _sumRow('SGST', '₹${rs(tax - tax ~/ 2)}'),
            ],
            if (tax > 0 && !_cgst) _sumRow('IGST', '₹${rs(tax)}'),
          ]),
        ),
        pw.Container(
          color: navy,
          padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 8 * s),
          child: pw.Row(children: [
            pw.Text('Total Amount After Tax', style: t(8, font: f.heavy, color: PdfColors.white)),
            pw.Spacer(),
            pw.Text('₹${rs(total)}', style: t(12, font: f.black, color: PdfColors.white)),
          ]),
        ),
        pw.Padding(
          padding: pw.EdgeInsets.only(right: 8 * s, top: 2 * s),
          child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('(E & O.E.)', style: t(5.8, color: muted))),
        ),
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
          child: pw.Column(children: [
            for (final p in d.payments) _sumRow('(+) Paid — ${p.$1}', '₹${rs(p.$2)}', color: green),
            if (due > 0) _sumRow('Balance Due', '₹${rs(due)}', color: red),
          ]),
        ),
        if (o.signature) ...[
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
            child: pw.Text('Certified that the particulars given above are true and correct.',
                textAlign: pw.TextAlign.center, style: t(6.2, color: muted)),
          ),
          pw.SizedBox(height: 18 * s),
          pw.Center(child: pw.Container(width: 100 * s, height: .6, color: muted)),
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 3 * s, bottom: 7 * s),
            child: pw.Center(child: pw.Text('For $shop', style: t(8, font: f.heavy, color: navy))),
          ),
        ],
      ]),
    );

    final payAmount = due > 0 ? due : total;
    final qr = (!o.qr || upi.isEmpty)
        ? null
        : pw.Container(
            margin: pw.EdgeInsets.only(top: 8 * s),
            decoration: _box(border: c(0xFFC5CFF5, 0xCC)),
            child: pw.Column(children: [
              _boxHeader('PAY USING UPI'),
              pw.SizedBox(height: 7 * s),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: 'upi://pay?pa=$upi&pn=${Uri.encodeComponent(shop)}&am=${Money.edit(payAmount)}&cu=INR'
                    '&tn=${Uri.encodeComponent('${d.sale['number']}')}',
                width: 78 * s,
                height: 78 * s,
                color: c(0xFF0D1240, 0x00),
              ),
              pw.SizedBox(height: 4 * s),
              pw.Text(upi, style: t(7, color: muted)),
              pw.Text('₹${rs(payAmount)}', style: t(10, font: f.black, color: navy)),
              pw.SizedBox(height: 6 * s),
            ]),
          );

    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(flex: 64, child: left),
      pw.SizedBox(width: 12 * s),
      pw.Expanded(flex: 36, child: pw.Column(children: [summary, if (qr != null) qr])),
    ]);
  }

  pw.Widget _sumRow(String k, String v, {bool heavyKey = false, PdfColor? color}) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 2 * s),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: t(7.2, font: heavyKey ? f.heavy : f.semi, color: color ?? navy2))),
          pw.Text(v, style: t(7.6, font: f.heavy, color: color ?? ink)),
        ]),
      );

  // ---------------------------------------------------------------- thermal receipt
  void receipt(pw.Document doc, PdfPageFormat fmt) {
    final narrow = o.paper == '58mm';
    s = narrow ? .82 : 1;
    final sale = d.sale;
    final total = asInt(sale['total']), paid = asInt(sale['paid']);
    final discount = asInt(sale['discount']), tax = asInt(sale['tax']);
    final due = total - paid;
    final upi = setting('upi_id');
    final black = PdfColors.black;
    pw.TextStyle r(double size, {pw.Font? font}) => pw.TextStyle(font: font ?? f.regular, fontSize: size * s, color: black);
    pw.Widget dash() => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 4 * s),
          child: pw.Row(children: [
            for (var i = 0; i < (narrow ? 26 : 38); i++)
              pw.Expanded(child: pw.Container(height: .7, margin: const pw.EdgeInsets.symmetric(horizontal: .8), color: black)),
          ]),
        );
    pw.Widget line2(String a, String b, {pw.Font? font, double size = 8}) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 1 * s),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Text(a, style: r(size, font: font))),
            pw.Text(b, style: r(size, font: font)),
          ]),
        );
    doc.addPage(pw.Page(
      pageFormat: fmt.copyWith(marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 12),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Center(child: pw.Text(shop, style: r(14, font: f.black))),
        pw.Center(
          child: pw.Text(setting('address', ''), textAlign: pw.TextAlign.center, style: r(7)),
        ),
        if (setting('phone').isNotEmpty) pw.Center(child: pw.Text('Ph: ${setting('phone')}', style: r(7.5, font: f.bold))),
        if (setting('gstin').isNotEmpty) pw.Center(child: pw.Text('GSTIN: ${setting('gstin')}', style: r(7.5, font: f.bold))),
        dash(),
        pw.Center(child: pw.Text(o.title, style: r(10, font: f.heavy))),
        line2('Bill: ${sale['number']}', prettyDate('${sale['date']}'), font: f.bold),
        line2('Customer: ${sale['customer'] ?? 'Walk-in'}', '${sale['phone'] ?? ''}'),
        dash(),
        line2('Item', 'Amount', font: f.heavy),
        dash(),
        for (final it in d.items) ...[
          pw.Text('${it['name']}', style: r(8, font: f.bold)),
          line2('  ${it['qty']} × ${rs(asInt(it['rate']))}', rs(asInt(it['amount']))),
          if (o.imei && '${it['serial'] ?? ''}'.trim().isNotEmpty) pw.Text('  IMEI: ${it['serial']}', style: r(7)),
          if ('${it['opp_id'] ?? ''}'.trim().isNotEmpty) pw.Text('  Opportunity ID: ${it['opp_id']}', style: r(7)),
        ],
        dash(),
        line2('Subtotal', rs(asInt(sale['subtotal']))),
        if (discount > 0) line2('Discount', '- ${rs(discount)}'),
        if (tax > 0) line2('GST', rs(tax)),
        line2('TOTAL', '₹${rs(total)}', font: f.black, size: 11),
        for (final p in d.payments) line2('Paid (${p.$1})', rs(p.$2)),
        if (due > 0) line2('BALANCE DUE', '₹${rs(due)}', font: f.heavy, size: 9),
        dash(),
        pw.Center(child: pw.Text(amountInWords(total), textAlign: pw.TextAlign.center, style: r(6.6, font: f.semi))),
        if (o.qr && upi.isNotEmpty && due > 0) ...[
          pw.SizedBox(height: 6 * s),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: 'upi://pay?pa=$upi&pn=${Uri.encodeComponent(shop)}&am=${Money.edit(due)}&cu=INR',
              width: 90 * s,
              height: 90 * s,
            ),
          ),
          pw.Center(child: pw.Text('Scan to pay $upi', style: r(7))),
        ],
        pw.SizedBox(height: 6 * s),
        pw.Center(child: pw.Text('Thank you! Visit again', style: r(8.5, font: f.heavy))),
      ]),
    ));
  }
}
