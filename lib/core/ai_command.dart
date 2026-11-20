/// AI command: one sentence (typed or spoken) becomes an action —
///   "Rahim Sheikh 9830012345 ke Vivo T3 ekta 18 hajar cash"  → a bill (and
///       the customer, made if new)
///   "Rahim 5000 joma" / "Rahim theke 5000 pelam"              → money received
///   "new customer Karim 9830011111"                           → a customer
/// Anything else is a question for Brain.ask.
library;

import '../cloud/cloud.dart';
import 'books.dart';
import 'imei_smart.dart';
import 'money.dart';
import 'quick.dart';
import 'staff.dart';

class CmdLine {
  final Rec product;
  int qty;
  int? rate; // per unit, as said (incl. GST), paise
  CmdLine(this.product, this.qty, this.rate);
}

sealed class AiCommand {
  const AiCommand();
}

/// A bill. [customer] is an existing customer, or null with [newName] /
/// [newPhone] for one to create (or a walk-in when both are empty).
class BillCommand extends AiCommand {
  final List<CmdLine> lines;
  final Rec? customer;
  final String? newName, newPhone;
  final String? pay; // cash | upi | card | due
  final int? paidNow; // "5000 advance" / "baki 2000" — null = by [pay]
  final List<String> unknown;
  const BillCommand(this.lines, {this.customer, this.newName, this.newPhone, this.pay, this.paidNow, this.unknown = const []});
}

class ReceiptCommand extends AiCommand {
  final Rec? customer;
  final String? name; // said, but no such customer
  final int amount;
  final String? pay;
  const ReceiptCommand(this.customer, this.name, this.amount, this.pay);
}

/// "rent 5000 khoroch", "electric bill 1200 expense", "cha 150 khoroch upi"
class ExpenseCommand extends AiCommand {
  final String head; // expense head (Rent, Electricity…)
  final int amount;
  final String? pay;
  final String note;
  const ExpenseCommand(this.head, this.amount, this.pay, this.note);
}

class CustomerCommand extends AiCommand {
  final String name, phone;
  final Rec? existing;
  const CustomerCommand(this.name, this.phone, this.existing);
}

class AiCommands {
  static final _phone = RegExp(r'(?:\+?91[\s\-]?)?(?<!\d)([6-9]\d{4}[\s\-]?\d{5})(?!\d)');
  static const _billWords = {'bill', 'becho', 'bikri', 'sale', 'sell', 'dao', 'dilam', 'nilo', 'kinlo', 'kineche', 'invoice', 'order'};
  static const _receiptWords = {'joma', 'jama', 'pelam', 'paid', 'received', 'receive', 'dilo', 'diyeche', 'collect', 'collected', 'payment', 'shodh', 'shod'};
  static const _customerWords = {'customer', 'kastomar', 'grahok', 'add', 'notun', 'new', 'save'};
  static const _nameStop = {
    'ke', 'er', 'theke', 'for', 'to', 'customer', 'name', 'naam', 'mobile', 'phone', 'number', 'no', 'and', 'ar', 'with', 'bill', 'koro', 'kore',
    'dao', 'banao', 'new', 'notun', 'add', 'sale', 'sell', 'becho', 'bikri', 'invoice', 'order', 'mr', 'mrs', 'shri', 'sri', 'bhai', 'da', 'di',
    'make', 'create', 'please', 'ekta', 'one', 'rs', 'taka', 'rupees', 'hajar', 'pcs', 'piece', 'joma', 'jama', 'pelam', 'advance', 'baki',
  };

