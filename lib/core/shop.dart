part of 'books.dart';

const serviceIncomeCode = '4100';

/// One event in a device's life (IMEI history).
class DeviceEvent {
  final String date, kind, title, detail; // kind: bought | sold | returned | exchange | repair | emi | warranty
  final String? target;
  final int? targetId;
  const DeviceEvent(this.date, this.kind, this.title, this.detail, {this.target, this.targetId});
}

/// Mobile-shop work: repair job cards, exchange / second-hand phones bought
/// from customers, finance-company payouts and the full IMEI history.
///
/// Books:
///   repair advance / payment   receipt from the customer (Dr Cash · Cr Debtors)
///   repair delivered           Dr Debtors (customer) · Cr Service & Repair Income
///   used phone bought          a purchase from the seller (stock in, paid from cash)
///   finance payout received    receipt from the customer, paid by the finance company
class Shop {
  static const repairSteps = ['received', 'checking', 'waiting_parts', 'repairing', 'ready', 'delivered'];
  static const repairLabels = {
    'received': 'Received',
    'checking': 'Checking',
    'waiting_parts': 'Waiting for parts',
    'repairing': 'Repairing',
    'ready': 'Ready',
    'delivered': 'Delivered',
    'cancelled': 'Cancelled',
  };

  /// The customer with this phone (or name), created when new.
  static Future<int> customerFor(String name, String phone) async {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length >= 10) {
      final r = await Books.query(
          "SELECT id FROM customers WHERE REPLACE(REPLACE(IFNULL(phone, ''), ' ', ''), '+91', '') LIKE ? LIMIT 1", ['%${p.substring(p.length - 10)}']);
      if (r.isNotEmpty) return asInt(r.first['id']);
    }
    if (name.trim().isEmpty) throw AccountingError('Enter the customer name');
    final r = await Books.query('SELECT id FROM customers WHERE name = ? COLLATE NOCASE LIMIT 1', [name.trim()]);
    if (r.isNotEmpty && p.isEmpty) return asInt(r.first['id']);
    return Books.saveParty('customer', {'name': name.trim(), 'phone': phone.trim().isEmpty ? null : phone.trim()});
  }

  // ---------------------------------------------------------------- repairs
  static Future<int> createRepair({
    required int customerId,
    required String device,
    required String problem,
    String? imei,
    String? condition,
    String? lockCode,
    int estimate = 0,
    int advance = 0,
    int? accountId,
    String? promised,
    String? technician,
    String? note,
    String? date,
  }) async {
    Books.need('repairs', 'Repair jobs');
    if (device.trim().isEmpty) throw AccountingError('Enter the device');
    if (problem.trim().isEmpty) throw AccountingError('Describe the problem');
    final id = await Books._write((x) async {
      final number = await Books._nextNumber(x, 'repairs', 'JOB');
      String? t(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
      final id = await x.insert('repairs', {
        'number': number,
        'date': date ?? ymd(DateTime.now()),
        'customer_id': customerId,
        'device': device.trim(),
        'imei': t(imei),
        'problem': problem.trim(),
        'condition': t(condition),
        'lock_code': t(lockCode),
        'estimate': estimate,
        'advance': 0,
        'status': 'received',
        'promised': promised,
        'technician': t(technician),
        'note': t(note),
        'created_at': Books._now(),
      });
      await Books._log(x, 'repair', 'Repair $number · ${device.trim()}', number, estimate);
      return id;
    });
    if (advance > 0) await repairPayment(id, advance, accountId: accountId, date: date);
    Books.notifyChanged();
    return id;
  }

  /// Money from the customer for a repair (advance or final payment).
  static Future<void> repairPayment(int id, int amount, {int? accountId, String? date}) async {
    if (amount <= 0) return;
    final r = (await Books.query('SELECT * FROM repairs WHERE id = ?', [id])).first;
    final acc = accountId ?? asInt((await Books.query('SELECT id FROM accounts WHERE code = ?', [cashCode])).first['id']);
    await Books.trusted(() => Books.createPayment(
        kind: 'receipt',
        partyId: asInt(r['customer_id']),
        amount: amount,
        accountId: acc,
        date: date,
        reference: '${r['number']}',
        note: 'Repair ${r['device']}'));
    await Books.execute('UPDATE repairs SET advance = advance + ? WHERE id = ?', [amount, id]);
  }

  static Future<void> repairStatus(int id, String status, {int? charge, int? partsCost}) async {
    final now = ymd(DateTime.now());
    await Books.execute(
        'UPDATE repairs SET status = ?, charge = COALESCE(?, charge), parts_cost = COALESCE(?, parts_cost), '
        "ready_at = CASE WHEN ? = 'ready' AND ready_at IS NULL THEN ? ELSE ready_at END WHERE id = ?",
        [status, charge, partsCost, status, now, id]);
  }

  /// Hands the device back: books the repair charge as income (owed by the
  /// customer) and takes [paidNow]. Returns what is still due.
  static Future<int> deliverRepair(int id, {required int charge, int partsCost = 0, int paidNow = 0, int? accountId, String? date}) async {
    Books.need('repairs', 'Repair jobs');
    final r = (await Books.query('SELECT * FROM repairs WHERE id = ?', [id])).first;
    if (r['status'] == 'delivered') throw AccountingError('Already delivered');
    if (charge < 0) throw AccountingError('Charge cannot be negative');
    final when = date ?? ymd(DateTime.now());
    final cid = asInt(r['customer_id']);
    await Books._write((x) async {
      if (charge > 0) {
        await Books.post(x, 'repair', id, when, 'Repair ${r['number']} · ${r['device']}', [
          JL(await Books.accountId_(x, arCode), charge, 0, 'customer', cid),
          JL(await Books.accountId_(x, serviceIncomeCode), 0, charge),
        ]);
      }
      await x.update('repairs', {'status': 'delivered', 'charge': charge, 'parts_cost': partsCost, 'delivered_at': when}, where: 'id = ?', whereArgs: [id]);
      await Books._log(x, 'repair', 'Delivered ${r['number']} · ${r['device']}', '${r['number']}', charge);
    });
    if (paidNow > 0) await repairPayment(id, paidNow, accountId: accountId, date: when);
    Books.notifyChanged();
    final paid = asInt(r['advance']) + paidNow;
    return charge - paid;
  }

  static Future<List<Rec>> repairs({String? status}) => Books.query(
      'SELECT r.*, c.name AS customer, c.phone FROM repairs r LEFT JOIN customers c ON c.id = r.customer_id '
      "${status == null ? '' : status == 'open' ? "WHERE r.status NOT IN ('delivered', 'cancelled') " : 'WHERE r.status = ? '}"
      "ORDER BY CASE r.status WHEN 'ready' THEN 0 WHEN 'delivered' THEN 2 WHEN 'cancelled' THEN 3 ELSE 1 END, r.id DESC",
      status == null || status == 'open' ? const [] : [status]);

  static String repairMessage(Map<String, String> s, Rec r) {
    final shop = (s['business_name'] ?? '').trim().isEmpty ? 'our shop' : s['business_name']!.trim();
    final due = (asInt(r['charge']) > 0 ? asInt(r['charge']) : asInt(r['estimate'])) - asInt(r['advance']);
    return switch ('${r['status']}') {
      'ready' => 'Hello ${r['customer']} 🙏\nYour ${r['device']} is repaired and ready for pickup at $shop (job ${r['number']}).'
          '${due > 0 ? '\nAmount to pay: ${Money.rs(due)}' : ''}\nPlease bring this message. Thank you!',
      'delivered' => 'Thank you ${r['customer']}! Your ${r['device']} was delivered (job ${r['number']}). '
          'Repair warranty as discussed. — $shop',
      _ => 'Hello ${r['customer']} 🙏\nWe received your ${r['device']} for repair at $shop. Job no. ${r['number']}.'
          '\nProblem: ${r['problem']}${asInt(r['estimate']) > 0 ? '\nEstimate: ${Money.rs(asInt(r['estimate']))}' : ''}'
          '${r['promised'] == null ? '' : '\nReady by: ${prettyDate('${r['promised']}')}'}\nWe will message you when it is ready.',
    };
  }

  // ---------------------------------------------------------------- exchange / used phones
  /// Buys a used phone from a customer: it becomes a 'used' product in stock
  /// (bought through a purchase from the seller, paid from [accountId]).
  static Future<int> buyUsed({
    String sellerName = '',
    String sellerPhone = '',
    int? customerId, // the seller, already a customer
    String? storage,
    String? color,
    List<String> checks = const [], // what was tested OK ("Screen", "Camera"…)
    String? idPhoto,
    required String model,
    String? brand,
    String? imei,
    required int price,
    int resale = 0,
    String? grade,
    int? battery,
    String? accessories,
    String? idProof,
    String? photo,
    String? note,
    int? accountId,
    String? date,
  }) async {
    Books.need('exchange', 'Buying a used phone');
    if (model.trim().isEmpty) throw AccountingError('Enter the phone model');
    if (price <= 0) throw AccountingError('Enter the price paid');
    final when = date ?? ymd(DateTime.now());
    if (customerId == null && sellerName.trim().isEmpty && sellerPhone.trim().isEmpty) throw AccountingError('Choose who is selling the phone');
    final i = (imei ?? '').replaceAll(RegExp(r'\s'), '');
    if (i.isNotEmpty) {
      final again = await Books.query('SELECT e.number FROM exchanges e JOIN products p ON p.id = e.product_id WHERE e.imei = ? AND p.stock > 0', [i]);
      if (again.isNotEmpty) throw AccountingError('This IMEI is already in your used stock (${again.first['number']})');
    }
    return Books.trusted(() => _buyUsed(
        sellerName, sellerPhone, model, brand, i, price, resale, grade, battery, accessories, idProof, photo, note, accountId, when,
        customerId: customerId, storage: storage, color: color, checks: checks, idPhoto: idPhoto));
  }

  static Future<int> _buyUsed(String sellerName, String sellerPhone, String model, String? brand, String? imei, int price, int resale, String? grade,
      int? battery, String? accessories, String? idProof, String? photo, String? note, int? accountId, String when,
      {int? customerId, String? storage, String? color, List<String> checks = const [], String? idPhoto}) async {
    final cid = customerId ?? await customerFor(sellerName, sellerPhone);
    final cust = (await Books.query('SELECT * FROM customers WHERE id = ?', [cid])).first;
    // the seller as a supplier (same name and phone), for the purchase
    var sid = asInt((await Books.query(
            'SELECT id FROM suppliers WHERE name = ? COLLATE NOCASE AND IFNULL(phone, \'\') = ? LIMIT 1', ['${cust['name']}', '${cust['phone'] ?? ''}']))
        .firstOrNull?['id']);
    if (sid == 0) {
      sid = await Books.saveParty('supplier', {'name': '${cust['name']}', 'phone': cust['phone'], 'notes': 'Exchange / used phone seller'});
    }
    final cat = await Books.addCategory('Used Phones');
    final pid = await Books.saveProduct({
      'name': model.trim(),
      'variant': [storage, color].where((v) => (v ?? '').trim().isNotEmpty).map((v) => v!.trim()).join(' · '),
      'brand': (brand ?? '').trim().isEmpty ? null : brand!.trim(),
      'category_id': cat,
      'condition': 'used',
      'price': resale > 0 ? resale : (price * 1.15).round(),
      'gst_bp': 0,
      'low_stock': 0,
      'image': photo,
    }, openingCost: price);
    final acc = accountId ?? asInt((await Books.query('SELECT id FROM accounts WHERE code = ?', [cashCode])).first['id']);
    final purchase = await Books.createPurchase(
        items: [ItemIn(pid, 1, price, (imei ?? '').trim().isEmpty ? null : imei!.trim())],
        supplierId: sid,
        paid: price,
        accountId: acc,
        date: when,
        note: 'Used phone from ${cust['name']}');
    final id = await Books._write((x) async {
      final number = await Books._nextNumber(x, 'exchanges', 'EXC');
      String? t(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
      return x.insert('exchanges', {
        'number': number,
        'date': when,
        'customer_id': cid,
        'supplier_id': sid,
        'purchase_id': purchase,
        'product_id': pid,
        'model': model.trim(),
        'imei': t(imei),
        'grade': t(grade),
        'battery': battery,
        'accessories': t(accessories),
        'id_proof': t(idProof),
        'photo': photo,
        'price': price,
        'resale': resale,
        'note': t(note),
        'brand': t(brand),
        'storage': t(storage),
        'color': t(color),
        'checks': checks.isEmpty ? null : checks.join(','),
        'id_photo': idPhoto,
        'created_at': Books._now(),
      });
    });
    if ((imei ?? '').trim().length == 15) {
      try {
        await SmartImei.learn(imei!, productId: pid, name: model, brand: brand);
      } catch (_) {}
    }
    Books.notifyChanged();
    return id;
  }

  /// The new phone's bill for an exchange (the old phone was taken in part payment).
  static Future<void> linkExchangeSale(int exchangeId, int saleId) async {
    await Books.execute('UPDATE exchanges SET sale_id = ? WHERE id = ?', [saleId, exchangeId]);
    Books.notifyChanged();
  }

  /// People who sold or exchanged phones: count and money paid.
  static Future<List<Rec>> sellers() => Books.query('SELECT c.*, COUNT(e.id) AS phones, IFNULL(SUM(e.price), 0) AS paid, MAX(e.date) AS last '
      'FROM exchanges e JOIN customers c ON c.id = e.customer_id GROUP BY c.id ORDER BY last DESC');

  static Future<Rec?> exchange(int id) async => (await Books.query(
          'SELECT e.*, c.name AS customer, c.phone, c.address, c.aadhaar, c.photo AS customer_photo, p.stock, p.price AS list_price, '
          's.number AS new_bill, s.total AS new_total, s.date AS new_date, '
          '(SELECT GROUP_CONCAT(i.name, \' + \') FROM sale_items i WHERE i.sale_id = e.sale_id) AS new_phone, '
          '(SELECT s2.number FROM sale_items i2 JOIN sales s2 ON s2.id = i2.sale_id WHERE i2.product_id = e.product_id ORDER BY s2.id DESC LIMIT 1) AS sold_on, '
          '(SELECT i3.rate FROM sale_items i3 WHERE i3.product_id = e.product_id ORDER BY i3.id DESC LIMIT 1) AS sold_for '
          'FROM exchanges e LEFT JOIN customers c ON c.id = e.customer_id LEFT JOIN products p ON p.id = e.product_id '
          'LEFT JOIN sales s ON s.id = e.sale_id WHERE e.id = ?',
          [id]))
      .firstOrNull;

  static Future<List<Rec>> exchanges() => Books.query('SELECT e.*, c.name AS customer, c.phone, p.stock, s.number AS new_bill, '
      '(SELECT GROUP_CONCAT(i.name, \' + \') FROM sale_items i WHERE i.sale_id = e.sale_id) AS new_phone, '
      '(SELECT s.number FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE i.product_id = e.product_id ORDER BY s.id DESC LIMIT 1) AS sold_on, '
      '(SELECT i.rate FROM sale_items i WHERE i.product_id = e.product_id ORDER BY i.id DESC LIMIT 1) AS sold_for '
      'FROM exchanges e LEFT JOIN customers c ON c.id = e.customer_id LEFT JOIN products p ON p.id = e.product_id '
      'LEFT JOIN sales s ON s.id = e.sale_id ORDER BY e.id DESC');

  // ---------------------------------------------------------------- finance companies
  /// Finance-company sales still waiting for the payout, by company.
  static Future<List<Rec>> financePending() => Books.query('SELECT e.*, c.name AS customer, c.phone, s.number AS sale_no, s.date AS sale_date, '
      '(e.price - e.down_payment) AS expected FROM emi_plans e JOIN customers c ON c.id = e.customer_id '
      'LEFT JOIN sales s ON s.id = e.sale_id '
      "WHERE e.kind = 'finance' AND e.disbursed = 0 AND e.status != 'cancelled' ORDER BY e.start_date, e.id");

  static Future<List<Rec>> financeReceived() => Books.query('SELECT e.*, c.name AS customer FROM emi_plans e JOIN customers c ON c.id = e.customer_id '
      "WHERE e.kind = 'finance' AND e.disbursed = 1 ORDER BY e.disbursed_on DESC LIMIT 50");

  /// The finance company paid the shop. With [post] the money is booked as a
  /// receipt against the customer's bill (use it when the sale left that
  /// amount due); without, it is only marked (already in the books).
  static Future<void> financeReceivedOn(int planId, int amount, {int? accountId, bool post = true, String? date}) async {
    final e = (await Books.query('SELECT * FROM emi_plans WHERE id = ?', [planId])).first;
    final when = date ?? ymd(DateTime.now());
    if (post && amount > 0) {
      if (accountId == null) throw AccountingError('Choose the bank account');
      await Books.createPayment(
          kind: 'receipt',
          partyId: asInt(e['customer_id']),
          amount: amount,
          accountId: accountId,
          date: when,
          reference: '${e['loan_no'] ?? e['opp_id'] ?? ''}',
          note: 'Payout from ${e['financer'] ?? 'finance company'}');
    }
    await Books.execute('UPDATE emi_plans SET disbursed = 1, disbursed_on = ?, disbursed_amount = ? WHERE id = ?', [when, amount, planId]);
    Books.notifyChanged();
  }

  // ---------------------------------------------------------------- IMEI history
  static Future<List<DeviceEvent>> imeiHistory(String imei) async {
    final c = imei.replaceAll(RegExp(r'[\s\-/]'), '');
    if (c.isEmpty) return const [];
    final out = <DeviceEvent>[];
    for (final r in await Books.query(
        'SELECT b.id, b.number, b.date, i.name, i.rate, s.name AS supplier FROM purchase_items i JOIN purchases b ON b.id = i.purchase_id '
        'JOIN suppliers s ON s.id = b.supplier_id WHERE TRIM(i.serial) = ?',
        [c])) {
      out.add(DeviceEvent('${r['date']}', 'bought', 'Bought · ${r['name']}', '${r['number']} from ${r['supplier']} at ${Money.rs(asInt(r['rate']))}',
          target: 'purchase', targetId: asInt(r['id'])));
    }
    for (final r in await Books.query(
        'SELECT s.id, s.number, s.date, i.id AS item, i.name, i.rate, i.opp_id, p.warranty_months, c.name AS customer FROM sale_items i '
        'JOIN sales s ON s.id = i.sale_id JOIN products p ON p.id = i.product_id LEFT JOIN customers c ON c.id = s.customer_id WHERE TRIM(i.serial) = ?',
        [c])) {
      out.add(DeviceEvent('${r['date']}', 'sold', 'Sold · ${r['name']}',
          '${r['number']} to ${r['customer'] ?? 'walk-in'} at ${Money.rs(asInt(r['rate']))}${(r['opp_id'] ?? '').toString().isEmpty ? '' : ' · finance ${r['opp_id']}'}',
          target: 'sale', targetId: asInt(r['id'])));
      final m = asInt(r['warranty_months']);
      if (m > 0) {
        final d = DateTime.parse('${r['date']}');
        final end = DateTime(d.year, d.month + m, d.day);
        final left = end.difference(DateTime.now()).inDays;
        out.add(DeviceEvent(
            ymd(end),
            'warranty',
            left >= 0 ? 'Warranty ends' : 'Warranty ended',
            '$m months from ${prettyDate('${r['date']}')}'
                '${left >= 0 ? ' · $left days left' : ''}'));
      }
      for (final x in await Books.query(
          'SELECT r.number, r.date, r.reason, i.value FROM sale_return_items i JOIN sale_returns r ON r.id = i.return_id WHERE i.sale_item_id = ?',
          [r['item']])) {
        out.add(DeviceEvent(
            '${x['date']}', 'returned', 'Returned', '${x['number']} · ${Money.rs(asInt(x['value']))}${x['reason'] == null ? '' : ' · ${x['reason']}'}',
            target: 'sale', targetId: asInt(r['id'])));
      }
    }
    for (final r in await Books.query(
        'SELECT e.number, e.date, e.price, e.grade, c.name AS customer FROM exchanges e LEFT JOIN customers c ON c.id = e.customer_id WHERE TRIM(e.imei) = ?',
        [c])) {
      out.add(DeviceEvent('${r['date']}', 'exchange', 'Bought back (exchange)',
          '${r['number']} from ${r['customer'] ?? '—'} at ${Money.rs(asInt(r['price']))}${r['grade'] == null ? '' : ' · grade ${r['grade']}'}'));
    }
    for (final r in await Books.query('SELECT r.id, r.number, r.date, r.problem, r.status, r.charge FROM repairs r WHERE TRIM(r.imei) = ?', [c])) {
      out.add(DeviceEvent('${r['date']}', 'repair', 'Repair · ${repairLabels[r['status']] ?? r['status']}',
          '${r['number']} · ${r['problem']}${asInt(r['charge']) > 0 ? ' · ${Money.rs(asInt(r['charge']))}' : ''}',
          target: 'repair', targetId: asInt(r['id'])));
    }
    for (final r
        in await Books.query('SELECT e.id, e.kind, e.financer, e.emi, e.months, e.start_date, e.status FROM emi_plans e WHERE TRIM(e.imei) = ?', [c])) {
      out.add(DeviceEvent('${r['start_date']}', 'emi', r['kind'] == 'finance' ? 'Finance · ${r['financer'] ?? 'company'}' : 'Shop EMI',
          '${Money.rs(asInt(r['emi']))} × ${r['months']} · ${r['status']}',
          target: 'emi', targetId: asInt(r['id'])));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }
}
