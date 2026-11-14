import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Brand + model for a TAC (first 8 digits of an IMEI).
class TacModel {
  final String brand, model;
  const TacModel(this.brand, this.model);
  String get name => model.toLowerCase().startsWith(brand.toLowerCase()) ? model : '$brand $model';
}

/// The public Osmocom TAC database (crowd-sourced phone models by TAC),
/// downloaded once and kept on the phone; refreshed every 30 days.
/// Coverage is best for well-known models; very new phones may be missing.
class TacDb {
  static const url = 'https://tacdb.osmocom.org/export/tacdb.csv';
  static Map<String, TacModel>? _map;
  static DateTime? _failedAt; // don't retry a failed download for 10 minutes

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'tacdb.csv'));
  }

  /// Splits one CSV line, honouring double quotes.
  static List<String> _split(String line) {
    final out = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if (ch == ',' && !q) {
        out.add(b.toString().trim());
        b.clear();
      } else {
        b.write(ch);
      }
    }
    out.add(b.toString().trim());
    return out;
  }

  static Map<String, TacModel> _parse(String csv) {
    final lines = const LineSplitter().convert(csv);
    final map = <String, TacModel>{};
    if (lines.isEmpty) return map;
    var tacCol = 0, brandCol = 1, modelCol = 2, start = 0;
    final head = _split(lines.first).map((h) => h.toLowerCase()).toList();
    if (head.any((h) => h.contains('tac'))) {
      start = 1;
      tacCol = head.indexWhere((h) => h.contains('tac'));
      final b = head.indexWhere((h) => h == 'name1' || h.contains('brand') || h.contains('manufacturer') || h.contains('vendor'));
      final m = head.indexWhere((h) => h == 'name2' || h.contains('model'));
      if (b >= 0) brandCol = b;
      if (m >= 0) modelCol = m;
    }
    for (var i = start; i < lines.length; i++) {
      final f = _split(lines[i]);
      if (f.length <= tacCol || f.length <= brandCol || f.length <= modelCol) continue;
      final tac = f[tacCol].replaceAll(RegExp(r'\D'), '');
      if (tac.length != 8) continue;
      final brand = f[brandCol], model = f[modelCol];
      if (model.isEmpty && brand.isEmpty) continue;
      map[tac] = TacModel(brand, model.isEmpty ? brand : model);
    }
    return map;
  }

  /// Downloads (or refreshes) the database. Returns how many models it has.
  static Future<int> download() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return 0;
      final text = await res.transform(utf8.decoder).join();
      final map = _parse(text);
      if (map.isEmpty) return 0;
      await (await _file()).writeAsString(text, flush: true);
      _map = map;
      return map.length;
    } catch (_) {
      return 0;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, TacModel>> _load() async {
    if (_map != null) return _map!;
    try {
      final f = await _file();
      if (await f.exists()) {
        _map = _parse(await f.readAsString());
        final age = DateTime.now().difference(await f.lastModified()).inDays;
        if (age > 30) download(); // refresh in the background
        return _map!;
      }
    } catch (_) {}
    if (_failedAt != null && DateTime.now().difference(_failedAt!).inMinutes < 10) return const {};
    if (await download() == 0) _failedAt = DateTime.now();
    return _map ?? const {};
  }

  /// Model for an IMEI, or null when the database doesn't know it.
  static Future<TacModel?> lookup(String imei) async {
    final d = imei.replaceAll(RegExp(r'\D'), '');
    if (d.length < 8) return null;
    final map = await _load();
    return map[d.substring(0, 8)];
  }
}
