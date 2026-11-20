/// e-Invoice (IRN) and e-Way bill for a sale.
///
/// The app prepares the JSON in the government's layout (NIC e-invoice
/// schema 1.1, e-way bill bulk-upload layout). The shop uploads it on the
/// portal (or through its GSP), gets the IRN / e-way bill number back and
/// saves it here; the bill then prints the IRN, the signed QR code and the
/// e-way bill number. Talking to the portal directly needs API access from a
/// GST Suvidha Provider (GSP).
library;

import 'dart:convert';

import 'books.dart';
import 'gst.dart';
import 'money.dart';

/// Transport details for an e-way bill.
class Transport {
  String mode; // 1 road · 2 rail · 3 air · 4 ship
  int distance; // km
  String vehicle, transporter, transporterId, docNo, docDate, toPin;
  Transport({
    this.mode = '1',
    this.distance = 0,
    this.vehicle = '',
    this.transporter = '',
    this.transporterId = '',
    this.docNo = '',
    this.docDate = '',
    this.toPin = '',
  });

  Map<String, Object> toJson() => {
        'mode': mode,
        'distance': distance,
        'vehicle': vehicle,
        'transporter': transporter,
        'transporterId': transporterId,
        'docNo': docNo,
        'docDate': docDate,
        'toPin': toPin,
      };

  static Transport from(String? json) {
    try {
      final m = jsonDecode(json ?? '') as Map;
      return Transport(
        mode: '${m['mode'] ?? '1'}',
        distance: (m['distance'] as num?)?.toInt() ?? 0,
        vehicle: '${m['vehicle'] ?? ''}',
        transporter: '${m['transporter'] ?? ''}',
        transporterId: '${m['transporterId'] ?? ''}',
        docNo: '${m['docNo'] ?? ''}',
        docDate: '${m['docDate'] ?? ''}',
        toPin: '${m['toPin'] ?? ''}',
      );
    } catch (_) {
      return Transport();
    }
  }

  static const modes = {'1': 'Road', '2': 'Rail', '3': 'Air', '4': 'Ship'};

  /// Days the e-way bill is valid: 1 day per 200 km by road (20 km for ODC).
  int get validDays => distance <= 0 ? 1 : (distance + 199) ~/ 200;
}

/// One sale with everything the e-documents need.
class EDoc {
  final Rec sale;
  final List<Rec> items;
  final Map<String, String> settings;
  EDoc(this.sale, this.items, this.settings);

  static Future<EDoc?> load(int saleId) async {
    final s = await Books.query(
        'SELECT s.*, c.name AS customer, c.phone AS customer_phone, c.address AS customer_address, c.gstin AS customer_gstin, c.email AS customer_email '
        'FROM sales s LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id = ?',
        [saleId]);
    if (s.isEmpty) return null;
    final items =
        await Books.query('SELECT i.*, p.hsn FROM sale_items i LEFT JOIN products p ON p.id = i.product_id WHERE i.sale_id = ? ORDER BY i.id', [saleId]);
    return EDoc(s.first, items, await Books.settings());
  }

  String get shopGstin => (settings['gstin'] ?? '').trim().toUpperCase();
  String get buyerGstin => '${sale['customer_gstin'] ?? ''}'.trim().toUpperCase();
  String get shopState => Gst.shopState(settings);
  String get pos => Gst.placeOfSupply(settings, buyerGstin);
  bool get inter => Gst.interState(settings, buyerGstin);
  int get total => asInt(sale['total']);
  int get subtotal => asInt(sale['subtotal']);
  int get discount => asInt(sale['discount']);
  int get tax => asInt(sale['tax']);
  int get taxable => subtotal - discount;

  String get shopPin => _pin(settings['pin']) ?? _pin(settings['address']) ?? '';
  String buyerPin([Transport? t]) => (t != null && _pin(t.toPin) != null) ? _pin(t.toPin)! : (_pin('${sale['customer_address'] ?? ''}') ?? '');
  String get shopPlace => _place(settings['address']) ?? (settings['state'] ?? '');
  String get buyerPlace => _place('${sale['customer_address'] ?? ''}') ?? (Gst.states[pos] ?? '');

