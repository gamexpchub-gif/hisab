import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'money.dart';

/// Double-entry accounting engine.
///
/// Every business document (sale, purchase, receipt, payment, expense,
/// transfer, opening balance) becomes exactly one balanced journal entry,
/// written in the same database transaction as the document. Reports read
/// only journal lines, so ledgers, P&L and balance sheet always agree.
class AccountingError implements Exception {
  final String message;
  AccountingError(this.message);
  @override
  String toString() => message;
}

class JL {
  final int account;
  final int debit;
  final int credit;
  final String? partyType;
  final int? partyId;
  const JL(this.account, this.debit, this.credit, [this.partyType, this.partyId]);
}

class ItemIn {
  final int productId;
  final int qty;
  final int rate; // paise
  final String? serial;
  const ItemIn(this.productId, this.qty, this.rate, [this.serial]);
}

typedef Rec = Map<String, Object?>;

int asInt(Object? v) => v == null ? 0 : (v as num).toInt();

const cashCode = '1000',
    arCode = '1100',
    inventoryCode = '1200',
    gstInCode = '1300',
    apCode = '2000',
    gstOutCode = '2100',
    obeCode = '3900',
    salesCode = '4000',
    cogsCode = '5000';

class Books {
  /// Bumped after every write; screens listen and reload.
  static final changes = ValueNotifier<int>(0);

  static Future<Database> get _db => AppDb.instance;

  static String _now() => DateTime.now().toIso8601String();

  // ------------------------------------------------------------ helpers
  static Future<int> accountId(DatabaseExecutor x, String code) async {
    final r = await x.query('accounts', columns: ['id'], where: 'code = ?', whereArgs: [code]);
    if (r.isEmpty) throw AccountingError('System account $code is missing');
    return asInt(r.first['id']);
  }

  static Future<String> _nextNumber(DatabaseExecutor x, String table, String prefix) async {
    final r = await x.rawQuery('SELECT COUNT(*) AS c FROM $table WHERE number LIKE ?', ['$prefix-%']);
    var n = asInt(r.first['c']) + 1;
    while (true) {
      final candidate = '$prefix-${n.toString().padLeft(5, '0')}';
      final e = await x.query(table, columns: ['id'], where: 'number = ?', whereArgs: [candidate]);
      if (e.isEmpty) return candidate;
      n++;
    }
  }

  static Future<int> post(DatabaseExecutor x, String sourceType, int sourceId, String date, String narration,
      List<JL> lines) async {
    final clean = lines.where((l) => l.debit != 0 || l.credit != 0).toList();
    if (clean.isEmpty) throw AccountingError('Nothing to post');
    final dr = clean.fold<int>(0, (a, l) => a + l.debit);
    final cr = clean.fold<int>(0, (a, l) => a + l.credit);
    if (dr != cr) throw AccountingError('Unbalanced entry: Dr $dr ≠ Cr $cr');
    final dup = await x.query('journal_entries',
        columns: ['id'], where: 'source_type = ? AND source_id = ?', whereArgs: [sourceType, sourceId]);
    if (dup.isNotEmpty) throw AccountingError('$sourceType #$sourceId is already posted');
    final c = await x.rawQuery('SELECT COUNT(*) AS c FROM journal_entries');
    var n = asInt(c.first['c']) + 1;
    String ref;
    while (true) {
      ref = 'JV-${n.toString().padLeft(6, '0')}';
      final e = await x.query('journal_entries', columns: ['id'], where: 'ref = ?', whereArgs: [ref]);
      if (e.isEmpty) break;
      n++;
    }
    final entryId = await x.insert('journal_entries', {
      'date': date,
      'ref': ref,
      'narration': narration,
      'source_type': sourceType,
      'source_id': sourceId,
      'created_at': _now(),
    });
    for (final l in clean) {
      await x.insert('journal_lines', {
        'entry_id': entryId,
        'account_id': l.account,
        'debit': l.debit,
        'credit': l.credit,
        'party_type': l.partyType,
        'party_id': l.partyId,
      });
    }
    return entryId;
  }

  static Future<void> _log(DatabaseExecutor x, String kind, String message, [String? ref, int? amount]) async {
    await x.insert('audit_log', {'kind': kind, 'message': message, 'ref': ref, 'amount': amount, 'created_at': _now()});
  }

  static Future<T> _write<T>(Future<T> Function(Transaction t) body) async {
    final db = await _db;
    final result = await db.transaction(body);
    changes.value++;
    return result;
  }

  static Future<Rec> _product(DatabaseExecutor x, int id) async {
    final r = await x.query('products', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw AccountingError('Unknown product');
    return r.first;
  }

  static List<ItemIn> _validItems(List<ItemIn> items) {
    final out = items.where((i) => i.productId > 0 && i.qty > 0).toList();
    if (out.isEmpty) throw AccountingError('Add at least one item');
    if (out.any((i) => i.rate < 0)) throw AccountingError('Rate cannot be negative');
    return out;
  }

  // ------------------------------------------------------------ sales
  static Future<int> createSale({
    required List<ItemIn> items,
    int? customerId,
    int? paid,
    int? accountId,
    int discount = 0,
    String? date,
    String? note,
    List<MapEntry<int, int>>? splits, // account id → amount, for split payments
  }) {
    return _write((x) async {
      final when = date ?? ymd(DateTime.now());
      String? customerName;
      if (customerId != null) {
        final c = await x.query('customers', where: 'id = ?', whereArgs: [customerId]);
        if (c.isEmpty) throw AccountingError('Unknown customer');
        customerName = c.first['name'] as String;
      }
      final valid = _validItems(items);
      // stock check per product (an item may repeat)
      final need = <int, int>{};
      for (final i in valid) {
        need[i.productId] = (need[i.productId] ?? 0) + i.qty;
      }
      for (final e in need.entries) {
        final p = await _product(x, e.key);
        if (asInt(p['stock']) < e.value) {
          throw AccountingError('Only ${p['stock']} × ${p['name']} in stock');
        }
      }
      var subtotal = 0, tax = 0, cogs = 0;
      final rows = <Rec>[];
      for (final i in valid) {
        final p = await _product(x, i.productId);
        final amount = i.rate * i.qty;
        final gst = asInt(p['gst_bp']);
        final lineTax = Money.percent(amount, gst);
        final unitCost = asInt(p['cost']);
        rows.add({
          'product_id': i.productId,
          'name': p['name'],
          'qty': i.qty,
          'rate': i.rate,
          'gst_bp': gst,
          'amount': amount,
          'tax': lineTax,
          'unit_cost': unitCost,
          'serial': (i.serial ?? '').trim().isEmpty ? null : i.serial!.trim(),
        });
        await x.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [i.qty, i.productId]);
        subtotal += amount;
        tax += lineTax;
        cogs += unitCost * i.qty;
      }
      if (discount < 0 || discount > subtotal) throw AccountingError('Discount must be between 0 and the subtotal');
      final total = subtotal + tax - discount;
      final parts = (splits ?? const <MapEntry<int, int>>[]).where((e) => e.value != 0).toList();
      if (parts.any((e) => e.value < 0)) throw AccountingError('Split amounts cannot be negative');
      final paidAmt = parts.isNotEmpty ? parts.fold<int>(0, (a, e) => a + e.value) : (paid ?? (customerId == null ? total : 0));
      if (paidAmt < 0 || paidAmt > total) throw AccountingError('Paid amount must be between 0 and the total');
      if (customerId == null && paidAmt != total) {
        throw AccountingError('Walk-in sales must be fully paid — select a customer for credit sales');
      }
      final money = parts.isNotEmpty ? parts.first.key : (accountId ?? await accountId_(x, cashCode));
      final payments = parts.isNotEmpty ? parts : [if (paidAmt > 0) MapEntry(money, paidAmt)];
      final number = await _nextNumber(x, 'sales', 'INV');
      final saleId = await x.insert('sales', {
        'number': number,
        'date': when,
        'customer_id': customerId,
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'paid': paidAmt,
        'cogs': cogs,
        'account_id': money,
        'note': note,
        'created_at': _now(),
      });
      for (final r in rows) {
        await x.insert('sale_items', {...r, 'sale_id': saleId});
      }
      for (final p in payments) {
        await x.insert('sale_payments', {'sale_id': saleId, 'account_id': p.key, 'amount': p.value});
      }
      final ar = await accountId_(x, arCode);
      await post(x, 'sale', saleId, when, 'Sale $number${customerName != null ? ' to $customerName' : ''}', [
        JL(ar, total, 0, 'customer', customerId),
        JL(await accountId_(x, salesCode), 0, subtotal - discount),
        JL(await accountId_(x, gstOutCode), 0, tax),
        JL(await accountId_(x, cogsCode), cogs, 0),
        JL(await accountId_(x, inventoryCode), 0, cogs),
        for (final p in payments) JL(p.key, p.value, 0),
        JL(ar, 0, paidAmt, 'customer', customerId),
      ]);
      await _log(x, 'sale', 'New sale recorded', number, total);
      return saleId;
    });
  }

  // small alias so the long parameter name `accountId` above does not shadow the helper
  static Future<int> accountId_(DatabaseExecutor x, String code) => accountId(x, code);

