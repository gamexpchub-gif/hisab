part of 'cloud.dart';

// =============================================================================
// Accounts, plans and the admin panel, on Firestore:
//   accounts/{uid}  email, name, shop, phone, plan, planUntil, trialUntil,
//                   blocked, pending, stores, products, sales, lastSeen
//   requests/{id}   uid, email, name, plan, months, note, status, created
// The rules let a user create their own account (as a trial) and update
// everything except plan / planUntil / trialUntil / blocked; only the admin
// (by email, in the rules) can read every account and change plans.
// =============================================================================

class CloudAccount {
  final String uid, email, name, shop, phone, plan, note;
  final DateTime? planUntil, trialUntil, lastSeen, created;
  final bool blocked;
  final String? pending;
  final int stores, products, sales;
  CloudAccount({
    required this.uid,
    required this.email,
    required this.name,
    required this.shop,
    required this.phone,
    required this.plan,
    required this.note,
    this.planUntil,
    this.trialUntil,
    this.lastSeen,
    this.created,
    required this.blocked,
    this.pending,
    required this.stores,
    required this.products,
    required this.sales,
  });

  DateTime? get until => plan == 'trial' ? trialUntil : planUntil;
  bool get active => !blocked && until != null && until!.isAfter(DateTime.now()) && plan != 'none';
  int get price => active ? (planById(plan)?.price ?? 0) : 0;
  String get status => blocked ? 'Blocked' : !active ? 'Expired' : plan == 'trial' ? 'Trial' : planById(plan)?.name ?? plan;
}

class PlanRequest {
  final String id, uid, email, name, plan, note, status;
  final int months;
  final DateTime? created;
  PlanRequest(this.id, this.uid, this.email, this.name, this.plan, this.months, this.note, this.status, this.created);
  int get amount => planById(plan)?.amount(months) ?? 0;
}

// Firestore value helpers ---------------------------------------------------
Map<String, dynamic> _v(Object? v) => switch (v) {
      null => {'nullValue': null},
      bool b => {'booleanValue': b},
      int i => {'integerValue': '$i'},
      DateTime d => {'timestampValue': d.toUtc().toIso8601String()},
      _ => {'stringValue': '$v'},
    };

Object? _read(Map<String, dynamic>? f) {
  if (f == null) return null;
  if (f.containsKey('stringValue')) return f['stringValue'];
  if (f.containsKey('integerValue')) return int.tryParse('${f['integerValue']}');
  if (f.containsKey('booleanValue')) return f['booleanValue'];
  if (f.containsKey('timestampValue')) return DateTime.tryParse('${f['timestampValue']}')?.toLocal();
  return null;
}

String _mask(Iterable<String> keys) => '?${keys.map((k) => 'updateMask.fieldPaths=$k').join('&')}';

CloudAccount _account(Map<String, dynamic> d) {
  final f = (d['fields'] ?? {}) as Map<String, dynamic>;
  T? g<T>(String k) => _read(f[k] as Map<String, dynamic>?) as T?;
  return CloudAccount(
    uid: '${d['name']}'.split('/').last,
    email: g<String>('email') ?? '',
    name: g<String>('name') ?? '',
    shop: g<String>('shop') ?? '',
    phone: g<String>('phone') ?? '',
    plan: g<String>('plan') ?? 'trial',
    note: g<String>('note') ?? '',
    planUntil: g<DateTime>('planUntil'),
    trialUntil: g<DateTime>('trialUntil'),
    lastSeen: g<DateTime>('lastSeen'),
    created: g<DateTime>('created'),
    blocked: g<bool>('blocked') ?? false,
    pending: g<String>('pending'),
    stores: g<int>('stores') ?? 1,
    products: g<int>('products') ?? 0,
    sales: g<int>('sales') ?? 0,
  );
}

