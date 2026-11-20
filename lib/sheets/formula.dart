import 'dart:math' as math;

/// An error value shown in a cell, like Excel's #DIV/0!.
class CellError {
  final String code;
  const CellError(this.code);
  @override
  String toString() => code;
}

const errDiv0 = CellError('#DIV/0!');
const errValue = CellError('#VALUE!');
const errRef = CellError('#REF!');
const errName = CellError('#NAME?');
const errCycle = CellError('#CYCLE!');
const errNa = CellError('#N/A');

/// Column letters ⇄ index: A=0, Z=25, AA=26.
String colName(int c) {
  var n = c + 1, s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int colIndex(String letters) {
  var n = 0;
  for (final ch in letters.toUpperCase().codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

String cellName(int r, int c) => '${colName(c)}${r + 1}';

/// (row, col) from "B12", or null.
(int, int)? parseRef(String s) {
  final m = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$').firstMatch(s.trim());
  if (m == null) return null;
  final r = int.parse(m.group(2)!) - 1;
  if (r < 0) return null;
  return (r, colIndex(m.group(1)!));
}

class _Range {
  final int r1, c1, r2, c2;
  _Range(int a, int b, int c, int d)
      : r1 = math.min(a, c),
        c1 = math.min(b, d),
        r2 = math.max(a, c),
        c2 = math.max(b, d);
}

/// Reads the raw value of a cell for the evaluator (already computed).
typedef CellReader = Object? Function(int r, int c);

// ---------------------------------------------------------------- tokens
enum _T { num, str, ref, range, ident, op, lp, rp, comma, end }

class _Tok {
  final _T t;
  final String s;
  _Tok(this.t, this.s);
}

List<_Tok> _lex(String src) {
  final out = <_Tok>[];
  var i = 0;
  while (i < src.length) {
    final ch = src[i];
    if (ch == ' ' || ch == '\t') {
      i++;
      continue;
    }
    if (RegExp(r'[0-9.]').hasMatch(ch)) {
      final m = RegExp(r'\d*\.?\d+(?:[eE][+-]?\d+)?%?').matchAsPrefix(src, i) ?? RegExp(r'\d+\.?').matchAsPrefix(src, i);
      if (m == null) throw errValue;
      out.add(_Tok(_T.num, m.group(0)!));
      i = m.end;
      continue;
    }
    if (ch == '"') {
      final b = StringBuffer();
      i++;
      while (i < src.length) {
        if (src[i] == '"') {
          if (i + 1 < src.length && src[i + 1] == '"') {
            b.write('"');
            i += 2;
            continue;
          }
          break;
        }
        b.write(src[i]);
        i++;
      }
      i++;
      out.add(_Tok(_T.str, b.toString()));
      continue;
    }
    final word = RegExp(r'\$?[A-Za-z_][A-Za-z0-9_.]*\$?\d*(?::\$?[A-Za-z]{1,3}\$?\d+)?').matchAsPrefix(src, i);
    if (word != null) {
      final w = word.group(0)!;
      if (w.contains(':')) {
        out.add(_Tok(_T.range, w));
      } else if (parseRef(w) != null && !(i + w.length < src.length && src[i + w.length] == '(')) {
        out.add(_Tok(_T.ref, w));
      } else {
        out.add(_Tok(_T.ident, w.toUpperCase()));
      }
      i = word.end;
      continue;
    }
    final two = i + 1 < src.length ? src.substring(i, i + 2) : '';
    if (two == '<=' || two == '>=' || two == '<>') {
      out.add(_Tok(_T.op, two));
      i += 2;
      continue;
    }
    if ('+-*/^&=<>'.contains(ch)) {
      out.add(_Tok(_T.op, ch));
    } else if (ch == '(') {
      out.add(_Tok(_T.lp, ch));
    } else if (ch == ')') {
      out.add(_Tok(_T.rp, ch));
    } else if (ch == ',' || ch == ';') {
      out.add(_Tok(_T.comma, ch));
    } else {
      throw errValue;
    }
    i++;
  }
  out.add(_Tok(_T.end, ''));
  return out;
}

// ---------------------------------------------------------------- evaluator
/// Evaluates an expression (without the leading '=') to a number, string,
/// bool, CellError or List (a range, flattened).
class Formula {
  final List<_Tok> _t;
  int _i = 0;
  final CellReader read;
  Formula._(this._t, this.read);

  static Object? eval(String expr, CellReader read) {
    try {
      final f = Formula._(_lex(expr), read);
      final v = f._expr();
      if (f._t[f._i].t != _T.end) return errValue;
      if (v is _Rng) return v.v.isEmpty ? 0 : v.v.first;
      return v;
    } on CellError catch (e) {
      return e;
    } catch (_) {
      return errValue;
    }
  }

  /// Cells a formula reads (for dependency tracking).
  static Set<(int, int)> refs(String expr) {
    final out = <(int, int)>{};
    try {
      for (final t in _lex(expr)) {
        if (t.t == _T.ref) {
          final p = parseRef(t.s);
          if (p != null) out.add(p);
        } else if (t.t == _T.range) {
          final parts = t.s.split(':');
          final a = parseRef(parts[0]), b = parseRef(parts[1]);
          if (a == null || b == null) continue;
          final r = _Range(a.$1, a.$2, b.$1, b.$2);
          for (var i = r.r1; i <= r.r2 && i - r.r1 < 2000; i++) {
            for (var j = r.c1; j <= r.c2 && j - r.c1 < 100; j++) {
              out.add((i, j));
            }
          }
        }
      }
    } catch (_) {}
    return out;
  }

  _Tok get _p => _t[_i];
  _Tok _next() => _t[_i++];

  Object? _expr() => _cmp();

  Object? _cmp() {
    var a = _concat();
    while (_p.t == _T.op && ['=', '<>', '<', '>', '<=', '>='].contains(_p.s)) {
      final op = _next().s;
      final b = _concat();
      a = _compare(a, b, op);
    }
    return a;
  }

  Object? _concat() {
    var a = _add();
    while (_p.t == _T.op && _p.s == '&') {
      _next();
      final b = _add();
      a = '${_text(a)}${_text(b)}';
    }
    return a;
  }

  Object? _add() {
    var a = _mul();
    while (_p.t == _T.op && (_p.s == '+' || _p.s == '-')) {
      final op = _next().s;
      final b = _mul();
      final x = _num(a), y = _num(b);
      a = op == '+' ? x + y : x - y;
    }
    return a;
  }

  Object? _mul() {
    var a = _pow();
    while (_p.t == _T.op && (_p.s == '*' || _p.s == '/')) {
      final op = _next().s;
      final b = _pow();
      final x = _num(a), y = _num(b);
      if (op == '/' && y == 0) throw errDiv0;
      a = op == '*' ? x * y : x / y;
    }
    return a;
  }

  Object? _pow() {
    final a = _unary();
    if (_p.t == _T.op && _p.s == '^') {
      _next();
      final b = _pow();
      return math.pow(_num(a), _num(b)).toDouble();
    }
    return a;
  }

  Object? _unary() {
    if (_p.t == _T.op && (_p.s == '-' || _p.s == '+')) {
      final op = _next().s;
      final v = _unary();
      return op == '-' ? -_num(v) : _num(v);
    }
    return _atom();
  }

  Object? _atom() {
    final t = _next();
    switch (t.t) {
      case _T.num:
        if (t.s.endsWith('%')) return double.parse(t.s.substring(0, t.s.length - 1)) / 100;
        return double.parse(t.s);
      case _T.str:
        return t.s;
      case _T.ref:
        final p = parseRef(t.s)!;
        final v = read(p.$1, p.$2);
        if (v is CellError) throw v;
        return v;
      case _T.range:
        final parts = t.s.split(':');
        final a = parseRef(parts[0]), b = parseRef(parts[1]);
        if (a == null || b == null) throw errRef;
        final r = _Range(a.$1, a.$2, b.$1, b.$2);
        final out = <Object?>[];
        for (var i = r.r1; i <= r.r2; i++) {
          for (var j = r.c1; j <= r.c2; j++) {
            final v = read(i, j);
            if (v is CellError) throw v;
            out.add(v);
          }
        }
        return _Rng(out, r.c2 - r.c1 + 1);
      case _T.ident:
        if (t.s == 'TRUE') return true;
        if (t.s == 'FALSE') return false;
        if (_p.t != _T.lp) throw errName;
        _next();
        final args = <Object? Function()>[];
        // collect argument token spans so IF / IFERROR can be lazy
        while (_p.t != _T.rp) {
          final start = _i;
          _skipArg();
          final end = _i;
          args.add(() {
            final save = _i;
            _i = start;
            try {
              final v = _expr();
              if (_i != end) throw errValue;
              return v;
            } finally {
              _i = save; // an error inside an argument must not lose our place
            }
          });
          if (_p.t == _T.comma) {
            _next();
          } else if (_p.t != _T.rp) {
            throw errValue;
          }
        }
        _next();
        return _call(t.s, args);
      case _T.lp:
        final v = _expr();
        if (_next().t != _T.rp) throw errValue;
        return v;
      default:
        throw errValue;
    }
  }

  /// Moves past one argument (balanced parentheses).
  void _skipArg() {
    var depth = 0;
    while (true) {
      final t = _p;
      if (t.t == _T.end) throw errValue;
      if (depth == 0 && (t.t == _T.comma || t.t == _T.rp)) return;
      if (t.t == _T.lp) depth++;
      if (t.t == _T.rp) depth--;
      _i++;
    }
  }

  // ---------------------------------------------------------------- functions
  static const functions = [
    'SUM', 'AVERAGE', 'MIN', 'MAX', 'COUNT', 'COUNTA', 'COUNTIF', 'SUMIF', 'AVERAGEIF', 'IF', 'IFERROR', 'AND', 'OR', 'NOT',
    'ROUND', 'ROUNDUP', 'ROUNDDOWN', 'INT', 'ABS', 'SQRT', 'POWER', 'MOD', 'PRODUCT', 'MEDIAN', 'LARGE', 'SMALL', 'RANK',
    'CONCAT', 'CONCATENATE', 'LEN', 'UPPER', 'LOWER', 'PROPER', 'TRIM', 'LEFT', 'RIGHT', 'MID', 'TEXT',
    'TODAY', 'NOW', 'YEAR', 'MONTH', 'DAY', 'DAYS', 'VLOOKUP', 'HLOOKUP', 'INDEX', 'MATCH',
    'PMT', 'EMI', 'GST', 'GSTINCL', 'PROFIT', 'MARGIN', 'PERCENT', 'PI',
  ];

  List<Object?> _flat(List<Object? Function()> args) => [
        for (final a in args)
          ...switch (a()) {
            _Rng r => r.v,
            final v => [v],
          }
      ];

  Iterable<double> _nums(List<Object? Function()> args) sync* {
    for (final a in args) {
      final v = a();
      if (v is _Rng) {
        for (final x in v.v) {
          if (x is num) yield x.toDouble();
          if (x is String) {
            final d = double.tryParse(x.replaceAll(',', ''));
            if (d != null) yield d;
          }
        }
      } else if (v != null && v != '') {
        yield _num(v);
      }
    }
  }

  bool _match(Object? v, Object? crit) {
    if (crit is num) return v is num && v == crit;
    final c = '$crit'.trim();
    final m = RegExp(r'^(<=|>=|<>|<|>|=)?(.*)$').firstMatch(c)!;
    final op = m.group(1) ?? '=';
    final rhs = m.group(2)!;
    final rn = double.tryParse(rhs);
    if (rn != null && v is num) return _compare(v.toDouble(), rn, op) == true;
    final lhs = _text(v).toLowerCase(), r = rhs.toLowerCase();
    if (op == '=') {
      if (r.contains('*')) return RegExp('^${RegExp.escape(r).replaceAll(r'\*', '.*')}\$').hasMatch(lhs);
      return lhs == r;
    }
    if (op == '<>') return lhs != r;
    return false;
  }

  Object? _call(String f, List<Object? Function()> a) {
    double n(int i) => _num(a[i]());
    switch (f) {
      case 'SUM':
        return _nums(a).fold<double>(0, (s, x) => s + x);
      case 'AVERAGE':
        final l = _nums(a).toList();
        if (l.isEmpty) throw errDiv0;
        return l.reduce((x, y) => x + y) / l.length;
      case 'MIN':
        final l = _nums(a).toList();
        return l.isEmpty ? 0 : l.reduce(math.min);
      case 'MAX':
        final l = _nums(a).toList();
        return l.isEmpty ? 0 : l.reduce(math.max);
      case 'COUNT':
        return _flat(a).whereType<num>().length.toDouble();
      case 'COUNTA':
        return _flat(a).where((v) => v != null && v != '').length.toDouble();
      case 'PRODUCT':
        return _nums(a).fold<double>(1, (s, x) => s * x);
      case 'MEDIAN':
        final l = _nums(a).toList()..sort();
        if (l.isEmpty) throw errNa;
        return l.length.isOdd ? l[l.length ~/ 2] : (l[l.length ~/ 2 - 1] + l[l.length ~/ 2]) / 2;
      case 'LARGE' || 'SMALL':
        final l = _nums([a[0]]).toList()..sort();
        final k = n(1).toInt();
        if (k < 1 || k > l.length) throw errNa;
        return f == 'LARGE' ? l[l.length - k] : l[k - 1];
      case 'RANK':
        final x = n(0);
        final l = _nums([a[1]]).toList();
        return (l.where((y) => y > x).length + 1).toDouble();
      case 'COUNTIF':
        final r = a[0]();
        final crit = a[1]();
        return (r is _Rng ? r.v : [r]).where((v) => _match(v, crit)).length.toDouble();
      case 'SUMIF' || 'AVERAGEIF':
        final r = a[0]();
        final crit = a[1]();
        final cells = r is _Rng ? r.v : [r];
        final sumCells = a.length > 2 ? (switch (a[2]()) { _Rng s => s.v, final v => [v] }) : cells;
        final picked = <double>[];
        for (var i = 0; i < cells.length && i < sumCells.length; i++) {
          if (_match(cells[i], crit)) picked.add(_num(sumCells[i] ?? 0));
        }
        if (f == 'SUMIF') return picked.fold<double>(0, (s, x) => s + x);
        if (picked.isEmpty) throw errDiv0;
        return picked.reduce((x, y) => x + y) / picked.length;
      case 'IF':
        return _bool(a[0]()) ? (a.length > 1 ? a[1]() : true) : (a.length > 2 ? a[2]() : false);
      case 'IFERROR':
        try {
          final v = a[0]();
          if (v is CellError) return a[1]();
          return v;
        } on CellError {
          return a[1]();
        }
      case 'AND':
        return a.every((x) => _bool(x()));
      case 'OR':
        return a.any((x) => _bool(x()));
      case 'NOT':
        return !_bool(a[0]());
      case 'ROUND':
        final p = a.length > 1 ? n(1).toInt() : 0;
        final m = math.pow(10, p);
        return (n(0) * m).round() / m;
      case 'ROUNDUP':
        final m = math.pow(10, a.length > 1 ? n(1).toInt() : 0);
        return (n(0) * m).ceil() / m;
      case 'ROUNDDOWN':
        final m = math.pow(10, a.length > 1 ? n(1).toInt() : 0);
        return (n(0) * m).truncate() / m;
      case 'INT':
        return n(0).floorToDouble();
      case 'ABS':
        return n(0).abs();
      case 'SQRT':
        if (n(0) < 0) throw errValue;
        return math.sqrt(n(0));
      case 'POWER':
        return math.pow(n(0), n(1)).toDouble();
      case 'MOD':
        if (n(1) == 0) throw errDiv0;
        return n(0) % n(1);
      case 'PI':
        return math.pi;
      case 'CONCAT' || 'CONCATENATE':
        return _flat(a).map(_text).join();
      case 'LEN':
        return _text(a[0]()).length.toDouble();
      case 'UPPER':
        return _text(a[0]()).toUpperCase();
      case 'LOWER':
        return _text(a[0]()).toLowerCase();
      case 'PROPER':
        return _text(a[0]()).split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
      case 'TRIM':
        return _text(a[0]()).trim().replaceAll(RegExp(r'\s+'), ' ');
      case 'LEFT':
        final s = _text(a[0]());
        return s.substring(0, math.min(s.length, a.length > 1 ? n(1).toInt() : 1));
      case 'RIGHT':
        final s = _text(a[0]());
        final k = math.min(s.length, a.length > 1 ? n(1).toInt() : 1);
        return s.substring(s.length - k);
      case 'MID':
        final s = _text(a[0]());
        final st = (n(1).toInt() - 1).clamp(0, s.length), len = n(2).toInt();
        return s.substring(st, math.min(s.length, st + len));
      case 'TEXT':
        final v = n(0);
        final fmt = a.length > 1 ? _text(a[1]()) : '0';
        final dec = fmt.contains('.') ? fmt.split('.').last.replaceAll(RegExp(r'[^0#]'), '').length : 0;
        return v.toStringAsFixed(dec);
      case 'TODAY':
        final d = DateTime.now();
        return _serial(DateTime(d.year, d.month, d.day));
      case 'NOW':
        return _serial(DateTime.now());
      case 'YEAR':
        return _date(n(0)).year.toDouble();
      case 'MONTH':
        return _date(n(0)).month.toDouble();
      case 'DAY':
        return _date(n(0)).day.toDouble();
      case 'DAYS':
        return (n(0) - n(1)).floorToDouble();
      case 'VLOOKUP' || 'HLOOKUP':
        final key = a[0]();
        final t = a[1]();
        if (t is! _Rng) throw errRef;
        final idx = n(2).toInt() - 1;
        final exact = a.length > 3 ? !_bool(a[3]()) : true;
        final rows = t.v.length ~/ t.w, cols = t.w;
        if (f == 'VLOOKUP') {
          for (var r = 0; r < rows; r++) {
            final v = t.v[r * cols];
            if (_eq(v, key) || (!exact && _text(v).toLowerCase().startsWith(_text(key).toLowerCase()))) {
              if (idx < 0 || idx >= cols) throw errRef;
              return t.v[r * cols + idx];
            }
          }
        } else {
          for (var c = 0; c < cols; c++) {
            if (_eq(t.v[c], key)) {
              if (idx < 0 || idx >= rows) throw errRef;
              return t.v[idx * cols + c];
            }
          }
        }
        throw errNa;
      case 'INDEX':
        final t = a[0]();
        if (t is! _Rng) return t;
        final r = n(1).toInt() - 1, c = a.length > 2 ? n(2).toInt() - 1 : 0;
        final i = t.w == 1 ? r : r * t.w + c;
        if (i < 0 || i >= t.v.length) throw errRef;
        return t.v[i];
      case 'MATCH':
        final key = a[0]();
        final t = a[1]();
        final l = t is _Rng ? t.v : [t];
        for (var i = 0; i < l.length; i++) {
          if (_eq(l[i], key)) return (i + 1).toDouble();
        }
        throw errNa;
      // business helpers
      case 'PMT' || 'EMI':
        // EMI(principal, annual rate %, months) / PMT(rate per period, periods, principal)
        if (f == 'EMI') {
          final p = n(0), r = n(1) / 1200, m = n(2);
          if (m <= 0) throw errValue;
          if (r == 0) return p / m;
          final k = math.pow(1 + r, m);
          return p * r * k / (k - 1);
        }
        final r = n(0), m = n(1), p = n(2);
        if (r == 0) return -p / m;
        final k = math.pow(1 + r, m);
        return -p * r * k / (k - 1);
      case 'GST':
        return n(0) * n(1) / 100; // GST(amount, rate%) → tax
      case 'GSTINCL':
        return n(0) - n(0) / (1 + n(1) / 100); // tax inside an inclusive price
      case 'PROFIT':
        return n(0) - n(1); // PROFIT(sell, cost)
      case 'MARGIN':
        if (n(0) == 0) throw errDiv0;
        return (n(0) - n(1)) / n(0); // MARGIN(sell, cost) as a fraction
      case 'PERCENT':
        if (n(1) == 0) throw errDiv0;
        return n(0) / n(1);
    }
    throw errName;
  }

  static double _serial(DateTime d) => d.difference(DateTime(1899, 12, 30)).inMilliseconds / 86400000;
  static DateTime _date(double s) => DateTime(1899, 12, 30).add(Duration(milliseconds: (s * 86400000).round()));

  static bool _eq(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    return _text(a).toLowerCase() == _text(b).toLowerCase();
  }

  static Object _compare(Object? a, Object? b, String op) {
    int c;
    if ((a is num || a == null) && (b is num || b == null)) {
      c = ((a as num?) ?? 0).compareTo((b as num?) ?? 0);
    } else {
      c = _text(a).toLowerCase().compareTo(_text(b).toLowerCase());
    }
    return switch (op) { '=' => c == 0, '<>' => c != 0, '<' => c < 0, '>' => c > 0, '<=' => c <= 0, _ => c >= 0 };
  }

  static double _num(Object? v) {
    if (v == null || v == '') return 0;
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    if (v is _Rng) return v.v.isEmpty ? 0 : _num(v.v.first);
    if (v is CellError) throw v;
    final d = double.tryParse('$v'.replaceAll(',', '').replaceAll('₹', '').trim());
    if (d == null) throw errValue;
    return d;
  }

  static bool _bool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toUpperCase() == 'TRUE' || (double.tryParse(v) ?? 0) != 0;
    return false;
  }

  static String _text(Object? v) {
    if (v == null) return '';
    if (v is double) return v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : '$v';
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    if (v is _Rng) return v.v.isEmpty ? '' : _text(v.v.first);
    return '$v';
  }
}

/// A range value: cells row by row, [w] wide.
class _Rng {
  final List<Object?> v;
  final int w;
  _Rng(this.v, this.w);
}
