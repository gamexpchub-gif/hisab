import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/money.dart';
import '../core/native_files.dart';
import '../core/xlsx.dart' as xl;
import '../ui/charts.dart';
import '../ui/widgets.dart';
import 'formula.dart';
import 'templates.dart';
import 'workbook.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _grid = Color(0xFFE3E6F0);
const _green = Color(0xFF107C41);
const _sel = Color(0xFF1A7F4B);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c);

const _rowH = 34.0, _headH = 28.0, _numW = 44.0;

const _palette = [
  0xFF0A0E26, 0xFFDC4545, 0xFFE08A00, 0xFF16A36A, 0xFF107C41, 0xFF2F6BFF, 0xFF5B2EE0, 0xFFDB2777, 0xFF64748B, 0xFFFFFFFF,
];
const _fills = [
  0xFFFFFFFF, 0xFFFDECEC, 0xFFFFF4DC, 0xFFE9FBF2, 0xFFE6F4EA, 0xFFEAF2FF, 0xFFF1ECFF, 0xFFFDE7F3, 0xFFF1F2F9, 0xFF0F1240,
];

/// Text shown for a computed value with the cell's number format.
String showValue(Object? v, Cell? cell) {
  if (v == null) return '';
  if (v is CellError) return v.code;
  if (v is bool) return v ? 'TRUE' : 'FALSE';
  if (v is num) {
    final d = v.toDouble();
    switch (cell?.fmt) {
      case 'inr':
        return sheetInr(d);
      case 'pct':
        return '${(d * 100).toStringAsFixed((d * 100) == (d * 100).roundToDouble() ? 0 : 1)}%';
      case 'int':
        return _group(d.round().toString());
      case 'date':
        final dt = DateTime(1899, 12, 30).add(Duration(days: d.floor()));
        return prettyDate(ymd(dt));
      case 'number':
        return _group(d.toStringAsFixed(2));
      case 'text':
        return '$d';
    }
    if (d == d.roundToDouble() && d.abs() < 1e15) return _group(d.toInt().toString());
    final s = d.toStringAsFixed(d.abs() < 1 ? 4 : 2).replaceFirst(RegExp(r'\.?0+$'), '');
    return _group(s);
  }
  return '$v';
}

/// Indian digit grouping: 12,34,567.89
String _group(String s) {
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  var x = parts[0];
  if (x.length > 3) {
    final last = x.substring(x.length - 3);
    var rest = x.substring(0, x.length - 3);
    final out = <String>[];
    while (rest.length > 2) {
      out.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) out.insert(0, rest);
    x = '${out.join(',')},$last';
  }
  return '${neg ? '-' : ''}$x${parts.length > 1 ? '.${parts[1]}' : ''}';
}

class SheetEditor extends StatefulWidget {
  final Workbook book;
  const SheetEditor({super.key, required this.book});
  @override
  State<SheetEditor> createState() => _SheetEditorState();
}

class _SheetEditorState extends State<SheetEditor> {
  late Workbook wb = widget.book;
  int tab = 0;
  int r = 0, c = 0; // active cell
  int? ar, ac; // range anchor
  bool rangeMode = false;
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final hBody = ScrollController(), hHead = ScrollController(), vBody = ScrollController(), vHead = ScrollController();
  final undo = <String>[], redo = <String>[];
  Timer? _saveTimer;
  bool dirty = false;
  String? clip; // copied cells as JSON
  int clipW = 1, clipH = 1, clipR = 0, clipC = 0;

  GridSheet get sh => wb.sheets[tab];

