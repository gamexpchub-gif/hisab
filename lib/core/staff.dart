import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'books.dart';

/// A salesman / manager who uses the shop's phone with their own PIN.
class StaffMember {
  final String id;
  String name, role; // manager | sales | custom
  String pinHash;
  Set<String> perms;
  bool active;
  int maxDiscount; // % of the bill (with the discount permission)
  int maxCredit; // paise left unpaid on one bill, 0 = no limit
  int? fromHour, toHour; // working hours (24 h), null = any time
  int lockMinutes; // idle minutes before the app asks for a PIN again, 0 = never
  StaffMember(this.id, this.name, this.role, this.pinHash, this.perms,
      {this.active = true, this.maxDiscount = 10, this.maxCredit = 0, this.fromHour, this.toHour, this.lockMinutes = 0});

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'pin': pinHash,
        'perms': [...perms.where((p) => p != '_v3'), '_v3'], // '_v3': saved with the newer switches
        'active': active,
        'maxDiscount': maxDiscount,
        'maxCredit': maxCredit,
        'from': fromHour,
        'to': toHour,
        'lock': lockMinutes,
      };
  static StaffMember from(Map<String, dynamic> m) => StaffMember('${m['id']}', '${m['name']}', '${m['role'] ?? 'sales'}', '${m['pin'] ?? ''}',
      Staff._upgrade({for (final p in (m['perms'] as List? ?? const [])) '$p'}),
      active: m['active'] != false,
      maxDiscount: (m['maxDiscount'] as num?)?.toInt() ?? 10,
      maxCredit: (m['maxCredit'] as num?)?.toInt() ?? 0,
      fromHour: (m['from'] as num?)?.toInt(),
      toHour: (m['to'] as num?)?.toInt(),
      lockMinutes: (m['lock'] as num?)?.toInt() ?? 0);

  /// Inside the working hours now?
  bool onDuty([DateTime? at]) {
    if (fromHour == null || toHour == null) return true;
    final h = (at ?? DateTime.now()).hour;
    return fromHour! <= toHour! ? h >= fromHour! && h < toHour! : h >= fromHour! || h < toHour!;
  }
}

/// Staff login and permissions. The owner sets an owner PIN and adds staff;
/// when staff mode is on the app asks "who is working?" and each person
/// works with their own permissions. Every action in the activity log
/// carries the name of who did it.
class Staff {
  /// Every permission: key → (name, what it allows, group).
  static const perms = <String, (String, String, String)>{
    // Selling
    'sale': ('Make sales', 'New bills, scan, AI bills, add a customer while billing', 'Selling'),
    'credit': ('Sell on credit', 'Bills left unpaid or part-paid (khata)', 'Selling'),
    'discount': ('Give discounts', 'A discount on a bill', 'Selling'),
    'collect': ('Receive payments', 'Money from customers against their dues', 'Selling'),
    'returns': ('Sale returns', 'Take goods back and refund', 'Selling'),
    'edit_bill': ('Edit bills', 'Change a saved sale or purchase', 'Selling'),
    'price_edit': ('Sell below the price', 'Change a product\'s price down on a bill', 'Selling'),
    'all_bills': ('See everyone\'s bills', 'Without it: only their own bills in the sales list', 'Selling'),
    // Stock
    'products': ('Add & edit products', 'Products, prices, categories', 'Stock'),
    'purchase': ('Purchases', 'Supplier bills, stock in', 'Stock'),
    'profit': ('See cost & profit', 'Purchase price, margin and profit everywhere', 'Stock'),
    // Customers
    'customers': ('Customers & suppliers', 'Open khata, edit or add parties', 'Customers'),
    'see_phones': ('See phone numbers', 'Without it: customers\' numbers are hidden (98•••••321)', 'Customers'),
    // Money
    'expense': ('Expenses', 'Enter shop expenses', 'Money'),
    'cash_bank': ('Cash, bank & loans', 'Balances, transfers, paying suppliers, loans', 'Money'),
    // Reports
    'dashboard': ('Dashboard & home figures', 'Today\'s sales, totals, charts on the home screens', 'Reports'),
    'reports': ('Reports', 'P&L, ledgers, GST, Excel, analytics, daily report', 'Reports'),
    'ai_insights': ('AI insights', 'Forecast, alerts, customer scores, Autopilot', 'Reports'),
    // Mobile shop
    'repairs': ('Repair jobs', 'Job cards, status, deliver & bill', 'Shop'),
    'exchange': ('Exchange phones', 'Buy used phones from customers', 'Shop'),
    // Admin
    'delete': ('Delete', 'Delete bills, products, customers', 'Admin'),
    'settings': ('Settings & data', 'Shop settings, backup, stores, security, staff, activity log', 'Admin'),
  };

  static const groups = ['Selling', 'Stock', 'Customers', 'Money', 'Reports', 'Shop', 'Admin'];

