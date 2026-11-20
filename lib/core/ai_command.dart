/// AI command: one sentence (typed or spoken) becomes an action —
///   "Rahim Sheikh 9830012345 ke Vivo T3 ekta 18 hajar cash"  → a bill (and
///       the customer, made if new)
///   "Rahim 5000 joma" / "Rahim theke 5000 pelam"              → money received
///   "new customer Karim 9830011111"                           → a customer
///   "rent 5000 khoroch"                                      → an expense
///   several of these on separate lines / "tarpor"            → several cards
///   "aro ekta charger" / "dam 17500" / "upi te" (after a bill) → that bill changed
/// Anything else is a question for Brain.ask.
///
/// It runs on the phone, needs no internet and no outside AI, and learns: when
/// a bill is saved, the words used for each product are remembered (AiMemory),
/// so the shop's own way of naming things is understood next time.
library;

import 'dart:convert';

import 'books.dart';
import 'imei_smart.dart';
import 'money.dart';
import 'quick.dart';

class CmdLine {
  Rec product;
  int qty;
  int? rate; // per unit, as said (incl. GST), paise
  final String said; // the words used for the product (learnt on save)
  CmdLine(this.product, this.qty, this.rate, [this.said = '']);
}

/// What Hisab AI has learnt in this shop: the words people use for products
/// ("t3" → Vivo T3 5G 8/128) and customers' nicknames. Kept in settings, so it
/// goes with the backup and to the other phone.
class AiMemory {
  static Map<String, List<int>> _products = {}; // phrase → [product id, times]
  static Map<String, List<int>> _customers = {};
  static bool _loaded = false;

  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final m = jsonDecode((await Books.settings())['ai_memory'] ?? '{}') as Map;
      List<int> pair(Object? v) => [for (final x in (v as List)) (x as num).toInt()];
      _products = {for (final e in ((m['p'] as Map?) ?? const {}).entries) '${e.key}': pair(e.value)};
      _customers = {for (final e in ((m['c'] as Map?) ?? const {}).entries) '${e.key}': pair(e.value)};
    } catch (_) {
      _products = {};
      _customers = {};
    }
    _loaded = true;
  }

  static Future<void> _save() async {
    // keep the most used 1500 phrases
    Map<String, List<int>> top(Map<String, List<int>> m) {
      if (m.length <= 1500) return m;
      final e = m.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]));
      return Map.fromEntries(e.take(1500));
    }

    await Books.setSetting('ai_memory', jsonEncode({'p': top(_products), 'c': top(_customers)}));
  }

  static String key(String said) => SmartSearch.words(said).where((w) => !RegExp(r'^\d+$').hasMatch(w) || w.length <= 4).join(' ');

  /// The product these words meant before, if any.
  static int? product(String said) {
    final k = key(said);
    return k.isEmpty ? null : _products[k]?[0];
  }

  static int? customer(String said) {
    final k = key(said);
    return k.isEmpty ? null : _customers[k]?[0];
  }

  /// Remembers that [said] meant [productId] (a correction replaces the old meaning).
  static Future<void> learnProduct(String said, int productId) async {
    final k = key(said);
    if (k.isEmpty || k.length > 60) return;
    await load();
    final old = _products[k];
    _products[k] = [productId, old != null && old[0] == productId ? old[1] + 1 : 1];
    await _save();
  }

  static Future<void> learnCustomer(String said, int customerId) async {
    final k = key(said);
    if (k.isEmpty || k.length > 40) return;
    await load();
    final old = _customers[k];
    _customers[k] = [customerId, old != null && old[0] == customerId ? old[1] + 1 : 1];
    await _save();
  }

  static int get size => _products.length + _customers.length;

  static Future<void> forget() async {
    _products = {};
    _customers = {};
    await _save();
  }
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
  final int discount; // paise off the bill
  final int discountPct; // or a percent of the bill (0 = none)
  final String? said; // the customer as said (learnt on save)
  const BillCommand(this.lines,
      {this.customer, this.newName, this.newPhone, this.pay, this.paidNow, this.unknown = const [], this.discount = 0, this.discountPct = 0, this.said});

  BillCommand copy(
          {List<CmdLine>? lines,
          Rec? customer,
          bool clearCustomer = false,
          String? newName,
          String? newPhone,
          String? pay,
          int? paidNow,
          int? discount,
          int? discountPct}) =>
      BillCommand(lines ?? this.lines,
          customer: clearCustomer ? null : customer ?? this.customer,
          newName: newName ?? this.newName,
          newPhone: newPhone ?? this.newPhone,
          pay: pay ?? this.pay,
          paidNow: paidNow ?? this.paidNow,
          unknown: unknown,
          discount: discount ?? this.discount,
          discountPct: discountPct ?? this.discountPct,
          said: said);
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
    'ke',
    'er',
    'theke',
    'for',
    'to',
    'customer',
    'name',
    'naam',
    'mobile',
    'phone',
    'number',
    'no',
    'and',
    'ar',
    'with',
    'bill',
    'koro',
    'kore',
    'dao',
    'banao',
    'new',
    'notun',
    'add',
    'sale',
    'sell',
    'becho',
    'bikri',
    'invoice',
    'order',
    'mr',
    'mrs',
    'shri',
    'sri',
    'bhai',
    'da',
    'di',
    'make',
    'create',
    'please',
    'ekta',
    'one',
    'rs',
    'taka',
    'rupees',
    'hajar',
    'pcs',
    'piece',
    'joma',
    'jama',
    'pelam',
    'advance',
    'baki',
  };

  /// Several commands in one message (one per line, or joined by "tarpor" /
  /// "then"); a single one otherwise. Empty when it is a question.
  static List<AiCommand> parseAll(String said, List<Rec> products, List<Rec> customers) {
    final parts = said
        .split(RegExp(r'\n+|;\s*(?=\S)|\.(?=\s+[A-Za-z])|\b(?:tarpor|tarpore|then|ar ekta bill|arekta bill|next bill)\b', caseSensitive: false))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.length > 1) {
      final cmds = [for (final p in parts) parse(p, products, customers)];
      if (cmds.whereType<AiCommand>().length >= 2) return cmds.whereType<AiCommand>().toList();
    }
    final one = parse(said, products, customers);
    return one == null ? const [] : [one];
  }

  /// Bangla / Hindi ways of saying amounts: "dera lakh" 150000, "arai hajar"
  /// 2500, "sare 18 hajar" 18500, "pone 2 hajar" 1750, "sowa 3 hajar" 3250.
  static String spoken(String s) {
    var t = ' ${s.toLowerCase()} ';
    t = t.replaceAllMapped(RegExp(r'\b(?:dera|dedh|der|deṛ)\s+(?=(?:lakh|lac|hajar|hazar|k|sho)\b)'), (_) => '1.5 ');
    t = t.replaceAllMapped(RegExp(r'\b(?:arai|adai|aṛai|dhai|arhai)\s+(?=(?:lakh|lac|hajar|hazar|k|sho)\b)'), (_) => '2.5 ');
    t = t.replaceAllMapped(RegExp(r'\b(?:sare|saare|sade|saarhe)\s+(\d+)\b'), (m) => '${m[1]}.5');
    t = t.replaceAllMapped(RegExp(r'\b(?:sowa|sawa|soa)\s+(\d+)\b'), (m) => '${m[1]}.25');
    t = t.replaceAllMapped(RegExp(r'\b(?:pone|paune|poune)\s+(\d+)\b'), (m) => '${int.parse(m[1]!) - 0.25}');
    t = t.replaceAllMapped(RegExp(r'\bhalf\s+(?=lakh|lac)'), (_) => '0.5 ');
    return t.trim();
  }

  /// "500 discount", "discount 500", "10% off", "300 kom", "200 chhar" →
  /// (paise, percent) and the text without it.
  static (int, int, String) _discount(String text) {
    final pct = RegExp(r'\b(\d{1,2}(?:\.\d)?)\s*%\s*(?:discount|disc|chhar|chad|off|less|kom|chhad)?').firstMatch(text) ??
        RegExp(r'\b(?:discount|disc|chhar|chad|off|less)\s*(\d{1,2}(?:\.\d)?)\s*%').firstMatch(text);
    if (pct != null) return (0, (double.parse(pct.group(1)!) * 100).round(), text.replaceRange(pct.start, pct.end, ' '));
    final amt = RegExp(r'\b(\d{1,7})\s*(?:taka|tk|rs)?\s*(?:discount|disc|chhar|chad|chhad|off|less|kom|kom koro|kome)\b').firstMatch(text) ??
        RegExp(r'\b(?:discount|disc|chhar|chad|chhad|less)\s*(\d{1,7})\b').firstMatch(text);
    if (amt != null) return (int.parse(amt.group(1)!) * 100, 0, text.replaceRange(amt.start, amt.end, ' '));
    return (0, 0, text);
  }

  /// Reads a sentence; null when it is a question (not a command).
  static AiCommand? parse(String said, List<Rec> products, List<Rec> customers) {
    final raw = spoken(said.trim());
    if (raw.isEmpty) return null;
    final lower = ' ${raw.toLowerCase()} ';
    if (raw.endsWith('?') || RegExp(r'\b(koto|how much|what|who|kon|best|show|dekhao|report|kemon|kivabe|why|keno|list)\b').hasMatch(lower)) return null;

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
    // a nickname learnt before ("Rahim bhai" → Rahim Sheikh)
    if (customer == null) {
      final w = text.split(' ').where((x) => x.isNotEmpty).toList();
      for (var n = 3; n >= 1 && customer == null; n--) {
        for (var i = 0; i + n <= w.length && customer == null; i++) {
          final id = AiMemory.customer(w.sublist(i, i + n).join(' '));
          if (id != null) {
            customer = customers.where((c) => asInt(c['id']) == id).firstOrNull;
            if (customer != null) text = text.replaceFirst(w.sublist(i, i + n).join(' '), ' ');
          }
        }
      }
    }
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
    // discount
    final (discount, discountPct, afterDiscount) = _discount(text);
    text = afterDiscount;
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
        final rest = text.replaceAll(amt.group(0)!, ' ').split(' ').where((w) =>
            w.length >= 2 &&
            !{'khoroch', 'khorch', 'kharcha', 'khorcha', 'expense', 'expenses', 'kharch', 'holo', 'hoyeche', 'dilam', 'add', 'koro'}.contains(w));
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
    final unknown = <String>[];
    final leftover = <String>[];
    final lines = _lines(text, products, leftover, unknown);
    if (lines.isEmpty) return null;
    String? newName;
    if (customer == null) {
      final n = _name(leftover);
      if (n.isNotEmpty) newName = n;
    }
    return BillCommand(lines,
        customer: customer,
        newName: customer == null ? newName : null,
        newPhone: customer == null ? phone : null,
        pay: pay,
        paidNow: paidNow,
        unknown: unknown,
        discount: discount,
        discountPct: discountPct,
        said: customer == null ? newName : null);
  }

  /// The products, quantities and prices in a piece of text.
  static List<CmdLine> _lines(String text, List<Rec> products, List<String> leftover, List<String> unknown) {
    final lines = <CmdLine>[];
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
      lines.add(CmdLine(p, qty ?? 1, rate, toks.sublist(from, to).join(' ')));
    }
    return lines;
  }

  static const _followUp = {
    'aro',
    'also',
    'add',
    'plus',
    'sathe',
    'arekta',
    'aaro',
    'more',
    'dam',
    'price',
    'rate',
    'discount',
    'disc',
    'chhar',
    'bad',
    'baad',
    'remove',
    'hatao',
    'kato',
    'delete',
    'qty',
    'quantity',
    'payment',
    'advance',
    'mobile',
    'phone',
    'number',
    'naam',
    'name',
    'customer',
    'na',
  };

  /// A follow-up to the bill just made: "aro ekta charger", "dam 17500",
  /// "charger bad dao", "upi te", "500 discount", "advance 2000",
  /// "mobile 98300 12345", "naam Rahim Sheikh". Null when it is not one.
  static BillCommand? refine(BillCommand last, String said, List<Rec> products, List<Rec> customers) {
    var text = VoiceBill.normalise(spoken(said));
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 14) return null;
    if (said.trim().endsWith('?') || RegExp(r'\b(koto|how much|what|kon|keno|why|show|dekhao|report)\b').hasMatch(text)) return null;
    final first = words.first;
    final payOnly = words.length <= 3 && words.any(VoiceBill.payWords.containsKey);
    const anywhere = {'bad', 'baad', 'remove', 'hatao', 'kato', 'dam', 'price', 'rate', 'qty', 'quantity', 'advance', 'discount'};
    if (!_followUp.contains(first) &&
        !payOnly &&
        !words.any(anywhere.contains) &&
        !RegExp(r'^(\d+\s*(%|discount|disc|off|kom|chhar)|(cash|upi|card|baki|udhar|gpay|phonepe|paytm)\b)').hasMatch(text)) {
      return null;
    }
    var lines = [...last.lines];
    var cmd = last;
    var changed = false;

    // customer details
    final pm = _phone.firstMatch(said);
    if (pm != null && last.customer == null) {
      cmd = cmd.copy(newPhone: pm.group(1)!.replaceAll(RegExp(r'\D'), ''));
      text = text.replaceAll(RegExp(r'\d{5}\s?\d{5}'), ' ');
      changed = true;
    }
    final nm = RegExp(r'\b(?:naam|name|customer)\s+([a-z][a-z ]{1,40})$').firstMatch(text);
    if (nm != null) {
      final n = _name(nm.group(1)!.split(' '));
      if (n.isNotEmpty) {
        final hit = _customerByName(n.toLowerCase(), customers);
        cmd = hit != null ? cmd.copy(customer: hit) : cmd.copy(clearCustomer: true, newName: n);
        return cmd.copy(lines: lines);
      }
    }
    // payment
    for (final e in VoiceBill.payWords.entries) {
      if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(text)) {
        cmd = cmd.copy(pay: e.value);
        text = text.replaceAll(RegExp('\\b${RegExp.escape(e.key)}\\b'), ' ');
        changed = true;
      }
    }
    final adv = RegExp(r'\b(?:advance|agrim|deposit)\s*(\d+)').firstMatch(text) ?? RegExp(r'\b(\d+)\s*(?:advance|agrim|deposit)\b').firstMatch(text);
    if (adv != null) {
      cmd = cmd.copy(pay: 'due', paidNow: int.parse(adv.group(1)!) * 100);
      text = text.replaceRange(adv.start, adv.end, ' ');
      changed = true;
    }
    final (d, dp, rest) = _discount(text);
    if (d > 0 || dp > 0) {
      cmd = BillCommand(lines,
          customer: cmd.customer,
          newName: cmd.newName,
          newPhone: cmd.newPhone,
          pay: cmd.pay,
          paidNow: cmd.paidNow,
          unknown: cmd.unknown,
          discount: d,
          discountPct: dp,
          said: cmd.said);
      text = rest;
      changed = true;
    }
    final toks = text.split(' ').where((w) => w.isNotEmpty).toList();
    final hit = _bestProduct(toks, products);
    CmdLine? target = hit == null ? null : lines.where((l) => asInt(l.product['id']) == asInt(hit.$1['id'])).firstOrNull;

    // remove a line
    if (toks.any({'bad', 'baad', 'remove', 'hatao', 'kato', 'delete'}.contains)) {
      final t = target;
      if (t != null) {
        lines.remove(t);
        return cmd.copy(lines: lines);
      }
    }
    // a new price: "dam 17500" / "charger dam 450"
    final pr = RegExp(r'\b(?:dam|price|rate)\s*(?:hobe|koro|kore)?\s*(\d{2,9})\b').firstMatch(text) ??
        RegExp(r'\b(\d{2,9})\s*(?:dam|price|rate|kore dao)\b').firstMatch(text);
    if (pr != null && lines.isNotEmpty && !toks.any({'aro', 'also', 'add', 'plus', 'arekta', 'aaro', 'more'}.contains)) {
      (target ?? lines.last).rate = int.parse(pr.group(1)!) * 100;
      return cmd.copy(lines: lines);
    }
    // a new quantity: "qty 3" / "charger 3 ta koro"
    final q =
        RegExp(r'\b(?:qty|quantity)\s*(\d{1,3})\b').firstMatch(text) ?? RegExp(r'\b(\d{1,3})\s*(?:ta|ti|pcs)\s*(?:koro|kore dao|hobe)\b').firstMatch(text);
    if (q != null && lines.isNotEmpty) {
      (target ?? lines.last).qty = int.parse(q.group(1)!).clamp(1, 999);
      return cmd.copy(lines: lines);
    }
    // more items: "aro ekta charger 450"
    if (hit != null && !toks.any({'bad', 'baad', 'remove', 'hatao', 'kato', 'delete'}.contains)) {
      final more = _lines(text.replaceAll(RegExp(r'\b(aro|also|add|plus|sathe|arekta|aaro|more)\b'), ' '), products, [], []);
      for (final m in more) {
        final same = lines.where((l) => asInt(l.product['id']) == asInt(m.product['id']) && (m.rate == null || m.rate == l.rate)).firstOrNull;
        if (same != null) {
          same.qty += m.qty;
        } else {
          lines.add(m);
        }
      }
      if (more.isNotEmpty) return cmd.copy(lines: lines);
    }
    return changed ? cmd.copy(lines: lines) : null;
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
        // the shop's own words, learnt from saved bills, come first
        final learnt = AiMemory.product(q);
        if (learnt != null) {
          final p = products.where((x) => asInt(x['id']) == learnt).firstOrNull;
          if (p != null) {
            final score = 1.6 + (j - i) * 0.15;
            if (best == null || score > best.$4) best = (p, i, j, score);
            continue;
          }
        }
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
      var hit = 0.0;
      var exact = 0;
      for (final n in name) {
        if (said.contains(n)) {
          hit++;
          exact++;
        } else if (n.length >= 4 && said.any((w) => w.length >= 3 && w[0] == n[0] && SmartSearch.distance(n, w, max: 2) <= (n.length >= 6 ? 2 : 1))) {
          hit += 0.85; // a spelling slip: "Rahim Sekh" for "Rahim Sheikh"
        }
      }
      // the full name, or two of its words, are needed (not one common word)
      final score = hit / name.length;
      if (exact > 0 && (score >= 0.85 || hit >= 1.85) && score > bestScore) {
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

  /// The bill's discount in paise (said amount, or percent of the total).
  static int discountOf(BillCommand c, [int? gross]) {
    final t = gross ?? total(c.lines);
    final d = c.discountPct > 0 ? (t * c.discountPct / 10000).round() : c.discount;
    return d.clamp(0, t);
  }

  /// The money account for a way of paying.
  static Future<int?> account(String? pay) async {
    final acc = await Books.moneyAccounts();
    if (acc.isEmpty) return null;
    bool kind(Rec a, List<String> w) => w.any('${a['name']} ${a['card_type'] ?? ''} ${a['code'] ?? ''}'.toLowerCase().contains);
    final pick = switch (pay) {
      'upi' =>
        acc.where((a) => kind(a, ['upi', 'gpay', 'phonepe', 'paytm'])).firstOrNull ?? acc.where((a) => kind(a, ['bank', 'savings', 'current'])).firstOrNull,
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
    final discount = discountOf(c);
    final t = total(c.lines) - discount;
    final paid = pay == 'due' ? (paidNow ?? 0).clamp(0, t) : (paidNow ?? t).clamp(0, t);
    if (cid == null && paid < t) throw AccountingError('A credit bill needs the customer\'s name or phone');
    final id = await Books.createSale(items: items, customerId: cid, paid: paid, discount: discount, accountId: await account(pay == 'due' ? 'cash' : pay));
    // learn the shop's words for next time
    try {
      for (final l in c.lines) {
        if (l.said.trim().isNotEmpty) await AiMemory.learnProduct(l.said, asInt(l.product['id']));
      }
      if (cid != null && (c.said ?? '').trim().isNotEmpty) await AiMemory.learnCustomer(c.said!, cid);
    } catch (_) {}
    final number = '${(await Books.query('SELECT number FROM sales WHERE id = ?', [id])).first['number']}';
    return (id, number, t, paid);
  }
}

/// A question for the shop's own report engine (Brain.ask).
class AskBooks {
  final String question;
  const AskBooks(this.question);
}