  // ------------------------------------------------------------ purchases
  static Future<int> createPurchase({
    required List<ItemIn> items,
    required int supplierId,
    int paid = 0,
    int? accountId,
    String? date,
    String? billNo,
    String? note,
    String? billImage,
  }) {
    return _write((x) async {
      final when = date ?? ymd(DateTime.now());
      final s = await x.query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
      if (s.isEmpty) throw AccountingError('Select a supplier');
      final supplierName = s.first['name'] as String;
      final valid = _validItems(items);
      var subtotal = 0, tax = 0;
      final rows = <Rec>[];
      for (final i in valid) {
        final p = await _product(x, i.productId);
        final amount = i.rate * i.qty;
        final gst = asInt(p['gst_bp']);
        final lineTax = Money.percent(amount, gst);
        // weighted average cost
        final oldQty = asInt(p['stock']) < 0 ? 0 : asInt(p['stock']);
        final newQty = oldQty + i.qty;
        final newCost = (asInt(p['cost']) * oldQty + amount + newQty ~/ 2) ~/ newQty;
        await x.rawUpdate('UPDATE products SET stock = stock + ?, cost = ? WHERE id = ?', [i.qty, newCost, i.productId]);
        rows.add({
          'product_id': i.productId,
          'name': p['name'],
          'qty': i.qty,
          'rate': i.rate,
          'gst_bp': gst,
          'amount': amount,
          'tax': lineTax,
          'serial': (i.serial ?? '').trim().isEmpty ? null : i.serial!.trim(),
        });
        subtotal += amount;
        tax += lineTax;
      }
      final total = subtotal + tax;
      if (paid < 0 || paid > total) throw AccountingError('Paid amount must be between 0 and the bill total');
      final money = accountId ?? await accountId_(x, cashCode);
      final number = await _nextNumber(x, 'purchases', 'PUR');
      final pid = await x.insert('purchases', {
        'number': number,
        'bill_no': billNo,
        'date': when,
        'supplier_id': supplierId,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'paid': paid,
        'account_id': money,
        'note': note,
        'bill_image': billImage,
        'created_at': _now(),
      });
      for (final r in rows) {
        await x.insert('purchase_items', {...r, 'purchase_id': pid});
      }
      final ap = await accountId_(x, apCode);
      await post(x, 'purchase', pid, when, 'Purchase $number from $supplierName', [
        JL(await accountId_(x, inventoryCode), subtotal, 0),
        JL(await accountId_(x, gstInCode), tax, 0),
        JL(ap, 0, total, 'supplier', supplierId),
        JL(ap, paid, 0, 'supplier', supplierId),
        JL(money, 0, paid),
      ]);
      await _log(x, 'purchase', 'Purchase from $supplierName', number, total);
      return pid;
    });
  }

  // ------------------------------------------------------------ receipts / payments
  /// kind: 'receipt' (customer pays us) or 'payment' (we pay a supplier).
  static Future<int> createPayment({
    required String kind,
    required int partyId,
    required int amount,
    required int accountId,
    String? date,
    String? reference,
    String? note,
  }) {
    return _write((x) async {
      if (amount <= 0) throw AccountingError('Amount must be greater than zero');
      final isReceipt = kind == 'receipt';
      final partyType = isReceipt ? 'customer' : 'supplier';
      final p = await x.query(isReceipt ? 'customers' : 'suppliers', where: 'id = ?', whereArgs: [partyId]);
      if (p.isEmpty) throw AccountingError('Select a $partyType');
      final name = p.first['name'] as String;
      final when = date ?? ymd(DateTime.now());
      final number = await _nextNumber(x, 'payments', isReceipt ? 'RCT' : 'PAY');
      final id = await x.insert('payments', {
        'number': number,
        'kind': kind,
        'date': when,
        'party_type': partyType,
        'party_id': partyId,
        'account_id': accountId,
        'amount': amount,
        'reference': reference,
        'note': note,
        'created_at': _now(),
      });
      final msg = isReceipt ? 'Payment received from $name' : 'Payment made to $name';
      final lines = isReceipt
          ? [JL(accountId, amount, 0), JL(await accountId_(x, arCode), 0, amount, 'customer', partyId)]
          : [JL(await accountId_(x, apCode), amount, 0, 'supplier', partyId), JL(accountId, 0, amount)];
      await post(x, kind, id, when, msg, lines);
      await _log(x, kind, msg, number, amount);
      return id;
    });
  }

  // ------------------------------------------------------------ expenses & transfers
  static Future<int> createExpense({
    required int headId,
    required int amount,
    required int accountId,
    String? date,
    String? note,
    String? image,
  }) {
    return _write((x) async {
      if (amount <= 0) throw AccountingError('Amount must be greater than zero');
      final h = await x.query('accounts', where: 'id = ? AND type = ?', whereArgs: [headId, 'expense']);
      if (h.isEmpty) throw AccountingError('Select an expense category');
      final when = date ?? ymd(DateTime.now());
      final number = await _nextNumber(x, 'expenses', 'EXP');
      final id = await x.insert('expenses', {
        'number': number,
        'date': when,
        'head_id': headId,
        'account_id': accountId,
        'amount': amount,
        'note': note,
        'image': image,
        'created_at': _now(),
      });
      final head = h.first['name'] as String;
      await post(x, 'expense', id, when, (note ?? '').isEmpty ? head : '$head — $note',
          [JL(headId, amount, 0), JL(accountId, 0, amount)]);
      await _log(x, 'expense', 'Expense: $head', number, amount);
      return id;
    });
  }

  static Future<int> createTransfer({
    required int fromId,
    required int toId,
    required int amount,
    String? date,
    String? note,
  }) {
    return _write((x) async {
      if (amount <= 0) throw AccountingError('Amount must be greater than zero');
      if (fromId == toId) throw AccountingError('Choose two different accounts');
      final when = date ?? ymd(DateTime.now());
      final number = await _nextNumber(x, 'transfers', 'CON');
      final id = await x.insert('transfers', {
        'number': number,
        'date': when,
        'from_id': fromId,
        'to_id': toId,
        'amount': amount,
        'note': note,
        'created_at': _now(),
      });
      await post(x, 'transfer', id, when, 'Fund transfer $number', [JL(toId, amount, 0), JL(fromId, 0, amount)]);
      await _log(x, 'transfer', 'Fund transfer', number, amount);
      return id;
    });
  }

  // ------------------------------------------------------------ masters
  static Future<int> saveProduct(Rec data, {int? id, int openingQty = 0, int openingCost = 0}) {
    return _write((x) async {
      final name = (data['name'] as String? ?? '').trim();
      if (name.isEmpty) throw AccountingError('Product name is required');
      final sku = (data['sku'] as String? ?? '').trim();
      final values = {...data, 'name': name, 'sku': sku.isEmpty ? null : sku};
      if (sku.isNotEmpty) {
        final d = await x.query('products',
            columns: ['id'], where: 'sku = ? AND id != ?', whereArgs: [sku, id ?? -1]);
        if (d.isNotEmpty) throw AccountingError('SKU already used by another product');
      }
      if (id != null) {
        await x.update('products', values, where: 'id = ?', whereArgs: [id]);
        return id;
      }
      final pid = await x.insert('products', {...values, 'stock': 0, 'cost': 0, 'created_at': _now()});
      if (openingQty > 0) {
        await x.update('products', {'stock': openingQty, 'cost': openingCost}, where: 'id = ?', whereArgs: [pid]);
        final value = openingQty * openingCost;
        if (value > 0) {
          await post(x, 'opening_stock', pid, ymd(DateTime.now()), 'Opening stock — $name', [
            JL(await accountId_(x, inventoryCode), value, 0),
            JL(await accountId_(x, obeCode), 0, value),
          ]);
        }
      }
      await _log(x, 'product', 'Product added: $name');
      return pid;
    });
  }

  /// type: 'customer' or 'supplier'
  static Future<int> saveParty(String type, Rec data, {int? id, int opening = 0}) {
    return _write((x) async {
      final table = type == 'customer' ? 'customers' : 'suppliers';
      final name = (data['name'] as String? ?? '').trim();
      if (name.isEmpty) throw AccountingError('Name is required');
      final values = {...data, 'name': name};
      if (id != null) {
        await x.update(table, values, where: 'id = ?', whereArgs: [id]);
        return id;
      }
      final pid = await x.insert(table, {...values, 'opening': opening, 'created_at': _now()});
      if (opening > 0) {
        final obe = await accountId_(x, obeCode);
        if (type == 'customer') {
          await post(x, 'opening_customer', pid, ymd(DateTime.now()), 'Opening balance — $name',
              [JL(await accountId_(x, arCode), opening, 0, 'customer', pid), JL(obe, 0, opening)]);
        } else {
          await post(x, 'opening_supplier', pid, ymd(DateTime.now()), 'Opening balance — $name',
              [JL(obe, opening, 0), JL(await accountId_(x, apCode), 0, opening, 'supplier', pid)]);
        }
      }
      await _log(x, type, 'New $type: $name');
      return pid;
    });
  }

  static Future<int> addMoneyAccount(String name, String kind) => saveMoneyAccount({'name': name, 'kind': kind});

  /// Creates or updates a cash / bank / UPI / wallet / credit-card account.
  /// card_type: cash | savings | current | debit | credit | upi | wallet.
  /// A credit card is a liability (its balance is what you owe); an opening
  /// balance is posted against Opening Balance Equity.
  static Future<int> saveMoneyAccount(Rec data, {int? id, int opening = 0}) {
    return _write((x) async {
      final name = '${data['name'] ?? ''}'.trim();
      if (name.isEmpty) throw AccountingError('Account name is required');
      final cardType = (data['card_type'] as String?) ??
          switch (data['kind']) { 'cash' => 'cash', 'upi' => 'upi', 'wallet' => 'wallet', _ => 'savings' };
      final credit = cardType == 'credit';
      final kind = switch (cardType) { 'cash' => 'cash', 'upi' => 'upi', 'wallet' => 'wallet', 'credit' => 'card', _ => 'bank' };
      final values = <String, Object?>{
        'name': name,
        'kind': kind,
        'type': credit ? 'liability' : 'asset',
        'card_type': cardType,
        for (final k in ['bank_name', 'acc_no', 'holder', 'ifsc', 'network', 'color'])
          if (data.containsKey(k)) k: data[k],
        if (data.containsKey('credit_limit')) 'credit_limit': asInt(data['credit_limit']),
        if (data.containsKey('bill_days')) 'bill_days': asInt(data['bill_days']) <= 0 ? 40 : asInt(data['bill_days']),
      };
      if (id != null) {
        await x.update('accounts', values, where: 'id = ?', whereArgs: [id]);
        return id;
      }
      final prefix = credit ? '21' : '10';
      var n = 30;
      while ((await x.query('accounts', where: 'code = ?', whereArgs: ['$prefix$n'])).isNotEmpty) {
        n++;
      }
      final aid = await x.insert('accounts', {...values, 'code': '$prefix$n', 'is_system': 0});
      if (opening > 0) {
        final obe = await accountId_(x, obeCode);
        await post(x, 'opening_account', aid, ymd(DateTime.now()), 'Opening balance — $name',
            credit ? [JL(obe, opening, 0), JL(aid, 0, opening)] : [JL(aid, opening, 0), JL(obe, 0, opening)]);
      }
      await _log(x, 'transfer', 'Account added: $name');
      return aid;
    });
  }