  static const roles = <String, (String, Set<String>, String)>{
    'sales': ('Salesman', {'sale', 'collect', 'repairs'}, 'Sells and collects — no profit, no dashboard, no reports'),
    'cashier': ('Cashier', {'sale', 'credit', 'discount', 'collect', 'returns', 'customers', 'see_phones', 'all_bills', 'expense', 'repairs'}, 'Billing, credit, returns, khata — no profit'),
    'stock': ('Stock keeper', {'products', 'purchase'}, 'Products and purchases only'),
    'accountant': ('Accountant', {'dashboard', 'reports', 'profit', 'expense', 'cash_bank', 'customers', 'see_phones', 'all_bills', 'collect'}, 'Books and reports — no selling'),
    'manager': (
      'Manager',
      {'sale', 'credit', 'discount', 'collect', 'returns', 'edit_bill', 'price_edit', 'all_bills', 'products', 'purchase', 'profit', 'customers', 'see_phones', 'expense', 'cash_bank', 'dashboard', 'reports', 'ai_insights', 'repairs', 'exchange'},
      'Everything except delete and settings'
    ),
    'custom': ('Custom', {}, 'Choose each permission'),
  };

  /// Staff saved by an older version had fewer, wider permissions.
  static Set<String> _upgrade(Set<String> p) {
    if (p.contains('_v3')) return {...p}..remove('_v3'); // saved by this version: as is
    if (p.contains('sale') || p.contains('dashboard') || p.contains('products') || p.contains('collect')) {
      // saved before the 'see_phones' / 'all_bills' / 'price_edit' switches: keep what they could do
      return {...p, 'see_phones', 'all_bills', 'price_edit'};
    }
    final out = {...p, 'sale', 'collect', 'credit', 'returns', 'customers', 'repairs', 'exchange', 'see_phones', 'all_bills', 'price_edit'};
    if (p.contains('reports')) out.addAll({'dashboard', 'profit', 'ai_insights', 'cash_bank'});
    if (p.contains('purchase')) out.add('products');
    return out;
  }

  /// Who is using the app now (null = the owner).
  static final current = ValueNotifier<StaffMember?>(null);

  /// True while the app waits for someone to sign in (staff mode).
  static final picking = ValueNotifier<bool>(false);
  static bool _first = true;
  static List<StaffMember> _list = [];
  static bool _on = false;

  static String hash(String pin) => sha256.convert(utf8.encode('hisab-staff:$pin')).toString();

  static bool get modeOn => _on;
  static List<StaffMember> get list => List.unmodifiable(_list);
  static String get who => current.value?.name ?? 'Owner';

  /// Allowed for the person using the app now?
  static bool can(String perm) {
    final s = current.value;
    return s == null || s.perms.contains(perm);
  }

  static Future<void> load() async {
    final s = await Books.settings();
    _on = s['staff_mode'] == '1' && (s['staff_owner_pin'] ?? '').isNotEmpty;
    try {
      _list = [for (final m in jsonDecode(s['staff_list'] ?? '[]') as List) StaffMember.from(m as Map<String, dynamic>)];
    } catch (_) {
      _list = [];
    }
    final c = current.value;
    if (c != null) current.value = _list.where((x) => x.id == c.id && x.active).firstOrNull;
    if (!_on) {
      picking.value = false;
    } else if (_first) {
      picking.value = true; // app start: ask who is working
    }
    _first = false;
    // hooks used by the books
    Books.allow = can;
    Books.actor = () => current.value?.name;
    Books.ownBillsOf = () => ownBillsOf;
    Books.limits = () {
      final c = current.value;
      return c == null ? (null, null) : (c.maxDiscount, c.maxCredit == 0 ? null : c.maxCredit);
    };
  }

  static Future<void> _save() async {
    await Books.setSetting('staff_list', jsonEncode([for (final s in _list) s.toJson()]));
    await load();
  }

  static Future<bool> ownerPinSet() async => ((await Books.settings())['staff_owner_pin'] ?? '').isNotEmpty;

  static Future<bool> checkOwner(String pin) async => (await Books.settings())['staff_owner_pin'] == hash(pin);

