// =============================================================================
// GameX Hisab — Liquid Glass bottom navigation
//
// Self-contained: this file owns the bottom bar's look and motion. Screens
// only use [LiquidGlassNav] and [LiquidGlassNav.outerHeight], so redesigning a
// page never changes the navigation bar.
//
// Look:   frosted lavender glass panel, specular top highlight, inner shading.
// Motion: a jelly glass bubble that stretches while it travels to the tapped
//         tab, overshoots, wobbles and settles; the icon pops with a bounce and
//         a soft ripple pulse; haptic tick on every tap.
// =============================================================================
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NavItem {
  final String label;
  final IconData? icon; // null → 3D cube glyph
  const NavItem(this.label, this.icon);
}

class LiquidGlassNav extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<NavItem> items;
  const LiquidGlassNav({super.key, required this.index, required this.onTap, this.items = defaultItems});

  static const defaultItems = [
    NavItem('Home', Icons.home_rounded),
    NavItem('Dashboard', Icons.pie_chart_rounded),
    NavItem('Products', null),
    NavItem('Menu', Icons.menu_rounded),
  ];

  // Geometry is defined against an 849 px-wide reference and scales with the
  // screen width, like the rest of the design.
  static double _u(BuildContext c) => MediaQuery.sizeOf(c).width / 849;
  static double barHeightOf(BuildContext c) => 118 * _u(c);
  static double bottomGapOf(BuildContext c) => 26 * _u(c);

  /// Total height the bar occupies from the bottom of the screen.
  static double outerHeight(double safeBottom, [BuildContext? context]) {
    final u = context == null ? _lastU : _u(context);
    return 118 * u + 26 * u + safeBottom;
  }

  static double _lastU = 393 / 849;

  @override
  State<LiquidGlassNav> createState() => _LiquidGlassNavState();
}

class _LiquidGlassNavState extends State<LiquidGlassNav> with TickerProviderStateMixin {
  late final AnimationController _move =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  static const _lavender = Color(0xFFEDE7FF);
  static const _active = Color(0xFF5B1FD9);
  static const _inactive = Color(0xFF3A4155);

