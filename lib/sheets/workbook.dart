import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'formula.dart';

/// One cell: what was typed ([input]) plus its look.
class Cell {
  String input;
  bool bold, italic, under;
  int? color, fill; // ARGB
  String align; // auto | left | center | right
  String fmt; // auto | number | inr | pct | int | date | text
  Cell(this.input, {this.bold = false, this.italic = false, this.under = false, this.color, this.fill, this.align = 'auto', this.fmt = 'auto'});

  bool get isFormula => input.startsWith('=');
  bool get styled => bold || italic || under || color != null || fill != null || align != 'auto' || fmt != 'auto';

  Cell copy() => Cell(input, bold: bold, italic: italic, under: under, color: color, fill: fill, align: align, fmt: fmt);

  Map<String, Object?> toJson() => {
        'i': input,
        if (bold) 'b': 1,
        if (italic) 'it': 1,
        if (under) 'u': 1,
        if (color != null) 'c': color,
        if (fill != null) 'f': fill,
        if (align != 'auto') 'a': align,
        if (fmt != 'auto') 'n': fmt,
      };

  static Cell from(Map<String, dynamic> m) => Cell('${m['i'] ?? ''}',
      bold: m['b'] == 1, italic: m['it'] == 1, under: m['u'] == 1, color: m['c'] as int?, fill: m['f'] as int?, align: '${m['a'] ?? 'auto'}', fmt: '${m['n'] ?? 'auto'}');
}

/// One sheet of a workbook, with values computed from formulas.
class GridSheet {
  String name;
  int rows, cols;
  final Map<int, Cell> cells; // key = row * 1000 + col
  final Map<int, double> widths; // col → width
  int frozenRows, frozenCols;
  GridSheet(this.name, {this.rows = 60, this.cols = 12, Map<int, Cell>? cells, Map<int, double>? widths, this.frozenRows = 1, this.frozenCols = 0})
      : cells = cells ?? {},
        widths = widths ?? {};

  static int key(int r, int c) => r * 1000 + c;

  Cell? at(int r, int c) => cells[key(r, c)];
  String input(int r, int c) => cells[key(r, c)]?.input ?? '';

  void put(int r, int c, String input) {
    final k = key(r, c);
    final cell = cells[k];
    if (input.isEmpty && (cell == null || !cell.styled)) {
      cells.remove(k);
    } else if (cell == null) {
      cells[k] = Cell(input);
    } else {
      cell.input = input;
    }
    if (r >= rows - 2) rows = r + 10;
    if (c >= cols - 1) cols = c + 3;
    _cache.clear();
  }

  Cell style(int r, int c) => cells.putIfAbsent(key(r, c), () => Cell(''));

  double width(int c) => widths[c] ?? (c == 0 ? 130 : 96);

  // ---------------------------------------------------------------- values
  final Map<int, Object?> _cache = {};
  final Set<int> _busy = {};
  void invalidate() => _cache.clear();

  /// Computed value: number (double), string, bool, CellError or null.
  Object? value(int r, int c) {
    final k = key(r, c);
    if (_cache.containsKey(k)) return _cache[k];
    final cell = cells[k];
    Object? v;
    if (cell == null || cell.input.isEmpty) {
      v = null;
    } else if (cell.isFormula) {
      if (_busy.contains(k)) return errCycle;
      _busy.add(k);
      v = Formula.eval(cell.input.substring(1), (rr, cc) => value(rr, cc));
      _busy.remove(k);
    } else {
      v = literal(cell.input);
    }
    _cache[k] = v;
    return v;
  }

