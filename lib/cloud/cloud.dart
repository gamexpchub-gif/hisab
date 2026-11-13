import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/books.dart';

// =============================================================================
// GameX Cloud — account login and cloud backup on the shop's own Firebase
// project, through Firebase's REST APIs (Identity Toolkit + Firestore). Pure
// Dart: no native plugins, no google-services.json. The session and the
// project keys live in the app-support folder, outside the books' backups.
// =============================================================================

/// Optional built-in project keys. Leave empty and enter them in the app
/// (Login → Cloud setup) instead, or fill them here before building.
const _builtInApiKey = '';
const _builtInProjectId = '';

class CloudError implements Exception {
  final String message;
  CloudError(this.message);
  @override
  String toString() => message;
}

class CloudUser {
  final String uid, email;
  final String? name;
  CloudUser(this.uid, this.email, this.name);
}

class CloudBackup {
  final String id;
  final DateTime created;
  final int bytes, chunks, sales, products, customers;
  final String device;
  CloudBackup(this.id, this.created, this.bytes, this.chunks, this.sales, this.products, this.customers, this.device);
}

class Cloud {
  static String _apiKey = _builtInApiKey, _projectId = _builtInProjectId;
  static String? _uid, _email, _name, _idToken, _refreshToken;
  static DateTime? _expires;
  static bool _loaded = false;

  static bool get configured => _apiKey.isNotEmpty && _projectId.isNotEmpty;
  static CloudUser? get user => _uid == null ? null : CloudUser(_uid!, _email ?? '', _name);
  static String get projectId => _projectId;