  static String? _pin(String? s) => RegExp(r'(?<!\d)[1-9]\d{5}(?!\d)').firstMatch(s ?? '')?.group(0);
  static String? _place(String? address) {
    final parts = (address ?? '').split(RegExp(r'[,\n]')).map((x) => x.replaceAll(RegExp(r'\d{6}'), '').trim()).where((x) => x.length >= 3).toList();
    return parts.isEmpty ? null : parts.last;
  }

  static String dmy(String ymdDate, [String sep = '/']) {
    final p = ymdDate.split('-');
    return p.length == 3 ? '${p[2]}$sep${p[1]}$sep${p[0]}' : ymdDate;
  }

  /// Taxable value of each line after the bill discount.
  int lineTaxable(Rec i) => asInt(i['amount']) - Gst.share(discount, asInt(i['amount']), subtotal);

  // ---------------------------------------------------------------- checks
  /// What is missing for an e-invoice (empty = ready).
  List<String> einvoiceProblems() => [
        if (!Gst.valid(shopGstin)) 'Shop GSTIN missing or wrong — Settings',
        if (!Gst.valid(buyerGstin)) 'e-Invoice is only for customers with a GSTIN (B2B) — add the customer\'s GSTIN',
        if (shopPin.isEmpty) 'Shop PIN code missing — Settings',
        if (buyerPin().isEmpty) 'Customer PIN code missing — add it to the customer\'s address',
        if ('${sale['number']}'.length > 16) 'Invoice number longer than 16 characters',
        for (final i in items)
          if ('${i['hsn'] ?? ''}'.trim().length < 4) 'HSN code missing for ${i['name']}',
      ];

  /// What is missing for an e-way bill (empty = ready).
  List<String> ewayProblems(Transport t) => [
        if (!Gst.valid(shopGstin)) 'Shop GSTIN missing or wrong — Settings',
        if (shopPin.isEmpty) 'Shop PIN code missing — Settings',
        if (buyerPin(t).isEmpty) 'Delivery PIN code missing',
        if (t.distance <= 0 || t.distance > 4000) 'Enter the distance in km',
        if (t.mode == '1' && t.vehicle.trim().isEmpty && t.transporterId.trim().isEmpty) 'Enter the vehicle number (or the transporter ID)',
        if (t.mode != '1' && t.docNo.trim().isEmpty) 'Enter the transport document number',
        for (final i in items)
          if ('${i['hsn'] ?? ''}'.trim().length < 4) 'HSN code missing for ${i['name']}',
      ];

  /// An e-way bill is needed when goods worth more than ₹50,000 move.
  bool get ewayNeeded => total > 5000000;

  static num _r(int paise) => double.parse((paise / 100).toStringAsFixed(2));
  num _rate(Rec i) {
    final bp = asInt(i['gst_bp']);
    return bp % 100 == 0 ? bp ~/ 100 : bp / 100;
  }

  (int, int, int) _split(int t) => inter ? (t, 0, 0) : (0, t ~/ 2, t - t ~/ 2);

