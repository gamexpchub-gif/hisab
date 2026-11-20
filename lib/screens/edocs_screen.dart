import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/books.dart';
import '../core/edocs.dart';
import '../core/native_files.dart';
import '../ui/widgets.dart';

// =============================================================================
// e-Invoice (IRN) and e-Way bill for one sale.
// =============================================================================

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _green = Color(0xFF0BA360);
const _red = Color(0xFFE0245E);
const _purple = Color(0xFF4318D2);
const _amber = Color(0xFFF97316);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.3);

BoxDecoration _card({Color? border}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border ?? const Color(0xFFF0F1F8)),
      boxShadow: const [BoxShadow(color: Color(0x0F1B2163), blurRadius: 16, offset: Offset(0, 6))],
    );

InputDecoration _dec(String label, {String? helper, String? hint}) => InputDecoration(
      labelText: label,
      helperText: helper,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8F8FC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
    );

Future<void> _shareJson(BuildContext context, String name, String json, String subject) async {
  try {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsString(json, flush: true);
    await NativeFiles.share(f, mime: 'application/json', subject: subject, text: subject);
  } catch (e) {
    if (context.mounted) toast(context, 'Could not share: $e', error: true);
  }
}

Future<void> _openSite(BuildContext context, String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && context.mounted) {
    toast(context, 'Could not open $url', error: true);
  }
}

Widget _problems(List<String> list) => list.isEmpty
    ? Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFEAF8F1), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.verified_rounded, color: _green),
          const SizedBox(width: 8),
          Expanded(child: Text('All details are ready', style: _j(13, FontWeight.w800, _green))),
        ]),
      )
    : Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFEEF2), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fix before uploading', style: _j(13, FontWeight.w800, _red)),
          const SizedBox(height: 4),
          for (final x in list) Text('• $x', style: _j(12, FontWeight.w600, _ink)),
        ]),
      );

Widget _step(String n, String title, String sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEFEAFF)),
          child: Text(n, style: _j(11, FontWeight.w800, _purple)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _j(13, FontWeight.w800, _ink)),
            Text(sub, style: _j(11.5, FontWeight.w500, _muted)),
          ]),
        ),
      ]),
    );

/// The e-Invoice / e-Way bill strip on a bill.
class EDocsCard extends StatelessWidget {
  final Rec sale;
  const EDocsCard(this.sale, {super.key});

  @override
  Widget build(BuildContext context) {
    final irn = (sale['irn'] ?? '').toString();
    final ewb = (sale['ewb_no'] ?? '').toString();
    final id = asInt(sale['id']);
    Widget tile(IconData icon, String title, String status, bool done, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: _card(border: done ? const Color(0xFFBFE8D4) : null),
              child: Row(children: [
                Icon(icon, color: done ? _green : _purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: _j(13, FontWeight.w800, _ink)),
                    Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w700, done ? _green : _muted)),
                  ]),
                ),
              ]),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.qr_code_2_rounded, 'e-Invoice', irn.isEmpty ? 'Make IRN' : 'IRN saved ✓', irn.isNotEmpty, () => open(context, EInvoiceScreen(saleId: id))),
      const SizedBox(width: 10),
      tile(Icons.local_shipping_rounded, 'e-Way bill', ewb.isEmpty ? 'Make e-way bill' : 'EWB $ewb', ewb.isNotEmpty,
          () => open(context, EwayBillScreen(saleId: id))),
    ]);
  }
}

// =============================================================================
// e-Invoice
// =============================================================================
class EInvoiceScreen extends StatefulWidget {
  final int saleId;
  const EInvoiceScreen({super.key, required this.saleId});
  @override
  State<EInvoiceScreen> createState() => _EInvoiceScreenState();
}

class _EInvoiceScreenState extends State<EInvoiceScreen> {
  final irn = TextEditingController(), ack = TextEditingController(), ackDate = TextEditingController(), qr = TextEditingController();