  /// Reads a sentence; null when it is a question (not a command).
  static AiCommand? parse(String said, List<Rec> products, List<Rec> customers) {
    final raw = said.trim();
    if (raw.isEmpty) return null;
    final lower = ' ${raw.toLowerCase()} ';
    if (raw.endsWith('?') || RegExp(r'\b(koto|how much|what|who|kon|best|show|dekhao|report)\b').hasMatch(lower)) return null;

    // phone number
    String? phone;
    final pm = _phone.firstMatch(raw);
    var rest = raw;
    if (pm != null) {
      phone = pm.group(1)!.replaceAll(RegExp(r'\D'), '');
      rest = raw.replaceRange(pm.start, pm.end, ' ');
    }
    var text = VoiceBill.normalise(rest);
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    bool has(Set<String> set) => words.any(set.contains);

    // the customer: by phone first, then by name
    Rec? customer;
    if (phone != null) {
      customer = customers.where((c) => Books.phoneKey(c['phone']) == phone).firstOrNull;
    }
    customer ??= _customerByName(text, customers);
    if (customer != null) {
      for (final n in SmartSearch.words('${customer['name']}')) {
        text = text.replaceAll(RegExp('\\b${RegExp.escape(n)}\\b'), ' ');
      }
    }

    // payment words
    String? pay;
    for (final e in VoiceBill.payWords.entries) {
      if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(text)) {
        pay = e.value;
        text = text.replaceAll(RegExp('\\b${RegExp.escape(e.key)}\\b'), ' ');
      }
    }
    // "5000 advance" / "advance 5000" / "baki 2000"
    int? paidNow;
    final adv = RegExp(r'\b(?:advance|agrim|deposit)\s*(\d+)').firstMatch(text) ?? RegExp(r'\b(\d+)\s*(?:advance|agrim|deposit)\b').firstMatch(text);
    if (adv != null) {
      paidNow = int.parse(adv.group(1)!) * 100;
      text = text.replaceRange(adv.start, adv.end, ' ');
    }

    // a customer only: "new customer Karim 98300…"
    final isCustomerCmd = has(_customerWords) && (has({'new', 'notun', 'add'}) || words.first == 'customer');
    if (isCustomerCmd && phone != null && !RegExp(r'\d{2,}').hasMatch(text)) {
      final name = _name(text.split(' '));
      if (name.isNotEmpty) return CustomerCommand(name, phone, customer);
    }

    // an expense: "rent 5000 khoroch"
    if (has({'khoroch', 'khorch', 'kharcha', 'khorcha', 'expense', 'expenses', 'kharch'})) {
      final amt = RegExp(r'\b(\d{1,9})\b').firstMatch(text);
      if (amt != null) {
        final rest = text.replaceAll(amt.group(0)!, ' ').split(' ').where((w) => w.length >= 2 && !{'khoroch', 'khorch', 'kharcha', 'khorcha', 'expense', 'expenses', 'kharch', 'holo', 'hoyeche', 'dilam', 'add', 'koro'}.contains(w));
        final head = _expenseHead(rest.join(' '));
        return ExpenseCommand(head, int.parse(amt.group(1)!) * 100, pay ?? 'cash', rest.join(' ').trim());
      }
    }

    // money received: "Rahim 5000 joma"
    if (has(_receiptWords) && !has(_billWords)) {
      final amt = RegExp(r'\b(\d{2,9})\b').firstMatch(text);
      if (amt != null && _bestProduct(text.split(' '), products) == null) {
        final name = customer == null ? _name(text.replaceAll(amt.group(0)!, ' ').split(' ')) : null;
        return ReceiptCommand(customer, name, int.parse(amt.group(1)!) * 100, pay ?? 'cash');
      }
    }

