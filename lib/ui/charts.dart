import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/money.dart';

/// A data series for [TrendChart].
class ChartSeries {
  final String name;
  final List<int> values; // paise
  final Color color;
  final bool area; // filled gradient under the line
  const ChartSeries(this.name, this.values, this.color, {this.area = false});
}

/// Smooth multi-series line/area chart with grid, ₹ axis and touch tooltip.
class TrendChart extends StatefulWidget {
  final List<String> labels;
  final List<ChartSeries> series;
  final double height;
  const TrendChart({super.key, required this.labels, required this.series, this.height = 220});

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? touched;

  void _touch(Offset local, double width) {
    const left = _TrendPainter.leftPad;
    final n = widget.labels.length;
    if (n == 0) return;
    final plotW = width - left - _TrendPainter.rightPad;
    final i = n == 1 ? 0 : ((local.dx - left) / plotW * (n - 1)).round().clamp(0, n - 1);
    if (i != touched) setState(() => touched = i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return GestureDetector(
        onTapDown: (d) => _touch(d.localPosition, c.maxWidth),
        onHorizontalDragUpdate: (d) => _touch(d.localPosition, c.maxWidth),
        onHorizontalDragEnd: (_) {},
        child: SizedBox(
          height: widget.height,
          width: c.maxWidth,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(Object.hashAll([...widget.labels, for (final s in widget.series) ...s.values])),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(
              painter: _TrendPainter(widget.labels, widget.series, touched, t),
            ),
          ),
        ),
      );
    });
  }
}

class _TrendPainter extends CustomPainter {
  static const leftPad = 46.0, rightPad = 8.0, topPad = 12.0, bottomPad = 26.0;
  final List<String> labels;
  final List<ChartSeries> series;
  final int? touched;
  final double t;
  _TrendPainter(this.labels, this.series, this.touched, this.t);