  @override
  void dispose() {
    for (final c in [irn, ack, ackDate, qr]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await EDocs.saveIrn(widget.saleId, irn: irn.text, ackNo: ack.text, ackDate: ackDate.text, signedQr: qr.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      toast(context, 'IRN saved — it prints on the bill with the QR code');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Live<EDoc?>(
      load: () => EDoc.load(widget.saleId),
      builder: (context, d) {
        if (d == null) return const Scaffold(body: Center(child: Text('Bill not found')));
        final saved = '${d.sale['irn'] ?? ''}';
        final problems = d.einvoiceProblems();
        return PageShell(
          title: 'e-Invoice',
          subtitle: '${d.sale['number']} · ${d.sale['customer'] ?? 'Walk-in'} · ${EDocs.money(d.total)}',
          children: [
            const SizedBox(height: 8),
            if (saved.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _card(border: const Color(0xFFBFE8D4)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.verified_rounded, color: _green),
                    const SizedBox(width: 8),
                    Expanded(child: Text('e-Invoice registered', style: _j(15, FontWeight.w800, _green))),
                    TextButton(
                      onPressed: () async {
                        if (await confirmDelete(context, 'Remove the IRN?', 'Only do this if the e-invoice was cancelled on the portal.')) {
                          await EDocs.clear(widget.saleId, 'irn');
                        }
                      },
                      child: const Text('Remove', style: TextStyle(color: _red)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  SelectableText('IRN: $saved', style: _j(11.5, FontWeight.w600, _ink)),
                  if (d.sale['ack_no'] != null) Text('Ack No: ${d.sale['ack_no']} · ${d.sale['ack_date'] ?? ''}', style: _j(12, FontWeight.w700, _muted)),
                  const SizedBox(height: 10),
                  Center(child: QrImageView(data: '${d.sale['signed_qr'] ?? saved}', size: 160)),
                  Center(
                      child: Text(d.sale['signed_qr'] == null ? 'QR of the IRN (paste the signed QR for the official one)' : 'Signed QR — prints on the bill',
                          style: _j(11, FontWeight.w600, _muted))),
                ]),
              ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('How it works', style: _j(15, FontWeight.w800, _ink)),
                const SizedBox(height: 6),
                _step('1', 'Download the e-invoice file', 'Hisab AI makes the JSON in the government format'),
                _step('2', 'Upload it on the IRP portal', 'einvoice1.gst.gov.in → e-Invoice → Bulk upload'),
                _step('3', 'Copy the IRN, Ack No and signed QR here', 'The bill then prints the IRN and QR code'),
                const SizedBox(height: 6),
                Text('Needed for businesses with turnover above ₹5 crore, for bills to GST-registered customers (B2B).',
                    style: _j(11.5, FontWeight.w600, _amber)),
              ]),
            ),
            const SizedBox(height: 12),
            _problems(problems),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _purple),
                  onPressed: problems.isNotEmpty
                      ? null
                      : () => _shareJson(context, 'einvoice-${d.sale['number']}.json', d.einvoiceJson(), 'e-Invoice ${d.sale['number']}'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('e-Invoice JSON'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _openSite(context, 'https://einvoice1.gst.gov.in'),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open portal'),
                ),
              ),
            ]),
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(saved.isEmpty ? 'Enter what the portal gave' : 'Update IRN details', style: _j(15, FontWeight.w800, _ink)),
                const SizedBox(height: 10),
                TextField(controller: irn, decoration: _dec('IRN (64 characters)')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: ack, keyboardType: TextInputType.number, decoration: _dec('Ack No'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: ackDate, decoration: _dec('Ack date', hint: 'dd/mm/yyyy'))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: qr, maxLines: 3, decoration: _dec('Signed QR code text (optional)')),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: _green),
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save IRN'),
                ),
              ]),
            ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}

// =============================================================================
// e-Way bill
// =============================================================================
class EwayBillScreen extends StatefulWidget {
  final int saleId;
  const EwayBillScreen({super.key, required this.saleId});
  @override
  State<EwayBillScreen> createState() => _EwayBillScreenState();
}