  /// Credit-card position: spends are settled oldest-first by payments; each
  /// unpaid spend falls due [bill_days] (default 40) after it was made.
  static Future<CardStatus> cardStatus(Rec card) async {
    final id = asInt(card['id']);
    final days = asInt(card['bill_days']) <= 0 ? 40 : asInt(card['bill_days']);
    final rows = await query(
        'SELECT e.date AS date, l.debit AS dr, l.credit AS cr FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id '
        'WHERE l.account_id = ? ORDER BY e.date, e.id, l.id',
        [id]);
    final open = <List<Object>>[];
    for (final r in rows) {
      final spend = asInt(r['cr']);
      var pay = asInt(r['dr']);
      if (spend > 0) open.add([r['date'] as String, spend]);
      while (pay > 0 && open.isNotEmpty) {
        final take = math.min(pay, open.first[1] as int);
        open.first[1] = (open.first[1] as int) - take;
        pay -= take;
        if (open.first[1] == 0) open.removeAt(0);
      }
    }
    final buckets = <String, int>{}; // due date → amount
    for (final o in open) {
      final due = ymd(DateTime.parse(o[0] as String).add(Duration(days: days)));
      buckets[due] = (buckets[due] ?? 0) + (o[1] as int);
    }
    final dues = buckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final outstanding = await balance(id, 'liability');
    return CardStatus(outstanding, asInt(card['credit_limit']), dues, days);
  }