  /// A typed value: numbers (1,234.5 · ₹99 · 18%), TRUE/FALSE, else text.
  static Object? literal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    if (t.startsWith("'")) return t.substring(1);
    final up = t.toUpperCase();
    if (up == 'TRUE') return true;
    if (up == 'FALSE') return false;
    final pct = t.endsWith('%');
    final n = double.tryParse(t.replaceAll(',', '').replaceAll('₹', '').replaceAll('%', '').trim());
    if (n != null && RegExp(r'^[₹\s]*-?[\d,]*\.?\d+\s*%?$').hasMatch(t)) return pct ? n / 100 : n;
    return s;
  }

  // ---------------------------------------------------------------- structure
  void insertRow(int at) => _shift(rowAt: at, dr: 1);
  void deleteRow(int at) => _shift(rowAt: at, dr: -1);
  void insertCol(int at) => _shift(colAt: at, dc: 1);
  void deleteCol(int at) => _shift(colAt: at, dc: -1);

  void _shift({int? rowAt, int? colAt, int dr = 0, int dc = 0}) {
    final moved = <int, Cell>{};
    cells.forEach((k, v) {
      var r = k ~/ 1000, c = k % 1000;
      if (rowAt != null) {
        if (dr < 0 && r == rowAt) return;
        if (r >= rowAt + (dr < 0 ? 1 : 0)) r += dr;
      }
      if (colAt != null) {
        if (dc < 0 && c == colAt) return;
        if (c >= colAt + (dc < 0 ? 1 : 0)) c += dc;
      }
      v.input = v.isFormula ? _moveRefs(v.input, rowAt, colAt, dr, dc) : v.input;
      moved[key(r, c)] = v;
    });
    cells
      ..clear()
      ..addAll(moved);
    if (colAt != null) {
      final w = <int, double>{};
      widths.forEach((c, v) {
        if (dc < 0 && c == colAt) return;
        w[c >= colAt + (dc < 0 ? 1 : 0) ? c + dc : c] = v;
      });
      widths
        ..clear()
        ..addAll(w);
      cols = (cols + dc).clamp(1, 999);
    } else {
      rows = (rows + dr).clamp(1, 100000);
    }
    _cache.clear();
  }

  /// Keeps formulas pointing at the same cells after rows / columns move.
  static String _moveRefs(String f, int? rowAt, int? colAt, int dr, int dc) =>
      f.replaceAllMapped(RegExp(r'(?<![A-Za-z"])(\$?)([A-Za-z]{1,3})(\$?)(\d+)(?![\w(])'), (m) {
        var c = colIndex(m.group(2)!), r = int.parse(m.group(4)!) - 1;
        if (rowAt != null && r >= rowAt) r += dr;
        if (colAt != null && c >= colAt) c += dc;
        if (r < 0 || c < 0) return '#REF!';
        return '${m.group(1)}${colName(c)}${m.group(3)}${r + 1}';
      });

  /// Shifts relative references by (dr, dc) — for copy / fill.
  static String offsetFormula(String f, int dr, int dc) =>
      f.replaceAllMapped(RegExp(r'(?<![A-Za-z"])(\$?)([A-Za-z]{1,3})(\$?)(\d+)(?![\w(])'), (m) {
        var c = colIndex(m.group(2)!), r = int.parse(m.group(4)!) - 1;
        if (m.group(1)!.isEmpty) c += dc;
        if (m.group(3)!.isEmpty) r += dr;
        if (r < 0 || c < 0) return '#REF!';
        return '${m.group(1)}${colName(c)}${m.group(3)}${r + 1}';
      });

  /// Sorts rows [r1..r2] by column [c] (values), keeping row formatting.
  void sortRows(int r1, int r2, int c, {bool asc = true}) {
    final rowsData = <int, Map<int, Cell>>{};
    for (var r = r1; r <= r2; r++) {
      rowsData[r] = {};
    }
    cells.forEach((k, v) {
      final r = k ~/ 1000;
      if (r >= r1 && r <= r2) rowsData[r]![k % 1000] = v;
    });
    final order = rowsData.keys.toList()
      ..sort((a, b) {
        final x = value(a, c), y = value(b, c);
        int cmp;
        if (x == null && y == null) {
          cmp = 0;
        } else if (x == null) {
          return 1;
        } else if (y == null) {
          return -1;
        } else if (x is num && y is num) {
          cmp = x.compareTo(y);
        } else {
          cmp = '$x'.toLowerCase().compareTo('$y'.toLowerCase());
        }
        return asc ? cmp : -cmp;
      });
    cells.removeWhere((k, _) => k ~/ 1000 >= r1 && k ~/ 1000 <= r2);
    for (var i = 0; i < order.length; i++) {
      rowsData[order[i]]!.forEach((c, cell) => cells[key(r1 + i, c)] = cell);
    }
    _cache.clear();
  }

  /// Last row / column that has anything in it.
  (int, int) get used {
    var r = -1, c = -1;
    for (final k in cells.keys) {
      if ((cells[k]!.input).isEmpty) continue;
      if (k ~/ 1000 > r) r = k ~/ 1000;
      if (k % 1000 > c) c = k % 1000;
    }
    return (r, c);
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'rows': rows,
        'cols': cols,
        'fr': frozenRows,
        'fc': frozenCols,
        'w': {for (final e in widths.entries) '${e.key}': e.value},
        'c': {for (final e in cells.entries) '${e.key}': e.value.toJson()},
      };

  static GridSheet from(Map<String, dynamic> m) => GridSheet(
        '${m['name'] ?? 'Sheet1'}',
        rows: (m['rows'] as num?)?.toInt() ?? 60,
        cols: (m['cols'] as num?)?.toInt() ?? 12,
        frozenRows: (m['fr'] as num?)?.toInt() ?? 1,
        frozenCols: (m['fc'] as num?)?.toInt() ?? 0,
        widths: {for (final e in ((m['w'] as Map?) ?? {}).entries) int.parse('${e.key}'): (e.value as num).toDouble()},
        cells: {for (final e in ((m['c'] as Map?) ?? {}).entries) int.parse('${e.key}'): Cell.from(e.value as Map<String, dynamic>)},
      );

  GridSheet clone() => GridSheet.from(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

class Workbook {
  final String id;
  String name, category;
  int color; // ARGB accent
  DateTime created, updated;
  final List<GridSheet> sheets;
  bool starred;
  Workbook(this.id, this.name, {this.category = 'Blank', this.color = 0xFF16A36A, DateTime? created, DateTime? updated, List<GridSheet>? sheets, this.starred = false})
      : created = created ?? DateTime.now(),
        updated = updated ?? DateTime.now(),
        sheets = sheets ?? [GridSheet('Sheet1')];

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'cat': category,
        'color': color,
        'star': starred,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'sheets': [for (final s in sheets) s.toJson()],
      };

  static Workbook from(Map<String, dynamic> m) => Workbook(
        '${m['id']}',
        '${m['name'] ?? 'Untitled'}',
        category: '${m['cat'] ?? 'Blank'}',
        color: (m['color'] as num?)?.toInt() ?? 0xFF16A36A,
        starred: m['star'] == true,
        created: DateTime.tryParse('${m['created']}'),
        updated: DateTime.tryParse('${m['updated']}'),
        sheets: [for (final s in (m['sheets'] as List? ?? const [])) GridSheet.from(s as Map<String, dynamic>)],
      );

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

/// Workbooks saved on the phone (app-support/sheets/*.json), per app — not
/// part of the books' backups.
class SheetStore {
  static Future<Directory> _dir() async {
    final d = Directory(p.join((await getApplicationSupportDirectory()).path, 'sheets'));
    await d.create(recursive: true);
    return d;
  }

  static Future<List<Workbook>> list() async {
    final out = <Workbook>[];
    await for (final f in (await _dir()).list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(Workbook.from(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  static Future<void> save(Workbook w) async {
    w.updated = DateTime.now();
    final f = File(p.join((await _dir()).path, '${w.id}.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(w.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  static Future<void> delete(String id) async {
    final f = File(p.join((await _dir()).path, '$id.json'));
    if (await f.exists()) await f.delete();
  }

  static Future<Workbook> duplicate(Workbook w) async {
    final c = Workbook.from(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
    final copy = Workbook(Workbook.newId(), '${w.name} (copy)', category: w.category, color: w.color, sheets: c.sheets);
    await save(copy);
    return copy;
  }
}
