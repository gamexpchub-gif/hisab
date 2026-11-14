import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/imei_smart.dart';

/// Full-screen barcode / QR / IMEI scanner. Pops with the scanned text.
///
/// - The camera fills the whole screen; the scan frame sits in the middle.
/// - HD camera stream so the thin, dense IMEI barcodes on boxes are read.
/// - Pinch or slide to zoom, tap to focus, torch, front/back camera.
/// - A box usually has several barcodes (IMEI 1, IMEI 2, EAN): when more
///   than one is seen, each is listed with its type so the right one is
///   picked; a single code is taken at once.
class BarcodeScannerScreen extends StatefulWidget {
  final String title;

  /// Batch mode: every code is handed to [onCode] and the camera keeps
  /// scanning. [onCode] returns what was done ("iPhone 15 added") or null
  /// when the code matched nothing.
  final Future<String?> Function(String code)? onCode;
  const BarcodeScannerScreen({super.key, this.title = 'Scan barcode', this.onCode});

  /// Keeps scanning until Done; returns how many codes were used.
  static Future<int> scanMany(BuildContext context,
          {String title = 'Batch scan', required Future<String?> Function(String code) onCode}) async =>
      await Navigator.of(context)
          .push<int>(MaterialPageRoute(builder: (_) => BarcodeScannerScreen(title: title, onCode: onCode))) ??
      0;