  static Future<int> addCategory(String name) {
    return _write((x) async {
      final n = name.trim();
      if (n.isEmpty) throw AccountingError('Category name is required');
      final e = await x.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [n]);
      if (e.isNotEmpty) return asInt(e.first['id']);
      return x.insert('categories', {'name': n});
    });
  }

  static Future<int> addExpenseHead(String name) {
    return _write((x) async {
      if (name.trim().isEmpty) throw AccountingError('Name is required');
      var n = 6100;
      while ((await x.query('accounts', where: 'code = ?', whereArgs: ['$n'])).isNotEmpty) {
        n += 10;
      }
      return x.insert('accounts', {'code': '$n', 'name': name.trim(), 'type': 'expense', 'kind': 'expense', 'is_system': 0});
    });
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await _db;
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    changes.value++;
  }

  static Future<Map<String, String>> settings() async {
    final db = await _db;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''};
  }

  // ------------------------------------------------------------ queries
  static Future<List<Rec>> query(String sql, [List<Object?>? args]) async => (await _db).rawQuery(sql, args);

  static Future<List<Rec>> accounts({String? kind, String? type}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    return db.query('accounts', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: 'code');
  }

  /// Cash, bank, UPI and wallet accounts; credit cards too when [withCards]
  /// (cards can pay for purchases and expenses but never hold money).
  static Future<List<Rec>> moneyAccounts({bool withCards = false}) async => (await _db).query('accounts',
      where: withCards ? "kind IN ('cash','bank','upi','wallet','card')" : "kind IN ('cash','bank','upi','wallet')",
      orderBy: 'type, code');

  /// Natural balance of a money account: what you hold (cash/bank/UPI/wallet)
  /// or, for a credit card, what you owe on it.
  static Future<int> moneyBalance(Rec a) => balance(asInt(a['id']), a['type'] as String);

  static bool debitNormal(String type) => type == 'asset' || type == 'expense';

  static String _range(String alias, String? from, String? to, List<Object?> args) {
    var s = '';
    if (from != null) {
      s += ' AND $alias.date >= ?';
      args.add(from);
    }
    if (to != null) {
      s += ' AND $alias.date <= ?';
      args.add(to);
    }
    return s;
  }

  /// Natural-side balance of an account.
  static Future<int> balance(int accountId, String type, {String? from, String? to}) async {
    final args = <Object?>[accountId];
    final r = await query(
        'SELECT COALESCE(SUM(l.debit),0) AS dr, COALESCE(SUM(l.credit),0) AS cr FROM journal_lines l '
        'JOIN journal_entries e ON e.id = l.entry_id WHERE l.account_id = ?${_range('e', from, to, args)}',
        args);
    final dr = asInt(r.first['dr']), cr = asInt(r.first['cr']);
    return debitNormal(type) ? dr - cr : cr - dr;
  }

  static Future<int> balanceByCode(String code, {String? from, String? to}) async {
    final a = await query('SELECT id, type FROM accounts WHERE code = ?', [code]);
    if (a.isEmpty) return 0;
    return balance(asInt(a.first['id']), a.first['type'] as String, from: from, to: to);
  }

  /// party_id → outstanding (customers: they owe us; suppliers: we owe them).
  static Future<Map<int, int>> partyBalances(String type) async {
    final db = await _db;
    final acct = await accountId_(db, type == 'customer' ? arCode : apCode);
    final rows = await query(
        'SELECT party_id, COALESCE(SUM(debit),0) AS dr, COALESCE(SUM(credit),0) AS cr FROM journal_lines '
        'WHERE account_id = ? AND party_type = ? AND party_id IS NOT NULL GROUP BY party_id',
        [acct, type]);
    return {
      for (final r in rows)
        asInt(r['party_id']):
            type == 'customer' ? asInt(r['dr']) - asInt(r['cr']) : asInt(r['cr']) - asInt(r['dr'])
    };
  }

  static Future<int> partyBalance(String type, int id) async => (await partyBalances(type))[id] ?? 0;

  /// Statement rows with running balance.
  static Future<List<Rec>> ledger(
      {int? accountId, String? accountType, String? partyType, int? partyId, String? from, String? to}) async {
    final args = <Object?>[];
    var where = '1=1';
    if (accountId != null) {
      where += ' AND l.account_id = ?';
      args.add(accountId);
    }
    if (partyType != null) {
      where += ' AND l.party_type = ? AND l.party_id = ?';
      args.addAll([partyType, partyId]);
    }
    where += _range('e', from, to, args);
    final rows = await query(
        'SELECT e.date, e.ref, e.narration, a.name AS account, l.debit, l.credit FROM journal_lines l '
        'JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id '
        'WHERE $where ORDER BY e.date, e.id, l.id',
        args);
    final dn = accountType != null ? debitNormal(accountType) : partyType == 'customer';
    var running = 0;
    return [
      for (final r in rows)
        {
          ...r,
          'balance': running += dn ? asInt(r['debit']) - asInt(r['credit']) : asInt(r['credit']) - asInt(r['debit'])
        }
    ];
  }

  static Future<List<Rec>> trialBalance({String? to}) async {
    final args = <Object?>[];
    final range = _range('e', null, to, args);
    return query(
        'SELECT a.id, a.code, a.name, a.type, COALESCE(SUM(l.debit),0) AS dr, COALESCE(SUM(l.credit),0) AS cr '
        'FROM accounts a JOIN journal_lines l ON l.account_id = a.id JOIN journal_entries e ON e.id = l.entry_id '
        'WHERE 1=1$range GROUP BY a.id HAVING dr != 0 OR cr != 0 ORDER BY a.code',
        args);
  }

  static Future<ProfitLoss> profitLoss(String? from, String to) async {
    final args = <Object?>[];
    final range = _range('e', from, to, args);
    final rows = await query(
        'SELECT a.code, a.name, a.type, COALESCE(SUM(l.debit),0) AS dr, COALESCE(SUM(l.credit),0) AS cr '
        'FROM accounts a JOIN journal_lines l ON l.account_id = a.id JOIN journal_entries e ON e.id = l.entry_id '
        "WHERE a.type IN ('income','expense')$range GROUP BY a.id ORDER BY a.code",
        args);
    final pl = ProfitLoss();
    for (final r in rows) {
      final dr = asInt(r['dr']), cr = asInt(r['cr']);
      final code = r['code'] as String, name = r['name'] as String;
      if (r['type'] == 'income') {
        final v = cr - dr;
        if (v == 0) continue;
        pl.income.add(MapEntry(name, v));
        if (code == salesCode) pl.revenue = v;
      } else {
        final v = dr - cr;
        if (v == 0) continue;
        if (code == cogsCode) {
          pl.cogs = v;
        } else {
          pl.expenses.add(MapEntry(name, v));
        }
      }
    }
    return pl;
  }

  static Future<BalanceSheet> balanceSheet(String to) async {
    final rows = await trialBalance(to: to);
    final bs = BalanceSheet();
    for (final r in rows) {
      final type = r['type'] as String;
      final net = asInt(r['dr']) - asInt(r['cr']);
      final v = debitNormal(type) ? net : -net;
      if (v == 0) continue;
      final e = MapEntry(r['name'] as String, v);
      if (type == 'asset') bs.assets.add(e);
      if (type == 'liability') bs.liabilities.add(e);
      if (type == 'equity') bs.equity.add(e);
    }
    bs.profit = (await profitLoss(null, to)).netProfit;
    return bs;
  }

  // ------------------------------------------------------------ dashboard
  static Future<int> _sum(String table, String from, String to) async {
    final r = await query('SELECT COALESCE(SUM(total),0) AS s FROM $table WHERE date >= ? AND date <= ?', [from, to]);
    return asInt(r.first['s']);
  }

  static Future<int> _count(String table, String from, String to) async {
    final r = await query('SELECT COUNT(*) AS c FROM $table WHERE date >= ? AND date <= ?', [from, to]);
    return asInt(r.first['c']);
  }

  static Future<HomeMetrics> homeMetrics() async {
    final now = DateTime.now();
    final t = ymd(now), y = ymd(now.subtract(const Duration(days: 1)));
    final dues = await partyBalances('customer');
    return HomeMetrics(
      todaySales: await _sum('sales', t, t),
      todayInvoices: await _count('sales', t, t),
      todayPurchases: await _sum('purchases', t, t),
      todayBills: await _count('purchases', t, t),
      yesterdaySales: await _sum('sales', y, y),
      totalDue: dues.values.where((v) => v > 0).fold(0, (a, b) => a + b),
    );
  }

  /// period: today | week | month | year → [from, to, prevFrom, prevTo]
  static List<String> periodRange(String period, [DateTime? today]) {
    final t = today ?? DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    switch (period) {
      case 'today':
        final p = d.subtract(const Duration(days: 1));
        return [ymd(d), ymd(d), ymd(p), ymd(p)];
      case 'week':
        final s = d.subtract(Duration(days: d.weekday - 1));
        return [ymd(s), ymd(d), ymd(s.subtract(const Duration(days: 7))), ymd(d.subtract(const Duration(days: 7)))];
      case 'year':
        final pe = DateTime(d.year - 1, d.month, d.day > 28 && d.month == 2 ? 28 : d.day);
        return [ymd(DateTime(d.year, 1, 1)), ymd(d), ymd(DateTime(d.year - 1, 1, 1)), ymd(pe)];
      default:
        final s = DateTime(d.year, d.month, 1);
        final prevEnd = s.subtract(const Duration(days: 1));
        final ps = DateTime(prevEnd.year, prevEnd.month, 1);
        final pe = DateTime(prevEnd.year, prevEnd.month, d.day > prevEnd.day ? prevEnd.day : d.day);
        return [ymd(s), ymd(d), ymd(ps), ymd(pe)];
    }
  }

  static int pctChange(int cur, int prev) {
    if (prev == 0) return cur == 0 ? 0 : 100;
    return ((cur - prev) * 100 / prev).round();
  }

  static Future<Overview> overview(String period) async {
    final r = periodRange(period);
    final sales = await _sum('sales', r[0], r[1]);
    final purchases = await _sum('purchases', r[0], r[1]);
    return Overview(
      sales: sales,
      purchases: purchases,
      salesChange: pctChange(sales, await _sum('sales', r[2], r[3])),
      purchaseChange: pctChange(purchases, await _sum('purchases', r[2], r[3])),
    );
  }

  static Future<List<Alert>> notifications() async {
    final out = <Alert>[];
    final low = await query('SELECT id, name, stock, low_stock FROM products WHERE stock <= low_stock ORDER BY stock LIMIT 30');
    for (final p in low) {
      out.add(Alert('stock', 'Low stock: ${p['name']}', 'Only ${p['stock']} left (alert at ${p['low_stock']})',
          asInt(p['id'])));
    }
    final dues = await partyBalances('customer');
    if (dues.isNotEmpty) {
      final cs = await query('SELECT id, name, credit_limit FROM customers WHERE credit_limit > 0');
      for (final c in cs) {
        final due = dues[asInt(c['id'])] ?? 0;
        if (due > asInt(c['credit_limit'])) {
          out.add(Alert('due', 'Credit limit crossed: ${c['name']}',
              'Due ${Money.rs(due)} / limit ${Money.rs(asInt(c['credit_limit']))}', asInt(c['id'])));
        }
      }
    }
    final pay = await partyBalances('supplier');
    if (pay.isNotEmpty) {
      final ss = await query('SELECT id, name FROM suppliers');
      for (final s in ss) {
        final v = pay[asInt(s['id'])] ?? 0;
        if (v > 0) out.add(Alert('payable', 'Payable to ${s['name']}', '${Money.rs(v)} outstanding', asInt(s['id'])));
      }
    }
    return out;
  }

  static Future<DashboardData> dashboard() async {
    final now = DateTime.now();
    final t = ymd(now);
    final monthStart = ymd(DateTime(now.year, now.month, 1));
    final today = await profitLoss(t, t);
    final month = await profitLoss(monthStart, t);
    final money = <MapEntry<String, int>>[];
    for (final a in await moneyAccounts()) {
      money.add(MapEntry(a['name'] as String, await balance(asInt(a['id']), 'asset')));
    }
    final months = <MonthBar>[];
    for (var i = 5; i >= 0; i--) {
      final s = DateTime(now.year, now.month - i, 1);
      final e = DateTime(s.year, s.month + 1, 1).subtract(const Duration(days: 1));
      months.add(MonthBar(monthName(s.month), await _sum('sales', ymd(s), ymd(e)), await _sum('purchases', ymd(s), ymd(e))));
    }
    final dues = await partyBalances('customer');
    final pays = await partyBalances('supplier');
    final topDue = <Rec>[];
    final ids = dues.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ids.take(5)) {
      final c = await query('SELECT id, name, phone FROM customers WHERE id = ?', [e.key]);
      if (c.isNotEmpty) topDue.add({...c.first, 'due': e.value});
    }
    final stock = await query('SELECT COALESCE(SUM(cost * stock),0) AS v FROM products WHERE stock > 0');
    return DashboardData(
      profitToday: today.netProfit,
      grossToday: today.grossProfit,
      month: month,
      money: money,
      receivable: dues.values.where((v) => v > 0).fold(0, (a, b) => a + b),
      payable: pays.values.where((v) => v > 0).fold(0, (a, b) => a + b),
      stockValue: asInt(stock.first['v']),
      months: months,
      topProducts: await query(
          'SELECT i.name, SUM(i.qty) AS qty, SUM(i.amount) AS amount FROM sale_items i JOIN sales s ON s.id = i.sale_id '
          'WHERE s.date >= ? GROUP BY i.product_id ORDER BY amount DESC LIMIT 5',
          [monthStart]),
      topDue: topDue,
      lowStock: await query('SELECT * FROM products WHERE stock <= low_stock ORDER BY stock LIMIT 6'),
      recentSales: await recentSales(6),
    );
  }

  /// Every sale with what the Sales book searches and shows: customer name,
  /// phone, address and photo, item names, IMEI / serial numbers and the
  /// accounts that took the money.
  static Future<List<Rec>> salesBook() => query(
      'SELECT s.*, c.name AS customer, c.phone AS phone, c.alt_phone AS alt_phone, c.address AS address, '
      'c.photo AS photo, '
      '(SELECT GROUP_CONCAT(i.name, \' · \') FROM sale_items i WHERE i.sale_id = s.id) AS items, '
      '(SELECT IFNULL(SUM(i.qty), 0) FROM sale_items i WHERE i.sale_id = s.id) AS qty, '
      '(SELECT GROUP_CONCAT(i.serial, \' \') FROM sale_items i WHERE i.sale_id = s.id AND i.serial IS NOT NULL AND i.serial <> \'\') AS serials, '
      '(SELECT GROUP_CONCAT(a.name, \' + \') FROM sale_payments p JOIN accounts a ON a.id = p.account_id WHERE p.sale_id = s.id) AS accounts '
      'FROM sales s LEFT JOIN customers c ON c.id = s.customer_id ORDER BY s.date DESC, s.id DESC');

  static Future<List<Rec>> recentSales(int limit, {String? search}) async {
    final args = <Object?>[];
    var where = '';
    if (search != null && search.isNotEmpty) {
      where = 'WHERE s.number LIKE ? OR c.name LIKE ? OR c.phone LIKE ?';
      args.addAll(['%$search%', '%$search%', '%$search%']);
    }
    args.add(limit);
    return query(
        'SELECT s.*, c.name AS customer FROM sales s LEFT JOIN customers c ON c.id = s.customer_id '
        '$where ORDER BY s.date DESC, s.id DESC LIMIT ?',
        args);
  }

  static Future<List<Rec>> recentPurchases(int limit, {String? search}) async {
    final args = <Object?>[];
    var where = '';
    if (search != null && search.isNotEmpty) {
      where = 'WHERE p.number LIKE ? OR p.bill_no LIKE ? OR s.name LIKE ?';
      args.addAll(['%$search%', '%$search%', '%$search%']);
    }
    args.add(limit);
    return query(
        'SELECT p.*, s.name AS supplier FROM purchases p JOIN suppliers s ON s.id = p.supplier_id '
        '$where ORDER BY p.date DESC, p.id DESC LIMIT ?',
        args);
  }

  static Future<List<Rec>> activity(int limit) => query('SELECT * FROM audit_log ORDER BY id DESC LIMIT ?', [limit]);

  // ------------------------------------------------------------ analytics
  /// Everything the Dashboard needs for one period, plus the same figures
  /// for the previous period of equal length (for % change).
  static Future<Analytics> analytics(DateTime from, DateTime to) async {
    final f = ymd(from), t = ymd(to);
    final days = DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays + 1;
    final prevTo = from.subtract(const Duration(days: 1));
    final prevFrom = prevTo.subtract(Duration(days: days - 1));
    final cur = await _periodTotals(f, t);
    final prev = await _periodTotals(ymd(prevFrom), ymd(prevTo));

    // ---- time series
    final gran = days <= 1 ? 'hour' : days <= 31 ? 'day' : days <= 120 ? 'week' : 'month';
    final keyExpr = gran == 'hour' ? 'substr(created_at, 12, 2)' : 'date';
    Future<Map<String, List<int>>> grouped(String sql) async {
      final rows = await query(sql.replaceAll('{k}', keyExpr), [f, t]);
      return {for (final r in rows) r['k'] as String: [asInt(r['a']), asInt(r['b'])]};
    }

    final s = await grouped('SELECT {k} AS k, COALESCE(SUM(total),0) AS a, COALESCE(SUM(subtotal - discount - cogs),0) AS b '
        'FROM sales WHERE date >= ? AND date <= ? GROUP BY k');
    final pu = await grouped('SELECT {k} AS k, COALESCE(SUM(total),0) AS a, 0 AS b FROM purchases WHERE date >= ? AND date <= ? GROUP BY k');
    final ex = await grouped('SELECT {k} AS k, COALESCE(SUM(amount),0) AS a, 0 AS b FROM expenses WHERE date >= ? AND date <= ? GROUP BY k');

    final buckets = <SeriesPoint>[];
    void add(String label, Iterable<String> keys) {
      var sa = 0, pa = 0, gp = 0, e = 0;
      for (final k in keys) {
        sa += s[k]?[0] ?? 0;
        gp += s[k]?[1] ?? 0;
        pa += pu[k]?[0] ?? 0;
        e += ex[k]?[0] ?? 0;
      }
      buckets.add(SeriesPoint(label, sa, pa, gp - e));
    }

    if (gran == 'hour') {
      for (var h = 0; h < 24; h++) {
        add(h == 0 ? '12a' : h < 12 ? '${h}a' : h == 12 ? '12p' : '${h - 12}p', [two(h)]);
      }
    } else {
      final allDays = [for (var i = 0; i < days; i++) DateTime(from.year, from.month, from.day + i)];
      if (gran == 'day') {
        for (final d in allDays) {
          add(days <= 7 ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1] : '${d.day}', [ymd(d)]);
        }
      } else if (gran == 'week') {
        for (var i = 0; i < allDays.length; i += 7) {
          final chunk = allDays.sublist(i, i + 7 > allDays.length ? allDays.length : i + 7);
          add('${chunk.first.day} ${monthName(chunk.first.month)}', chunk.map(ymd));
        }
      } else {
        final byMonth = <String, List<String>>{};
        for (final d in allDays) {
          byMonth.putIfAbsent('${d.year}-${two(d.month)}', () => []).add(ymd(d));
        }
        for (final e in byMonth.entries) {
          add(monthName(int.parse(e.key.substring(5))), e.value);
        }
      }
    }

    // ---- breakdowns
    final categories = await query(
        "SELECT IFNULL(c.name, 'Other') AS name, COALESCE(SUM(i.amount),0) AS v FROM sale_items i "
        'JOIN sales s ON s.id = i.sale_id JOIN products p ON p.id = i.product_id '
        'LEFT JOIN categories c ON c.id = p.category_id WHERE s.date >= ? AND s.date <= ? '
        "GROUP BY IFNULL(c.name, 'Other') ORDER BY v DESC",
        [f, t]);
    final payments = await query(
        'SELECT a.name AS name, a.kind AS kind, COALESCE(SUM(x.v),0) AS v FROM ('
        '  SELECT sp.account_id AS account_id, sp.amount AS v FROM sale_payments sp JOIN sales s ON s.id = sp.sale_id '
        '  WHERE s.date >= ? AND s.date <= ? '
        "  UNION ALL SELECT account_id, amount AS v FROM payments WHERE kind = 'receipt' AND date >= ? AND date <= ?"
        ') x JOIN accounts a ON a.id = x.account_id GROUP BY a.id ORDER BY v DESC',
        [f, t, f, t]);
    final expenseHeads = await query(
        'SELECT h.name AS name, COALESCE(SUM(e.amount),0) AS v FROM expenses e JOIN accounts h ON h.id = e.head_id '
        'WHERE e.date >= ? AND e.date <= ? GROUP BY h.id ORDER BY v DESC LIMIT 6',
        [f, t]);
    final topProducts = await query(
        'SELECT i.product_id AS id, i.name AS name, SUM(i.qty) AS qty, SUM(i.amount) AS v, '
        'SUM(i.amount - i.unit_cost * i.qty) AS profit FROM sale_items i JOIN sales s ON s.id = i.sale_id '
        'WHERE s.date >= ? AND s.date <= ? GROUP BY i.product_id ORDER BY v DESC LIMIT 5',
        [f, t]);
    final dues = await partyBalances('customer');
    final topCustomersRaw = await query(
        'SELECT c.id AS id, c.name AS name, c.phone AS phone, COUNT(s.id) AS n, SUM(s.total) AS v, SUM(s.paid) AS paid, '
        'MAX(s.date) AS last FROM sales s JOIN customers c ON c.id = s.customer_id '
        'WHERE s.date >= ? AND s.date <= ? GROUP BY c.id ORDER BY v DESC LIMIT 8',
        [f, t]);
    final topCustomers = [for (final r in topCustomersRaw) {...r, 'due': dues[asInt(r['id'])] ?? 0}];
    final walkIn = asInt((await query(
            'SELECT COALESCE(SUM(total),0) AS v FROM sales WHERE customer_id IS NULL AND date >= ? AND date <= ?', [f, t]))
        .first['v']);

    final money = <MapEntry<String, int>>[];
    for (final a in await moneyAccounts()) {
      money.add(MapEntry(a['name'] as String, await balance(asInt(a['id']), 'asset')));
    }
    return Analytics(
      from: from,
      to: to,
      granularity: gran,
      cur: cur,
      prev: prev,
      series: buckets,
      categories: categories,
      payments: payments,
      expenseHeads: expenseHeads,
      topProducts: topProducts,
      topCustomers: topCustomers,
      walkInSales: walkIn,
      money: money,
      receivable: dues.values.where((v) => v > 0).fold(0, (a, b) => a + b),
      payable: (await partyBalances('supplier')).values.where((v) => v > 0).fold(0, (a, b) => a + b),
      lowStock: await query('SELECT * FROM products WHERE stock <= low_stock ORDER BY stock LIMIT 5'),
      recentSales: await recentSales(5),
    );
  }

  static Future<PeriodTotals> _periodTotals(String f, String t) async {
    final s = (await query(
            'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total, COALESCE(SUM(paid),0) AS paid, '
            'COALESCE(SUM(tax),0) AS tax FROM sales WHERE date >= ? AND date <= ?',
            [f, t]))
        .first;
    final p = (await query('SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total FROM purchases WHERE date >= ? AND date <= ?',
            [f, t]))
        .first;
    final newCustomers = asInt((await query('SELECT COUNT(*) AS c FROM customers WHERE substr(created_at,1,10) >= ? AND substr(created_at,1,10) <= ?',
            [f, t]))
        .first['c']);
    final pl = await profitLoss(f, t);
    return PeriodTotals(
      sales: asInt(s['total']),
      invoices: asInt(s['n']),
      collected: asInt(s['paid']),
      gstCollected: asInt(s['tax']),
      purchases: asInt(p['total']),
      bills: asInt(p['n']),
      revenue: pl.revenue,
      cogs: pl.cogs,
      expenses: pl.operatingExpenses,
      grossProfit: pl.grossProfit,
      netProfit: pl.netProfit,
      newCustomers: newCustomers,
    );
  }

  // ------------------------------------------------------------ party ledger intelligence
  /// FIFO ageing of each party's outstanding balance: payments settle the
  /// oldest bills first; what remains is aged by bill date.
  static Future<Map<int, Ageing>> ageing(String type) async {
    final db = await _db;
    final acct = await accountId_(db, type == 'customer' ? arCode : apCode);
    final rows = await query(
        'SELECT l.party_id AS pid, e.date AS date, l.debit AS dr, l.credit AS cr FROM journal_lines l '
        'JOIN journal_entries e ON e.id = l.entry_id WHERE l.account_id = ? AND l.party_type = ? AND l.party_id IS NOT NULL '
        'ORDER BY e.date, e.id, l.id',
        [acct, type]);
    final open = <int, List<List<Object>>>{}; // pid → [[date, amount]]
    final last = <int, String>{};
    for (final r in rows) {
      final pid = asInt(r['pid']);
      final inc = type == 'customer' ? asInt(r['dr']) : asInt(r['cr']);
      var dec = type == 'customer' ? asInt(r['cr']) : asInt(r['dr']);
      final q = open.putIfAbsent(pid, () => []);
      last[pid] = r['date'] as String;
      if (inc > 0) q.add([r['date'] as String, inc]);
      while (dec > 0 && q.isNotEmpty) {
        final head = q.first;
        final take = math.min(dec, head[1] as int);
        head[1] = (head[1] as int) - take;
        dec -= take;
        if (head[1] == 0) q.removeAt(0);
      }
    }
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    final out = <int, Ageing>{};
    for (final pid in {...open.keys, ...last.keys}) {
      final b = [0, 0, 0, 0];
      var oldest = 0;
      for (final item in open[pid] ?? const <List<Object>>[]) {
        final days = d0.difference(DateTime.parse(item[0] as String)).inDays;
        oldest = math.max(oldest, days);
        final amt = item[1] as int;
        b[days <= 30 ? 0 : days <= 60 ? 1 : days <= 90 ? 2 : 3] += amt;
      }
      out[pid] = Ageing(b, oldest, last[pid]);
    }
    return out;
  }

  /// Lifetime numbers for a customer (sales) or supplier (purchases).
  static Future<PartyStats> partyStats(String type, int id) async {
    final isC = type == 'customer';
    final docs = (await query(
            isC
                ? 'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS t, COALESCE(SUM(paid),0) AS p, MAX(date) AS last, MIN(date) AS first FROM sales WHERE customer_id = ?'
                : 'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS t, COALESCE(SUM(paid),0) AS p, MAX(date) AS last, MIN(date) AS first FROM purchases WHERE supplier_id = ?',
            [id]))
        .first;
    final pay = (await query(
            'SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS t, MAX(date) AS last FROM payments WHERE party_type = ? AND party_id = ?',
            [type, id]))
        .first;
    final reminder = await query(
        "SELECT created_at FROM audit_log WHERE kind = 'reminder' AND ref = ? ORDER BY id DESC LIMIT 1", ['$type:$id']);
    return PartyStats(
      docs: asInt(docs['n']),
      business: asInt(docs['t']),
      paidAtBill: asInt(docs['p']),
      payments: asInt(pay['n']),
      paymentsTotal: asInt(pay['t']),
      lastDoc: docs['last'] as String?,
      firstDoc: docs['first'] as String?,
      lastPayment: pay['last'] as String?,
      lastReminder: reminder.isEmpty ? null : reminder.first['created_at'] as String,
    );
  }

  static Future<void> logReminder(String type, int id, String name, String channel) async {
    final db = await _db;
    await _log(db, 'reminder', 'Payment reminder to $name ($channel)', '$type:$id');
    changes.value++;
  }

  // ------------------------------------------------------------ khata: cash lending & due dates
  /// Cash given to / taken from a party outside a sale or purchase
  /// ("You gave" / "You got"). kind: 'gave' | 'got'.
  static Future<int> createLend({
    required String kind,
    required String partyType,
    required int partyId,
    required int amount,
    required int accountId,
    String? date,
    String? reason,
  }) {
    return _write((x) async {
      if (amount <= 0) throw AccountingError('Amount must be greater than zero');
      if (kind != 'gave' && kind != 'got') throw AccountingError('Unknown entry type');
      final isC = partyType == 'customer';
      final p = await x.query(isC ? 'customers' : 'suppliers', where: 'id = ?', whereArgs: [partyId]);
      if (p.isEmpty) throw AccountingError('Choose a customer or supplier');
      final name = p.first['name'] as String;
      final when = date ?? ymd(DateTime.now());
      final number = await _nextNumber(x, 'cash_lends', 'KH');
      final id = await x.insert('cash_lends', {
        'number': number,
        'kind': kind,
        'party_type': partyType,
        'party_id': partyId,
        'account_id': accountId,
        'amount': amount,
        'date': when,
        'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
        'created_at': _now(),
      });
      final party = await accountId_(x, isC ? arCode : apCode);
      final why = (reason ?? '').trim().isEmpty ? '' : ' — ${reason!.trim()}';
      final lines = kind == 'gave'
          ? [JL(party, amount, 0, partyType, partyId), JL(accountId, 0, amount)]
          : [JL(accountId, amount, 0), JL(party, 0, amount, partyType, partyId)];
      final text = kind == 'gave' ? 'Cash given to $name$why' : 'Cash received from $name$why';
      await post(x, 'lend', id, when, text, lines);
      await _log(x, kind == 'gave' ? 'payment' : 'receipt', text, number, amount);
      return id;
    });
  }

  static Future<int> addDue(String partyType, int partyId, int amount, String dueDate, String? note) {
    return _write((x) async {
      if (amount <= 0) throw AccountingError('Amount must be greater than zero');
      return x.insert('party_dues', {
        'party_type': partyType,
        'party_id': partyId,
        'amount': amount,
        'due_date': dueDate,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'status': 'open',
        'created_at': _now(),
      });
    });
  }

  static Future<void> setDueStatus(int id, String status) =>
      _write((x) => x.update('party_dues', {'status': status}, where: 'id = ?', whereArgs: [id]));

  static Future<void> deleteDue(int id) => _write((x) => x.delete('party_dues', where: 'id = ?', whereArgs: [id]));

  /// Due dates, soonest first, with the party's name and phone.
  static Future<List<Rec>> dues({String? partyType, int? partyId, bool openOnly = true}) => query(
      'SELECT d.*, CASE d.party_type WHEN \'customer\' THEN (SELECT name FROM customers WHERE id = d.party_id) '
      'ELSE (SELECT name FROM suppliers WHERE id = d.party_id) END AS party, '
      'CASE d.party_type WHEN \'customer\' THEN (SELECT phone FROM customers WHERE id = d.party_id) '
      'ELSE (SELECT phone FROM suppliers WHERE id = d.party_id) END AS phone, '
      'CASE d.party_type WHEN \'customer\' THEN (SELECT photo FROM customers WHERE id = d.party_id) '
      'ELSE (SELECT photo FROM suppliers WHERE id = d.party_id) END AS photo '
      'FROM party_dues d WHERE 1=1'
      '${openOnly ? " AND d.status = 'open'" : ''}'
      '${partyType != null ? ' AND d.party_type = ? AND d.party_id = ?' : ''} '
      'ORDER BY d.status = \'open\' DESC, d.due_date',
      partyType != null ? [partyType, partyId] : null);

  /// Every credit movement: goods on credit (sales/purchases with balance),
  /// cash given / received, and payments — newest first.
  static Future<List<Rec>> khataFeed() => query(
      "SELECT 'goods' AS kind, s.id AS doc_id, s.number AS ref, s.date AS date, 'customer' AS party_type, "
      's.customer_id AS party_id, c.name AS party, c.photo AS photo, s.total AS amount, s.total - s.paid AS credit, '
      "(SELECT GROUP_CONCAT(name || ' ×' || qty, ', ') FROM sale_items WHERE sale_id = s.id) AS reason, s.created_at AS created_at "
      'FROM sales s JOIN customers c ON c.id = s.customer_id WHERE s.total > s.paid '
      'UNION ALL '
      "SELECT 'bill', p.id, p.number, p.date, 'supplier', p.supplier_id, su.name, su.photo, p.total, p.total - p.paid, "
      "(SELECT GROUP_CONCAT(name || ' ×' || qty, ', ') FROM purchase_items WHERE purchase_id = p.id), p.created_at "
      'FROM purchases p JOIN suppliers su ON su.id = p.supplier_id WHERE p.total > p.paid '
      'UNION ALL '
      "SELECT 'cash_' || l.kind, l.id, l.number, l.date, l.party_type, l.party_id, "
      "CASE l.party_type WHEN 'customer' THEN (SELECT name FROM customers WHERE id = l.party_id) ELSE (SELECT name FROM suppliers WHERE id = l.party_id) END, "
      "CASE l.party_type WHEN 'customer' THEN (SELECT photo FROM customers WHERE id = l.party_id) ELSE (SELECT photo FROM suppliers WHERE id = l.party_id) END, "
      'l.amount, l.amount, l.reason, l.created_at FROM cash_lends l '
      'UNION ALL '
      'SELECT pm.kind, pm.id, pm.number, pm.date, pm.party_type, pm.party_id, '
      "CASE pm.party_type WHEN 'customer' THEN (SELECT name FROM customers WHERE id = pm.party_id) ELSE (SELECT name FROM suppliers WHERE id = pm.party_id) END, "
      "CASE pm.party_type WHEN 'customer' THEN (SELECT photo FROM customers WHERE id = pm.party_id) ELSE (SELECT photo FROM suppliers WHERE id = pm.party_id) END, "
      'pm.amount, pm.amount, COALESCE(pm.note, pm.reference), pm.created_at FROM payments pm '
      'ORDER BY date DESC, created_at DESC');

  static Future<KhataTotals> khataTotals() async {
    Future<int> one(String sql) async => asInt((await query(sql)).first['v']);
    final cb = await partyBalances('customer'), sb = await partyBalances('supplier');
    // a party can be on either side: customers who paid in advance are owed money, and so on
    final get = cb.values.where((v) => v > 0).fold<int>(0, (a, b) => a + b) + sb.values.where((v) => v < 0).fold<int>(0, (a, b) => a - b);
    final give = sb.values.where((v) => v > 0).fold<int>(0, (a, b) => a + b) + cb.values.where((v) => v < 0).fold<int>(0, (a, b) => a - b);
    return KhataTotals(
      youGet: get,
      youGive: give,
      goodsCredit: await one('SELECT COALESCE(SUM(total - paid),0) AS v FROM sales WHERE customer_id IS NOT NULL'),
      cashLent: await one("SELECT COALESCE(SUM(amount),0) AS v FROM cash_lends WHERE kind = 'gave' AND party_type = 'customer'"),
      received: await one("SELECT COALESCE(SUM(amount),0) AS v FROM payments WHERE kind = 'receipt'") +
          await one("SELECT COALESCE(SUM(amount),0) AS v FROM cash_lends WHERE kind = 'got' AND party_type = 'customer'"),
      customersWithDue: cb.values.where((v) => v > 0).length,
      suppliersToPay: sb.values.where((v) => v > 0).length,
    );
  }

  /// Products a customer has bought (newest first).
  static Future<List<Rec>> boughtBy(int customerId) => query(
      'SELECT i.product_id AS pid, i.name AS name, i.qty AS qty, i.rate AS rate, i.amount AS amount, i.tax AS tax, '
      'i.serial AS serial, s.date AS date, s.number AS number, s.id AS sale_id, p.image AS image, c.name AS category '
      'FROM sale_items i JOIN sales s ON s.id = i.sale_id LEFT JOIN products p ON p.id = i.product_id '
      'LEFT JOIN categories c ON c.id = p.category_id WHERE s.customer_id = ? ORDER BY s.date DESC, s.id DESC',
      [customerId]);

  /// Goods-on-credit vs cash lent vs money received, for one party.
  static Future<CreditSplit> creditSplit(String type, int id) async {
    Future<int> one(String sql, List<Object?> a) async => asInt((await query(sql, a)).first['v']);
    final isC = type == 'customer';
    return CreditSplit(
      goods: await one(
          isC
              ? 'SELECT COALESCE(SUM(total - paid),0) AS v FROM sales WHERE customer_id = ?'
              : 'SELECT COALESCE(SUM(total - paid),0) AS v FROM purchases WHERE supplier_id = ?',
          [id]),
      cashGave: await one("SELECT COALESCE(SUM(amount),0) AS v FROM cash_lends WHERE kind = 'gave' AND party_type = ? AND party_id = ?", [type, id]),
      cashGot: await one("SELECT COALESCE(SUM(amount),0) AS v FROM cash_lends WHERE kind = 'got' AND party_type = ? AND party_id = ?", [type, id]),
      payments: await one('SELECT COALESCE(SUM(amount),0) AS v FROM payments WHERE party_type = ? AND party_id = ?', [type, id]),
    );
  }

  // ------------------------------------------------------------ expense intelligence
  static Future<ExpenseInsights> expenseInsights(DateTime from, DateTime to) async {
    final f = ymd(from), t = ymd(to);
    final days = to.difference(from).inDays + 1;
    final pTo = from.subtract(const Duration(days: 1));
    final pFrom = pTo.subtract(Duration(days: days - 1));
    Future<int> sum(String a, String b) async =>
        asInt((await query('SELECT COALESCE(SUM(amount),0) AS v FROM expenses WHERE date >= ? AND date <= ?', [a, b])).first['v']);
    final heads = await query(
        'SELECT h.id AS id, h.name AS name, COALESCE(SUM(e.amount),0) AS v, COUNT(e.id) AS n FROM expenses e '
        'JOIN accounts h ON h.id = e.head_id WHERE e.date >= ? AND e.date <= ? GROUP BY h.id ORDER BY v DESC',
        [f, t]);
    final now = DateTime.now();
    // monthly totals for the last 6 months and per-head history for 3 full months
    final months = <MonthBar>[];
    for (var i = 5; i >= 0; i--) {
      final s0 = DateTime(now.year, now.month - i, 1);
      final e0 = DateTime(s0.year, s0.month + 1, 0);
      months.add(MonthBar(monthName(s0.month), await sum(ymd(s0), ymd(e0)), 0));
    }
    final histFrom = ymd(DateTime(now.year, now.month - 3, 1));
    final histTo = ymd(DateTime(now.year, now.month, 0));
    final hist = await query(
        "SELECT e.head_id AS id, h.name AS name, substr(e.date,1,7) AS ym, SUM(e.amount) AS v, "
        "CAST(AVG(CAST(substr(e.date,9,2) AS INTEGER)) AS INTEGER) AS dom FROM expenses e JOIN accounts h ON h.id = e.head_id "
        'WHERE e.date >= ? AND e.date <= ? GROUP BY e.head_id, ym',
        [histFrom, histTo]);
    final byHead = <int, List<Rec>>{};
    for (final r in hist) {
      byHead.putIfAbsent(asInt(r['id']), () => []).add(r);
    }
    final thisMonth = ymd(DateTime(now.year, now.month, 1));
    final paidThisMonth = {
      for (final r in await query('SELECT DISTINCT head_id FROM expenses WHERE date >= ?', [thisMonth])) asInt(r['head_id'])
    };
    final recurring = <RecurringExpense>[];
    final avg3 = <int, int>{};
    for (final e in byHead.entries) {
      final total = e.value.fold<int>(0, (a, r) => a + asInt(r['v']));
      avg3[e.key] = total ~/ 3;
      if (e.value.length >= 2) {
        final amounts = [for (final r in e.value) asInt(r['v'])]..sort();
        final day = e.value.fold<int>(0, (a, r) => a + asInt(r['dom'])) ~/ e.value.length;
        recurring.add(RecurringExpense(e.key, e.value.first['name'] as String, amounts[amounts.length ~/ 2], day,
            paidThisMonth.contains(e.key)));
      }
    }
    recurring.sort((a, b) => a.day.compareTo(b.day));
    final spikes = <MapEntry<String, int>>[];
    for (final h in heads) {
      final avg = avg3[asInt(h['id'])] ?? 0;
      final v = asInt(h['v']);
      if (avg > 0 && v > avg * 3 ~/ 2 && v - avg > 50000) spikes.add(MapEntry(h['name'] as String, ((v - avg) * 100 / avg).round()));
    }
    final revenue = (await profitLoss(f, t)).revenue;
    final recent = await query(
        'SELECT e.head_id AS head_id, h.name AS head, e.amount AS amount, e.account_id AS account_id, e.note AS note '
        'FROM expenses e JOIN accounts h ON h.id = e.head_id ORDER BY e.id DESC LIMIT 20');
    final seen = <String>{};
    final repeat = <Rec>[];
    for (final r in recent) {
      if (seen.add('${r['head_id']}|${r['amount']}') && repeat.length < 4) repeat.add(r);
    }
    final budgets = <int, int>{};
    for (final r in await query("SELECT key, value FROM settings WHERE key LIKE 'budget_%'")) {
      final id = int.tryParse((r['key'] as String).substring(7));
      final v = int.tryParse('${r['value']}');
      if (id != null && v != null && v > 0) budgets[id] = v;
    }
    final total = await sum(f, t);
    return ExpenseInsights(
      total: total,
      previous: await sum(ymd(pFrom), ymd(pTo)),
      days: days,
      heads: heads,
      months: months,
      recurring: recurring,
      spikes: spikes,
      revenue: revenue,
      repeat: repeat,
      budgets: budgets,
    );
  }

  static Future<void> setBudget(int headId, int amount) =>
      setSetting('budget_$headId', amount <= 0 ? '0' : '$amount');

  // ------------------------------------------------------------ inventory
  /// Products with category, units sold and realised gross profit.
  /// filter: all | in | low | out
  static Future<List<Rec>> inventory({String filter = 'all', String search = ''}) {
    final where = <String>[];
    final args = <Object?>[];
    switch (filter) {
      case 'in':
        where.add('p.stock > p.low_stock');
        break;
      case 'low':
        where.add('p.stock > 0 AND p.stock <= p.low_stock');
        break;
      case 'out':
        where.add('p.stock <= 0');
        break;
    }
    if (search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      where.add("(p.name LIKE ? OR IFNULL(p.brand,'') LIKE ? OR IFNULL(c.name,'') LIKE ? OR "
          "IFNULL(p.sku,'') LIKE ? OR IFNULL(p.variant,'') LIKE ?)");
      args.addAll([like, like, like, like, like]);
    }
    return query(
        'SELECT p.*, c.name AS category, '
        '(SELECT COALESCE(SUM(qty),0) FROM sale_items WHERE product_id = p.id) AS sold, '
        '(SELECT COALESCE(SUM(amount - unit_cost * qty),0) FROM sale_items WHERE product_id = p.id) AS profit '
        'FROM products p LEFT JOIN categories c ON c.id = p.category_id '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY p.name COLLATE NOCASE',
        args);
  }

  static Future<InventoryStats> inventoryStats() async {
    final r = (await query('SELECT COUNT(*) AS total, '
            'SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END) AS out_n, '
            'SUM(CASE WHEN stock > 0 AND stock <= low_stock THEN 1 ELSE 0 END) AS low_n, '
            'SUM(CASE WHEN stock > low_stock THEN 1 ELSE 0 END) AS in_n FROM products'))
        .first;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final before = asInt((await query('SELECT COUNT(*) AS c FROM products WHERE created_at < ?', [monthStart])).first['c']);
    final total = asInt(r['total']);
    return InventoryStats(
      total: total,
      out: asInt(r['out_n']),
      low: asInt(r['low_n']),
      inStock: asInt(r['in_n']),
      growth: pctChange(total, before),
    );
  }

  /// Deletes a product that has never been bought or sold.
  static Future<void> deleteProduct(int id) {
    return _write((x) async {
      final used = await x.rawQuery(
          'SELECT (SELECT COUNT(*) FROM sale_items WHERE product_id = ?) + '
          '(SELECT COUNT(*) FROM purchase_items WHERE product_id = ?) + '
          "(SELECT COUNT(*) FROM journal_entries WHERE source_type = 'opening_stock' AND source_id = ?) AS n",
          [id, id, id]);
      if (asInt(used.first['n']) > 0) {
        throw AccountingError('This product has stock or transactions in the books, so it cannot be deleted');
      }
      final p = await _product(x, id);
      await x.delete('products', where: 'id = ?', whereArgs: [id]);
      await _log(x, 'product', 'Product deleted: ${p['name']}');
    });
  }

  // ------------------------------------------------------------ demo data
  static Future<void> loadDemo() async {
    final existing = await query('SELECT COUNT(*) AS c FROM products');
    if (asInt(existing.first['c']) > 0) throw AccountingError('Demo data can only be loaded into an empty book');
    final cats = {for (final c in await query('SELECT * FROM categories')) c['name'] as String: asInt(c['id'])};
    final specs = [
      ['iPhone 14 Pro', 'Apple', 'Mobile', 7200000, 8999900, 10, '256GB • Deep Purple', 11990000, 'asset:mobile'],
      ['Samsung Galaxy S23', 'Samsung', 'Mobile', 5200000, 5999900, 3, '8GB • 256GB', 7499900, null],
      ['Redmi Note 13 Pro', 'Xiaomi', 'Mobile', 1950000, 2399900, 6, '8GB • 128GB', 2899900, null],
      ['MacBook Air M1', 'Apple', 'Laptop', 5000000, 5999900, 4, '8GB • 256GB SSD', 7990000, 'asset:laptop'],
      ['Dell Inspiron 3520 i3', 'Dell', 'Laptop', 3100000, 3650000, 3, '8GB • 512GB SSD', 4499000, null],
      ['AirPods Pro', 'Apple', 'Accessories', 1900000, 2499900, 12, '2nd Gen • USB-C', 3490000, 'asset:accessory'],
      ['20W USB-C Charger', 'Apple', 'Accessories', 90000, 149900, 1, 'Type-C', 190000, null],
      ['Logitech G102 Mouse', 'Logitech', 'Accessories', 110000, 159500, 0, 'RGB • Wired', 199500, null],
    ];
    final ids = <int>[];
    for (final s in specs) {
      ids.add(await saveProduct({
        'name': s[0],
        'brand': s[1],
        'category_id': cats[s[2]],
        'gst_bp': 1800,
        'price': s[4],
        'low_stock': 2,
        'condition': 'new',
        'variant': s[6],
        'mrp': s[7],
        'image': s[8],
      }, openingQty: s[5] as int, openingCost: s[3] as int));
    }
    final sup = await saveParty('supplier', {'name': 'Kolkata Mobile Distributors', 'phone': '9830000001'});
    final rahul = await saveParty('customer', {
      'name': 'Rahul Das',
      'phone': '9800000011',
      'alt_phone': '9830012345',
      'address': '12 Station Road, Howrah',
      'credit_limit': 2000000,
      'aadhaar': '234567891234',
      'notes': 'Pays after the 5th of every month',
    });
    final priya = await saveParty('customer', {'name': 'Priya Sen', 'phone': '9800000022'}, opening: 350000);
    final money = await moneyAccounts();
    final cash = asInt(money[0]['id']), bank = asInt(money[1]['id']), upi = asInt(money[2]['id']);
    final now = DateTime.now();
    String ago(int d) => ymd(now.subtract(Duration(days: d)));
    for (final d in [150, 120, 90, 60, 30]) {
      await createSale(items: [ItemIn(ids[5], 2, 2499900)], accountId: upi, date: ago(d));
    }
    await createPurchase(
        items: [ItemIn(ids[2], 4, 1900000)], supplierId: sup, paid: 4000000, accountId: bank, date: ago(20), billNo: 'KMD/889');
    await createSale(
        items: [ItemIn(ids[0], 1, 8999900, '356789104455667')],
        customerId: rahul,
        paid: 6000000,
        accountId: upi,
        date: ago(1));
    await createSale(
        items: [ItemIn(ids[3], 1, 5999900), ItemIn(ids[6], 1, 149900)],
        customerId: priya,
        paid: 6000000,
        accountId: bank,
        discount: 50000);
    await createSale(items: [ItemIn(ids[2], 1, 2399900)], accountId: cash);
    await createPurchase(items: [ItemIn(ids[6], 6, 88000)], supplierId: sup);
    await createPayment(kind: 'receipt', partyId: rahul, amount: 1000000, accountId: upi, reference: 'UPI 4423');
    await createLend(kind: 'gave', partyType: 'customer', partyId: rahul, amount: 500000, accountId: cash, reason: 'Cash loan', date: ago(3));
    await addDue('customer', rahul, 1500000, ymd(now.add(const Duration(days: 4))), '1st installment');
    await addDue('customer', priya, 350000, ymd(now.subtract(const Duration(days: 2))), 'Old due');
    final heads = await accounts(kind: 'expense');
    await createExpense(headId: asInt(heads[0]['id']), amount: 1200000, accountId: bank, date: ago(5), note: 'Monthly rent');
    await createExpense(headId: asInt(heads.last['id']), amount: 24000, accountId: cash, note: 'Tea & snacks');
    await saveMoneyAccount({
      'name': 'HDFC Debit 4821', 'card_type': 'debit', 'bank_name': 'HDFC Bank', 'acc_no': '5241 8800 1234 4821',
      'holder': 'Said Hasan', 'network': 'visa',
    }, opening: 4500000);
    final card = await saveMoneyAccount({
      'name': 'ICICI Credit 7709', 'card_type': 'credit', 'bank_name': 'ICICI Bank', 'acc_no': '4375 5100 2231 7709',
      'holder': 'Said Hasan', 'network': 'mastercard', 'credit_limit': 20000000, 'bill_days': 40,
    });
    await createPurchase(
        items: [ItemIn(ids[6], 10, 85000)], supplierId: sup, paid: 850000, accountId: card, date: ago(33), billNo: 'KMD/921');
    await createExpense(headId: asInt(heads[0]['id']), amount: 350000, accountId: card, date: ago(8), note: 'Shop electricity');
    await createTransfer(fromId: card, toId: cash, amount: 500000, date: ago(2), note: 'ATM cash on card');
  }
}