  // ---------------------------------------------------------------- e-invoice
  /// e-Invoice JSON (NIC schema 1.1) — a list, as the portal's bulk upload takes.
  String einvoiceJson() {
    final rows = <Map<String, Object>>[];
    var ass = 0, ig = 0, cg = 0, sg = 0;
    for (final (n, i) in items.indexed) {
      final gross = asInt(i['amount']);
      final disc = gross - lineTaxable(i);
      final t = asInt(i['tax']);
      final (a, b, c) = _split(t);
      ass += gross - disc;
      ig += a;
      cg += b;
      sg += c;
      rows.add({
        'SlNo': '${n + 1}',
        'PrdDesc': '${i['name']}${'${i['serial'] ?? ''}'.isEmpty ? '' : ' IMEI ${i['serial']}'}',
        'IsServc': 'N',
        'HsnCd': '${i['hsn'] ?? ''}'.trim(),
        'Qty': asInt(i['qty']),
        'Unit': 'NOS',
        'UnitPrice': _r(asInt(i['rate'])),
        'TotAmt': _r(gross),
        'Discount': _r(disc),
        'AssAmt': _r(gross - disc),
        'GstRt': _rate(i),
        'IgstAmt': _r(a),
        'CgstAmt': _r(b),
        'SgstAmt': _r(c),
        'CesRt': 0,
        'CesAmt': 0,
        'CesNonAdvlAmt': 0,
        'StateCesRt': 0,
        'StateCesAmt': 0,
        'StateCesNonAdvlAmt': 0,
        'OthChrg': 0,
        'TotItemVal': _r(gross - disc + t),
      });
    }
    final doc = {
      'Version': '1.1',
      'TranDtls': {'TaxSch': 'GST', 'SupTyp': 'B2B', 'RegRev': 'N', 'IgstOnIntra': 'N'},
      'DocDtls': {'Typ': 'INV', 'No': '${sale['number']}', 'Dt': dmy('${sale['date']}')},
      'SellerDtls': {
        'Gstin': shopGstin,
        'LglNm': (settings['business_name'] ?? 'Shop').trim(),
        'Addr1': _clip(settings['address'] ?? shopPlace, 100),
        'Loc': _clip(shopPlace, 50),
        'Pin': int.tryParse(shopPin) ?? 0,
        'Stcd': shopState,
        if ((settings['phone'] ?? '').replaceAll(RegExp(r'\D'), '').length >= 6) 'Ph': (settings['phone'] ?? '').replaceAll(RegExp(r'\D'), ''),
      },
      'BuyerDtls': {
        'Gstin': buyerGstin,
        'LglNm': '${sale['customer'] ?? ''}',
        'Pos': pos,
        'Addr1': _clip('${sale['customer_address'] ?? buyerPlace}', 100),
        'Loc': _clip(buyerPlace, 50),
        'Pin': int.tryParse(buyerPin()) ?? 0,
        'Stcd': Gst.stateOf(buyerGstin) ?? pos,
        if ('${sale['customer_phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '').length >= 6) 'Ph': '${sale['customer_phone']}'.replaceAll(RegExp(r'\D'), ''),
      },
      'ItemList': rows,
      'ValDtls': {
        'AssVal': _r(ass),
        'CgstVal': _r(cg),
        'SgstVal': _r(sg),
        'IgstVal': _r(ig),
        'CesVal': 0,
        'StCesVal': 0,
        'Discount': 0,
        'OthChrg': 0,
        'RndOffAmt': _r(total - (ass + ig + cg + sg)),
        'TotInvVal': _r(total),
      },
    };
    return const JsonEncoder.withIndent(' ').convert([doc]);
  }

  // ---------------------------------------------------------------- e-way bill
  /// e-Way bill JSON (bulk-upload layout of the e-way bill portal).
  String ewayJson(Transport t) {
    final (ig, cg, sg) = _split(tax);
    String hsn(Rec i) => '${i['hsn'] ?? ''}'.trim();
    final mainHsn = items.isEmpty ? '' : hsn((items.toList()..sort((a, b) => lineTaxable(b).compareTo(lineTaxable(a)))).first);
    final toState = int.tryParse(Gst.stateOf(buyerGstin) ?? pos) ?? 0;
    final bill = {
      'userGstin': shopGstin,
      'supplyType': 'O',
      'subSupplyType': 1,
      'subSupplyDesc': '',
      'docType': 'INV',
      'docNo': '${sale['number']}',
      'docDate': dmy('${sale['date']}'),
      'transType': 1,
      'fromGstin': shopGstin,
      'fromTrdName': (settings['business_name'] ?? 'Shop').trim(),
      'fromAddr1': _clip(settings['address'] ?? shopPlace, 120),
      'fromAddr2': '',
      'fromPlace': _clip(shopPlace, 50),
      'fromPincode': int.tryParse(shopPin) ?? 0,
      'fromStateCode': int.tryParse(shopState) ?? 0,
      'actualFromStateCode': int.tryParse(shopState) ?? 0,
      'toGstin': Gst.valid(buyerGstin) ? buyerGstin : 'URP',
      'toTrdName': '${sale['customer'] ?? 'Customer'}',
      'toAddr1': _clip('${sale['customer_address'] ?? buyerPlace}', 120),
      'toAddr2': '',
      'toPlace': _clip(buyerPlace, 50),
      'toPincode': int.tryParse(buyerPin(t)) ?? 0,
      'toStateCode': toState,
      'actualToStateCode': toState,
      'totalValue': _r(taxable),
      'cgstValue': _r(cg),
      'sgstValue': _r(sg),
      'igstValue': _r(ig),
      'cessValue': 0,
      'cessNonAdvolValue': 0,
      'OthValue': _r(total - taxable - tax),
      'totInvValue': _r(total),
      'transMode': int.parse(t.mode),
      'transDistance': '${t.distance}',
      'transporterName': t.transporter.trim(),
      'transporterId': t.transporterId.trim().toUpperCase(),
      'transDocNo': t.docNo.trim(),
      'transDocDate': t.docDate.trim(),
      'vehicleNo': t.vehicle.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase(),
      'vehicleType': 'R',
      'mainHsnCode': int.tryParse(mainHsn) ?? 0,
      'itemList': [
        for (final (n, i) in items.indexed)
          {
            'itemNo': n + 1,
            'productName': _clip('${i['name']}', 100),
            'productDesc': _clip('${i['name']}', 100),
            'hsnCode': int.tryParse(hsn(i)) ?? 0,
            'quantity': asInt(i['qty']),
            'qtyUnit': 'NOS',
            'taxableAmount': _r(lineTaxable(i)),
            'sgstRate': inter ? 0 : _rate(i) / 2,
            'cgstRate': inter ? 0 : _rate(i) / 2,
            'igstRate': inter ? _rate(i) : 0,
            'cessRate': 0,
            'cessNonAdvol': 0,
          }
      ],
    };
    return const JsonEncoder.withIndent(' ').convert({
      'version': '1.0.0621',
      'billLists': [bill]
    });
  }

  static String _clip(String s, int n) {
    final t = s.replaceAll('\n', ', ').trim();
    return t.length > n ? t.substring(0, n) : t;
  }
}