class _EwayBillScreenState extends State<EwayBillScreen> {
  EDoc? d;
  Transport t = Transport();
  final distance = TextEditingController(), vehicle = TextEditingController(), transporter = TextEditingController(), transporterId = TextEditingController();
  final docNo = TextEditingController(), docDate = TextEditingController(), toPin = TextEditingController();
  final ewb = TextEditingController(), ewbDate = TextEditingController(), ewbValid = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await EDoc.load(widget.saleId);
    if (!mounted || x == null) return;
    final tr = Transport.from(x.sale['transport'] as String?);
    setState(() {
      d = x;
      t = tr;
      distance.text = tr.distance == 0 ? '' : '${tr.distance}';
      vehicle.text = tr.vehicle;
      transporter.text = tr.transporter;
      transporterId.text = tr.transporterId;
      docNo.text = tr.docNo;
      docDate.text = tr.docDate;
      toPin.text = tr.toPin.isEmpty ? x.buyerPin() : tr.toPin;
      ewb.text = '${x.sale['ewb_no'] ?? ''}';
      ewbDate.text = '${x.sale['ewb_date'] ?? ''}';
      ewbValid.text = '${x.sale['ewb_valid'] ?? ''}';
    });
  }

  @override
  void dispose() {
    for (final c in [distance, vehicle, transporter, transporterId, docNo, docDate, toPin, ewb, ewbDate, ewbValid]) {
      c.dispose();
    }
    super.dispose();
  }

  Transport _read() => Transport(
        mode: t.mode,
        distance: int.tryParse(distance.text.trim()) ?? 0,
        vehicle: vehicle.text,
        transporter: transporter.text,
        transporterId: transporterId.text,
        docNo: docNo.text,
        docDate: docDate.text,
        toPin: toPin.text.trim(),
      );

  Future<void> _download() async {
    final x = d;
    if (x == null) return;
    t = _read();
    final problems = x.ewayProblems(t);
    if (problems.isNotEmpty) {
      toast(context, problems.first, error: true);
      setState(() {});
      return;
    }
    await EDocs.saveTransport(widget.saleId, t);
    if (!mounted) return;
    await _shareJson(context, 'ewaybill-${x.sale['number']}.json', x.ewayJson(t), 'e-Way bill ${x.sale['number']}');
  }

  Future<void> _saveNumber() async {
    try {
      await EDocs.saveTransport(widget.saleId, _read());
      await EDocs.saveEwb(widget.saleId, number: ewb.text, date: ewbDate.text, validUpto: ewbValid.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      toast(context, 'e-Way bill saved — it prints on the bill');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = d;
    if (x == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cur = _read();
    final problems = x.ewayProblems(cur);
    final saved = '${x.sale['ewb_no'] ?? ''}';
    return PageShell(
      title: 'e-Way bill',
      subtitle: '${x.sale['number']} · ${x.sale['customer'] ?? 'Walk-in'} · ${EDocs.money(x.total)}',
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: x.ewayNeeded ? const [Color(0xFFFFA24A), Color(0xFFE0245E)] : const [Color(0xFF3EE08F), Color(0xFF0E7F4C)]),
          ),
          child: Row(children: [
            const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                x.ewayNeeded
                    ? 'Goods worth ${EDocs.money(x.total)} — an e-way bill is needed before the goods move'
                    : 'Under ₹50,000 — an e-way bill is usually not needed (some states differ)',
                style: _j(13, FontWeight.w700, Colors.white),
              ),
            ),
          ]),
        ),
        if (saved.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: _card(border: const Color(0xFFBFE8D4)),
            child: Row(children: [
              const Icon(Icons.verified_rounded, color: _green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('EWB $saved', style: _j(15, FontWeight.w800, _green)),
                  Text('${x.sale['ewb_date'] ?? ''}${x.sale['ewb_valid'] == null ? '' : ' · valid till ${x.sale['ewb_valid']}'}',
                      style: _j(12, FontWeight.w600, _muted)),
                ]),
              ),
              TextButton(
                onPressed: () async {
                  if (await confirmDelete(context, 'Remove the e-way bill number?', 'Only if it was cancelled on the portal.')) {
                    await EDocs.clear(widget.saleId, 'ewb');
                    await _load();
                  }
                },
                child: const Text('Remove', style: TextStyle(color: _red)),
              ),
            ]),
          ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Transport', style: _j(15, FontWeight.w800, _ink)),
            const SizedBox(height: 10),
            Row(children: [
              for (final e in Transport.modes.entries)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => t = _read()..mode = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        gradient: t.mode == e.key ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                        color: t.mode == e.key ? null : const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(e.value, textAlign: TextAlign.center, style: _j(12.5, FontWeight.w800, t.mode == e.key ? Colors.white : _ink)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: distance,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: _dec('Distance (km)', helper: cur.distance > 0 ? 'Valid ${cur.validDays} day${cur.validDays == 1 ? '' : 's'}' : null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(controller: toPin, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: _dec('Delivery PIN'))),
            ]),
            const SizedBox(height: 8),
            if (t.mode == '1')
              TextField(
                controller: vehicle,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: _dec('Vehicle number', hint: 'WB12AB1234'),
              )
            else
              Row(children: [
                Expanded(child: TextField(controller: docNo, onChanged: (_) => setState(() {}), decoration: _dec('Transport doc no.'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: docDate, decoration: _dec('Doc date', hint: 'dd/mm/yyyy'))),
              ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: transporter, textCapitalization: TextCapitalization.words, decoration: _dec('Transporter (optional)'))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: transporterId,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: _dec('Transporter ID / GSTIN'),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        _problems(problems),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _purple),
              onPressed: _download,
              icon: const Icon(Icons.download_rounded),
              label: const Text('e-Way bill JSON'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => _openSite(context, 'https://ewaybillgst.gov.in'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open portal'),
            ),
          ),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Enter the e-way bill number', style: _j(15, FontWeight.w800, _ink)),
            const SizedBox(height: 4),
            Text('Upload the JSON on ewaybillgst.gov.in (Generate → Bulk), then type the 12-digit number here.', style: _j(11.5, FontWeight.w500, _muted)),
            const SizedBox(height: 10),
            TextField(controller: ewb, keyboardType: TextInputType.number, decoration: _dec('EWB number (12 digits)')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: ewbDate, decoration: _dec('Generated on', hint: 'dd/mm/yyyy'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ewbValid, decoration: _dec('Valid till', hint: 'dd/mm/yyyy'))),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: _green),
              onPressed: _saveNumber,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save e-way bill'),
            ),
          ]),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