class PeriodTotals {
  final int sales, invoices, collected, gstCollected, purchases, bills, revenue, cogs, expenses, grossProfit, netProfit, newCustomers;
  PeriodTotals({
    required this.sales,
    required this.invoices,
    required this.collected,
    required this.gstCollected,
    required this.purchases,
    required this.bills,
    required this.revenue,
    required this.cogs,
    required this.expenses,
    required this.grossProfit,
    required this.netProfit,
    required this.newCustomers,
  });
  int get avgBill => invoices == 0 ? 0 : sales ~/ invoices;
  double get margin => revenue == 0 ? 0 : netProfit * 100 / revenue;
}

class SeriesPoint {
  final String label;
  final int sales, purchases, profit;
  SeriesPoint(this.label, this.sales, this.purchases, this.profit);
}

class Analytics {
  final DateTime from, to;
  final String granularity; // hour | day | week | month
  final PeriodTotals cur, prev;
  final List<SeriesPoint> series;
  final List<Rec> categories, payments, expenseHeads, topProducts, topCustomers, lowStock, recentSales;
  final int walkInSales, receivable, payable;
  final List<MapEntry<String, int>> money;
  Analytics({
    required this.from,
    required this.to,
    required this.granularity,
    required this.cur,
    required this.prev,
    required this.series,
    required this.categories,
    required this.payments,
    required this.expenseHeads,
    required this.topProducts,
    required this.topCustomers,
    required this.walkInSales,
    required this.money,
    required this.receivable,
    required this.payable,
    required this.lowStock,
    required this.recentSales,
  });
  int change(int Function(PeriodTotals p) f) => Books.pctChange(f(cur), f(prev));
}