  static Future<void> setOwnerPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) throw AccountingError('PIN must be 4–6 digits');
    await Books.setSetting('staff_owner_pin', hash(pin));
    await load();
  }

  static Future<void> setMode(bool on) async {
    if (on && !await ownerPinSet()) throw AccountingError('Set the owner PIN first');
    await Books.setSetting('staff_mode', on ? '1' : '0');
    if (!on) current.value = null;
    await load();
  }

  static Future<StaffMember> add(String name, String pin, String role, Set<String> perms, {StaffLimits? limits}) async {
    name = name.trim();
    if (name.isEmpty) throw AccountingError('Enter the name');
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) throw AccountingError('PIN must be 4–6 digits');
    if (_list.any((s) => s.pinHash == hash(pin)) || await checkOwner(pin)) throw AccountingError('This PIN is already used — choose another');
    final s = StaffMember(DateTime.now().microsecondsSinceEpoch.toRadixString(36), name, role, hash(pin), perms);
    limits?.applyTo(s);
    _list.add(s);
    await _save();
    await Books.log('staff', 'Staff added · $name (${roles[role]?.$1 ?? role})');
    return s;
  }

  static Future<void> update(StaffMember s,
      {String? name, String? role, Set<String>? perms, String? pin, bool? active, StaffLimits? limits}) async {
    if (limits != null) limits.applyTo(s);
    if (name != null && name.trim().isNotEmpty) s.name = name.trim();
    if (role != null) s.role = role;
    if (perms != null) s.perms = perms;
    if (active != null) s.active = active;
    if (pin != null && pin.isNotEmpty) {
      if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) throw AccountingError('PIN must be 4–6 digits');
      s.pinHash = hash(pin);
    }
    await _save();
  }

  static Future<void> remove(StaffMember s) async {
    _list.removeWhere((x) => x.id == s.id);
    await _save();
    await Books.log('staff', 'Staff removed · ${s.name}');
  }

  /// Signs in by PIN: a staff member, or the owner (returns null for the owner).
  /// Throws when the PIN matches nobody.
  static Future<StaffMember?> signIn(String pin) async {
    if (await checkOwner(pin)) {
      current.value = null;
      picking.value = false;
      await Books.log('staff', 'Owner signed in');
      return null;
    }
    final s = _list.where((x) => x.active && x.pinHash == hash(pin)).firstOrNull;
    if (s == null) throw AccountingError('Wrong PIN');
    if (!s.onDuty()) throw AccountingError('${s.name}: outside working hours (${s.fromHour}:00–${s.toHour}:00)');
    current.value = s;
    picking.value = false;
    await Books.log('staff', '${s.name} signed in');
    return s;
  }

  /// A phone number as this person may see it.
  static String phone(Object? p) {
    final t = '${p ?? ''}';
    if (t.isEmpty || can('see_phones')) return t;
    final d = t.replaceAll(RegExp(r'\D'), '');
    return d.length < 6 ? '•••' : '${d.substring(0, 2)}•••••${d.substring(d.length - 3)}';
  }

  /// Only the person's own bills (no 'all_bills')?
  static String? get ownBillsOf => current.value != null && !can('all_bills') ? current.value!.name : null;

  /// The owner's PIN allows one blocked action now ("owner override").
  static Future<T> withOwner<T>(String pin, Future<T> Function() action) async {
    if (!await checkOwner(pin)) throw AccountingError('Wrong owner PIN');
    await Books.log('staff', 'Owner allowed an action for ${who}');
    return Books.trusted(action);
  }

  // ---------------------------------------------------------------- idle lock
  static DateTime _lastTouch = DateTime.now();
  static void touch() => _lastTouch = DateTime.now();

  /// Locks when the person has been idle longer than their limit.
  static void checkIdle() {
    final c = current.value;
    if (c == null || c.lockMinutes <= 0 || picking.value) return;
    if (DateTime.now().difference(_lastTouch).inMinutes >= c.lockMinutes) signOut();
  }

  /// Bills and sales per staff member from [from] (activity log).
  static Future<Map<String, (int, int)>> sales({String? from}) async {
    final rows = await Books.query(
        "SELECT staff, COUNT(*) AS n, IFNULL(SUM(amount), 0) AS v FROM audit_log WHERE kind = 'sale' AND message LIKE 'New sale%' "
        "AND staff IS NOT NULL AND substr(created_at, 1, 10) >= ? GROUP BY staff",
        [from ?? '0000']);
    return {for (final r in rows) '${r['staff']}': (asInt(r['n']), asInt(r['v']))};
  }

  /// Locks the app for the next person ("switch user").
  static void signOut() {
    if (!_on) return;
    current.value = null;
    picking.value = true;
  }
}

/// The extra limits set in the staff editor.
class StaffLimits {
  final int maxDiscount, maxCredit, lockMinutes;
  final int? fromHour, toHour;
  const StaffLimits({this.maxDiscount = 10, this.maxCredit = 0, this.fromHour, this.toHour, this.lockMinutes = 0});
  void applyTo(StaffMember s) {
    s.maxDiscount = maxDiscount.clamp(0, 100);
    s.maxCredit = maxCredit < 0 ? 0 : maxCredit;
    final ok = fromHour != null && toHour != null && fromHour != toHour;
    s.fromHour = ok ? fromHour : null;
    s.toHour = ok ? toHour : null;
    s.lockMinutes = lockMinutes < 0 ? 0 : lockMinutes;
  }
}
