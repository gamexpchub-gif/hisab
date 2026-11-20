import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'books.dart';
import 'money.dart';

// =============================================================================
// Hisab AI plans. Basic ₹199, Gold ₹599, Premium ₹999 a month. Every feature
// of the app belongs to one tier: Basic opens about 30% of them, Gold about
// 65% and Premium all of them. New accounts get a 7-day trial of everything.
// The plan is kept on the phone (app-support folder, shared by all stores)
// and refreshed from the cloud account when signed in.
// =============================================================================

class PlanDef {
  final String id, name, tagline;
  final int price; // ₹ a month
  final int yearly; // ₹ a year
  final int tier; // 1 basic · 2 gold · 3 premium
  final int products, sales, stores; // per 30 days / stores; 0 = unlimited
  const PlanDef(this.id, this.name, this.tagline, this.price, this.yearly, this.tier, this.products, this.sales, this.stores);

  /// Price for [months]: whole years at the yearly price, the rest monthly.
  int amount(int months) => (months ~/ 12) * yearly + (months % 12) * price;

  /// What a year saves against 12 monthly payments.
  int get yearSaving => price * 12 - yearly;
  int get yearSavingPct => price == 0 ? 0 : (yearSaving * 100 / (price * 12)).round();
  int get yearlyPerMonth => (yearly / 12).round();
}

const plans = [
  PlanDef('basic', 'Basic', 'For small shops getting started', 199, 1999, 1, 60, 300, 1),
  PlanDef('gold', 'Gold', 'For growing businesses', 599, 6999, 2, 500, 3000, 3),
  PlanDef('premium', 'Premium', 'Every feature, no limits', 999, 9999, 3, 0, 0, 10),
];

PlanDef? planById(String? id) => plans.where((x) => x.id == id).firstOrNull;

class Feature {
  final String key, name;
  final int tier;
  const Feature(this.key, this.name, this.tier);
}

/// Every feature, by the plan that opens it. Basic ≈ 30%, Gold ≈ 65%, Premium 100%.
const features = [
  // Basic (tier 1)
  Feature('sales', 'Sale & billing', 1),
  Feature('purchases', 'Purchase & stock in', 1),
  Feature('products', 'Products & stock', 1),
  Feature('parties', 'Customer & supplier khata', 1),
  Feature('expenses', 'Expenses', 1),
  Feature('print', 'Bill print (A4 / 80mm / 58mm)', 1),
  Feature('scanner', 'Barcode scanner', 1),
  Feature('cash_bank', 'Cash & bank', 1),
  Feature('backup', 'Phone backup & restore', 1),
  Feature('search', 'Search everything', 1),
  Feature('dashboard', 'Dashboard & home stats', 1),
  // Gold (tier 2)
  Feature('returns', 'Sale return', 2),
  Feature('emi', 'EMI / instalment tracker', 2),
  Feature('imei', 'IMEI & warranty', 2),
  Feature('labels', 'Barcode label print', 2),
  Feature('whatsapp', 'WhatsApp reminder', 2),
  Feature('due_alarm', 'Due date ring alarm', 2),
  Feature('reports', 'P&L, ledgers, day book', 2),
  Feature('gst', 'GST report (GSTR-1, 3B, HSN)', 2),
  Feature('excel', 'Excel export', 2),
  Feature('cloud', 'Cloud backup', 2),
  Feature('lock', 'App lock (PIN / fingerprint)', 2),
  Feature('multi_store', 'Multiple stores (3)', 2),
  Feature('opp_id', 'Finance / opportunity ID on bill', 2),
  // Premium (tier 3)
  Feature('smart_ai', 'Smart Business AI', 3),
  Feature('daily_ai', 'Daily AI report', 3),
  Feature('analytics', 'Pro Analytics', 3),
  Feature('loans', 'Loans & investment', 3),
  Feature('smart_imei', 'Smart IMEI (model from IMEI)', 3),
  Feature('batch_scan', 'Batch scan', 3),
  Feature('custom_print', 'Custom print studio', 3),
  Feature('balance_sheet', 'Balance sheet & trial balance', 3),
  Feature('unlimited', 'Unlimited product & sale', 3),
  Feature('stores10', 'Up to 10 stores', 3),
  Feature('loan_alarm', 'Loan EMI alarm', 3),
  Feature('priority', 'Priority support', 3),
  Feature('early', 'Early access to new features', 3),
];

int featurePercent(int tier) => (features.where((f) => f.tier <= tier).length * 100 / features.length).round();

class PlanLimitError extends AccountingError {
  final String feature;
  PlanLimitError(super.message, {this.feature = ''});
}

/// The subscription on this phone.
class Sub {
  static const trialDays = 7;
  static String plan = 'trial'; // trial | basic | gold | premium | none
  static DateTime? until; // plan or trial end
  static bool admin = false, blocked = false;
  static String? pending; // plan requested and waiting for approval
  static bool _loaded = false;

