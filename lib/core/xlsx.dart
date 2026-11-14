import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One cell value: text, a whole number, or money (paise → rupees with
/// 2 decimals and a ₹ format in Excel).
class Money2 {
  final int paise;
  const Money2(this.paise);
}

class Sheet {
  final String name;
  final List<String> header;
  final List<List<Object?>> rows = [];
  final List<double> widths;
  /// Rows (0-based, after the header) shown in bold — totals.
  final Set<int> boldRows = {};
  Sheet(this.name, this.header, {List<double>? widths}) : widths = widths ?? [for (final _ in header) 16];

  void add(List<Object?> row, {bool bold = false}) {
    if (bold) boldRows.add(rows.length);
    rows.add(row);
  }
}

/// A tiny, dependency-free .xlsx writer: real Excel workbooks with several
/// sheets, a bold coloured header row, frozen header, column widths and
/// money cells as numbers (so Excel can sum them).
class Xlsx {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String col(int i) {
    var n = i + 1, s = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _sheetName(String n) {
    final s = n.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
    return s.length > 31 ? s.substring(0, 31) : (s.isEmpty ? 'Sheet' : s);
  }

  // styles: 0 normal · 1 header · 2 money · 3 bold text · 4 bold money · 5 integer
  static String _cell(String ref, Object? v, {bool bold = false}) {
    if (v == null) return '';
    if (v is Money2) return '<c r="$ref" s="${bold ? 4 : 2}"><v>${(v.paise / 100).toStringAsFixed(2)}</v></c>';
    if (v is int) return '<c r="$ref" s="${bold ? 4 : 5}"><v>$v</v></c>';
    if (v is double) return '<c r="$ref" s="${bold ? 4 : 2}"><v>$v</v></c>';
    final t = _esc('$v');
    return '<c r="$ref" t="inlineStr"${bold ? ' s="3"' : ''}><is><t xml:space="preserve">$t</t></is></c>';
  }

  static String _sheetXml(Sheet s) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
      ..write('<cols>');
    for (var i = 0; i < s.header.length; i++) {
      final w = i < s.widths.length ? s.widths[i] : 16;
      b.write('<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>');
    }
    b.write('</cols><sheetData>');
    b.write('<row r="1" ht="22" customHeight="1">');
    for (var i = 0; i < s.header.length; i++) {
      b.write('<c r="${col(i)}1" t="inlineStr" s="1"><is><t>${_esc(s.header[i])}</t></is></c>');
    }
    b.write('</row>');
    for (var r = 0; r < s.rows.length; r++) {
      final n = r + 2;
      final bold = s.boldRows.contains(r);
      b.write('<row r="$n">');
      final row = s.rows[r];
      for (var i = 0; i < row.length; i++) {
        b.write(_cell('${col(i)}$n', row[i], bold: bold));
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (s.rows.isNotEmpty) b.write('<autoFilter ref="A1:${col(s.header.length - 1)}${s.rows.length + 1}"/>');
    b.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/></worksheet>');
    return b.toString();
  }

  static const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;₹&quot;#,##0.00"/></numFmts>'
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF4318D2"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left/><right/><top/><bottom style="thin"><color rgb="FFD9DCEB"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="6">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>'
      '<xf numFmtId="164" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  static Uint8List build(List<Sheet> sheets, {String title = 'Hisab AI'}) {
    final a = Archive();
    void put(String name, String text) {
      final bytes = utf8.encode(text);
      a.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final names = <String>{};
    final sheetNames = <String>[];
    for (final s in sheets) {
      var n = _sheetName(s.name);
      var k = 2;
      while (names.contains(n.toLowerCase())) {
        n = '${_sheetName(s.name).substring(0, _sheetName(s.name).length.clamp(0, 27))} ($k)';
        k++;
      }
      names.add(n.toLowerCase());
      sheetNames.add(n);
    }

    put('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    put('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '</Relationships>');
    put('docProps/core.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_esc(title)}</dc:title><dc:creator>Hisab AI</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${DateTime.now().toUtc().toIso8601String().split('.').first}Z</dcterms:created>'
        '</cp:coreProperties>');
    put('xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheetNames[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>');
    put('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    put('xl/styles.xml', _styles);
    for (var i = 0; i < sheets.length; i++) {
      put('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
    }
    final zip = ZipEncoder().encode(a);
    if (zip == null) throw StateError('Could not create the Excel file');
    return Uint8List.fromList(zip);
  }
}
