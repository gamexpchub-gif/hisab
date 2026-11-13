import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/lock.dart';
import '../ui/widgets.dart';

// =============================================================================
// App lock — a glass lock screen with a PIN pad and fingerprint, a gate that
// locks the app on start and after it has been in the background, and the
// Security settings page (set / change / remove PIN, fingerprint, auto-lock).
// =============================================================================

const _navy = Color(0xFF0B0F5E);
const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _bg = Color(0xFFF6F7FC);

TextStyle _j(double size, FontWeight w, Color c, {double? spacing}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      letterSpacing: spacing,
    );

/// Number pad with PIN dots. [onDone] gets the PIN once [length] digits are in.
class PinPad extends StatefulWidget {
  final String title, subtitle;
  final int length;
  final Future<bool> Function(String pin) onDone;
  final VoidCallback? onBiometric;
  final bool dark;
  const PinPad({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onDone,
    this.length = 4,
    this.onBiometric,
    this.dark = true,
  });
  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String pin = '';
  bool busy = false;
  late final shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  void clear() => setState(() => pin = '');

  Future<void> _tap(String d) async {
    if (busy || pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => pin += d);
    if (pin.length == widget.length) {
      busy = true;
      final ok = await widget.onDone(pin);
      busy = false;
      if (!mounted) return;
      if (!ok) {
        HapticFeedback.heavyImpact();
        shake.forward(from: 0);
        await Future<void>.delayed(const Duration(milliseconds: 380));
      }
      if (mounted) setState(() => pin = '');
    }
  }

  void _back() {
    if (pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? Colors.white : _ink;
    final sub = widget.dark ? const Color(0xCCFFFFFF) : _muted;
    Widget key(Widget child, VoidCallback? onTap, {bool plain = false}) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: plain
                ? null
                : BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.dark ? const Color(0x1FFFFFFF) : Colors.white,
                    border: Border.all(color: widget.dark ? const Color(0x40FFFFFF) : const Color(0xFFE6E8F4)),
                    boxShadow: widget.dark
                        ? null
                        : const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
                  ),
            child: child,
          ),
        );
    Widget digit(String d) => key(Text(d, style: _j(28, FontWeight.w600, fg)), () => _tap(d));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, style: _j(22, FontWeight.w800, fg)),
      const SizedBox(height: 6),
      Text(widget.subtitle, textAlign: TextAlign.center, style: _j(13, FontWeight.w500, sub)),
      const SizedBox(height: 26),
      AnimatedBuilder(
        animation: shake,
        builder: (context, child) => Transform.translate(
          offset: Offset(math.sin(shake.value * math.pi * 6) * 12 * (1 - shake.value), 0),
          child: child,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < widget.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 9),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < pin.length ? fg : Colors.transparent,
                border: Border.all(color: fg.withAlpha(0xAA), width: 1.6),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 34),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final d in row) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: digit(d)),
          ]),
        ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: widget.onBiometric == null
              ? const SizedBox(width: 74, height: 74)
              : key(Icon(Icons.fingerprint_rounded, color: fg, size: 34), widget.onBiometric, plain: true),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: digit('0')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: key(Icon(Icons.backspace_outlined, color: fg, size: 26), _back, plain: true),
        ),
      ]),
    ]);
  }
}