class EDocs {
  /// Saves the IRN details the portal gave for a sale.
  static Future<void> saveIrn(int saleId, {required String irn, String ackNo = '', String ackDate = '', String signedQr = ''}) async {
    final i = irn.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(i)) throw AccountingError('IRN has 64 letters and digits — copy it from the portal');
    await Books.execute('UPDATE sales SET irn = ?, ack_no = ?, ack_date = ?, signed_qr = ? WHERE id = ?', [
      i,
      ackNo.trim().isEmpty ? null : ackNo.trim(),
      ackDate.trim().isEmpty ? null : ackDate.trim(),
      signedQr.trim().isEmpty ? null : signedQr.trim(),
      saleId
    ]);
    await Books.log('sale', 'e-Invoice IRN saved', null, null);
  }

  static Future<void> saveTransport(int saleId, Transport t) => Books.execute('UPDATE sales SET transport = ? WHERE id = ?', [jsonEncode(t.toJson()), saleId]);

  /// Saves the e-way bill number (12 digits) for a sale.
  static Future<void> saveEwb(int saleId, {required String number, String date = '', String validUpto = ''}) async {
    final n = number.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{12}$').hasMatch(n)) throw AccountingError('The e-way bill number has 12 digits');
    await Books.execute('UPDATE sales SET ewb_no = ?, ewb_date = ?, ewb_valid = ? WHERE id = ?',
        [n, date.trim().isEmpty ? null : date.trim(), validUpto.trim().isEmpty ? null : validUpto.trim(), saleId]);
    await Books.log('sale', 'e-Way bill $n saved', null, null);
  }

  static Future<void> clear(int saleId, String kind) => kind == 'irn'
      ? Books.execute('UPDATE sales SET irn = NULL, ack_no = NULL, ack_date = NULL, signed_qr = NULL WHERE id = ?', [saleId])
      : Books.execute('UPDATE sales SET ewb_no = NULL, ewb_date = NULL, ewb_valid = NULL WHERE id = ?', [saleId]);

  static String money(int p) => Money.rs(p);
}
