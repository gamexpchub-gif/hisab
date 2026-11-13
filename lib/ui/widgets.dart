import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import 'theme.dart';

/// Loads data and reloads automatically whenever the books change.
class Live<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  /// When this value changes the data is reloaded, keeping the old data on
  /// screen until the new data arrives (no loading flash).
  final Object? reloadKey;
  const Live({super.key, required this.load, required this.builder, this.reloadKey});

  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
    Books.changes.addListener(_reload);
  }

  void _reload() {
    if (mounted) setState(() => _future = widget.load());
  }

  @override
  void didUpdateWidget(covariant Live<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _future = widget.load();
  }

  @override
  void dispose() {
    Books.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: ${snap.error}', style: const TextStyle(color: C.red)),
          );
        }
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

/// White rounded card with a soft shadow.
class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final double radius;
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(top: 14),
    this.onTap,
    this.gradient,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? C.surface : null,
        gradient: gradient,
        borderRadius: r,
        boxShadow: C.shadow,
        border: Border.all(color: const Color(0xFFF0F1F8)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: r, onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Frosted glass panel.
class Glass extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final EdgeInsetsGeometry padding;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradient = const LinearGradient(colors: [Color(0xF2FFFFFF), Color(0xE6F0EEFF), Color(0xBFCEBEFF)], stops: [0, .55, 1]),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: C.shadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xD9FFFFFF)),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Round pastel orb holding a gradient-tinted icon.
class Orb extends StatelessWidget {
  final IconData icon;
  final List<Color> colors; // icon gradient
  final List<Color> bg; // orb gradient
  final double size;
  const Orb({super.key, required this.icon, required this.colors, required this.bg, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: bg),
      ),
      child: ShaderMask(
        shaderCallback: (r) =>
            LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
        child: Icon(icon, color: Colors.white, size: size * 0.56, shadows: const [
          Shadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 3)),
        ]),
      ),
    );
  }
}

class Palette {
  final List<Color> icon, bg;
  const Palette(this.icon, this.bg);
  static const purple = Palette([Color(0xFFB58CFF), Color(0xFF7B3FF2)], [Color(0xFFF2EBFF), Color(0xFFDCCBFF)]);
  static const orange = Palette([Color(0xFFFFB547), Color(0xFFF08A24)], [Color(0xFFFFF4E2), Color(0xFFFFDDB0)]);
  static const blue = Palette([Color(0xFF6AA5FF), Color(0xFF1A47C8)], [Color(0xFFEAF1FF), Color(0xFFC9DAFF)]);
  static const green = Palette([Color(0xFF3EE08F), Color(0xFF0E9F5E)], [Color(0xFFE6FBF0), Color(0xFFBDF0D5)]);
  static const violet = Palette([Color(0xFFA47BFF), Color(0xFF6A35D9)], [Color(0xFFF0EBFF), Color(0xFFD6C8FF)]);
  static const teal = Palette([Color(0xFF4FD8E0), Color(0xFF139DB0)], [Color(0xFFE2FAFA), Color(0xFFB5EDEE)]);
  static const amber = Palette([Color(0xFFFFA24A), Color(0xFFF06A1A)], [Color(0xFFFFF1E0), Color(0xFFFFD3A3)]);
  static const pink = Palette([Color(0xFFFF5C7A), Color(0xFFD81E4A)], [Color(0xFFFFEAF0), Color(0xFFFFC9D6)]);
  static const red = Palette([Color(0xFFFF7A7A), Color(0xFFDC4545)], [Color(0xFFFFECEC), Color(0xFFFFC9C9)]);
}

/// Quick-action tile (icon orb + label).
class ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Palette palette;
  final VoidCallback onTap;
  const ActionTile({super.key, required this.label, required this.icon, required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CardBox(
      margin: EdgeInsets.zero,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Orb(icon: icon, colors: palette.icon, bg: palette.bg),
        const SizedBox(height: 9),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: C.ink)),
      ]),
    );
  }
}

/// Inner page scaffold with a round back button.
class PageShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? action;
  final Widget? fab;
  final bool showBack;
  const PageShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.action,
    this.fab,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: fab,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
          children: [
            Row(children: [
              if (showBack && Navigator.of(context).canPop())
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: RoundIcon(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: C.muted)),
                    ),
                ]),
              ),
              if (action != null) action!,
            ]),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class RoundIcon extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onTap;
  final double size;
  final int badge;
  const RoundIcon({super.key, this.icon, this.child, this.onTap, this.size = 44, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: C.shadow, color: Colors.white),
            child: Center(child: child ?? Icon(icon, color: C.ink, size: size * 0.5)),
          ),
        ),
      ),
      if (badge > 0)
        Positioned(
          top: -3,
          right: -3,
          child: Container(
            constraints: const BoxConstraints(minWidth: 21),
            height: 21,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8344E),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(badge > 99 ? '99+' : '$badge',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final Gradient gradient;
  final double fontSize;
  final EdgeInsets padding;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.expand = false,
    this.gradient = C.primaryGradient,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(999), boxShadow: C.fabShadow),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fontSize)),
              if (icon != null) ...[const SizedBox(width: 8), Icon(icon, color: Colors.white, size: fontSize + 4)],
            ]),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.icon, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (icon != null) ...[Icon(icon, color: C.purple2, size: 24), const SizedBox(width: 10)],
      Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
      if (actionLabel != null)
        InkWell(
          onTap: onAction,
          child: Row(children: [
            Text(actionLabel!, style: const TextStyle(color: C.blue2, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_rounded, color: C.blue2, size: 18),
          ]),
        ),
    ]);
  }
}