class CardStatus {
  final int outstanding, limit, billDays;
  final List<MapEntry<String, int>> dues; // due date → amount, soonest first
  CardStatus(this.outstanding, this.limit, this.dues, this.billDays);
  int get available => limit <= 0 ? 0 : limit - outstanding;
  double get used => limit <= 0 ? 0 : (outstanding / limit).clamp(0, 1).toDouble();
  MapEntry<String, int>? get next => dues.isEmpty ? null : dues.first;
}

class KhataTotals {
  final int youGet, youGive, goodsCredit, cashLent, received, customersWithDue, suppliersToPay;
  KhataTotals({
    required this.youGet,
    required this.youGive,
    required this.goodsCredit,
    required this.cashLent,
    required this.received,
    required this.customersWithDue,
    required this.suppliersToPay,
  });
  int get net => youGet - youGive;
}

class CreditSplit {
  final int goods, cashGave, cashGot, payments;
  CreditSplit({required this.goods, required this.cashGave, required this.cashGot, required this.payments});
}

class RecurringExpense {
  final int headId;
  final String name;
  final int typical; // paise
  final int day; // usual day of month
  final bool paidThisMonth;
  RecurringExpense(this.headId, this.name, this.typical, this.day, this.paidThisMonth);
}

class ExpenseInsights {
  final int total, previous, days, revenue;
  final List<Rec> heads, repeat;
  final List<MonthBar> months;
  final List<RecurringExpense> recurring;
  final List<MapEntry<String, int>> spikes; // head → % above its 3-month average
  final Map<int, int> budgets; // head id → monthly budget (paise)
  ExpenseInsights({
    required this.total,
    required this.previous,
    required this.days,
    required this.heads,
    required this.months,
    required this.recurring,
    required this.spikes,
    required this.revenue,
    required this.repeat,
    required this.budgets,
  });
  int get change => Books.pctChange(total, previous);
  int get dailyAvg => days == 0 ? 0 : total ~/ days;
  double get ofRevenue => revenue == 0 ? 0 : total * 100 / revenue;
}

