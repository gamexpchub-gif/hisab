import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/photo.dart';
import '../ui/widgets.dart';
import 'scanner.dart';

// =============================================================================
// Add / edit customer or supplier — photo, phones, address, GSTIN, credit
// limit, opening balance, Aadhaar & PAN (number + photo) and private notes.
// Documents stay on this phone only.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _green = Color(0xFF16A36A);

TextStyle _j(double size, FontWeight w, Color c, {double? height}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
    );

BoxDecoration _card({double r = 22}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [
        BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
        BoxShadow(color: Color(0x0A2A2F7A), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );

/// "XXXX XXXX 1234" for an Aadhaar number.
String maskAadhaar(String? v) {
  final d = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length < 4) return d;
  return 'XXXX XXXX ${d.substring(d.length - 4)}';
}

/// "ABXXXXX34F" for a PAN.
String maskPan(String? v) {
  final p = (v ?? '').toUpperCase();
  if (p.length != 10) return p;
  return '${p.substring(0, 2)}XXXXX${p.substring(7)}';
}

class PartyForm extends StatefulWidget {
  final String type; // customer | supplier
  final Rec? party;
  const PartyForm({super.key, required this.type, this.party});
  @override
  State<PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends State<PartyForm> {
  late final c = <String, TextEditingController>{
    for (final k in ['name', 'phone', 'alt_phone', 'email', 'address', 'gstin', 'aadhaar', 'pan', 'notes'])
      k: TextEditingController(text: '${widget.party?[k] ?? ''}'),
    'credit_limit': TextEditingController(
        text: widget.party == null || asInt(widget.party!['credit_limit']) == 0 ? '' : Money.edit(asInt(widget.party!['credit_limit']))),
    'opening': TextEditingController(),
  };
  late String? photo = widget.party?['photo'] as String?;
  late String? aadhaarImg = widget.party?['aadhaar_img'] as String?;
  late String? panImg = widget.party?['pan_img'] as String?;
  bool saving = false;

  bool get isC => widget.type == 'customer';
  bool get isNew => widget.party == null;

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  String? _v(String k) => c[k]!.text.trim().isEmpty ? null : c[k]!.text.trim();

  String? _validate() {
    if (c['name']!.text.trim().isEmpty) return 'Enter the name';
    final ph = c['phone']!.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (ph.isNotEmpty && ph.length < 10) return 'Mobile number looks too short';
    final a = c['aadhaar']!.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (a.isNotEmpty && a.length != 12) return 'Aadhaar number must have 12 digits';
    final p = c['pan']!.text.trim().toUpperCase();
    if (p.isNotEmpty && !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(p)) return 'PAN format is ABCDE1234F';
    final g = c['gstin']!.text.trim().toUpperCase();
    if (g.isNotEmpty && g.length != 15) return 'GSTIN must have 15 characters';
    return null;
  }

  Future<void> _save() async {
    if (saving) return;
    final err = _validate();
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    setState(() => saving = true);
    int money(String k) {
      try {
        return Money.parse(c[k]!.text);
      } catch (_) {
        return 0;
      }
    }

    try {
      await Books.saveParty(
        widget.type,
        {
          'name': c['name']!.text,
          'phone': _v('phone'),
          'alt_phone': _v('alt_phone'),
          'email': _v('email'),
          'address': _v('address'),
          'gstin': _v('gstin')?.toUpperCase(),
          'credit_limit': money('credit_limit'),
          'aadhaar': _v('aadhaar')?.replaceAll(RegExp(r'[^0-9]'), ''),
          'pan': _v('pan')?.toUpperCase(),
          'notes': _v('notes'),
          'photo': photo,
          'aadhaar_img': aadhaarImg,
          'pan_img': panImg,
        },
        id: isNew ? null : asInt(widget.party!['id']),
        opening: isNew ? money('opening') : 0,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      toast(context, isNew ? '${isC ? 'Customer' : 'Supplier'} added' : 'Saved');
      Navigator.of(context).pop();
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 100 + safe), children: [
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
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${isNew ? 'New' : 'Edit'} ${isC ? 'customer' : 'supplier'}', style: _j(21, FontWeight.w800, _navy)),
                  Text('Profile, contact, documents & credit', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            _photoCard(),
            const SizedBox(height: 14),
            _section(Icons.contact_phone_rounded, 'Contact', [
              _field('name', 'Full name *', Icons.person_rounded, caps: TextCapitalization.words),
              _field('phone', 'Mobile number', Icons.phone_rounded, keyboard: TextInputType.phone),
              _field('alt_phone', 'Alternate number', Icons.phone_forwarded_rounded, keyboard: TextInputType.phone),
              _field('email', 'Email', Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress),
              _field('address', 'Address', Icons.location_on_rounded, lines: 2, caps: TextCapitalization.sentences),
            ]),
            const SizedBox(height: 14),
            _section(Icons.account_balance_wallet_rounded, 'Credit & tax', [
              _field('gstin', 'GSTIN (optional)', Icons.receipt_long_rounded, caps: TextCapitalization.characters),
              if (isC) _field('credit_limit', 'Credit limit ₹ (0 = no limit)', Icons.speed_rounded, keyboard: const TextInputType.numberWithOptions(decimal: true)),
              if (isNew)
                _field('opening', isC ? 'Old due — they already owe you ₹' : 'Old due — you already owe them ₹', Icons.history_rounded,
                    keyboard: const TextInputType.numberWithOptions(decimal: true)),
            ]),
            const SizedBox(height: 14),
            _section(Icons.badge_rounded, 'KYC documents', [
              _field('aadhaar', 'Aadhaar number', Icons.fingerprint_rounded, keyboard: TextInputType.number),
              _docRow('Aadhaar photo', aadhaarImg, (v) => setState(() => aadhaarImg = v), 'kyc'),
              const SizedBox(height: 12),
              _field('pan', 'PAN number', Icons.credit_card_rounded, caps: TextCapitalization.characters),
              _docRow('PAN card photo', panImg, (v) => setState(() => panImg = v), 'kyc'),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.lock_rounded, size: 14, color: _green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Documents are stored only on this phone and shown masked.', style: _j(11, FontWeight.w600, _muted)),
                ),
              ]),
            ]),
            const SizedBox(height: 14),
            _section(Icons.sticky_note_2_rounded, 'Private notes', [
              _field('notes', 'e.g. pays on salary day, father\'s shop near station', Icons.edit_note_rounded, lines: 3, caps: TextCapitalization.sentences),
            ]),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safe),
            decoration: const BoxDecoration(
              color: Color(0xF7FFFFFF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 24, offset: Offset(0, -6), spreadRadius: -8)],
            ),
            child: GestureDetector(
              onTap: _save,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF3A10CC)]),
                  boxShadow: const [BoxShadow(color: Color(0x804A17C9), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
                ),
                alignment: Alignment.center,
                child: saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(isNew ? 'Save ${isC ? 'customer' : 'supplier'}' : 'Save changes', style: _j(15, FontWeight.w800, Colors.white)),
                      ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _photoCard() {
    final name = c['name']!.text.trim();
    final initials = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: isC ? const [Color(0xFF6A2FF0), Color(0xFF2F55E8)] : const [Color(0xFFFF8A3D), Color(0xFFD9480F)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x554A17C9), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -10)],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () async {
            final r = await pickPhoto(context, folder: 'people', allowRemove: photo != null);
            if (r != null) setState(() => photo = r.isEmpty ? null : r);
          },
          child: Stack(children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33FFFFFF),
                border: Border.all(color: const Color(0x99FFFFFF), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: storedImage(photo, fallback: Text(initials.isEmpty ? '+' : initials, style: _j(28, FontWeight.w800, Colors.white))),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.photo_camera_rounded, size: 16, color: _purple),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? (isC ? 'New customer' : 'New supplier') : name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(18, FontWeight.w800, Colors.white)),
            const SizedBox(height: 4),
            Text('Tap the circle to add a photo', style: _j(12, FontWeight.w500, const Color(0xCCFFFFFF))),
          ]),
        ),
      ]),
    );
  }

  Widget _docRow(String label, String? img, ValueChanged<String?> set, String folder) => Row(children: [
        GestureDetector(
          onTap: () async {
            final r = await pickPhoto(context, folder: folder, allowRemove: img != null);
            if (r != null) set(r.isEmpty ? null : r);
          },
          child: Container(
            width: 96,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F3FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD6CCFF), width: 1.4),
            ),
            clipBehavior: Clip.antiAlias,
            child: img == null
                ? const Icon(Icons.add_photo_alternate_rounded, color: _purple)
                : storedImage(img),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _j(13, FontWeight.w700, _ink)),
            Text(img == null ? 'Tap to take or choose a photo' : 'Saved · tap to change', style: _j(11, FontWeight.w500, img == null ? _muted : _green)),
          ]),
        ),
        if (label.startsWith('Aadhaar'))
          IconButton(
            tooltip: 'Scan Aadhaar QR',
            icon: const Icon(Icons.qr_code_scanner_rounded, color: _purple),
            onPressed: () async {
              final code = await BarcodeScannerScreen.scan(context, title: 'Scan Aadhaar QR');
              if (code == null) return;
              final digits = RegExp(r'\d{12}').firstMatch(code)?.group(0);
              if (digits != null) {
                setState(() => c['aadhaar']!.text = digits);
              } else if (mounted) {
                toast(context, 'Could not read the number — please type it', error: true);
              }
            },
          ),
      ]);

  Widget _section(IconData icon, String title, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: const Color(0xFFEFEBFF), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _purple, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: _j(15, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 14),
          ...children,
          const SizedBox(height: 8),
        ]),
      );

  Widget _field(String key, String label, IconData icon,
          {TextInputType keyboard = TextInputType.text, int lines = 1, TextCapitalization caps = TextCapitalization.none}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c[key],
          keyboardType: lines > 1 ? TextInputType.multiline : keyboard,
          maxLines: lines,
          textCapitalization: caps,
          onChanged: key == 'name' ? (_) => setState(() {}) : null,
          style: _j(14.5, FontWeight.w600, _ink),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: const Color(0xFF8B7FD6), size: 20),
            filled: true,
            fillColor: const Color(0xFFFBFBFE),
            labelStyle: _j(13, FontWeight.w500, _muted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.6)),
          ),
        ),
      );
}