class Accounts {
  /// Reads (or creates) this user's account, applies the plan on the phone
  /// and reports usage. Quietly does nothing offline.
  static Future<void> sync() async {
    await Cloud.load();
    if (Cloud.user == null) return;
    try {
      final token = await Cloud._token();
      final uid = Cloud._uid!;
      CloudAccount? acc;
      try {
        acc = _account(await Cloud._call('GET', Cloud._doc('accounts/$uid'), token: token));
      } on CloudError {
        if (Cloud._status != 404) rethrow;
      }
      if (acc == null) {
        // first sign-in: a trial that ends when the phone's trial ends (≤ 7 days)
        final end = Sub.until != null && Sub.plan == 'trial' && Sub.until!.isBefore(DateTime.now().add(const Duration(days: 7)))
            ? Sub.until!
            : DateTime.now().add(const Duration(days: Sub.trialDays));
        await Cloud._call('PATCH', Cloud._doc('accounts/$uid', '?currentDocument.exists=false'), token: token, body: {
          'fields': {
            'email': _v(Cloud._email ?? ''),
            'name': _v(Cloud._name ?? ''),
            'plan': _v('trial'),
            'trialUntil': _v(end),
            'blocked': _v(false),
            'created': _v(DateTime.now()),
          }
        });
        acc = _account(await Cloud._call('GET', Cloud._doc('accounts/$uid'), token: token));
      }
      // admin? (only the admin may list every account)
      var admin = false;
      try {
        await Cloud._call('GET', Cloud._doc('accounts', '?pageSize=1'), token: token);
        admin = true;
      } on CloudError {
        admin = false;
      }
      await Sub.apply(plan: acc.plan, until: acc.until, admin: admin, blocked: acc.blocked, pending: acc.pending);
      // usage for the admin panel
      final s = await Books.settings();
      final counts = await Stores.counts();
      final usage = <String, Object?>{
        'email': Cloud._email ?? acc.email,
        'name': Cloud._name ?? acc.name,
        'shop': (s['business_name'] ?? '').trim(),
        'phone': (s['phone'] ?? '').trim(),
        'stores': Stores.all.length,
        'products': counts.values.fold<int>(0, (a, c) => a + c.$1),
        'sales': counts.values.fold<int>(0, (a, c) => a + c.$2),
        'lastSeen': DateTime.now(),
      };
      await Cloud._call('PATCH', Cloud._doc('accounts/$uid', _mask(usage.keys)),
          token: token, body: {'fields': {for (final e in usage.entries) e.key: _v(e.value)}});
    } catch (_) {
      // offline or rules not updated yet: keep what the phone knows
    }
  }

  /// Asks the admin for a plan (payment is settled outside the app for now).
  static Future<void> requestPlan(String plan, int months, String note) async {
    final token = await Cloud._token();
    await Cloud._call('POST', Cloud._doc('requests'), token: token, body: {
      'fields': {
        'uid': _v(Cloud._uid),
        'email': _v(Cloud._email ?? ''),
        'name': _v(Cloud._name ?? ''),
        'plan': _v(plan),
        'months': _v(months),
        'note': _v(note.trim()),
        'status': _v('pending'),
        'created': _v(DateTime.now()),
      }
    });
    await Cloud._call('PATCH', Cloud._doc('accounts/${Cloud._uid}', _mask(['pending'])), token: token, body: {
      'fields': {'pending': _v('$plan × $months')}
    });
    await Sub.apply(plan: Sub.plan, until: Sub.until, admin: Sub.admin, blocked: Sub.blocked, pending: '$plan × $months');
  }

  // ---------------------------------------------------------------- admin
  static Future<List<CloudAccount>> listAccounts() async {
    final token = await Cloud._token();
    final out = <CloudAccount>[];
    String? page;
    do {
      final r = await Cloud._call('GET', Cloud._doc('accounts', '?pageSize=300${page == null ? '' : '&pageToken=$page'}'), token: token);
      for (final d in (r['documents'] as List? ?? const [])) {
        out.add(_account(d as Map<String, dynamic>));
      }
      page = r['nextPageToken'] as String?;
    } while (page != null);
    out.sort((a, b) => (b.lastSeen ?? DateTime(2000)).compareTo(a.lastSeen ?? DateTime(2000)));
    return out;
  }