  static Future<String?> scan(BuildContext context, {String title = 'Scan barcode'}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BarcodeScannerScreen(title: title)));

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> with SingleTickerProviderStateMixin {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 350,
    cameraResolution: const Size(1920, 1080),
    autoZoom: true,
  );
  late final AnimationController laser = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  bool torch = false;
  bool done = false;
  double zoom = 0;
  double _pinchStart = 0;

  /// Codes seen recently: value → (format, last seen).
  final seen = <String, (BarcodeFormat, DateTime)>{};
  Timer? settle;

  // batch mode
  bool get batch => widget.onCode != null;
  bool busy = false;
  int count = 0;
  final recent = <String, DateTime>{}; // code → when used (no double scans)
  final log = <(String, bool)>[]; // (message, ok) newest first

  @override
  void dispose() {
    settle?.cancel();
    laser.dispose();
    controller.dispose();
    super.dispose();
  }

  static void beep() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.heavyImpact();
  }

  void _finish(String code) {
    code = code.trim();
    if (done || code.isEmpty) return;
    if (batch) {
      _use(code);
      return;
    }
    done = true;
    beep();
    Navigator.of(context).pop(code);
  }

  Future<void> _use(String code) async {
    final last = recent[code];
    if (busy || (last != null && DateTime.now().difference(last).inMilliseconds < 2500)) {
      seen.clear();
      setState(() {});
      return;
    }
    busy = true;
    beep();
    String? msg;
    try {
      msg = await widget.onCode!(code);
    } catch (e) {
      msg = null;
    }
    if (!mounted) return;
    recent[code] = DateTime.now();
    seen.clear();
    setState(() {
      busy = false;
      if (msg != null) count++;
      log.insert(0, (msg ?? '$code — not found', msg != null));
      if (log.length > 4) log.removeLast();
    });
    if (msg == null) HapticFeedback.vibrate();
  }

  void _detect(BarcodeCapture capture) {
    if (done) return;
    final now = DateTime.now();
    var added = false;
    for (final b in capture.barcodes) {
      final v = (b.rawValue ?? '').trim();
      if (v.isEmpty) continue;
      if (batch && (busy || (recent[v] != null && now.difference(recent[v]!).inMilliseconds < 2500))) continue;
      if (!seen.containsKey(v)) added = true;
      seen[v] = (b.format, now);
    }
    if (!added) return;
    HapticFeedback.selectionClick();
    // wait a moment so every barcode on a box is collected, then decide
    settle?.cancel();
    settle = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || done) return;
      if (seen.length == 1) {
        _finish(seen.keys.first);
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  String _kind(String v, BarcodeFormat f) {
    final c = SmartImei.clean(v);
    if (SmartImei.looksLikeImei(c)) return SmartImei.luhn(c) ? 'IMEI ✓' : 'IMEI ?';
    if (f == BarcodeFormat.qrCode) return 'QR';
    if (f == BarcodeFormat.ean13 || f == BarcodeFormat.ean8 || f == BarcodeFormat.upcA || f == BarcodeFormat.upcE) return 'Box barcode';
    if (RegExp(r'^[A-Z0-9]{8,14}$').hasMatch(v)) return 'Serial / SN';
    return 'Code';
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Type the code'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword,
          decoration: const InputDecoration(hintText: 'Barcode / SKU / IMEI (*#06#)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Use code')),
        ],
      ),
    );
    if (r != null) _finish(r);
  }

  void _setZoom(double v) {
    zoom = v.clamp(0.0, 1.0).toDouble();
    controller.setZoomScale(zoom);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final frameW = w * .82;
          final frameH = frameW * .6;
          final frame = Rect.fromCenter(center: Offset(w / 2, h * .47), width: frameW, height: frameH);
          final codes = seen.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
          return GestureDetector(
            onScaleStart: (_) => _pinchStart = zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) return;
              _setZoom(_pinchStart + (d.scale - 1) * .5);
            },
            child: Stack(children: [
              // the camera fills the whole screen
              SizedBox(
                width: w,
                height: h,
                child: MobileScanner(
                  controller: controller,
                  fit: BoxFit.cover,
                  tapToFocus: true,
                  onDetect: _detect,
                ),
              ),
              Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FramePainter(frame, seen.isNotEmpty)))),
              // laser line inside the frame
              AnimatedBuilder(
                animation: laser,
                builder: (context, _) => Positioned(
                  left: frame.left + 16,
                  width: frame.width - 32,
                  top: frame.top + 12 + (frame.height - 24) * Curves.easeInOut.transform(laser.value),
                  height: 2.5,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(colors: [
                          const Color(0x007B5CFF),
                          seen.isNotEmpty ? const Color(0xFF34D399) : const Color(0xFF9F7BFF),
                          const Color(0x007B5CFF),
                        ]),
                        boxShadow: [
                          BoxShadow(
                              color: seen.isNotEmpty ? const Color(0xCC34D399) : const Color(0xCC7B5CFF), blurRadius: 12, spreadRadius: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // top bar
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(14, mq.padding.top + 10, 14, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA000000), Color(0x00000000)]),
                  ),
                  child: Row(children: [
                    _glassBtn(Icons.arrow_back_rounded, () => Navigator.of(context).pop(count)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Jakarta', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    _glassBtn(torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, () {
                      controller.toggleTorch();
                      setState(() => torch = !torch);
                    }),
                    const SizedBox(width: 10),
                    _glassBtn(Icons.cameraswitch_rounded, () => controller.switchCamera()),
                  ]),
                ),
              ),
              // hint under the frame
              Positioned(
                left: 24,
                right: 24,
                top: frame.bottom + 18,
                child: IgnorePointer(
                  child: Text(
                    busy
                        ? 'Adding…'
                        : seen.isEmpty
                        ? (batch
                            ? 'Batch mode · scan items one after another'
                            : 'Hold the barcode or IMEI label inside the frame · tap to focus · pinch to zoom')
                        : codes.length > 1
                            ? '${codes.length} codes found — tap the one you need'
                            : 'Reading…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Jakarta', color: Color(0xEEFFFFFF), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // bottom: zoom, found codes, type instead
              Positioned(
                left: 16,
                right: 16,
                bottom: mq.padding.bottom + 18,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (batch && log.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xEE14164A), borderRadius: BorderRadius.circular(18)),
                      child: Column(children: [
                        for (final (i, e) in log.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Icon(e.$2 ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                  size: 18, color: e.$2 ? const Color(0xFF34D399) : const Color(0xFFFFB020)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(e.$1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Jakarta',
                                        color: i == 0 ? Colors.white : Colors.white60,
                                        fontSize: 13.5,
                                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  if (codes.length > 1)
                    Container(
                      constraints: BoxConstraints(maxHeight: h * .3),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xEE14164A), borderRadius: BorderRadius.circular(20)),
                      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                        for (final e in codes)
                          ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _kind(e.key, e.value.$1).startsWith('IMEI') ? const Color(0xFF34D399) : const Color(0xFF7B5CFF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_kind(e.key, e.value.$1),
                                  style: const TextStyle(fontFamily: 'Jakarta', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                            title: Text(e.key,
                                style: const TextStyle(
                                    fontFamily: 'Jakarta', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: .5)),
                            trailing: const Icon(Icons.check_circle_rounded, color: Colors.white),
                            onTap: () => _finish(e.key),
                          ),
                      ]),
                    ),
                  Row(children: [
                    const Icon(Icons.zoom_out_rounded, color: Colors.white70, size: 20),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF9F7BFF),
                          inactiveTrackColor: const Color(0x55FFFFFF),
                          thumbColor: Colors.white,
                          trackHeight: 3,
                        ),
                        child: Slider(value: zoom, onChanged: _setZoom),
                      ),
                    ),
                    const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 20),
                  ]),
                  const SizedBox(height: 8),
                  if (batch)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(count),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF059669)]),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          alignment: Alignment.center,
                          child: Text(count == 0 ? 'Done' : 'Done · $count item${count == 1 ? '' : 's'} added',
                              style: const TextStyle(fontFamily: 'Jakarta', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: _manual,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0x66FFFFFF)),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.keyboard_rounded, color: Colors.white),
                        SizedBox(width: 10),
                        Text('Type code instead',
                            style: TextStyle(fontFamily: 'Jakarta', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _glassBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x40FFFFFF),
            border: Border.all(color: const Color(0x66FFFFFF)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}

class _FramePainter extends CustomPainter {
  final Rect frame;
  final bool found;
  _FramePainter(this.frame, this.found);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(frame, const Radius.circular(22));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rr);
    canvas.drawPath(dim, Paint()..color = const Color(0x8C000000));
    final corner = Paint()
      ..color = found ? const Color(0xFF34D399) : const Color(0xFF9F7BFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    final r = frame;
    for (final p in [
      [r.topLeft, const Offset(l, 0), const Offset(0, l)],
      [r.topRight, const Offset(-l, 0), const Offset(0, l)],
      [r.bottomLeft, const Offset(l, 0), const Offset(0, -l)],
      [r.bottomRight, const Offset(-l, 0), const Offset(0, -l)],
    ]) {
      final o = p[0];
      canvas.drawLine(o, o + p[1], corner);
      canvas.drawLine(o, o + p[2], corner);
    }
    canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0x33FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.frame != frame || old.found != found;
}
