import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hand-drawn 3D-style illustrations (no image assets needed).
/// Each painter draws in a fixed design box and is scaled to fit.
enum ArtKind { cart, box, calendar, moneyBag, hero, rocket, bars, logo }

class Art extends StatelessWidget {
  final ArtKind kind;
  final double width;
  final double? height;
  const Art(this.kind, {super.key, required this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final box = _box(kind);
    final h = height ?? width * box.height / box.width;
    return SizedBox(width: width, height: h, child: CustomPaint(painter: _ArtPainter(kind, box)));
  }

  static Size _box(ArtKind k) {
    switch (k) {
      case ArtKind.hero:
        return const Size(220, 140);
      case ArtKind.bars:
        return const Size(100, 90);
      default:
        return const Size(100, 100);
    }
  }
}

class _ArtPainter extends CustomPainter {
  final ArtKind kind;
  final Size box;
  _ArtPainter(this.kind, this.box);

  Paint fill(Color c) => Paint()..color = c;

  Paint grad(Rect r, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter}) =>
      Paint()..shader = LinearGradient(colors: colors, begin: begin, end: end).createShader(r);

  Path poly(List<double> pts) {
    final p = Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i < pts.length; i += 2) {
      p.lineTo(pts[i], pts[i + 1]);
    }
    return p..close();
  }

  void text(Canvas c, String s, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / box.width, size.height / box.height);
    canvas.save();
    canvas.translate((size.width - box.width * s) / 2, (size.height - box.height * s) / 2);
    canvas.scale(s);
    switch (kind) {
      case ArtKind.cart:
        _cart(canvas);
        break;
      case ArtKind.box:
        _boxArt(canvas);
        break;
      case ArtKind.calendar:
        _calendar(canvas);
        break;
      case ArtKind.moneyBag:
        _bag(canvas);
        break;
      case ArtKind.hero:
        _hero(canvas);
        break;
      case ArtKind.rocket:
        _rocket(canvas);
        break;
      case ArtKind.bars:
        _bars(canvas);
        break;
      case ArtKind.logo:
        _logo(canvas);
        break;
    }
    canvas.restore();
  }

  void _shadow(Canvas c, Rect r) {
    c.drawOval(r, Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  }

  void _cart(Canvas c) {
    _shadow(c, const Rect.fromLTWH(22, 86, 64, 8));
    final handle = Path()
      ..moveTo(8, 18)
      ..lineTo(20, 18)
      ..lineTo(32, 68)
      ..lineTo(80, 68);
    c.drawPath(
        handle,
        grad(const Rect.fromLTWH(0, 0, 100, 100), const [Color(0xFF1FC777), Color(0xFF077A45)])
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    final basket = poly([24, 28, 90, 28, 82, 60, 31, 60]);
    c.drawPath(basket, grad(const Rect.fromLTWH(24, 28, 66, 32), const [Color(0xFF3EE08F), Color(0xFF0E9F5E)]));
    c.drawPath(poly([24, 28, 90, 28, 88, 36, 26, 36]), fill(const Color(0x59FFFFFF)));
    final wire = Paint()
      ..color = const Color(0xFF0B7C47)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final l in [
      [40.0, 30.0, 43.0, 58.0],
      [54.0, 30.0, 54.0, 58.0],
      [68.0, 30.0, 66.0, 58.0],
      [28.0, 40.0, 86.0, 40.0],
      [30.0, 50.0, 83.0, 50.0],
    ]) {
      c.drawLine(Offset(l[0], l[1]), Offset(l[2], l[3]), wire);
    }
    for (final x in [38.0, 74.0]) {
      c.drawCircle(Offset(x, 80), 8, fill(const Color(0xFF0A6E3F)));
      c.drawCircle(Offset(x, 80), 3.5, fill(const Color(0xFFB6F5D3)));
    }
  }

  void _boxArt(Canvas c) {
    _shadow(c, const Rect.fromLTWH(14, 84, 74, 10));
    const r = Rect.fromLTWH(0, 0, 100, 100);
    c.drawPath(poly([50, 14, 88, 30, 50, 46, 12, 30]),
        grad(r, const [Color(0xFFC3A8FF), Color(0xFF9A72F5)], begin: Alignment.topLeft, end: Alignment.bottomRight));
    c.drawPath(poly([12, 30, 50, 46, 50, 90, 12, 74]), grad(r, const [Color(0xFF8B5CF6), Color(0xFF6034D4)]));
    c.drawPath(poly([88, 30, 50, 46, 50, 90, 88, 74]), grad(r, const [Color(0xFF7044D8), Color(0xFF4A22A8)]));
    c.drawPath(poly([31, 22, 69, 38, 69, 50, 61, 53, 61, 41, 23, 25]), fill(const Color(0xFFEDE5FF)));
    c.drawPath(poly([61, 41, 61, 53, 69, 50, 69, 38]), fill(const Color(0xFFCDBBFF)));
    c.drawPath(poly([66, 66, 80, 60, 80, 66, 66, 72]), fill(const Color(0x99E9E0FF)));
  }

  void _calendar(Canvas c) {
    _shadow(c, const Rect.fromLTWH(16, 86, 70, 8));
    c.drawRRect(RRect.fromLTRBR(12, 20, 88, 90, const Radius.circular(12)),
        grad(const Rect.fromLTWH(12, 20, 76, 70), const [Color(0xFF5AA2FF), Color(0xFF2463EB)]));
    c.drawRRect(RRect.fromLTRBAndCorners(12, 20, 88, 40, topLeft: const Radius.circular(12), topRight: const Radius.circular(12)),
        grad(const Rect.fromLTWH(12, 20, 76, 20), const [Color(0xFF2F7BFF), Color(0xFF1747C9)]));
    for (final x in [28.0, 64.0]) {
      c.drawRRect(RRect.fromLTRBR(x, 10, x + 8, 30, const Radius.circular(4)), fill(const Color(0xFFDCE8FF)));
    }
    for (final y in [48.0, 66.0]) {
      for (final x in [22.0, 43.0, 64.0]) {
        c.drawRRect(RRect.fromLTRBR(x, y, x + 14, y + 11, const Radius.circular(3)),
            fill(x == 43 && y == 66 ? Colors.white : const Color(0xFFEAF2FF)));
      }
    }
  }

  void _bag(Canvas c) {
    _shadow(c, const Rect.fromLTWH(18, 86, 66, 9));
    c.drawPath(poly([36, 10, 64, 10, 58, 24, 42, 24]), fill(const Color(0xFFE59D1C)));
    final body = Path()
      ..moveTo(42, 27)
      ..cubicTo(18, 38, 12, 60, 16, 74)
      ..cubicTo(20, 87, 34, 92, 50, 92)
      ..cubicTo(66, 92, 80, 87, 84, 74)
      ..cubicTo(88, 60, 82, 38, 58, 27)
      ..close();
    c.drawPath(
        body,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.3),
            radius: 0.9,
            colors: [Color(0xFFFFE08A), Color(0xFFF2B233), Color(0xFFC8820E)],
          ).createShader(const Rect.fromLTWH(14, 27, 72, 65)));
    c.drawLine(const Offset(38, 25), const Offset(62, 25), Paint()
      ..color = const Color(0xFFA8650A)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round);
    final shine = Path()
      ..moveTo(28, 44)
      ..quadraticBezierTo(20, 56, 22, 70);
    c.drawPath(shine, Paint()
      ..color = const Color(0x73FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round);
    text(c, '₹', const Offset(51, 62), 32, Colors.white);
  }

  void _hero(Canvas c) {
    _shadow(c, const Rect.fromLTWH(10, 118, 200, 14));
    // laptop
    c.drawPath(poly([18, 18, 120, 8, 126, 96, 22, 104]), fill(const Color(0xFF151827)));
    c.drawPath(
        poly([23, 22, 116, 13, 121, 92, 26, 99]),
        grad(const Rect.fromLTWH(23, 13, 98, 86),
            const [Color(0xFF2A1B6B), Color(0xFF5B3BE8), Color(0xFFC04BFF), Color(0xFF1B1050)],
            begin: Alignment.topLeft, end: Alignment.bottomRight));
    final swirl = Path()
      ..moveTo(30, 70)
      ..quadraticBezierTo(60, 30, 116, 40);
    c.drawPath(swirl, Paint()
      ..color = const Color(0x40FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);
    c.drawPath(poly([6, 106, 122, 97, 144, 111, 16, 122]),
        grad(const Rect.fromLTWH(6, 97, 138, 25), const [Color(0xFFEDEFF7), Color(0xFFAEB3C7)]));
    c.drawPath(poly([50, 108, 90, 105, 94, 108, 53, 111]), fill(const Color(0xFF9AA0B8)));
    // back phone (lavender)
    c.save();
    c.translate(160, 70);
    c.rotate(6 * math.pi / 180);
    c.drawRRect(RRect.fromLTRBR(-22, -48, 22, 48, const Radius.circular(9)),
        grad(const Rect.fromLTWH(-22, -48, 44, 96), const [Color(0xFFC8B8FF), Color(0xFF7E66E8)],
            begin: Alignment.topLeft, end: Alignment.bottomRight));
    c.drawRRect(RRect.fromLTRBR(-17, -42, 3, -20, const Radius.circular(6)), fill(const Color(0xFFADA0E8)));
    for (final o in [const Offset(-11, -36), const Offset(-3, -36), const Offset(-11, -27)]) {
      c.drawCircle(o, 4, fill(const Color(0xFF1B1D2E)));
    }
    c.restore();
    // front phone
    c.save();
    c.translate(196, 60);
    c.rotate(8 * math.pi / 180);
    c.drawRRect(RRect.fromLTRBR(-20, -46, 20, 46, const Radius.circular(9)), fill(const Color(0xFF141522)));
    c.drawRRect(
        RRect.fromLTRBR(-17, -42, 17, 42, const Radius.circular(7)),
        grad(const Rect.fromLTWH(-17, -42, 34, 84), const [Color(0xFF3B2A9E), Color(0xFF7B4DFF), Color(0xFF160C45)],
            begin: Alignment.topLeft, end: Alignment.bottomRight));
    c.restore();
  }

  void _rocket(Canvas c) {
    final flame = Path()
      ..moveTo(30, 70)
      ..cubicTo(22, 74, 16, 84, 16, 92)
      ..cubicTo(24, 92, 34, 86, 38, 78)
      ..close();
    c.drawPath(flame, fill(const Color(0xFFFFB020)));
    final flame2 = Path()
      ..moveTo(30, 72)
      ..cubicTo(26, 75, 23, 81, 23, 85)
      ..cubicTo(27, 85, 33, 82, 36, 78)
      ..close();
    c.drawPath(flame2, fill(const Color(0xFFFF5A3C)));
    c.drawPath(poly([36, 64, 24, 60, 34, 44, 48, 46]), fill(const Color(0xFFE8344E)));
    c.drawPath(poly([36, 64, 40, 76, 56, 66, 54, 52]), fill(const Color(0xFFC21F3A)));
    final body = Path()
      ..moveTo(36, 64)
      ..cubicTo(48, 36, 66, 18, 88, 12)
      ..cubicTo(82, 34, 64, 52, 36, 64)
      ..close();
    c.drawPath(body, grad(const Rect.fromLTWH(36, 12, 52, 52), const [Colors.white, Color(0xFFC9CFE6)],
        begin: Alignment.topLeft, end: Alignment.bottomRight));
    c.drawPath(poly([78, 12, 88, 12, 88, 22]), fill(const Color(0xFFE8344E)));
    c.drawCircle(const Offset(62, 38), 9, fill(Colors.white));
    c.drawCircle(const Offset(62, 38), 6, fill(const Color(0xFF2F6BFF)));
  }

  void _bars(Canvas c) {
    final r = const Rect.fromLTWH(0, 20, 100, 70);
    final p = grad(r, const [Color(0xFF6B7BFF), Color(0xFF3D2BD8)]);
    final hs = [22.0, 34.0, 46.0, 62.0];
    for (var i = 0; i < 4; i++) {
      final x = 6.0 + i * 22;
      c.drawRRect(RRect.fromLTRBR(x, 84 - hs[i], x + 14, 84, const Radius.circular(4)), p);
    }
    final line = Path()
      ..moveTo(6, 52)
      ..quadraticBezierTo(46, 40, 84, 10);
    final stroke = Paint()
      ..color = C2.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(line, stroke);
    final head = Path()
      ..moveTo(72, 8)
      ..lineTo(86, 8)
      ..lineTo(84, 21);
    c.drawPath(head, stroke);
  }

  void _logo(Canvas c) {
    final rect = Rect.fromCircle(center: const Offset(50, 50), radius: 30);
    final p = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4FC3FF), Color(0xFF7B5CFF), Color(0xFFE040FB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    c.drawArc(rect, -0.7, -4.9, false, p);
    final bar = Path()
      ..moveTo(52, 52)
      ..lineTo(80, 52)
      ..lineTo(80, 62);
    c.drawPath(bar, p..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => old.kind != kind;
}

class C2 {
  static const blue = Color(0xFF2F6BFF);
}