/// Full-screen lock shown over the app.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool bio = false;
  int wrong = 0;
  DateTime? coolUntil;
  Timer? tick;
  String shop = 'GameX Hisab';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final s = await Books.settings();
    final on = s['lock_bio'] == '1' && await AppLock.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      bio = on;
      shop = (s['business_name'] ?? '').trim().isEmpty ? 'GameX Hisab' : s['business_name']!.trim();
    });
    if (on) _bio();
  }

  Future<void> _bio() async {
    if (await AppLock.authenticate() && mounted) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
    }
  }

  Future<bool> _pin(String pin) async {
    if (coolUntil != null && DateTime.now().isBefore(coolUntil!)) return false;
    if (await AppLock.check(pin)) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
      return true;
    }
    wrong++;
    if (wrong >= 5) {
      wrong = 0;
      coolUntil = DateTime.now().add(const Duration(seconds: 30));
      tick?.cancel();
      tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (DateTime.now().isAfter(coolUntil!)) {
          t.cancel();
          coolUntil = null;
        }
        setState(() {});
      });
    }
    setState(() {});
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cooling = coolUntil != null && DateTime.now().isBefore(coolUntil!);
    final left = cooling ? coolUntil!.difference(DateTime.now()).inSeconds + 1 : 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2163), Color(0xFF3A2BC9), Color(0xFF6A2FF0)],
            ),
          ),
          child: Stack(children: [
            Positioned(
              right: -80,
              top: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
              ),
            ),
            Positioned(
              left: -100,
              bottom: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x332F55E8), Color(0x002F55E8)])),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
                        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -8)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset('assets/home/logo.png', fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 12),
                    Text(shop, style: _j(14, FontWeight.w700, const Color(0xDDFFFFFF), spacing: .4)),
                    const SizedBox(height: 26),
                    PinPad(
                      title: cooling ? 'Too many tries' : 'Enter PIN',
                      subtitle: cooling
                          ? 'Try again in $left s'
                          : wrong > 0
                              ? 'Wrong PIN · ${5 - wrong} tries left'
                              : 'Your books are locked',
                      onDone: _pin,
                      onBiometric: bio ? _bio : null,
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Locks the app on start and after [AppLock.lockAfter] seconds away.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool? locked; // null while checking
  DateTime? leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.enabled().then((on) {
      if (mounted) setState(() => locked = on);
    }).catchError((_) {
      if (mounted) setState(() => locked = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = leftAt == null ? 0 : DateTime.now().difference(leftAt!).inSeconds;
      leftAt = null;
      if (locked == true) return;
      Future.wait([AppLock.enabled(), AppLock.lockAfter()]).then((r) {
        if (mounted && r[0] == true && away >= (r[1] as int)) setState(() => locked = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (locked == null) return const Scaffold(backgroundColor: Color(0xFF1B2163));
    return Stack(children: [
      widget.child,
      if (locked!)
        Positioned.fill(
          child: LockScreen(onUnlocked: () => setState(() => locked = false)),
        ),
    ]);
  }
}

// =============================================================================
// Settings → Security
// =============================================================================
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool on = false, bio = false, bioAvailable = false;
  int after = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await AppLock.enabled();
    final b = await AppLock.biometricOn();
    final a = await AppLock.lockAfter();
    final av = await AppLock.canUseBiometrics();
    if (mounted) {
      setState(() {
        on = e;
        bio = b;
        after = a;
        bioAvailable = av;
      });
    }
  }

  /// Asks for a new PIN twice. Returns it, or null when cancelled.
  Future<String?> _newPin() async {
    String? first;
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (ctx) => _PinPage(
        title: 'Set a PIN',
        subtitle: 'Choose 4 digits you will remember',
        onDone: (pin, page) async {
          if (first == null) {
            first = pin;
            page.retitle('Confirm PIN', 'Enter the same 4 digits again');
            return true;
          }
          if (pin == first) {
            Navigator.of(ctx).pop(pin);
            return true;
          }
          first = null;
          page.retitle('Set a PIN', "PINs didn't match — start again");
          return false;
        },
      ),
    ));
    return r;
  }

  Future<bool> _verify() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (ctx) => _PinPage(
        title: 'Current PIN',
        subtitle: 'Enter your PIN to continue',
        onDone: (pin, page) async {
          if (await AppLock.check(pin)) {
            if (ctx.mounted) Navigator.of(ctx).pop(true);
            return true;
          }
          return false;
        },
      ),
    ));
    return ok == true;
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      final pin = await _newPin();
      if (pin == null) return;
      await AppLock.setPin(pin);
      if (bioAvailable) await Books.setSetting('lock_bio', '1');
      if (mounted) toast(context, 'App lock is on');
    } else {
      if (!await _verify()) return;
      await AppLock.disable();
      if (mounted) toast(context, 'App lock removed');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String s, Widget trailing, {List<Color> colors = const [Color(0xFF6B35EE), Color(0xFF4318D2)]}) =>
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFEEF0F8)),
            boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6)],
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: colors)),
              child: Icon(i, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: _j(14.5, FontWeight.w800, _ink)),
                const SizedBox(height: 2),
                Text(s, style: _j(11.5, FontWeight.w500, _muted)),
              ]),
            ),
            trailing,
          ]),
        );
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
                ),
                child: const Icon(Icons.arrow_back_rounded, color: _ink),
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Security', style: _j(22, FontWeight.w800, _navy)),
              Text('App lock · PIN · fingerprint', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: on
                    ? const [Color(0xFF0F9F6E), Color(0xFF0B7A55), Color(0xFF14532D)]
                    : const [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)],
              ),
              boxShadow: const [BoxShadow(color: Color(0x554A17C9), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -10)],
            ),
            child: Row(children: [
              Icon(on ? Icons.verified_user_rounded : Icons.shield_outlined, color: Colors.white, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(on ? 'Your books are protected' : 'App lock is off', style: _j(17, FontWeight.w800, Colors.white)),
                  const SizedBox(height: 3),
                  Text(
                    on
                        ? 'PIN${bio ? ' + fingerprint' : ''} · locks ${after == 0 ? 'immediately' : 'after ${after < 60 ? '$after s' : '${after ~/ 60} min'}'} away'
                        : 'Anyone holding the phone can see sales, dues and profit',
                    style: _j(12, FontWeight.w600, const Color(0xDDFFFFFF)),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          tile(Icons.lock_rounded, 'App lock', 'Ask for PIN when the app opens', Switch(value: on, onChanged: _toggle)),
          if (on) ...[
            tile(
              Icons.fingerprint_rounded,
              'Fingerprint / face unlock',
              bioAvailable ? 'Unlock without typing the PIN' : 'No fingerprint set up on this phone',
              Switch(
                value: bio && bioAvailable,
                onChanged: !bioAvailable
                    ? null
                    : (v) async {
                        if (v && !await AppLock.authenticate()) return;
                        await Books.setSetting('lock_bio', v ? '1' : '0');
                        await _load();
                      },
              ),
              colors: const [Color(0xFF38BDF8), Color(0xFF2563EB)],
            ),
            tile(
              Icons.timer_rounded,
              'Auto-lock',
              'Lock again after the app is in the background',
              const SizedBox.shrink(),
              colors: const [Color(0xFFFFA24A), Color(0xFFF06A1A)],
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in [(0, 'Immediately'), (30, '30 sec'), (60, '1 min'), (300, '5 min'), (900, '15 min')])
                ChoiceChip(
                  label: Text(s.$2),
                  selected: after == s.$1,
                  onSelected: (_) async {
                    await Books.setSetting('lock_after', '${s.$1}');
                    await _load();
                  },
                ),
            ]),
            const SizedBox(height: 14),
            tile(
              Icons.password_rounded,
              'Change PIN',
              'Enter your current PIN, then a new one',
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () async {
                  if (!await _verify()) return;
                  final pin = await _newPin();
                  if (pin == null) return;
                  await AppLock.setPin(pin);
                  if (mounted) toast(context, 'PIN changed');
                },
              ),
              colors: const [Color(0xFF94A3B8), Color(0xFF475569)],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'The PIN is stored only as a secure hash on this phone. If you forget it, reinstalling the app clears the lock '
            'and the data — keep a backup.',
            style: _j(11.5, FontWeight.w500, _muted),
          ),
        ]),
      ),
    );
  }
}

class _PinPage extends StatefulWidget {
  final String title, subtitle;
  final Future<bool> Function(String pin, _PinPageState page) onDone;
  const _PinPage({required this.title, required this.subtitle, required this.onDone});
  @override
  State<_PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<_PinPage> {
  late String title = widget.title, subtitle = widget.subtitle;

  void retitle(String t, String s) => setState(() {
        title = t;
        subtitle = s;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            dark: false,
            title: title,
            subtitle: subtitle,
            onDone: (pin) => widget.onDone(pin, this),
          ),
        ),
      ),
    );
  }
}