  @override
  void didUpdateWidget(covariant LiquidGlassNav old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = _position; // start from wherever the bubble is right now
      _to = widget.index.toDouble();
      _move.forward(from: 0);
      _pulse.forward(from: 0);
    }
  }

  /// Current (possibly mid-flight) bubble position in tab units.
  double get _position {
    final t = const ElasticOutCurve(0.62).transform(_move.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _tap(int i) {
    HapticFeedback.selectionClick();
    if (i == widget.index) {
      _pulse.forward(from: 0); // a little "boing" when tapping the active tab
      return;
    }
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final u = LiquidGlassNav._u(context);
    LiquidGlassNav._lastU = u;
    final safe = MediaQuery.of(context).padding.bottom;
    final h = LiquidGlassNav.barHeightOf(context);
    final radius = BorderRadius.circular(46 * u);
    final n = widget.items.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(12 * u, 0, 12 * u, LiquidGlassNav.bottomGapOf(context) + safe),
      child: Container(
        height: h,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: Color(0x332A2F7A), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -8),
            BoxShadow(color: Color(0x1A5B1FD9), blurRadius: 18, offset: Offset(0, 4), spreadRadius: -6),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xE6FFFFFF), Color(0xD1F6F2FF), Color(0xC7EEE8FF)],
                ),
                border: Border.all(color: const Color(0xF2FFFFFF), width: 1.4),
              ),
              child: LayoutBuilder(builder: (context, c) {
                final slot = c.maxWidth / n;
                return AnimatedBuilder(
                  animation: Listenable.merge([_move, _pulse]),
                  builder: (context, _) {
                    final pos = _position;
                    // jelly: stretch while travelling, squash vertically, wobble
                    final double travel = math.sin(math.pi * _move.value.clamp(0.0, 1.0)) * (_to - _from).abs().clamp(0.0, 1.6).toDouble();
                    final pulse = math.sin(math.pi * _pulse.value);
                    final stretchX = 1 + 0.42 * travel + 0.06 * pulse;
                    final squashY = 1 - 0.14 * travel + 0.05 * pulse;
                    final bubbleW = (slot - 34 * u) * stretchX;
                    final bubbleH = (h - 22 * u) * squashY;
                    final cx = slot * (pos + .5);
                    return Stack(clipBehavior: Clip.none, children: [
                      // specular highlight along the top edge
                      Positioned(
                        left: 34 * u,
                        right: 34 * u,
                        top: 0,
                        height: 30 * u,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30 * u)),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xF2FFFFFF), Color(0x00FFFFFF)],
                            ),
                          ),
                        ),
                      ),
                      // jelly glass bubble
                      Positioned(
                        left: cx - bubbleW / 2,
                        top: (h - bubbleH) / 2 - 2 * u,
                        width: bubbleW,
                        height: bubbleH,
                        child: _Bubble(radius: 30 * u, pulse: pulse),
                      ),
                      // liquid underline that trails the bubble
                      Positioned(
                        left: cx - bubbleW * .36,
                        width: bubbleW * .72,
                        bottom: 4 * u,
                        height: 6 * u,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4 * u),
                            gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF5B1FD9), Color(0xFF3D8BFF)]),
                            boxShadow: const [BoxShadow(color: Color(0x805B1FD9), blurRadius: 8, offset: Offset(0, 2))],
                          ),
                        ),
                      ),
                      Row(children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _tap(i),
                              child: _NavButton(
                                item: widget.items[i],
                                // how "selected" this tab is right now (0..1) — colours blend while the bubble moves
                                focus: (1 - (pos - i).abs()).clamp(0.0, 1.0).toDouble(),
                                active: i == widget.index,
                                pulse: i == widget.index ? pulse : 0,
                                u: u,
                              ),
                            ),
                          ),
                      ]),
                    ]);
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass "jelly" lens behind the active tab.
class _Bubble extends StatelessWidget {
  final double radius, pulse;
  const _Bubble({required this.radius, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6F2FF), _LiquidGlassNavState._lavender, Color(0xFFDCD0FF)],
        ),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0x40 + 0x30 * pulse).round(), 0x5B, 0x1F, 0xD9),
            blurRadius: 16 + 8 * pulse,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(children: [
          // glossy top half
          Positioned(
            left: 6,
            right: 6,
            top: 2,
            height: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
          // inner bottom shade gives the jelly some depth
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 14,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00B9A5FF), Color(0x40B9A5FF)],
                ),
              ),
            ),
          ),
          // specular dot
          Positioned(
            right: 10,
            top: 6,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xE6FFFFFF)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;
  final double focus, pulse, u;
  final bool active;
  const _NavButton({required this.item, required this.focus, required this.active, required this.pulse, required this.u});

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(_LiquidGlassNavState._inactive, _LiquidGlassNavState._active, focus)!;
    final size = 46 * u;
    // bump: the icon lifts and grows as the bubble arrives, plus a pop on tap
    final scale = 1 + 0.10 * focus + 0.16 * pulse;
    final lift = -4 * u * focus - 3 * u * pulse;
    Widget icon = item.icon == null
        ? _Cube(size: size * .92, color: color, gradient: active)
        : Icon(item.icon, size: size, color: color);
    if (active && item.icon != null) {
      icon = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7A45F5), Color(0xFF4A17C9)],
        ).createShader(r),
        child: Icon(item.icon, size: size, color: Colors.white),
      );
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Transform.translate(offset: Offset(0, lift), child: Transform.scale(scale: scale, child: icon)),
      SizedBox(height: 8 * u),
      Text(
        item.label,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'Jakarta',
          fontSize: 9.3 * u * 849 / 393,
          height: 1.0,
          fontWeight: focus > .5 ? FontWeight.w700 : FontWeight.w600,
          fontVariations: [FontVariation('wght', focus > .5 ? 700 : 600)],
          color: color,
        ),
      ),
    ]);
  }
}

/// Isometric 3D cube glyph for "Products".
class _Cube extends StatelessWidget {
  final double size;
  final Color color;
  final bool gradient;
  const _Cube({required this.size, required this.color, required this.gradient});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _CubePainter(color, gradient)));
}

class _CubePainter extends CustomPainter {
  final Color color;
  final bool gradient;
  _CubePainter(this.color, this.gradient);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Path poly(List<double> p) {
      final path = Path()..moveTo(p[0] * w, p[1] * h);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i] * w, p[i + 1] * h);
      }
      return path..close();
    }

    Paint fill(double a) {
      final paint = Paint()..isAntiAlias = true;
      if (gradient) {
        paint.shader = const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF4A17C9)]).createShader(Offset.zero & s);
        paint.color = Color.fromARGB((a * 255).round(), 255, 255, 255);
      } else {
        paint.color = color.withAlpha((a * 255).round());
      }
      return paint;
    }

    canvas.drawPath(poly([.1, .35, .46, .55, .46, .94, .1, .74]), fill(.85));
    canvas.drawPath(poly([.9, .35, .54, .55, .54, .94, .9, .74]), fill(1));
    canvas.drawPath(poly([.5, .08, .9, .29, .5, .5, .1, .29]), fill(.6));
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) => old.color != color || old.gradient != gradient;
}