  static double niceMax(double v) {
    if (v <= 0) return 100;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (v <= m * exp) return m * exp;
    }
    return 10 * exp;
  }

  void _text(Canvas c, String s, Offset at, {double size = 10, Color color = const Color(0xFF8A8FAD), bool center = false, bool right = false, FontWeight w = FontWeight.w500}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Jakarta', fontSize: size, color: color, fontWeight: w)),
      textDirection: TextDirection.ltr,
    )..layout();
    var o = at;
    if (center) o = o - Offset(tp.width / 2, 0);
    if (right) o = o - Offset(tp.width, 0);
    tp.paint(c, o);
  }

  Path _smooth(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final mx = (a.dx + b.dx) / 2;
      p.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final plot = Rect.fromLTRB(leftPad, topPad, size.width - rightPad, size.height - bottomPad);
    var maxV = 0.0, minV = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        maxV = math.max(maxV, v.toDouble());
        minV = math.min(minV, v.toDouble());
      }
    }
    final top = niceMax(maxV);
    final bottom = minV < 0 ? -niceMax(-minV) : 0.0;
    double y(num v) => plot.bottom - (v - bottom) / (top - bottom) * plot.height;
    double x(int i) => n <= 1 ? plot.center.dx : plot.left + i * plot.width / (n - 1);

    // grid + axis labels
    final grid = Paint()
      ..color = const Color(0xFFEDEEF6)
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final v = bottom + (top - bottom) * g / 4;
      final gy = y(v);
      canvas.drawLine(Offset(plot.left, gy), Offset(plot.right, gy), grid);
      _text(canvas, Money.compact(v.round()), Offset(plot.left - 8, gy - 7), right: true, size: 9.5);
    }
    if (bottom < 0) {
      canvas.drawLine(Offset(plot.left, y(0)), Offset(plot.right, y(0)), grid..color = const Color(0xFFD5D8EA));
    }
    // x labels (thinned)
    final step = math.max(1, (n / 7).ceil());
    for (var i = 0; i < n; i += step) {
      _text(canvas, labels[i], Offset(x(i), plot.bottom + 8), center: true, size: 9.5);
    }
    if (n == 0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, plot.left + plot.width * t + 1, size.height));
    for (final s in series) {
      final pts = [for (var i = 0; i < n; i++) Offset(x(i), y(i < s.values.length ? s.values[i] : 0))];
      final line = pts.length == 1 ? (Path()..addOval(Rect.fromCircle(center: pts.first, radius: 2))) : _smooth(pts);
      if (s.area && pts.length > 1) {
        final area = Path.from(line)
          ..lineTo(pts.last.dx, y(math.max(0, bottom)))
          ..lineTo(pts.first.dx, y(math.max(0, bottom)))
          ..close();
        canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.color.withAlpha(0x55), s.color.withAlpha(0x00)],
              ).createShader(plot));
      }
      // soft glow under the stroke
      canvas.drawPath(
          line,
          Paint()
            ..color = s.color.withAlpha(0x33)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawPath(
          line,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round);
    }
    canvas.restore();

    // tooltip
    final i = touched;
    if (i != null && i < n && t > .99) {
      final tx = x(i);
      canvas.drawLine(Offset(tx, plot.top), Offset(tx, plot.bottom),
          Paint()
            ..color = const Color(0xFFB9B2F0)
            ..strokeWidth = 1.2);
      for (final s in series) {
        final v = i < s.values.length ? s.values[i] : 0;
        canvas.drawCircle(Offset(tx, y(v)), 5.5, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(tx, y(v)), 3.8, Paint()..color = s.color);
      }
      const boxW = 150.0;
      final boxH = 26.0 + series.length * 18;
      var bx = tx + 10;
      if (bx + boxW > size.width) bx = tx - boxW - 10;
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(bx, plot.top, boxW, boxH), const Radius.circular(12));
      canvas.drawRRect(box.shift(const Offset(0, 3)),
          Paint()
            ..color = const Color(0x332A2F7A)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawRRect(box, Paint()..color = const Color(0xFF14164A));
      _text(canvas, labels[i], Offset(bx + 12, plot.top + 8), color: Colors.white, size: 10.5, w: FontWeight.w700);
      for (var k = 0; k < series.length; k++) {
        final s = series[k];
        final v = i < s.values.length ? s.values[i] : 0;
        final ry = plot.top + 26 + k * 18;
        canvas.drawCircle(Offset(bx + 16, ry + 6), 4, Paint()..color = s.color);
        _text(canvas, s.name, Offset(bx + 26, ry), color: const Color(0xFFC9CBE6), size: 10);
        _text(canvas, Money.rs(v), Offset(bx + boxW - 12, ry), color: Colors.white, size: 10, right: true, w: FontWeight.w700);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

/// Donut chart with a centre label.
class DonutChart extends StatelessWidget {
  final List<MapEntry<String, int>> parts;
  final List<Color> colors;
  final double size;
  final String centerTop, centerBottom;
  const DonutChart({
    super.key,
    required this.parts,
    required this.colors,
    this.size = 150,
    required this.centerTop,
    required this.centerBottom,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _DonutPainter(parts, colors, t),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(centerTop,
                  style: const TextStyle(fontFamily: 'Jakarta', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0A0E26))),
              Text(centerBottom, style: const TextStyle(fontFamily: 'Jakarta', fontSize: 10.5, color: Color(0xFF6B7094))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, int>> parts;
  final List<Color> colors;
  final double t;
  _DonutPainter(this.parts, this.colors, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(rect, 0, math.pi * 2, false,
        Paint()
          ..color = const Color(0xFFF0F1F8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    final total = parts.fold<int>(0, (a, e) => a + math.max(0, e.value));
    if (total == 0) return;
    var start = -math.pi / 2;
    const gap = 0.035;
    for (var i = 0; i < parts.length; i++) {
      final v = math.max(0, parts[i].value);
      if (v == 0) continue;
      final sweep = (v / total) * math.pi * 2 * t;
      canvas.drawArc(
          rect,
          start + gap / 2,
          math.max(0.001, sweep - gap),
          false,
          Paint()
            ..color = colors[i % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}

/// Tiny sparkline for KPI tiles.
class Sparkline extends StatelessWidget {
  final List<int> values;
  final Color color;
  final double width, height;
  const Sparkline(this.values, this.color, {super.key, this.width = 64, this.height = 26});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: CustomPaint(painter: _SparkPainter(values, color)));
}

class _SparkPainter extends CustomPainter {
  final List<int> v;
  final Color color;
  _SparkPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final maxV = v.reduce(math.max).toDouble(), minV = v.reduce(math.min).toDouble();
    final span = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    final pts = [
      for (var i = 0; i < v.length; i++)
        Offset(i * size.width / (v.length - 1), size.height - 2 - (v[i] - minV) / span * (size.height - 4)),
    ];
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1], mx = (a.dx + b.dx) / 2;
      p.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(p)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withAlpha(0x40), color.withAlpha(0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v || old.color != color;
}
