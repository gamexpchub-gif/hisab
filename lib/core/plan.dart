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
  PlanDef('basic', 'Basic', 'Choto dokan shuru korar jonno', 199, 1999, 1, 60, 300, 1),
  PlanDef('gold', 'Gold', 'Barte thaka business-er jonno', 599, 6999, 2, 500, 3000, 3),
  PlanDef('premium', 'Premium', 'Shob feature, kono limit nei', 999, 11988, 3, 0, 0, 10),
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
  Feature('emi', 'EMI / kisti tracker', 2),
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
  Feature('early', 'Notun feature shobar age', 3),
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

  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'subscription.json'));
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        plan = '${m['plan'] ?? 'trial'}';
        until = DateTime.tryParse('${m['until'] ?? ''}');
        admin = m['admin'] == true;
        blocked = m['blocked'] == true;
        pending = m['pending'] as String?;
      } else {
        plan = 'trial';
        until = DateTime.now().add(const Duration(days: trialDays));
        await save();
      }
    } catch (_) {
      plan = 'trial';
      until ??= DateTime.now().add(const Duration(days: trialDays));
    }
  }

  static Future<void> save() async {
    try {
      await (await _file()).writeAsString(jsonEncode({
        'plan': plan,
        'until': until?.toIso8601String(),
        'admin': admin,
        'blocked': blocked,
        'pending': pending,
      }));
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
    if (blocked) throw PlanLimitError('Ei account block kora — admin-er sathe jogajog korun');
    if (!active) {
      throw PlanLimitError(plan == 'trial'
          ? 'Free trial shesh — notun ${action == 'product' ? 'product' : 'bill'} korte plan nin (Menu → Plans)'
          : '$label plan-er meyad shesh — renew korun (Menu → Plans)');
    }
    final d = def;
    if (d == null) return;
    final since = ymd(DateTime.now().subtract(const Duration(days: 30)));
    if (action == 'product' && d.products > 0) {
      final n = asInt((await Books.query('SELECT COUNT(*) AS c FROM products WHERE substr(created_at, 1, 10) >= ?', [since])).first['c']);
      if (n >= d.products) {
        throw PlanLimitError('${d.name} plan-e 30 dine ${d.products} ta product — ${n >= d.products ? 'limit shesh' : ''}. Gold/Premium-e upgrade korun');
      }
    }
    if (action == 'sale' && d.sales > 0) {
      final n = asInt((await Books.query('SELECT COUNT(*) AS c FROM sales WHERE date >= ?', [since])).first['c']);
      if (n >= d.sales) throw PlanLimitError('${d.name} plan-e 30 dine ${d.sales} ta bill — limit shesh. Upgrade korun');
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

  /// Applies what the cloud account says.
  static Future<void> apply({required String plan, DateTime? until, bool admin = false, bool blocked = false, String? pending}) async {
    Sub.plan = plan;
    Sub.until = until;
    Sub.admin = admin;
    Sub.blocked = blocked;
    Sub.pending = pending;
    await save();
    Books.notifyChanged();
  }
}