class Ageing {
  final List<int> buckets; // 0-30, 31-60, 61-90, 90+ days (paise)
  final int oldestDays;
  final String? lastActivity;
  Ageing(this.buckets, this.oldestDays, this.lastActivity);
  int get total => buckets.fold(0, (a, b) => a + b);
}

class PartyStats {
  final int docs, business, paidAtBill, payments, paymentsTotal;
  final String? lastDoc, firstDoc, lastPayment, lastReminder;
  PartyStats({
    required this.docs,
    required this.business,
    required this.paidAtBill,
    required this.payments,
    required this.paymentsTotal,
    this.lastDoc,
    this.firstDoc,
    this.lastPayment,
    this.lastReminder,
  });
  int get avgBill => docs == 0 ? 0 : business ~/ docs;
}

class InventoryStats {
  final int total, out, low, inStock, growth;
  InventoryStats({required this.total, required this.out, required this.low, required this.inStock, required this.growth});
  int get alerts => out + low;
  double pct(int n) => total == 0 ? 0 : n * 100 / total;
}

class ProfitLoss {
  int revenue = 0;
  int cogs = 0;
  final income = <MapEntry<String, int>>[];
  final expenses = <MapEntry<String, int>>[]; // operating (excludes COGS)
  int get totalIncome => income.fold(0, (a, e) => a + e.value);
  int get operatingExpenses => expenses.fold(0, (a, e) => a + e.value);
  int get grossProfit => revenue - cogs;
  int get netProfit => totalIncome - cogs - operatingExpenses;
}