  @override
  void initState() {
    super.initState();
    hBody.addListener(() {
      if (hHead.hasClients && hHead.offset != hBody.offset) hHead.jumpTo(hBody.offset);
    });
    vBody.addListener(() {
      if (vHead.hasClients && vHead.offset != vBody.offset) vHead.jumpTo(vBody.offset);
    });
    _loadInput();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (dirty) SheetStore.save(wb);
    for (final x in [hBody, hHead, vBody, vHead, _frozenH]) {
      x.dispose();
    }
    input.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- state
  void _loadInput() => input.text = sh.input(r, c);

  void _snapshot() {
    undo.add(jsonEncode(sh.toJson()));
    if (undo.length > 60) undo.removeAt(0);
    redo.clear();
  }

  void _changed() {
    sh.invalidate();
    dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      SheetStore.save(wb);
      dirty = false;
    });
    setState(() {});
  }

  void _restore(String json) {
    wb.sheets[tab] = GridSheet.from(jsonDecode(json) as Map<String, dynamic>);
    _loadInput();
    _changed();
  }

  void _undo() {
    if (undo.isEmpty) return;
    redo.add(jsonEncode(sh.toJson()));
    _restore(undo.removeLast());
  }

  void _redo() {
    if (redo.isEmpty) return;
    undo.add(jsonEncode(sh.toJson()));
    _restore(redo.removeLast());
  }

  (int, int, int, int) get range {
    if (ar == null || ac == null) return (r, c, r, c);
    return (math.min(r, ar!), math.min(c, ac!), math.max(r, ar!), math.max(c, ac!));
  }

  bool get hasRange => ar != null && (ar != r || ac != c);

  String get rangeName {
    final g = range;
    return hasRange ? '${cellName(g.$1, g.$2)}:${cellName(g.$3, g.$4)}' : cellName(r, c);
  }

  void _commit() {
    final t = input.text;
    if (t == sh.input(r, c)) return;
    _snapshot();
    sh.put(r, c, t);
    _changed();
  }

  void _select(int row, int col, {bool extend = false}) {
    // while typing a formula, tapping a cell inserts its reference
    if (inputFocus.hasFocus && input.text.startsWith('=') && !(row == r && col == c)) {
      final sel = input.selection;
      final pos = sel.isValid ? sel.baseOffset : input.text.length;
      final ref = cellName(row, col);
      input.text = input.text.substring(0, pos) + ref + input.text.substring(pos);
      input.selection = TextSelection.collapsed(offset: pos + ref.length);
      HapticFeedback.selectionClick();
      return;
    }
    _commit();
    setState(() {
      if (extend || rangeMode) {
        ar ??= r;
        ac ??= c;
      } else {
        ar = null;
        ac = null;
      }
      r = row;
      c = col;
      _loadInput();
    });
  }

  void _move(int dr, int dc) => _select((r + dr).clamp(0, sh.rows - 1), (c + dc).clamp(0, sh.cols - 1));

  // apply to every cell in the selection
  void _each(void Function(Cell cell) f) {
    _snapshot();
    final g = range;
    for (var i = g.$1; i <= g.$3; i++) {
      for (var j = g.$2; j <= g.$4; j++) {
        f(sh.style(i, j));
      }
    }
    _changed();
  }

  // ---------------------------------------------------------------- actions
  void _autoSum() {
    // sum the numbers above (or to the left) of the active cell
    var top = r - 1;
    while (top >= 0 && sh.value(top, c) is num) {
      top--;
    }
    if (top < r - 1) {
      input.text = '=SUM(${cellName(top + 1, c)}:${cellName(r - 1, c)})';
    } else {
      var left = c - 1;
      while (left >= 0 && sh.value(r, left) is num) {
        left--;
      }
      input.text = left < c - 1 ? '=SUM(${cellName(r, left + 1)}:${cellName(r, c - 1)})' : '=SUM()';
    }
    _commit();
  }

  void _copy({bool cut = false}) {
    final g = range;
    final cells = <String, Object?>{};
    for (var i = g.$1; i <= g.$3; i++) {
      for (var j = g.$2; j <= g.$4; j++) {
        final cell = sh.at(i, j);
        if (cell != null) cells['${i - g.$1}:${j - g.$2}'] = cell.toJson();
      }
    }
    clip = jsonEncode(cells);
    clipR = g.$1;
    clipC = g.$2;
    clipH = g.$3 - g.$1 + 1;
    clipW = g.$4 - g.$2 + 1;
    final text = [
      for (var i = g.$1; i <= g.$3; i++) [for (var j = g.$2; j <= g.$4; j++) showValue(sh.value(i, j), sh.at(i, j))].join('\t'),
    ].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    if (cut) {
      _snapshot();
      for (var i = g.$1; i <= g.$3; i++) {
        for (var j = g.$2; j <= g.$4; j++) {
          sh.cells.remove(GridSheet.key(i, j));
        }
      }
      _loadInput();
      _changed();
    }
    toast(context, cut ? 'Cut $rangeName' : 'Copied $rangeName');
  }

  void _paste() {
    if (clip == null) return;
    _snapshot();
    final m = jsonDecode(clip!) as Map<String, dynamic>;
    m.forEach((k, v) {
      final parts = k.split(':');
      final dr = int.parse(parts[0]), dc = int.parse(parts[1]);
      final cell = Cell.from(v as Map<String, dynamic>);
      if (cell.isFormula) cell.input = GridSheet.offsetFormula(cell.input, r - clipR, c - clipC);
      sh.cells[GridSheet.key(r + dr, c + dc)] = cell;
      if (r + dr >= sh.rows - 2) sh.rows = r + dr + 10;
      if (c + dc >= sh.cols - 1) sh.cols = c + dc + 3;
    });
    _loadInput();
    _changed();
  }

  /// Copies the top cell of the selection down (formulas shift like Excel).
  void _fillDown() {
    final g = range;
    if (g.$3 == g.$1) return;
    _snapshot();
    for (var j = g.$2; j <= g.$4; j++) {
      final src = sh.at(g.$1, j);
      if (src == null) continue;
      for (var i = g.$1 + 1; i <= g.$3; i++) {
        final cell = src.copy();
        if (cell.isFormula) cell.input = GridSheet.offsetFormula(src.input, i - g.$1, 0);
        sh.cells[GridSheet.key(i, j)] = cell;
      }
    }
    _changed();
  }

  void _clear() {
    _snapshot();
    final g = range;
    for (var i = g.$1; i <= g.$3; i++) {
      for (var j = g.$2; j <= g.$4; j++) {
        sh.cells.remove(GridSheet.key(i, j));
      }
    }
    _loadInput();
    _changed();
  }

  void _sort(bool asc) {
    final (used, _) = sh.used;
    final g = range;
    final from = hasRange ? g.$1 : (sh.frozenRows > 0 ? 1 : 0);
    final to = hasRange ? g.$3 : used;
    if (to <= from) return;
    _snapshot();
    sh.sortRows(from, to, c, asc: asc);
    _changed();
    toast(context, 'Sorted by column ${colName(c)} ${asc ? 'A → Z' : 'Z → A'}');
  }

  void _structure(String what) {
    _snapshot();
    switch (what) {
      case 'row+':
        sh.insertRow(r);
      case 'row-':
        sh.deleteRow(r);
      case 'col+':
        sh.insertCol(c);
      case 'col-':
        sh.deleteCol(c);
    }
    _loadInput();
    _changed();
  }

  Future<void> _pickColor(bool fill) async {
    final colors = fill ? _fills : _palette;
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        title: fill ? 'Fill colour' : 'Text colour',
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final col in colors)
            GestureDetector(
              onTap: () => Navigator.pop(ctx, col),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Color(col),
                  shape: BoxShape.circle,
                  border: Border.all(color: _grid, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
                ),
              ),
            ),
          GestureDetector(
            onTap: () => Navigator.pop(ctx, -1),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _grid, width: 2)),
              child: const Icon(Icons.format_color_reset_rounded, color: _muted),
            ),
          ),
        ]),
      ),
    );
    if (v == null) return;
    _each((cell) => fill ? cell.fill = v == -1 ? null : v : cell.color = v == -1 ? null : v);
  }

  Future<void> _functions() async {
    const help = {
      'SUM': 'Total of numbers · SUM(A1:A10)',
      'AVERAGE': 'Average · AVERAGE(B2:B20)',
      'MIN': 'Smallest · MIN(A1:A10)',
      'MAX': 'Largest · MAX(A1:A10)',
      'COUNT': 'How many numbers · COUNT(A:A range)',
      'COUNTA': 'How many filled cells',
      'COUNTIF': 'Count matching · COUNTIF(B2:B9,"Paid")',
      'SUMIF': 'Sum matching · SUMIF(B2:B9,"Rent",C2:C9)',
      'AVERAGEIF': 'Average matching',
      'IF': 'Choose · IF(C2>1000,"Big","Small")',
      'IFERROR': 'Fallback · IFERROR(A1/B1,0)',
      'AND': 'All true', 'OR': 'Any true', 'NOT': 'Opposite',
      'ROUND': 'Round · ROUND(A1,2)', 'ROUNDUP': 'Round up', 'ROUNDDOWN': 'Round down', 'INT': 'Whole number',
      'ABS': 'Without sign', 'SQRT': 'Square root', 'POWER': 'Power · POWER(2,10)', 'MOD': 'Remainder', 'PRODUCT': 'Multiply all',
      'MEDIAN': 'Middle value', 'LARGE': 'k-th largest', 'SMALL': 'k-th smallest', 'RANK': 'Position in a list',
      'CONCAT': 'Join text', 'CONCATENATE': 'Join text', 'LEN': 'Text length', 'UPPER': 'CAPITALS', 'LOWER': 'small letters',
      'PROPER': 'Title Case', 'TRIM': 'Remove extra spaces', 'LEFT': 'First letters', 'RIGHT': 'Last letters', 'MID': 'Middle letters',
      'TEXT': 'Number as text · TEXT(A1,"0.00")', 'TODAY': "Today's date", 'NOW': 'Date and time', 'YEAR': 'Year of a date',
      'MONTH': 'Month of a date', 'DAY': 'Day of a date', 'DAYS': 'Days between · DAYS(end,start)',
      'VLOOKUP': 'Find in a table · VLOOKUP(key,A2:D50,3,FALSE)', 'HLOOKUP': 'Find across', 'INDEX': 'Value at row/col', 'MATCH': 'Position of a value',
      'PMT': 'Loan payment (Excel style)', 'EMI': 'EMI · EMI(amount,rate% per year,months)', 'GST': 'GST amount · GST(price,18)',
      'GSTINCL': 'GST inside a price · GSTINCL(1180,18)', 'PROFIT': 'PROFIT(sell,cost)', 'MARGIN': 'MARGIN(sell,cost) — format as %',
      'PERCENT': 'Part of total · PERCENT(part,total)', 'PI': 'π',
    };
    final f = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (ctx, sc) => _GlassSheet(
          fill: true,
          title: 'Functions · ${Formula.functions.length}',
          child: Expanded(
            child: ListView(controller: sc, children: [
              for (final name in Formula.functions)
                ListTile(
                  dense: true,
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(8)),
                    child: Text('fx', style: _j(12, FontWeight.w800, _green)),
                  ),
                  title: Text(name, style: _j(14, FontWeight.w800, _ink)),
                  subtitle: Text(help[name] ?? '', style: _j(12, FontWeight.w500, _muted)),
                  onTap: () => Navigator.pop(ctx, name),
                ),
            ]),
          ),
        ),
      ),
    );
    if (f == null) return;
    final g = range;
    final arg = hasRange ? '${cellName(g.$1, g.$2)}:${cellName(g.$3, g.$4)}' : '';
    final cur = input.text.startsWith('=') ? input.text : '=';
    input.text = '$cur$f($arg)';
    input.selection = TextSelection.collapsed(offset: input.text.length - 1);
    if (hasRange) {
      // put the result below the range, like AutoSum
      setState(() {
        r = g.$3 + 1;
        c = g.$2;
        ar = ac = null;
      });
    }
    inputFocus.requestFocus();
  }

  void _chart() {
    final g = range;
    if (!hasRange || g.$4 == g.$2) {
      toast(context, 'Select a range with labels in the first column and numbers next to it (long-press, then tap)');
      return;
    }
    final labels = <String>[];
    final series = <List<int>>[for (var j = g.$2 + 1; j <= g.$4; j++) []];
    final names = [for (var j = g.$2 + 1; j <= g.$4; j++) g.$1 > 0 ? showValue(sh.value(g.$1 - 1, j), null) : colName(j)];
    for (var i = g.$1; i <= g.$3; i++) {
      labels.add(showValue(sh.value(i, g.$2), sh.at(i, g.$2)));
      for (var j = g.$2 + 1; j <= g.$4; j++) {
        final v = sh.value(i, j);
        series[j - g.$2 - 1].add(v is num ? (v * 100).round() : 0);
      }
    }
    const colors = [Color(0xFF107C41), Color(0xFF5B2EE0), Color(0xFFF08A24), Color(0xFF2F6BFF), Color(0xFFDB2777)];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        title: 'Chart · $rangeName',
        child: Column(children: [
          TrendChart(
            labels: [for (final l in labels) l.length > 6 ? l.substring(0, 6) : l],
            series: [for (var k = 0; k < series.length; k++) ChartSeries(names[k], series[k], colors[k % colors.length], area: k == 0)],
            height: 260,
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 14, children: [
            for (var k = 0; k < series.length; k++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[k % colors.length], borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 5),
                Text(names[k].isEmpty ? colName(g.$2 + 1 + k) : names[k], style: _j(12, FontWeight.w700, _muted)),
              ]),
          ]),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- export
  Future<File> _tmp(String ext) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final safe = wb.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '').trim();
    return File(p.join(dir.path, '${safe.isEmpty ? 'Sheet' : safe}.$ext'));
  }

  Future<void> _exportXlsx() async {
    _commit();
    final sheets = <xl.Sheet>[];
    for (final s in wb.sheets) {
      final (lr, lc) = s.used;
      final widths = [for (var j = 0; j <= math.max(lc, 0); j++) s.width(j) / 7];
      final first = [for (var j = 0; j <= math.max(lc, 0); j++) _xcell(s, 0, j)];
      final out = xl.Sheet(s.name, [for (final v in first) v is xl.XFormula ? '${v.value ?? ''}' : '${v is xl.XBold ? v.value : v ?? ''}'], widths: widths);
      for (var i = 1; i <= lr; i++) {
        out.add([for (var j = 0; j <= lc; j++) _xcell(s, i, j)]);
      }
      sheets.add(out);
    }
    final f = await _tmp('xlsx');
    await f.writeAsBytes(xl.Xlsx.build(sheets, title: wb.name), flush: true);
    await NativeFiles.share(f, mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', subject: wb.name);
  }

  Object? _xcell(GridSheet s, int i, int j) {
    final cell = s.at(i, j);
    if (cell == null || cell.input.isEmpty) return null;
    final v = s.value(i, j);
    final money = cell.fmt == 'inr';
    if (cell.isFormula) return xl.XFormula(cell.input.substring(1), v is CellError ? v.code : v, bold: cell.bold, money: money);
    if (v is num) return money ? xl.Money2((v * 100).round()) : (cell.bold ? xl.XBold(v) : v.toDouble());
    return cell.bold ? xl.XBold(v) : v;
  }

  Future<void> _exportCsv() async {
    _commit();
    final (lr, lc) = sh.used;
    String q(String v) => RegExp(r'[",\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    final csv = [
      for (var i = 0; i <= lr; i++) [for (var j = 0; j <= lc; j++) q(showValue(sh.value(i, j), sh.at(i, j)).replaceAll('₹', ''))].join(','),
    ].join('\n');
    final f = await _tmp('csv');
    await f.writeAsString('﻿$csv', flush: true);
    await NativeFiles.share(f, mime: 'text/csv', subject: wb.name);
  }

  // ---------------------------------------------------------------- sheets
  Future<void> _sheetMenu(int i) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        title: wb.sheets[i].name,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.copy_all_rounded), title: const Text('Duplicate'), onTap: () => Navigator.pop(ctx, 'dup')),
          if (wb.sheets.length > 1)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC4545)),
              title: const Text('Delete', style: TextStyle(color: Color(0xFFDC4545))),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'rename') {
      final n = await _ask('Sheet name', wb.sheets[i].name);
      if (n != null && n.trim().isNotEmpty) wb.sheets[i].name = n.trim();
    } else if (v == 'dup') {
      wb.sheets.insert(i + 1, wb.sheets[i].clone()..name = '${wb.sheets[i].name} (2)');
    } else if (v == 'del') {
      wb.sheets.removeAt(i);
      tab = tab.clamp(0, wb.sheets.length - 1);
      undo.clear();
      redo.clear();
    }
    _loadInput();
    _changed();
  }

  Future<String?> _ask(String title, String value) {
    final t = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: t, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('Save')),
        ],
      ),
    );
  }

  // ================================================================ UI
  @override
  Widget build(BuildContext context) {
    final cell = sh.at(r, c);
    return Scaffold(
      backgroundColor: const Color(0xFFEFF2F8),
      body: Column(children: [
        _topBar(),
        _formulaBar(),
        _ribbon(cell),
        Expanded(child: _gridView()),
        _statusBar(),
        _tabs(),
      ]),
    );
  }

  Widget _topBar() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(6, top + 4, 6, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0B5A30), Color(0xFF107C41), Color(0xFF21A366)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            _commit();
            Navigator.of(context).pop();
          },
        ),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final n = await _ask('Workbook name', wb.name);
              if (n != null && n.trim().isNotEmpty) {
                wb.name = n.trim();
                _changed();
              }
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(wb.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(16.5, FontWeight.w800, Colors.white)),
              Text(dirty ? 'Saving…' : 'Saved · ${wb.sheets.length} sheet${wb.sheets.length == 1 ? '' : 's'}',
                  style: _j(11, FontWeight.w600, const Color(0xCCFFFFFF))),
            ]),
          ),
        ),
        IconButton(onPressed: undo.isEmpty ? null : _undo, icon: Icon(Icons.undo_rounded, color: undo.isEmpty ? Colors.white38 : Colors.white)),
        IconButton(onPressed: redo.isEmpty ? null : _redo, icon: Icon(Icons.redo_rounded, color: redo.isEmpty ? Colors.white38 : Colors.white)),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (v) {
            switch (v) {
              case 'xlsx':
                _exportXlsx();
              case 'csv':
                _exportCsv();
              case 'chart':
                _chart();
              case 'freeze':
                setState(() => sh.frozenRows = sh.frozenRows > 0 ? 0 : 1);
                _changed();
              case 'find':
                _find();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'xlsx', child: ListTile(leading: Icon(Icons.table_view_rounded, color: _green), title: Text('Export Excel (.xlsx)'))),
            const PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.description_rounded), title: Text('Export CSV'))),
            const PopupMenuItem(value: 'chart', child: ListTile(leading: Icon(Icons.insert_chart_rounded), title: Text('Chart from selection'))),
            const PopupMenuItem(value: 'find', child: ListTile(leading: Icon(Icons.search_rounded), title: Text('Find'))),
            PopupMenuItem(value: 'freeze', child: ListTile(leading: const Icon(Icons.vertical_align_top_rounded), title: Text(sh.frozenRows > 0 ? 'Unfreeze top row' : 'Freeze top row'))),
          ],
        ),
      ]),
    );
  }

  Future<void> _find() async {
    final q = await _ask('Find', '');
    if (q == null || q.trim().isEmpty) return;
    final s = q.trim().toLowerCase();
    final keys = sh.cells.keys.toList()..sort();
    for (final k in keys) {
      final i = k ~/ 1000, j = k % 1000;
      if (showValue(sh.value(i, j), sh.at(i, j)).toLowerCase().contains(s) || sh.input(i, j).toLowerCase().contains(s)) {
        _select(i, j);
        _scrollTo(i, j);
        return;
      }
    }
    if (mounted) toast(context, 'Not found: $q');
  }

  void _scrollTo(int i, int j) {
    if (vBody.hasClients) vBody.animateTo((i * _rowH - 80).clamp(0, vBody.position.maxScrollExtent), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    var x = 0.0;
    for (var k = 0; k < j; k++) {
      x += sh.width(k);
    }
    if (hBody.hasClients) hBody.animateTo((x - 40).clamp(0, hBody.position.maxScrollExtent), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Widget _formulaBar() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(children: [
          Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFF1F2F9), borderRadius: BorderRadius.circular(10)),
            child: Text(rangeName, textAlign: TextAlign.center, style: _j(12.5, FontWeight.w800, _green)),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _functions,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF21A366), Color(0xFF107C41)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('fx', style: _j(14, FontWeight.w800, Colors.white).copyWith(fontStyle: FontStyle.italic)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: input,
              focusNode: inputFocus,
              style: _j(14.5, FontWeight.w600, _ink),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Type a value or =formula',
                hintStyle: _j(13, FontWeight.w500, const Color(0xFFA3A7C2)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: (_) {
                _commit();
                _move(1, 0);
                inputFocus.requestFocus();
              },
            ),
          ),
          if (inputFocus.hasFocus || input.text != sh.input(r, c))
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.check_circle_rounded, color: _green),
              onPressed: () {
                _commit();
                inputFocus.unfocus();
              },
            ),
        ]),
      );

  Widget _ribbon(Cell? cell) {
    Widget b(IconData icon, String tip, VoidCallback onTap, {bool on = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Tooltip(
            message: tip,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: on
                      ? const LinearGradient(colors: [Color(0xFF21A366), Color(0xFF0B5A30)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                      : const LinearGradient(colors: [Colors.white, Color(0xFFEFF1F7)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  border: Border.all(color: on ? const Color(0xFF0B5A30) : const Color(0xFFDDE1EC)),
                  boxShadow: [
                    BoxShadow(color: on ? const Color(0x55107C41) : const Color(0x1A2A2F7A), blurRadius: 6, offset: const Offset(0, 3)),
                    const BoxShadow(color: Colors.white, blurRadius: 0, offset: Offset(0, -1)),
                  ],
                ),
                child: Icon(icon, size: 20, color: on ? Colors.white : _ink),
              ),
            ),
          ),
        );
    Widget sep() => Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 5), color: const Color(0xFFD5D9E6));
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FC),
        border: Border(top: BorderSide(color: Color(0xFFE3E6F0)), bottom: BorderSide(color: Color(0xFFE3E6F0))),
      ),
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7), children: [
        b(Icons.functions_rounded, 'AutoSum', _autoSum),
        b(Icons.format_bold_rounded, 'Bold', () => _each((x) => x.bold = !(cell?.bold ?? false)), on: cell?.bold ?? false),
        b(Icons.format_italic_rounded, 'Italic', () => _each((x) => x.italic = !(cell?.italic ?? false)), on: cell?.italic ?? false),
        b(Icons.format_underlined_rounded, 'Underline', () => _each((x) => x.under = !(cell?.under ?? false)), on: cell?.under ?? false),
        sep(),
        b(Icons.format_color_text_rounded, 'Text colour', () => _pickColor(false)),
        b(Icons.format_color_fill_rounded, 'Fill colour', () => _pickColor(true)),
        sep(),
        b(Icons.format_align_left_rounded, 'Left', () => _each((x) => x.align = 'left'), on: cell?.align == 'left'),
        b(Icons.format_align_center_rounded, 'Centre', () => _each((x) => x.align = 'center'), on: cell?.align == 'center'),
        b(Icons.format_align_right_rounded, 'Right', () => _each((x) => x.align = 'right'), on: cell?.align == 'right'),
        sep(),
        b(Icons.currency_rupee_rounded, 'Rupees', () => _each((x) => x.fmt = x.fmt == 'inr' ? 'auto' : 'inr'), on: cell?.fmt == 'inr'),
        b(Icons.percent_rounded, 'Percent', () => _each((x) => x.fmt = x.fmt == 'pct' ? 'auto' : 'pct'), on: cell?.fmt == 'pct'),
        b(Icons.numbers_rounded, 'Number 0.00', () => _each((x) => x.fmt = x.fmt == 'number' ? 'auto' : 'number'), on: cell?.fmt == 'number'),
        b(Icons.calendar_today_rounded, 'Date', () => _each((x) => x.fmt = x.fmt == 'date' ? 'auto' : 'date'), on: cell?.fmt == 'date'),
        sep(),
        b(Icons.arrow_upward_rounded, 'Sort A → Z', () => _sort(true)),
        b(Icons.arrow_downward_rounded, 'Sort Z → A', () => _sort(false)),
        b(Icons.vertical_align_bottom_rounded, 'Fill down', _fillDown),
        sep(),
        b(Icons.content_copy_rounded, 'Copy', _copy),
        b(Icons.content_cut_rounded, 'Cut', () => _copy(cut: true)),
        b(Icons.content_paste_rounded, 'Paste', _paste),
        b(Icons.backspace_rounded, 'Clear', _clear),
        sep(),
        b(Icons.table_rows_rounded, 'Insert row', () => _structure('row+')),
        b(Icons.playlist_remove_rounded, 'Delete row', () => _structure('row-')),
        b(Icons.view_column_rounded, 'Insert column', () => _structure('col+')),
        b(Icons.remove_road_rounded, 'Delete column', () => _structure('col-')),
        sep(),
        b(Icons.insert_chart_rounded, 'Chart', _chart),
        b(Icons.select_all_rounded, 'Range select', () => setState(() {
              rangeMode = !rangeMode;
              if (rangeMode) {
                ar = r;
                ac = c;
              }
            }), on: rangeMode),
      ]),
    );
  }

  // ---------------------------------------------------------------- grid
  double get _totalW {
    var w = 0.0;
    for (var j = 0; j < sh.cols; j++) {
      w += sh.width(j);
    }
    return w;
  }

  Widget _gridView() {
    final g = range;
    final frozen = sh.frozenRows > 0;
    final firstBodyRow = frozen ? 1 : 0;
    return LayoutBuilder(builder: (context, box) {
      return Column(children: [
        // column letters
        SizedBox(
          height: _headH,
          child: Row(children: [
            _corner(),
            Expanded(
              child: SingleChildScrollView(
                controller: hHead,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (var j = 0; j < sh.cols; j++) _colHead(j, j >= g.$2 && j <= g.$4),
                ]),
              ),
            ),
          ]),
        ),
        // frozen first row
        if (frozen)
          SizedBox(
            height: _rowH,
            child: Row(children: [
              _rowHead(0, 0 >= g.$1 && 0 <= g.$3),
              Expanded(
                child: SingleChildScrollView(
                  controller: _frozenH,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: _row(0, g, shadow: true),
                ),
              ),
            ]),
          ),
        Expanded(
          child: Row(children: [
            SizedBox(
              width: _numW,
              child: ListView.builder(
                controller: vHead,
                physics: const NeverScrollableScrollPhysics(),
                itemExtent: _rowH,
                itemCount: sh.rows - firstBodyRow,
                itemBuilder: (_, i) => _rowHead(i + firstBodyRow, i + firstBodyRow >= g.$1 && i + firstBodyRow <= g.$3),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.horizontal && _frozenH.hasClients && _frozenH.offset != n.metrics.pixels) {
                    _frozenH.jumpTo(n.metrics.pixels);
                  }
                  if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 400 && sh.rows < 5000) {
                    sh.rows += 40; // grow as you scroll
                    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() {}) : null);
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: hBody,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _totalW + 60,
                    child: ListView.builder(
                      controller: vBody,
                      itemExtent: _rowH,
                      itemCount: sh.rows - firstBodyRow,
                      itemBuilder: (_, i) => _row(i + firstBodyRow, g),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]);
    });
  }

  final _frozenH = ScrollController();

  Widget _corner() => GestureDetector(
        onTap: () {
          final (lr, lc) = sh.used;
          setState(() {
            ar = 0;
            ac = 0;
            r = math.max(lr, 0);
            c = math.max(lc, 0);
          });
        },
        child: Container(
          width: _numW,
          height: _headH,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFF7F8FC), Color(0xFFE9ECF5)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            border: Border(right: BorderSide(color: _grid), bottom: BorderSide(color: _grid)),
          ),
          child: const Icon(Icons.north_west_rounded, size: 13, color: _muted),
        ),
      );

  Widget _colHead(int j, bool on) => GestureDetector(
        onTap: () {
          _commit();
          setState(() {
            ar = 0;
            ac = j;
            r = math.max(sh.used.$1, 0);
            c = j;
            _loadInput();
          });
        },
        onHorizontalDragUpdate: (d) => setState(() => sh.widths[j] = (sh.width(j) + d.delta.dx).clamp(36, 400).toDouble()),
        onHorizontalDragEnd: (_) => _changed(),
        child: Container(
          width: sh.width(j),
          height: _headH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(colors: [Color(0xFFD6F2E2), Color(0xFFB9E6CC)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                : const LinearGradient(colors: [Color(0xFFF7F8FC), Color(0xFFE9ECF5)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            border: Border(right: const BorderSide(color: _grid), bottom: BorderSide(color: on ? _sel : _grid, width: on ? 2 : 1)),
          ),
          child: Text(colName(j), style: _j(11.5, FontWeight.w800, on ? _sel : _muted)),
        ),
      );

  Widget _rowHead(int i, bool on) => GestureDetector(
        onTap: () {
          _commit();
          setState(() {
            ar = i;
            ac = 0;
            r = i;
            c = math.max(sh.used.$2, 0);
            _loadInput();
          });
        },
        child: Container(
          height: _rowH,
          width: _numW,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0xFFD6F2E2) : const Color(0xFFF7F8FC),
            border: Border(bottom: const BorderSide(color: _grid), right: BorderSide(color: on ? _sel : _grid, width: on ? 2 : 1)),
          ),
          child: Text('${i + 1}', style: _j(11, FontWeight.w700, on ? _sel : _muted)),
        ),
      );

  Widget _row(int i, (int, int, int, int) g, {bool shadow = false}) => Container(
        decoration: shadow ? const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))]) : null,
        child: Row(children: [for (var j = 0; j < sh.cols; j++) _cell(i, j, g)]),
      );

  Widget _cell(int i, int j, (int, int, int, int) g) {
    final cell = sh.at(i, j);
    final v = sh.value(i, j);
    final inRange = hasRange && i >= g.$1 && i <= g.$3 && j >= g.$2 && j <= g.$4;
    final active = i == r && j == c;
    final text = showValue(v, cell);
    final isNum = v is num;
    final align = switch (cell?.align) {
      'left' => Alignment.centerLeft,
      'center' => Alignment.center,
      'right' => Alignment.centerRight,
      _ => isNum ? Alignment.centerRight : Alignment.centerLeft,
    };
    final err = v is CellError;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(i, j),
      onDoubleTap: () {
        _select(i, j);
        inputFocus.requestFocus();
        input.selection = TextSelection.collapsed(offset: input.text.length);
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _commit();
        setState(() {
          ar = i;
          ac = j;
          r = i;
          c = j;
          rangeMode = true;
          _loadInput();
        });
      },
      child: Container(
        width: sh.width(j),
        height: _rowH,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: align,
        decoration: BoxDecoration(
          color: inRange ? const Color(0x2216A36A) : (cell?.fill != null ? Color(cell!.fill!) : Colors.white),
          border: active
              ? Border.all(color: _sel, width: 2.2)
              : const Border(right: BorderSide(color: _grid, width: .7), bottom: BorderSide(color: _grid, width: .7)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            fontFamily: 'Jakarta',
            fontSize: 13,
            fontWeight: cell?.bold == true ? FontWeight.w800 : FontWeight.w500,
            fontStyle: cell?.italic == true ? FontStyle.italic : FontStyle.normal,
            decoration: cell?.under == true ? TextDecoration.underline : null,
            color: err ? const Color(0xFFDC4545) : (cell?.color != null ? Color(cell!.color!) : _ink),
          ),
        ),
      ),
    );
  }

  Widget _statusBar() {
    final g = range;
    var sum = 0.0, count = 0, filled = 0;
    var mn = double.infinity, mx = -double.infinity;
    if (hasRange) {
      for (var i = g.$1; i <= g.$3 && i - g.$1 < 5000; i++) {
        for (var j = g.$2; j <= g.$4; j++) {
          final v = sh.value(i, j);
          if (v != null && v != '') filled++;
          if (v is num) {
            sum += v;
            count++;
            mn = math.min(mn, v.toDouble());
            mx = math.max(mx, v.toDouble());
          }
        }
      }
    }
    Widget stat(String l, String v) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(text: '$l ', style: _j(11.5, FontWeight.w600, _muted)),
              TextSpan(text: v, style: _j(11.5, FontWeight.w800, _ink)),
            ]),
          ),
        );
    return Container(
      height: 30,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (hasRange && count > 0) ...[
                stat('Sum', showValue(sum, null)),
                stat('Avg', showValue(sum / count, null)),
                stat('Min', showValue(mn, null)),
                stat('Max', showValue(mx, null)),
                stat('Count', '$filled'),
              ] else if (hasRange)
                stat('Count', '$filled')
              else ...[
                Text(sh.input(r, c).startsWith('=') ? sh.input(r, c) : 'Tap a cell · long-press to select a range · double-tap to edit',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w600, _muted)),
              ],
            ]),
          ),
        ),
        if (rangeMode || hasRange)
          GestureDetector(
            onTap: () => setState(() {
              rangeMode = false;
              ar = ac = null;
            }),
            child: const Icon(Icons.close_rounded, size: 18, color: _muted),
          ),
      ]),
    );
  }

  Widget _tabs() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FC),
        border: Border(top: BorderSide(color: Color(0xFFE3E6F0))),
      ),
      child: SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var i = 0; i < wb.sheets.length; i++)
            GestureDetector(
              onTap: () {
                _commit();
                setState(() {
                  tab = i;
                  r = c = 0;
                  ar = ac = null;
                  undo.clear();
                  redo.clear();
                  _loadInput();
                });
              },
              onLongPress: () => _sheetMenu(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: i == tab ? const LinearGradient(colors: [Color(0xFF21A366), Color(0xFF107C41)]) : null,
                  color: i == tab ? null : Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: i == tab ? null : Border.all(color: const Color(0xFFDDE1EC)),
                  boxShadow: i == tab ? const [BoxShadow(color: Color(0x44107C41), blurRadius: 8, offset: Offset(0, 3))] : null,
                ),
                child: Text(wb.sheets[i].name, style: _j(12.5, FontWeight.w800, i == tab ? Colors.white : _ink)),
              ),
            ),
          GestureDetector(
            onTap: () {
              _commit();
              setState(() {
                wb.sheets.add(GridSheet('Sheet${wb.sheets.length + 1}'));
                tab = wb.sheets.length - 1;
                r = c = 0;
                ar = ac = null;
                undo.clear();
                redo.clear();
                _loadInput();
              });
              _changed();
            },
            child: Container(
              width: 36,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFDDE1EC))),
              child: const Icon(Icons.add_rounded, color: _green),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Frosted bottom sheet used by the editor's pickers.
class _GlassSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final bool fill; // take the whole height (child may be Expanded)
  const _GlassSheet({required this.title, required this.child, this.fill = false});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(color: Color(0xF2FFFFFF)),
            child: Column(mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _grid, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text(title, style: _j(17, FontWeight.w800, _ink)),
              const SizedBox(height: 12),
              child,
            ]),
          ),
        ),
      );
}
