part of 'cloud.dart';

class VpsError implements Exception {
  final int status;
  final String message;
  VpsError(this.status, this.message);
  @override
  String toString() => 'Server $status: $message';
}

/// Your own server (the VPS): the live copy of the books goes here within
/// seconds of every change. Photos stay in Firebase. Each request carries
/// the Firebase sign-in token; the server only lets each account see its
/// own data (tool/vps/hisab_sync.py).
class Vps {
  static const defaultBase = 'https://admin.deencircle.online/hisab/api';
  static String base = defaultBase;
  static bool? _up;
  static DateTime? _checked;

  /// Is the server reachable? (checked at most once a minute)
  static Future<bool> available({bool fresh = false}) async {
    if (!fresh && _checked != null && DateTime.now().difference(_checked!) < const Duration(minutes: 1) && _up != null) return _up!;
    try {
      final r = await _send('GET', 'health', auth: false, timeout: const Duration(seconds: 6));
      _up = r.$1 == 200;
    } catch (_) {
      _up = false;
    }
    _checked = DateTime.now();
    return _up!;
  }

  static void markDown() {
    _up = false;
    _checked = DateTime.now();
  }

  static Future<(int, List<int>)> _send(String method, String path,
      {List<int>? body, String type = 'application/octet-stream', bool auth = true, Duration timeout = const Duration(seconds: 30)}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse('$base/$path')).timeout(timeout);
      if (auth) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${await Cloud._token()}');
      req.headers.set(HttpHeaders.userAgentHeader, 'HisabAI/1.0');
      if (body != null) {
        req.headers.contentType = ContentType.parse(type);
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final bytes = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d)).timeout(timeout);
      return (res.statusCode, bytes.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<int>> _ok(String method, String path, {List<int>? body, String type = 'application/octet-stream'}) async {
    final (code, bytes) = await _send(method, path, body: body, type: type);
    if (code >= 200 && code < 300) return bytes;
    String msg;
    try {
      msg = '${(jsonDecode(utf8.decode(bytes)) as Map)['error']}';
    } catch (_) {
      msg = 'request failed';
    }
    throw VpsError(code, msg);
  }

  static Future<void> putBlob(String key, List<int> gz) => _ok('PUT', 'blob/$key', body: gz);

  /// A piece, un-gzipped.
  static Future<List<int>> getBlob(String key) async => GZipDecoder().decodeBytes(await _ok('GET', 'blob/$key'));

  static Future<void> deleteBlob(String key) => _ok('DELETE', 'blob/$key');

  static Future<void> putManifest(String store, String slot, Map<String, Object?> m) =>
      _ok('PUT', 'manifest/$store/$slot', body: utf8.encode(jsonEncode(m)), type: 'application/json');

  /// Waits (up to [hold] seconds) for a copy of [store] newer than [after];
  /// returns the newest {created, slot, install, changed}.
  static Future<Map<String, dynamic>> wait(String store, String after, {int hold = 25}) async {
    final (code, bytes) = await _send('GET', 'wait/$store?after=${Uri.encodeQueryComponent(after)}&hold=$hold',
        timeout: Duration(seconds: hold + 15));
    if (code != 200) throw VpsError(code, 'wait failed');
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  static Future<List<Map<String, dynamic>>> manifests() async =>
      [for (final x in jsonDecode(utf8.decode(await _ok('GET', 'manifests'))) as List) (x as Map).cast<String, dynamic>()];

  static Future<Map<String, dynamic>> manifest(String store, String slot) async =>
      (jsonDecode(utf8.decode(await _ok('GET', 'manifest/$store/$slot'))) as Map).cast<String, dynamic>();
}