class BalanceSheet {
  final assets = <MapEntry<String, int>>[];
  final liabilities = <MapEntry<String, int>>[];
  final equity = <MapEntry<String, int>>[];
  int profit = 0;
  int get totalAssets => assets.fold(0, (a, e) => a + e.value);
  int get totalLiabilities => liabilities.fold(0, (a, e) => a + e.value);
  int get totalEquity => equity.fold(0, (a, e) => a + e.value) + profit;
}

class HomeMetrics {
  final int todaySales, todayInvoices, todayPurchases, todayBills, yesterdaySales, totalDue;
  HomeMetrics({
    required this.todaySales,
    required this.todayInvoices,
    required this.todayPurchases,
    required this.todayBills,
    required this.yesterdaySales,
    required this.totalDue,
  });
}

class Overview {
  final int sales, purchases, salesChange, purchaseChange;
  Overview({required this.sales, required this.purchases, required this.salesChange, required this.purchaseChange});
}

class Alert {
  final String kind, title, text;
  final int targetId;
  Alert(this.kind, this.title, this.text, this.targetId);
}

class MonthBar {
  final String label;
  final int sales, purchases;
  MonthBar(this.label, this.sales, this.purchases);
}

class DashboardData {
  final int profitToday, grossToday, receivable, payable, stockValue;
  final ProfitLoss month;
  final List<MapEntry<String, int>> money;
  final List<MonthBar> months;
  final List<Rec> topProducts, topDue, lowStock, recentSales;
  DashboardData({
    required this.profitToday,
    required this.grossToday,
    required this.month,
    required this.money,
    required this.receivable,
    required this.payable,
    required this.stockValue,
    required this.months,
    required this.topProducts,
    required this.topDue,
    required this.lowStock,
    required this.recentSales,
  });
}