    // a bill: items split by "and", ",", "ar", "plus"
    final lines = <CmdLine>[];
    final unknown = <String>[];
    final leftover = <String>[];
    for (final partRaw in text.split(RegExp(r'\s*(?:,|;|\band\b|\bar\b|\baur\b|\bplus\b|\bsathe\b|\bwith\b)\s*'))) {
      final toks = partRaw.trim().split(' ').where((w) => w.isNotEmpty).toList();
      if (toks.isEmpty) continue;
      final hit = _bestProduct(toks, products);
      if (hit == null) {
        // no product here: its words may be the customer's name
        leftover.addAll(toks.where((w) => !RegExp(r'^\d').hasMatch(w)));
        if (toks.any((w) => RegExp(r'^\d{3,}$').hasMatch(w)) && toks.any((w) => !_nameStop.contains(w) && !RegExp(r'^\d').hasMatch(w))) {
          unknown.add(partRaw.trim());
        }
        continue;
      }
      final (p, from, to) = hit;
      int? qty, rate;
      for (var i = 0; i < toks.length; i++) {
        if (i >= from && i < to) continue;
        final w = toks[i];
        if (VoiceBill.qtyWords.containsKey(w) && qty == null && w != 'a' && w != 'do') {
          qty = VoiceBill.qtyWords[w];
          continue;
        }
        final n = RegExp(r'^\d+(\.\d+)?$').hasMatch(w) ? double.parse(w) : null;
        if (n != null) {
          final next = i + 1 < toks.length ? toks[i + 1] : '';
          if (['ta', 'ti', 'pcs', 'piece', 'pieces', 'nos', 'x', 'unit', 'units'].contains(next) && n <= 999 && qty == null) {
            qty = n.round();
          } else if (n >= 10 && rate == null) {
            rate = (n * 100).round();
          } else if (n < 10 && qty == null) {
            qty = n.round();
          }
          continue;
        }
        if (!VoiceBill.fillerWords.contains(w)) leftover.add(w);
      }
      lines.add(CmdLine(p, qty ?? 1, rate));
    }
    if (lines.isEmpty) return null;
    String? newName;
    if (customer == null) {
      final n = _name(leftover);
      if (n.isNotEmpty) newName = n;
    }
    return BillCommand(lines,
        customer: customer, newName: customer == null ? newName : null, newPhone: customer == null ? phone : null, pay: pay, paidNow: paidNow, unknown: unknown);
  }

  /// The best product in a run of words: (product, start, end) — the longest
  /// stretch of words that names one product well.
  static (Rec, int, int)? _bestProduct(List<String> toks, List<Rec> products) {
    (Rec, int, int, double)? best;
    for (var i = 0; i < toks.length; i++) {
      if (_nameStop.contains(toks[i]) || VoiceBill.fillerWords.contains(toks[i])) continue;
      for (var j = i + 1; j <= toks.length && j <= i + 6; j++) {
        final q = toks.sublist(i, j).join(' ');
        if (RegExp(r'^\d+$').hasMatch(q)) continue;
        final hits = SmartSearch.rank(products, q, limit: 1);
        if (hits.isEmpty) continue;
        final s = SmartSearch.score(q, hits.first);
        if (s < 0.7) continue;
        // a longer match wins; numbers only count when they belong to the name
        final score = s + (j - i) * 0.15;
        if (best == null || score > best.$4) best = (hits.first, i, j, score);
      }
    }
    if (best == null) return null;
    // a trailing number that is not in the product (a price) is not part of it
    var end = best.$3;
    final hay = SmartSearch.words(SmartSearch.haystack(best.$1)).toSet();
    while (end - 1 > best.$2 && RegExp(r'^\d+$').hasMatch(toks[end - 1]) && !hay.contains(toks[end - 1])) {
      end--;
    }
    return (best.$1, best.$2, end);
  }

  static Rec? _customerByName(String text, List<Rec> customers) {
    final said = SmartSearch.words(text).where((w) => !RegExp(r'^\d').hasMatch(w)).toList();
    Rec? best;
    var bestScore = 0.0;
    for (final c in customers) {
      final name = SmartSearch.words('${c['name'] ?? ''}');
      if (name.isEmpty) continue;
      var hit = 0;
      for (final n in name) {
        if (said.contains(n)) hit++;
      }
      // the full name, or a rare first name, is needed (not one common word)
      final score = hit / name.length;
      if (hit > 0 && (score == 1 || hit >= 2) && score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  /// Common shop expenses (Banglish / English words → head).
  static String _expenseHead(String s) {
    const heads = {
      'Rent': ['rent', 'vara', 'bhara', 'bhada', 'dokan vara'],
      'Electricity': ['electric', 'current', 'bijli', 'light bill', 'electricity', 'kareng'],
      'Salary': ['salary', 'beton', 'betan', 'staff', 'mojuri', 'wages'],
      'Tea & snacks': ['cha', 'chai', 'tea', 'nasta', 'snacks', 'khabar', 'tiffin'],
      'Transport': ['transport', 'auto', 'toto', 'bus', 'courier', 'delivery', 'petrol', 'fuel', 'gari'],
      'Internet & phone': ['internet', 'wifi', 'recharge', 'phone bill', 'mobile recharge', 'data'],
      'Repairs & maintenance': ['repair', 'maintenance', 'mistri', 'thik'],
      'Stationery': ['paper', 'pen', 'stationery', 'print', 'xerox', 'roll'],
    };
    for (final e in heads.entries) {
      if (e.value.any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(s))) return e.key;
    }
    final w = s.split(' ').where((x) => x.length >= 3).take(2).join(' ');
    return w.isEmpty ? 'Other expenses' : w[0].toUpperCase() + w.substring(1);
  }

  static String _name(List<String> words) {
    final w = words
        .map((x) => x.trim())
        .where((x) => x.length >= 2 && RegExp(r'^[a-zঀ-৿]+$').hasMatch(x) && !_nameStop.contains(x) && !VoiceBill.fillerWords.contains(x))
        .where((x) => !VoiceBill.payWords.containsKey(x) && !VoiceBill.qtyWords.containsKey(x))
        .take(3)
        .toList();
    return w.map((x) => x[0].toUpperCase() + x.substring(1)).join(' ');
  }
}

/// Carries out a command in the books.
class AiActions {
  static int exGst(int incl, int gstBp) => gstBp > 0 ? (incl * 10000 / (10000 + gstBp)).round() : incl;

  /// The list price a customer pays (with GST).
  static int listPrice(Rec p) {
    final price = asInt(p['price']);
    return price + Money.percent(price, asInt(p['gst_bp']));
  }

  /// Price per unit before GST for a line (said price, or the list price).
  static int rate(CmdLine l) => l.rate == null ? asInt(l.product['price']) : exGst(l.rate!, asInt(l.product['gst_bp']));

  static int lineTotal(CmdLine l) {
    final amount = rate(l) * l.qty;
    return amount + Money.percent(amount, asInt(l.product['gst_bp']));
  }

  static int total(List<CmdLine> lines) => lines.fold(0, (a, l) => a + lineTotal(l));

  /// The money account for a way of paying.
  static Future<int?> account(String? pay) async {
    final acc = await Books.moneyAccounts();
    if (acc.isEmpty) return null;
    bool kind(Rec a, List<String> w) => w.any('${a['name']} ${a['card_type'] ?? ''} ${a['code'] ?? ''}'.toLowerCase().contains);
    final pick = switch (pay) {
      'upi' => acc.where((a) => kind(a, ['upi', 'gpay', 'phonepe', 'paytm'])).firstOrNull ?? acc.where((a) => kind(a, ['bank', 'savings', 'current'])).firstOrNull,
      'card' => acc.where((a) => kind(a, ['debit', 'card', 'pos', 'bank'])).firstOrNull,
      _ => acc.where((a) => a['code'] == cashCode).firstOrNull,
    };
    return asInt((pick ?? acc.first)['id']);
  }

  /// The customer for a name + phone: the existing one, or a new one.
  static Future<int> customer(String name, String? phone) async {
    if (phone != null && phone.isNotEmpty) {
      final r = await Books.query('SELECT id, phone FROM customers');
      final hit = r.where((c) => Books.phoneKey(c['phone']) == Books.phoneKey(phone)).firstOrNull;
      if (hit != null) return asInt(hit['id']);
    }
    final dup = await Books.findDuplicateParty('customer', name, phone);
    if (dup != null) return asInt(dup['id']);
    return Books.saveParty('customer', {'name': name.trim().isEmpty ? 'Customer ${phone ?? ''}'.trim() : name.trim(), 'phone': phone});
  }

  /// Records an expense under its head (made if new).
  static Future<int> saveExpense(ExpenseCommand c, {String? pay}) async {
    final heads = await Books.query("SELECT id, name FROM accounts WHERE type = 'expense'");
    final hit = heads.where((h) => '${h['name']}'.toLowerCase() == c.head.toLowerCase()).firstOrNull ??
        heads.where((h) => '${h['name']}'.toLowerCase().contains(c.head.toLowerCase().split(' ').first)).firstOrNull;
    final head = hit != null ? asInt(hit['id']) : await Books.addExpenseHead(c.head);
    return Books.createExpense(headId: head, amount: c.amount, accountId: (await account(pay ?? c.pay))!, note: c.note.isEmpty ? null : c.note);
  }

  /// Saves the bill. Phones get the oldest IMEIs in stock, one line each.
  /// Returns (sale id, invoice number, total, paid).
  static Future<(int, String, int, int)> saveBill(BillCommand c, {required String pay, int? paidNow}) async {
    int? cid = c.customer == null ? null : asInt(c.customer!['id']);
    if (cid == null && ((c.newName ?? '').isNotEmpty || (c.newPhone ?? '').isNotEmpty)) {
      cid = await customer(c.newName ?? '', c.newPhone);
    }
    final items = <ItemIn>[];
    for (final l in c.lines) {
      final r = rate(l);
      final free = await SmartImei.inStock(asInt(l.product['id']));
      var left = l.qty;
      for (final sn in free.take(l.qty)) {
        items.add(ItemIn(asInt(l.product['id']), 1, r, sn));
        left--;
      }
      if (left > 0) items.add(ItemIn(asInt(l.product['id']), left, r));
    }
    final t = total(c.lines);
    final paid = pay == 'due' ? (paidNow ?? 0).clamp(0, t) : (paidNow ?? t).clamp(0, t);
    if (cid == null && paid < t) throw AccountingError('A credit bill needs the customer\'s name or phone');
    final id = await Books.createSale(items: items, customerId: cid, paid: paid, accountId: await account(pay == 'due' ? 'cash' : pay));
    final number = '${(await Books.query('SELECT number FROM sales WHERE id = ?', [id])).first['number']}';
    return (id, number, t, paid);
  }
}

/// Hisab AI in the cloud (Claude on your server): any language, any wording.
/// Turns the answer into the same commands as the phone's own engine, so the
/// same cards confirm them. Returns null when the cloud AI is not reachable.
class CloudAi {
  static Future<bool> enabled() async => (await Books.settings())['ai_cloud'] != '0';

  static Future<(String, List<Object>)?> ask(String text, List<(bool, String)> history) async {
    if (!await enabled()) return null;
    await Cloud.load();
    if (Cloud.user == null || !await Vps.available() || !Vps.aiReady) return null;
    final products = await Books.query(
        'SELECT p.*, (SELECT IFNULL(SUM(qty), 0) FROM sale_items WHERE product_id = p.id) AS sold FROM products p ORDER BY sold DESC, p.name LIMIT 600');
    final customers = Books.can('customers') || Books.can('sale') || Books.can('collect')
        ? await Books.query('SELECT id, name, phone FROM customers ORDER BY id DESC LIMIT 800')
        : const <Rec>[];
    final s = await Books.settings();
    final r = await Vps.ai({
      'message': text,
      'history': [for (final (mine, t) in history.take(6)) {'role': mine ? 'user' : 'assistant', 'text': t}],
      'shop': s['business_name'] ?? '',
      'today': ymd(DateTime.now()),
      'allowed': [for (final p in Staff.perms.keys) if (Books.can(p)) p],
      'products': [
        for (final p in products)
          {'id': p['id'], 'name': p['name'], 'variant': p['variant'], 'price': AiActions.listPrice(p) / 100, 'stock': p['stock']}
      ],
      'customers': [for (final c in customers) {'id': c['id'], 'name': c['name'], 'phone': c['phone']}],
    });
    final byId = {for (final p in products) asInt(p['id']): p};
    final custById = {for (final c in customers) asInt(c['id']): c};
    final out = <Object>[];
    int paise(Object? rupees) => ((rupees as num?) ?? 0) * 100 ~/ 1;
    for (final a in (r['actions'] as List? ?? const [])) {
      final m = (a as Map).cast<String, dynamic>();
      final i = ((m['input'] as Map?) ?? const {}).cast<String, dynamic>();
      switch (m['tool']) {
        case 'create_bill':
          final lines = <CmdLine>[];
          for (final it in (i['items'] as List? ?? const [])) {
            final x = (it as Map).cast<String, dynamic>();
            final p = byId[asInt(x['product_id'])];
            if (p == null) continue;
            final q = asInt(x['qty']);
            lines.add(CmdLine(p, q < 1 ? 1 : q, x['unit_price'] == null ? null : ((x['unit_price'] as num) * 100).round()));
          }
          if (lines.isEmpty) continue;
          final cid = i['customer_id'] == null ? null : custById[asInt(i['customer_id'])];
          final pay = i['payment'] == 'credit' ? 'due' : '${i['payment'] ?? 'cash'}';
          out.add(BillCommand(lines,
              customer: cid,
              newName: cid == null ? (i['new_customer_name'] as String?) : null,
              newPhone: cid == null ? (i['new_customer_phone'] as String?)?.replaceAll(RegExp(r'\D'), '') : null,
              pay: pay,
              paidNow: i['advance'] == null ? null : paise(i['advance'])));
        case 'receive_payment':
          final c = i['customer_id'] == null ? null : custById[asInt(i['customer_id'])];
          out.add(ReceiptCommand(c, i['customer_name'] as String?, paise(i['amount']), '${i['method'] ?? 'cash'}'));
        case 'add_customer':
          final phone = '${i['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
          final existing = customers.where((c) => Books.phoneKey(c['phone']) == Books.phoneKey(phone)).firstOrNull;
          out.add(CustomerCommand('${i['name'] ?? ''}', phone, existing));
        case 'add_expense':
          out.add(ExpenseCommand('${i['category'] ?? 'Other expenses'}', paise(i['amount']), '${i['method'] ?? 'cash'}', '${i['note'] ?? ''}'));
        case 'ask_books':
          out.add(AskBooks('${i['question'] ?? text}'));
      }
    }
    return ('${r['text'] ?? ''}', out);
  }
}

/// A question the cloud AI rephrased for the shop's report engine.
class AskBooks {
  final String question;
  const AskBooks(this.question);
}
