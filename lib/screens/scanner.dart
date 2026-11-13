import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen barcode / QR / IMEI scanner. Pops with the scanned text.
class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  const BarcodeScannerScreen({super.key, this.title = 'Scan barcode'});

  static Future<String?> scan(BuildContext context, {String title = 'Scan barcode'}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BarcodeScannerScreen(title: title)));

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> with SingleTickerProviderStateMixin {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.itf,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );
  late final AnimationController laser = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  bool torch = false;
  bool done = false;

  @override
  void dispose() {
    laser.dispose();
    controller.dispose();
    super.dispose();
  }

  void _found(String code) {
    if (done || code.trim().isEmpty) return;
    done = true;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop(code.trim());
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter code manually'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Barcode / SKU / IMEI'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Use code')),
        ],
      ),
    );
    if (r != null) _found(r);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frameW = size.width * .78;
    final frameH = frameW * .62;
    final frame = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: frameW, height: frameH);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: controller,
            fit: BoxFit.cover,
            // only codes inside the frame in the middle are read
            scanWindow: frame,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _found(v);
                  break;
                }
              }
            },
          ),
        ),
        // dimmed surroundings + glowing frame corners
        Positioned.fill(child: CustomPaint(painter: _FramePainter(frame))),
        // laser line
        AnimatedBuilder(
          animation: laser,
          builder: (context, _) => Positioned(
            left: frame.left + 14,
            width: frame.width - 28,
            top: frame.top + 10 + (frame.height - 20) * Curves.easeInOut.transform(laser.value),
            height: 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(colors: [Color(0x007B5CFF), Color(0xFF9F7BFF), Color(0x007B5CFF)]),
                boxShadow: const [BoxShadow(color: Color(0xCC7B5CFF), blurRadius: 12, spreadRadius: 1)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _glassBtn(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.title,
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
        Positioned(
          left: 0,
          right: 0,
          top: frame.bottom + 22,
          child: const Text(
            'Point the camera at a barcode, QR code or IMEI label',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Jakarta', color: Color(0xDDFFFFFF), fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 30,
          child: GestureDetector(
            onTap: _manual,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(27),
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
        ),
      ]),
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
  _FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(frame, const Radius.circular(22));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rr);
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));
    final corner = Paint()
      ..color = const Color(0xFF9F7BFF)
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
  bool shouldRepaint(covariant _FramePainter old) => old.frame != frame;
}