  /// Whose plan is in use: a cloud account's uid, or 'device' when signed out.
  /// Every account keeps its own plan on the phone, so signing in with another
  /// ID never carries the previous ID's plan (or admin rights) across.
  static String owner = 'device';
  static final Map<String, Map<String, dynamic>> _all = {};

  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'subscription.json'));
  }

  static Map<String, dynamic> _pack() => {
        'plan': plan,
        'until': until?.toIso8601String(),
        'admin': admin,
        'blocked': blocked,
        'pending': pending,
      };

  static void _unpack(Map<String, dynamic> m) {
    plan = '${m['plan'] ?? 'trial'}';
    until = DateTime.tryParse('${m['until'] ?? ''}');
    admin = m['admin'] == true;
    blocked = m['blocked'] == true;
    pending = m['pending'] as String?;
  }

  /// The phone's own free trial (made once, never restarted).
  static Map<String, dynamic> _deviceTrial() => _all.putIfAbsent(
      'device', () => {'plan': 'trial', 'until': DateTime.now().add(const Duration(days: trialDays)).toIso8601String()});

  /// Reads the saved plans and switches to [uid]'s (or the phone's when null).
  static Future<void> load({String? uid}) async {
    if (!_loaded) {
      _loaded = true;
      try {
        final f = await _file();
        if (await f.exists()) {
          final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          if (m['accounts'] is Map) {
            for (final e in (m['accounts'] as Map).entries) {
              if (e.value is Map) _all['${e.key}'] = Map<String, dynamic>.from(e.value as Map);
            }
          } else if (m.containsKey('plan')) {
            // older single-plan file: keep only the phone trial (the cloud
            // account's real plan is fetched again after sign-in)
            if (m['plan'] == 'trial') _all['device'] = {'plan': 'trial', 'until': m['until']};
          }
        }
      } catch (_) {}
    }
    await use(uid);
  }

  /// Makes [uid]'s plan the one in use (null = signed out → phone trial).
  static Future<void> use(String? uid) async {
    owner = (uid == null || uid.isEmpty) ? 'device' : uid;
    final d = _deviceTrial();
    final m = _all[owner];
    if (m != null) {
      _unpack(m);
    } else {
      // new account on this phone: the phone trial until the cloud answers
      _unpack({'plan': 'trial', 'until': d['until']});
    }
    await save();
    try {
      Books.notifyChanged();
    } catch (_) {}
  }

  static Future<void> save() async {
    _all[owner] = _pack();
    await _write();
  }

  static Future<void> _write() async {
    try {
      await (await _file()).writeAsString(jsonEncode({'v': 2, 'accounts': _all}));
    } catch (_) {}
  }

  static bool get active => admin || (!blocked && until != null && DateTime.now().isBefore(until!) && plan != 'none');
  static int get daysLeft => until == null ? 0 : until!.difference(DateTime.now()).inHours ~/ 24 + (until!.isAfter(DateTime.now()) ? 1 : 0);

  /// 0 = nothing (expired), 1 basic, 2 gold, 3 premium / trial / admin.
  static int get tier {
    if (admin) return 3;
    if (!active) return 0;
    return switch (plan) { 'basic' => 1, 'gold' => 2, _ => 3 };
  }

  static PlanDef? get def => admin || plan == 'trial' ? plans.last : planById(plan);
  static String get label => admin ? 'Admin' : !active ? 'Expired' : plan == 'trial' ? 'Free trial' : def?.name ?? plan;

  static Feature? feature(String key) => features.where((f) => f.key == key).firstOrNull;
  static bool can(String key) => tier >= (feature(key)?.tier ?? 1);
  static String need(String key) {
    final t = feature(key)?.tier ?? 1;
    return plans.firstWhere((p) => p.tier == t).name;
  }

  static int get storeLimit => tier == 0 ? 1 : (def?.stores ?? 1);

  /// Used by Books before a new product or sale is saved.
  static Future<void> guard(String action) async {
    if (admin) return;
    if (blocked) throw PlanLimitError('This account is blocked — please contact support');
    if (!active) {
      throw PlanLimitError(plan == 'trial'
          ? 'Your free trial has ended — choose a plan to add a new ${action == 'product' ? 'product' : 'bill'} (Menu → Plans)'
          : 'Your $label plan has expired — renew to continue (Menu → Plans)');
    }
    final d = def;
    if (d == null) return;
    final since = ymd(DateTime.now().subtract(const Duration(days: 30)));
    if (action == 'product' && d.products > 0) {
      final n = asInt((await Books.query('SELECT COUNT(*) AS c FROM products WHERE substr(created_at, 1, 10) >= ?', [since])).first['c']);
      if (n >= d.products) {
        throw PlanLimitError('${d.name} plan allows ${d.products} new products every 30 days — limit reached. Upgrade to Gold or Premium');
      }
    }
    if (action == 'sale' && d.sales > 0) {
      final n = asInt((await Books.query('SELECT COUNT(*) AS c FROM sales WHERE date >= ?', [since])).first['c']);
      if (n >= d.sales) throw PlanLimitError('${d.name} plan allows ${d.sales} bills every 30 days — limit reached. Upgrade your plan');
    }
  }

  /// Usage in the last 30 days: (products, sales).
  static Future<(int, int)> usage() async {
    final since = ymd(DateTime.now().subtract(const Duration(days: 30)));
    return (
      asInt((await Books.query('SELECT COUNT(*) AS c FROM products WHERE substr(created_at, 1, 10) >= ?', [since])).first['c']),
      asInt((await Books.query('SELECT COUNT(*) AS c FROM sales WHERE date >= ?', [since])).first['c']),
    );
  }

  /// Applies what the cloud account says. [uid] is the account the answer
  /// belongs to — if the phone has since switched to another ID, it is stored
  /// for that account only and the plan in use is left alone.
  static Future<void> apply({required String plan, DateTime? until, bool admin = false, bool blocked = false, String? pending, String? uid}) async {
    final m = {'plan': plan, 'until': until?.toIso8601String(), 'admin': admin, 'blocked': blocked, 'pending': pending};
    final key = uid ?? owner;
    if (key != owner) {
      if (key != 'device') {
        _all[key] = m;
        await _write();
      }
      return;
    }
    _unpack(m);
    await save();
    Books.notifyChanged();
  }

}