/// Standard list row: avatar, title/subtitle, trailing amount.
class ListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? trailingSub;
  final Color? trailingColor;
  final Color? trailingSubColor;
  final VoidCallback? onTap;
  const ListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingSub,
    this.trailingColor,
    this.trailingSubColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          if (trailing != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(trailing!, style: TextStyle(fontWeight: FontWeight.w700, color: trailingColor ?? C.ink)),
              if (trailingSub != null)
                Text(trailingSub!, style: TextStyle(fontSize: 12, color: trailingSubColor ?? C.muted)),
            ]),
        ]),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  const Avatar(this.text, {super.key, this.bg = const Color(0xFFEFEBFF), this.fg = C.purple2, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: fg, size: 22)
          : Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }
}

class Divided extends StatelessWidget {
  final List<Widget> children;
  const Divided(this.children, {super.key});

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(const Divider(height: 1, color: C.line));
      out.add(children[i]);
    }
    return Column(children: out);
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(children: [
        const Icon(Icons.inbox_rounded, size: 48, color: Color(0xFFB9BCD6)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
      ]),
    );
  }
}

class Kpi extends StatelessWidget {
  final String label;
  final int value;
  final bool accent;
  final Color? color;
  const Kpi(this.label, this.value, {super.key, this.accent = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent ? null : Colors.white,
        gradient: accent ? const LinearGradient(colors: [Color(0xFF5B2EE0), Color(0xFF3155C8)]) : null,
        borderRadius: BorderRadius.circular(18),
        boxShadow: C.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: accent ? const Color(0xCCFFFFFF) : C.muted)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(Money.rs(value),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: accent ? Colors.white : (color ?? C.ink))),
        ),
      ]),
    );
  }
}

class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  const KpiGrid(this.children, {super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(child: children[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Column(children: rows);
  }
}

class TotalLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const TotalLine(this.label, this.value, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontSize: bold ? 18 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Expanded(child: Text(label, style: st)), Text(value, style: st)]),
    );
  }
}

/// GameX logo tile (from the reference design).
class LogoTile extends StatelessWidget {
  final double size;
  const LogoTile({super.key, this.size = 62});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2),
        boxShadow: const [BoxShadow(color: Color(0x661B1F4B), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -6)],
      ),
      child: Image.asset('assets/home/logo.png', width: size, height: size, fit: BoxFit.fill),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? C.red : C.green,
  ));
}

Future<T?> open<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Isometric 3D cube icon (top face lighter, sides shaded) — the Products glyph.
class CubeIcon extends StatelessWidget {
  final double size;
  final Color color;
  final Gradient? gradient;
  const CubeIcon({super.key, required this.size, required this.color, this.gradient});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _CubePainter(color, gradient)));
}

class _CubePainter extends CustomPainter {
  final Color color;
  final Gradient? gradient;
  _CubePainter(this.color, this.gradient);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final top = Path()
      ..moveTo(w * .5, h * .08)
      ..lineTo(w * .9, h * .29)
      ..lineTo(w * .5, h * .5)
      ..lineTo(w * .1, h * .29)
      ..close();
    final left = Path()
      ..moveTo(w * .1, h * .35)
      ..lineTo(w * .46, h * .55)
      ..lineTo(w * .46, h * .94)
      ..lineTo(w * .1, h * .74)
      ..close();
    final right = Path()
      ..moveTo(w * .9, h * .35)
      ..lineTo(w * .54, h * .55)
      ..lineTo(w * .54, h * .94)
      ..lineTo(w * .9, h * .74)
      ..close();
    Paint paint(double alpha) {
      final p = Paint()..isAntiAlias = true;
      if (gradient != null) {
        p.shader = gradient!.createShader(Offset.zero & s);
        p.color = Colors.white.withAlpha((alpha * 255).round());
      } else {
        p.color = color.withAlpha((alpha * 255).round());
      }
      return p;
    }

    canvas.drawPath(left, paint(.85));
    canvas.drawPath(right, paint(1));
    canvas.drawPath(top, paint(.6));
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) => old.color != color || old.gradient != gradient;
}

/// Red "are you sure" dialog for deletes. Returns true when confirmed.
Future<bool> confirmDelete(BuildContext context, String title, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC4545), size: 42),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC4545)),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Runs a delete with confirmation; shows the result and pops the page when
/// [popAfter] is set.
Future<void> runDelete(BuildContext context,
    {required String title, required String message, required Future<void> Function() action, bool popAfter = true}) async {
  if (!await confirmDelete(context, title, message)) return;
  try {
    await action();
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    toast(context, 'Deleted');
    if (popAfter) Navigator.of(context).pop();
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}