  // ---------------------------------------------------------------- storage
  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, name));
  }

  /// Loads the saved project keys and session. Safe to call many times.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final cfg = await _file('cloud_config.json');
      if (await cfg.exists()) {
        final m = jsonDecode(await cfg.readAsString()) as Map<String, dynamic>;
        _apiKey = '${m['apiKey'] ?? _apiKey}';
        _projectId = '${m['projectId'] ?? _projectId}';
      }
      final s = await _file('cloud_session.json');
      if (await s.exists()) {
        final m = jsonDecode(await s.readAsString()) as Map<String, dynamic>;
        _uid = m['uid'] as String?;
        _email = m['email'] as String?;
        _name = m['name'] as String?;
        _refreshToken = m['refreshToken'] as String?;
      }
    } catch (_) {
      // missing or damaged files simply mean "not signed in"
    }
  }

  static Future<void> configure(String apiKey, String projectId) async {
    _apiKey = apiKey.trim();
    _projectId = projectId.trim();
    await (await _file('cloud_config.json')).writeAsString(jsonEncode({'apiKey': _apiKey, 'projectId': _projectId}));
  }

  static Future<void> _saveSession() async {
    final f = await _file('cloud_session.json');
    if (_uid == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.writeAsString(jsonEncode({'uid': _uid, 'email': _email, 'name': _name, 'refreshToken': _refreshToken}));
  }

  // ---------------------------------------------------------------- http
  static Future<Map<String, dynamic>> _call(String method, Uri url, {Object? body, String? token}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.openUrl(method, url);
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res.transform(utf8.decoder).join();
      final data = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        final err = data['error'];
        final msg = err is Map ? '${err['message'] ?? ''}' : '';
        final status = err is Map ? '${err['status'] ?? ''}' : '';
        final a = _friendly(msg), b = _friendly(status);
        throw CloudError(!a.startsWith('Cloud error') ? a : !b.startsWith('Cloud error') ? b : 'Cloud error: ${msg.isEmpty ? res.statusCode : msg}');
      }
      return data;
    } on SocketException {
      throw CloudError('No internet connection');
    } on HandshakeException {
      throw CloudError('Secure connection failed — check the phone date/time');
    } finally {
      client.close();
    }
  }

  static String _friendly(String code) {
    final c = code.split(' ').first.split(':').first;
    return switch (c) {
      'EMAIL_EXISTS' => 'An account with this email already exists — sign in instead',
      'EMAIL_NOT_FOUND' || 'INVALID_LOGIN_CREDENTIALS' || 'INVALID_PASSWORD' => 'Wrong email or password',
      'USER_DISABLED' => 'This account has been disabled',
      'WEAK_PASSWORD' => 'Password must be at least 6 characters',
      'INVALID_EMAIL' => 'Enter a valid email address',
      'MISSING_PASSWORD' => 'Enter your password',
      'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Too many tries — please wait a few minutes',
      'API_KEY_INVALID' || 'INVALID_API_KEY' => 'Cloud setup: the Web API key is wrong',
      'CONFIGURATION_NOT_FOUND' || 'OPERATION_NOT_ALLOWED' =>
        'Turn on Email/Password sign-in in Firebase (Authentication → Sign-in method)',
      'PERMISSION_DENIED' => 'Cloud refused access — check the Firestore rules',
      'NOT_FOUND' => 'Cloud database not found — create Firestore in the Firebase project',
      'TOKEN_EXPIRED' || 'INVALID_REFRESH_TOKEN' || 'USER_NOT_FOUND' => 'Session expired — please sign in again',
      _ => 'Cloud error: $code',
    };
  }

  static Uri _auth(String action) =>
      Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:$action?key=$_apiKey');

  static void _need() {
    if (!configured) throw CloudError('Cloud is not set up yet');
  }

  // ---------------------------------------------------------------- auth
  static Future<CloudUser> _session(Map<String, dynamic> r, {String? name}) async {
    _uid = r['localId'] as String;
    _email = r['email'] as String? ?? _email;
    _name = name ?? r['displayName'] as String? ?? _name;
    _idToken = r['idToken'] as String;
    _refreshToken = r['refreshToken'] as String;
    _expires = DateTime.now().add(Duration(seconds: int.tryParse('${r['expiresIn']}') ?? 3600) - const Duration(minutes: 2));
    await _saveSession();
    return user!;
  }

  static Future<CloudUser> signIn(String email, String password) async {
    _need();
    final r = await _call('POST', _auth('signInWithPassword'),
        body: {'email': email.trim(), 'password': password, 'returnSecureToken': true});
    return _session(r);
  }

  static Future<CloudUser> register(String name, String email, String password) async {
    _need();
    final r = await _call('POST', _auth('signUp'), body: {'email': email.trim(), 'password': password, 'returnSecureToken': true});
    if (name.trim().isNotEmpty) {
      await _call('POST', _auth('update'), body: {'idToken': r['idToken'], 'displayName': name.trim(), 'returnSecureToken': false});
    }
    return _session(r, name: name.trim().isEmpty ? null : name.trim());
  }

  static Future<void> resetPassword(String email) async {
    _need();
    await _call('POST', _auth('sendOobCode'), body: {'requestType': 'PASSWORD_RESET', 'email': email.trim()});
  }

  static Future<void> signOut() async {
    _uid = _email = _name = _idToken = _refreshToken = null;
    _expires = null;
    await _saveSession();
  }

  /// A valid ID token, refreshed when it is about to expire.
  static Future<String> _token() async {
    _need();
    if (_uid == null || _refreshToken == null) throw CloudError('Please sign in first');
    if (_idToken != null && _expires != null && DateTime.now().isBefore(_expires!)) return _idToken!;
    final r = await _call('POST', Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
        body: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken});
    _idToken = r['id_token'] as String;
    _refreshToken = r['refresh_token'] as String;
    _expires = DateTime.now().add(Duration(seconds: int.tryParse('${r['expires_in']}') ?? 3600) - const Duration(minutes: 2));
    await _saveSession();
    return _idToken!;
  }

  // ---------------------------------------------------------------- firestore
  static String get _base => 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';
  static Uri _doc(String path, [String query = '']) => Uri.parse('$_base/$path$query');

  static const chunkSize = 700 * 1024; // keeps every document under Firestore's 1 MiB limit

  /// Uploads a backup zip in chunks; keeps the newest [keep] backups in the cloud.
  static Future<CloudBackup> uploadBackup(File zip, {int keep = 5, void Function(double)? progress}) async {
    final token = await _token();
    final bytes = await zip.readAsBytes();
    final id = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final chunks = (bytes.length / chunkSize).ceil().clamp(1, 1 << 20).toInt();
    final root = 'users/$_uid/backups/$id';
    for (var i = 0; i < chunks; i++) {
      final part = bytes.sublist(i * chunkSize, ((i + 1) * chunkSize).clamp(0, bytes.length).toInt());
      await _call('PATCH', _doc('$root/chunks/${i.toString().padLeft(4, '0')}'),
          token: token, body: {'fields': {'data': {'bytesValue': base64Encode(part)}, 'n': {'integerValue': '$i'}}});
      progress?.call((i + 1) / (chunks + 1));
    }
    Future<int> count(String t) async => asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']);
    final meta = {
      'created': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      'bytes': {'integerValue': '${bytes.length}'},
      'chunks': {'integerValue': '$chunks'},
      'sales': {'integerValue': '${await count('sales')}'},
      'products': {'integerValue': '${await count('products')}'},
      'customers': {'integerValue': '${await count('customers')}'},
      'device': {'stringValue': Platform.localHostname},
      'complete': {'booleanValue': true},
    };
    await _call('PATCH', _doc(root), token: token, body: {'fields': meta});
    await _call('PATCH', _doc('users/$_uid'), token: token, body: {
      'fields': {
        'email': {'stringValue': _email ?? ''},
        'name': {'stringValue': _name ?? ''},
        'lastBackup': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      }
    });
    progress?.call(1);
    await Books.setSetting('last_cloud_backup_at', DateTime.now().toIso8601String());
    final all = await listBackups();
    for (final old in all.skip(keep)) {
      try {
        await deleteBackup(old);
      } catch (_) {}
    }
    return all.firstWhere((b) => b.id == id, orElse: () => all.first);
  }

  static Future<List<CloudBackup>> listBackups() async {
    final token = await _token();
    final r = await _call('GET', _doc('users/$_uid/backups', '?pageSize=100'), token: token);
    final out = <CloudBackup>[];
    for (final d in (r['documents'] as List? ?? const [])) {
      final m = d as Map<String, dynamic>;
      final f = (m['fields'] ?? {}) as Map<String, dynamic>;
      if (f['complete']?['booleanValue'] != true) continue;
      int n(String k) => int.tryParse('${f[k]?['integerValue'] ?? 0}') ?? 0;
      out.add(CloudBackup(
        '${m['name']}'.split('/').last,
        DateTime.tryParse('${f['created']?['timestampValue']}')?.toLocal() ?? DateTime(2000),
        n('bytes'),
        n('chunks'),
        n('sales'),
        n('products'),
        n('customers'),
        '${f['device']?['stringValue'] ?? ''}',
      ));
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  /// Downloads a backup into a temporary zip file.
  static Future<File> downloadBackup(CloudBackup b, {void Function(double)? progress}) async {
    final token = await _token();
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < b.chunks; i++) {
      final r = await _call('GET', _doc('users/$_uid/backups/${b.id}/chunks/${i.toString().padLeft(4, '0')}'), token: token);
      out.add(base64Decode('${r['fields']['data']['bytesValue']}'));
      progress?.call((i + 1) / b.chunks);
    }
    final tmp = await getTemporaryDirectory();
    final f = File(p.join(tmp.path, 'cloud-${b.id}.zip'));
    await f.writeAsBytes(out.takeBytes(), flush: true);
    return f;
  }

  static Future<void> deleteBackup(CloudBackup b) async {
    final token = await _token();
    for (var i = 0; i < b.chunks; i++) {
      await _call('DELETE', _doc('users/$_uid/backups/${b.id}/chunks/${i.toString().padLeft(4, '0')}'), token: token);
    }
    await _call('DELETE', _doc('users/$_uid/backups/${b.id}'), token: token);
  }
}
