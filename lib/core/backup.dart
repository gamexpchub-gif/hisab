import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cloud/cloud.dart';
import 'books.dart';
import 'db.dart';
import 'money.dart';

/// One backup file on the phone.
class BackupFile {
  final File file;
  final DateTime when;
  final int bytes;
  final bool auto;
  BackupFile(this.file, this.when, this.bytes, this.auto);
  String get name => p.basename(file.path);
}

/// Full backup of the books: the database plus every photo (products,
/// customers, KYC, bills, expenses) in one .zip. Restoring replaces
/// everything on the phone with the backup's contents.
class Backup {
  static const _magic = 'SQLite format 3';
  static const keepAuto = 10;

  static Future<Directory> _docs() => getApplicationDocumentsDirectory();

  static Future<Directory> folder() async {
    final d = Directory(p.join((await _docs()).path, 'backups'));
    await d.create(recursive: true);
    return d;
  }

  /// Backups on the phone, newest first.
  static Future<List<BackupFile>> list() async {
    final out = <BackupFile>[];
    await for (final e in (await folder()).list()) {
      if (e is File && e.path.endsWith('.zip')) {
        final st = await e.stat();
        out.add(BackupFile(e, st.modified, st.size, p.basename(e.path).contains('-auto-')));
      }
    }
    out.sort((a, b) => b.when.compareTo(a.when));
    return out;
  }

  /// Writes a new backup and returns it. Auto backups keep the last [keepAuto].
  static Future<File> create({bool auto = false}) async {
    final docs = await _docs();
    final archive = Archive();
    // the database file, copied while it is closed so it is consistent
    final dbPath = await AppDb.path();
    await AppDb.close();
    final dbBytes = await File(dbPath).readAsBytes();
    archive.addFile(ArchiveFile('hisab.db', dbBytes.length, dbBytes));
    // photos and documents (everything except the backups themselves)
    var photos = 0;
    await for (final e in docs.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: docs.path);
      if (rel.startsWith('backups') || rel.startsWith('flutter_assets') || rel.endsWith('.db')) continue;
      final b = await e.readAsBytes();
      archive.addFile(ArchiveFile('files/$rel', b.length, b));
      photos++;
    }
    final counts = <String, int>{};
    for (final t in ['sales', 'purchases', 'products', 'customers', 'suppliers', 'expenses']) {
      counts[t] = asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']);
    }
    final meta = utf8.encode(jsonEncode({
      'app': 'GameX Hisab',
      'created': DateTime.now().toIso8601String(),
      'schema': AppDb.schemaVersion,
      'photos': photos,
      ...counts,
    }));
    archive.addFile(ArchiveFile('backup.json', meta.length, meta));
    final zip = ZipEncoder().encode(archive) ?? (throw AccountingError("Could not create the backup file"));
    final now = DateTime.now();
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    final file = File(p.join((await folder()).path, 'GameX-Hisab-${auto ? 'auto-' : ''}$stamp.zip'));
    await file.writeAsBytes(zip, flush: true);
    await Books.setSetting('last_backup_at', now.toIso8601String());
    if (auto) {
      final autos = (await list()).where((b) => b.auto).toList();
      for (final old in autos.skip(keepAuto)) {
        await old.file.delete();
      }
    }
    return file;
  }

  /// Makes one automatic backup a day (called when the app opens).
  static Future<void> autoDaily() async {
    try {
      final s = await Books.settings();
      if (s['auto_backup'] == '0') return;
      final last = DateTime.tryParse(s['last_backup_at'] ?? '');
      final now = DateTime.now();
      if (last != null && last.year == now.year && last.month == now.month && last.day == now.day) return;
      if (await phoneIsEmpty()) return; // nothing to protect yet
      final f = await create(auto: true);
      // and the same backup to the cloud when signed in
      await Cloud.load();
      if (Cloud.user != null && s['cloud_auto'] != '0') await Cloud.uploadBackup(f);
    } catch (_) {
      // a failed automatic backup must never stop the app
    }
  }

  /// Counts of what is on this phone now (to warn before a restore).
  static Future<Map<String, int>> localCounts() async {
    final out = <String, int>{};
    for (final t in ['products', 'sales', 'purchases', 'customers', 'suppliers', 'expenses']) {
      out[t] = asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']);
    }
    return out;
  }

  /// True when the phone has no books at all (no products, parties or bills).
  static Future<bool> phoneIsEmpty() async => (await localCounts()).values.every((v) => v == 0);

  /// "12 products, 30 sales, 4 customers" for a restore warning.
  static Future<String> localSummary() async {
    final c = await localCounts();
    final parts = [
      if (c['products']! > 0) '${c['products']} products',
      if (c['sales']! > 0) '${c['sales']} sales',
      if (c['purchases']! > 0) '${c['purchases']} purchases',
      if (c['customers']! > 0) '${c['customers']} customers',
    ];
    return parts.isEmpty ? 'nothing yet' : parts.join(', ');
  }

  /// Reads what a backup contains without restoring it.
  static Future<Map<String, dynamic>> inspect(File zip) async {
    final a = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final meta = a.findFile('backup.json');
    final db = a.findFile('hisab.db');
    if (db == null) throw AccountingError('This is not a GameX Hisab backup');
    final info = meta == null ? <String, dynamic>{} : jsonDecode(utf8.decode(meta.content as List<int>)) as Map<String, dynamic>;
    return info;
  }

  /// Replaces the books on this phone with [zip]. A safety backup of the
  /// current data is made first.
  static Future<void> restore(File zip) async {
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final db = archive.findFile('hisab.db');
    if (db == null) throw AccountingError('This is not a GameX Hisab backup');
    final bytes = db.content as List<int>;
    if (bytes.length < 100 || ascii.decode(bytes.sublist(0, 15), allowInvalid: true) != _magic) {
      throw AccountingError('The backup database is damaged');
    }
    try {
      await create(auto: true); // safety copy of what is being replaced
    } catch (_) {}
    final docs = await _docs();
    final dbPath = await AppDb.path();
    await AppDb.close();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(dbPath).writeAsBytes(bytes, flush: true);
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('files/')) continue;
      final rel = f.name.substring(6);
      if (rel.contains('..')) continue;
      final out = File(p.join(docs.path, rel));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
    }
    await AppDb.instance; // reopen (runs upgrades for older backups)
    Books.notifyChanged();
  }

  static String size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