  static Future<List<PlanRequest>> listRequests() async {
    final token = await Cloud._token();
    final r = await Cloud._call('GET', Cloud._doc('requests', '?pageSize=300'), token: token);
    final out = <PlanRequest>[];
    for (final d in (r['documents'] as List? ?? const [])) {
      final m = d as Map<String, dynamic>;
      final f = (m['fields'] ?? {}) as Map<String, dynamic>;
      T? g<T>(String k) => _read(f[k] as Map<String, dynamic>?) as T?;
      out.add(PlanRequest('${m['name']}'.split('/').last, g<String>('uid') ?? '', g<String>('email') ?? '', g<String>('name') ?? '',
          g<String>('plan') ?? '', g<int>('months') ?? 1, g<String>('note') ?? '', g<String>('status') ?? 'pending', g<DateTime>('created')));
    }
    out.sort((a, b) => (b.created ?? DateTime(2000)).compareTo(a.created ?? DateTime(2000)));
    return out;
  }

  /// Sets a user's plan until [until] (admin only).
  static Future<void> setPlan(String uid, String plan, DateTime until) async {
    final token = await Cloud._token();
    final fields = <String, Object?>{
      'plan': plan,
      if (plan == 'trial') 'trialUntil': until else 'planUntil': until,
      'blocked': false,
      'pending': null,
    };
    await Cloud._call('PATCH', Cloud._doc('accounts/$uid', _mask(fields.keys)),
        token: token, body: {'fields': {for (final e in fields.entries) e.key: _v(e.value)}});
    if (uid == Cloud._uid) await sync();
  }

  static Future<void> setBlocked(String uid, bool blocked) async {
    final token = await Cloud._token();
    await Cloud._call('PATCH', Cloud._doc('accounts/$uid', _mask(['blocked'])), token: token, body: {
      'fields': {'blocked': _v(blocked)}
    });
  }

  static Future<void> setNote(String uid, String note) async {
    final token = await Cloud._token();
    await Cloud._call('PATCH', Cloud._doc('accounts/$uid', _mask(['note'])), token: token, body: {
      'fields': {'note': _v(note)}
    });
  }

  /// Approves a request: the plan runs from today (or from the current end
  /// if the user still has days left) for the requested months.
  static Future<void> approve(PlanRequest r, CloudAccount? acc) async {
    final start = acc != null && acc.active && acc.plan == r.plan && acc.until != null ? acc.until! : DateTime.now();
    await setPlan(r.uid, r.plan, addMonths(start, r.months));
    await _closeRequest(r.id, 'approved');
  }

  static Future<void> reject(PlanRequest r) async {
    await _closeRequest(r.id, 'rejected');
    final token = await Cloud._token();
    await Cloud._call('PATCH', Cloud._doc('accounts/${r.uid}', _mask(['pending'])), token: token, body: {
      'fields': {'pending': _v(null)}
    });
  }

  static Future<void> _closeRequest(String id, String status) async {
    final token = await Cloud._token();
    await Cloud._call('PATCH', Cloud._doc('requests/$id', _mask(['status', 'closed'])), token: token, body: {
      'fields': {'status': _v(status), 'closed': _v(DateTime.now())}
    });
  }
}

/// Firestore rules for Hisab AI. Paste into Firebase → Firestore → Rules,
/// with the admin's email in place of ADMIN_EMAIL.
const firestoreRules = r'''rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    function isAdmin() { return signedIn() && request.auth.token.email == 'ADMIN_EMAIL'; }

    match /users/{uid}/{document=**} {
      allow read, write: if signedIn() && (request.auth.uid == uid || isAdmin());
    }
    match /accounts/{uid} {
      allow get: if signedIn() && (request.auth.uid == uid || isAdmin());
      allow list, delete: if isAdmin();
      allow create: if isAdmin() || (signedIn() && request.auth.uid == uid
          && request.resource.data.plan == 'trial'
          && request.resource.data.blocked == false
          && request.resource.data.trialUntil <= request.time + duration.value(8, 'd'));
      allow update: if isAdmin() || (signedIn() && request.auth.uid == uid
          && !request.resource.data.diff(resource.data).affectedKeys()
              .hasAny(['plan', 'planUntil', 'trialUntil', 'blocked', 'note']));
    }
    match /requests/{id} {
      allow create: if signedIn() && request.resource.data.uid == request.auth.uid
          && request.resource.data.status == 'pending';
      allow get: if signedIn() && (resource.data.uid == request.auth.uid || isAdmin());
      allow list, update, delete: if isAdmin();
    }
  }
}''';
