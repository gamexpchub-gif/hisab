import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../cloud/cloud.dart';
import 'books.dart';
import 'db.dart';
import 'money.dart';
import 'plan.dart';
import 'stores.dart';

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
        out.add(BackupFile(e, st.modified, st.size, p.basename(e.path).contains('-auto-') || p.basename(e.path).contains('-live-')));
      }
    }
    out.sort((a, b) => b.when.compareTo(a.when));
    return out;
  }

  /// Writes a new backup and returns it. Auto backups keep the last [keepAuto].
  static Future<File> create({bool auto = false}) async {
    final docs = await _docs();
    final archive = Archive();
    final counts = <String, int>{};
    for (final t in ['sales', 'purchases', 'products', 'customers', 'suppliers', 'expenses']) {
      counts[t] = asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']);
    }
    // the database file, copied while it is closed (and locked) so it is consistent
    final dbBytes = await AppDb.exclusive((path) => File(path).readAsBytes());
    if (dbBytes.length < 100 || ascii.decode(dbBytes.sublist(0, 15), allowInvalid: true) != _magic) {
      throw AccountingError('Could not read the books for the backup');
    }
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
    final meta = utf8.encode(jsonEncode({
      'app': 'Hisab AI',
      'created': DateTime.now().toIso8601String(),
      'schema': AppDb.schemaVersion,
      'photos': photos,
      ...counts,
    }));
    archive.addFile(ArchiveFile('backup.json', meta.length, meta));
    final zip = ZipEncoder().encode(archive) ?? (throw AccountingError("Could not create the backup file"));
    final now = DateTime.now();
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    final file = File(p.join((await folder()).path, 'Hisab-AI-${auto ? 'auto-' : ''}$stamp.zip'));
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

  // ---------------------------------------------------------------- automatic backups
  static bool _running = false;
  static Timer? _timer;
  static _AutoObserver? _observer;

  /// Starts automatic backups: a few seconds after the app opens, every 30
  /// minutes while it is open, and whenever it comes back to the foreground.
  /// Each run only does what is due, so it is cheap.
  static void startAuto() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => autoRun());
    if (_observer == null) {
      _observer = _AutoObserver();
      WidgetsBinding.instance.addObserver(_observer!);
    }
    Future<void>.delayed(const Duration(seconds: 8), autoRun);
  }

  static Future<File> _stateFile() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'auto_backup.json'));
  }

  /// {stores: {id: {local, cloud}}, status: {at, ok, msg}}
  static Future<Map<String, dynamic>> autoState() async {
    try {
      final f = await _stateFile();
      if (await f.exists()) return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    return {'stores': <String, dynamic>{}};
  }

  static Future<void> _saveState(Map<String, dynamic> st) async {
    try {
      await (await _stateFile()).writeAsString(jsonEncode(st));
    } catch (_) {}
  }

  /// Records a cloud backup made by hand, so the automatic one is not repeated.
  static Future<void> markCloud(String storeId) async {
    final st = await autoState();
    final stores = (st['stores'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final rec = (stores[storeId] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    rec['cloud'] = DateTime.now().toIso8601String();
    stores[storeId] = rec;
    st['stores'] = stores;
    st['status'] = {'at': DateTime.now().toIso8601String(), 'ok': true, 'msg': 'Backed up to cloud'};
    await _saveState(st);
  }

  /// One pass: a phone backup of the open store once a day, and a cloud
  /// backup of every store (with data) every 20 hours when signed in.
  static Future<void> autoRun() async {
    if (_running) return;
    _running = true;
    final st = await autoState();
    final stores = (st['stores'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final now = DateTime.now();
    final did = <String>[];
    try {
      final s = await Books.settings();
      final localOn = s['auto_backup'] != '0';
      await Cloud.load();
      final cloudOn = Cloud.user != null && s['cloud_auto'] != '0' && Sub.can('cloud');
      for (final store in List.of(Stores.all)) {
        final rec = (stores[store.id] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final lastLocal = DateTime.tryParse('${rec['local'] ?? ''}');
        final lastCloud = DateTime.tryParse('${rec['cloud'] ?? ''}');
        final active = store.id == Stores.current;
        final needLocal = active && localOn && (lastLocal == null || !_sameDay(lastLocal, now));
        final needCloud = cloudOn && (lastCloud == null || now.difference(lastCloud) >= const Duration(hours: 20));
        if (!needLocal && !needCloud) continue;
        File? f;
        Map<String, int>? counts;
        if (active) {
          if (await phoneIsEmpty()) continue; // nothing to protect yet
          f = await create(auto: true);
          rec['local'] = now.toIso8601String();
          if (needLocal) did.add('phone');
        } else {
          if (!needCloud) continue;
          final made = await _zipStore(store);
          if (made == null) continue;
          (f, counts) = made;
        }
        if (needCloud) {
          await Cloud.uploadBackup(f!, storeId: store.id, storeName: store.name, counts: counts, auto: true);
          rec['cloud'] = now.toIso8601String();
          did.add('cloud · ${store.name}');
          if (!active) await f.delete().catchError((_) => f!);
        }
        stores[store.id] = rec;
      }
      st['stores'] = stores;
      if (did.isNotEmpty) st['status'] = {'at': now.toIso8601String(), 'ok': true, 'msg': 'Backed up: ${did.join(', ')}'};
    } catch (e) {
      st['stores'] = stores;
      st['status'] = {'at': now.toIso8601String(), 'ok': false, 'msg': '$e'};
    } finally {
      await _saveState(st);
      _running = false;
    }
  }

  // ---------------------------------------------------------------- live backup
  /// What the live backup is doing, for the screens ("Saved to cloud 4:12 PM").
  static final live = ValueNotifier<LiveState>(const LiveState('idle', null, 'Live backup starts after your next change'));
  static Timer? _liveWait;
  static Timer? _liveRetry; // every 2 min while a change waits to be sent
  static bool _liveDirty = false, _liveBusy = false, _liveStarted = false;
  static DateTime? _liveLast;

  /// Live (real-time) backup: a few seconds after any change to the books,
  /// the open store is copied to the phone and to the cloud. Offline, it
  /// waits and sends as soon as the internet is back; when the app goes to
  /// the background it is sent at once.
  static void startLive() {
    if (_liveStarted) return;
    _liveStarted = true;
    Books.changes.addListener(_changed);
    _liveRetry?.cancel();
    _liveRetry = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_liveDirty) _liveRun();
    });
  }

  static void _changed() {
    _liveDirty = true;
    _liveWait?.cancel();
    _liveWait = Timer(const Duration(seconds: 8), _liveRun);
  }

  /// A consistent copy of the open database without closing it (VACUUM INTO
  /// runs in the database's own queue, between sales). Phones with an old
  /// SQLite (before 3.27) fall back to the closed-file copy.
  static Future<List<int>> snapshot() async {
    try {
      final tmp = File(p.join((await getTemporaryDirectory()).path, 'hisab-live-${DateTime.now().microsecondsSinceEpoch}.db'));
      final db = await AppDb.instance;
      await db.execute('VACUUM INTO ?', [tmp.path]);
      final b = await tmp.readAsBytes();
      await tmp.delete().catchError((_) => tmp);
      return b;
    } catch (_) {
      return AppDb.exclusive((path) => File(path).readAsBytes());
    }
  }

  static void _liveRetryNow() {
    if (_liveDirty) _liveRun();
  }

  /// Sends the pending change now (app going to the background).
  static Future<void> liveNow() async {
    _liveWait?.cancel();
    if (_liveDirty) await _liveRun(force: true);
  }

  static Future<void> _liveRun({bool force = false}) async {
    if (_liveBusy) return; // the running pass checks the dirty flag again
    // at most one upload every 30 s while selling fast
    final since = _liveLast == null ? null : DateTime.now().difference(_liveLast!);
    if (!force && since != null && since < const Duration(seconds: 30)) {
      _liveWait?.cancel();
      _liveWait = Timer(const Duration(seconds: 30) - since, _liveRun);
      return;
    }
    _liveBusy = true;
    _liveDirty = false; // changes made from here on mark it again
    try {
      final s = await Books.settings();
      if (s['live_backup'] == '0') {
        live.value = const LiveState('off', null, 'Live backup is off');
        return;
      }
      if (await phoneIsEmpty()) return;
      final store = Stores.active;
      final counts = <String, int>{
        for (final t in ['sales', 'products', 'customers']) t: asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']),
      };
      // a consistent copy of the open store's database
      final dbBytes = await snapshot();
      if (dbBytes.length < 100 || ascii.decode(dbBytes.sublist(0, 15), allowInvalid: true) != _magic) return;
      final archive = Archive()..addFile(ArchiveFile('hisab.db', dbBytes.length, dbBytes));
      final meta = utf8.encode(jsonEncode({
        'app': 'Hisab AI',
        'created': DateTime.now().toIso8601String(),
        'schema': AppDb.schemaVersion,
        'store': store.id,
        'storeName': store.name,
        'live': true,
        ...counts,
      }));
      archive.addFile(ArchiveFile('backup.json', meta.length, meta));
      final zip = ZipEncoder().encode(archive) ?? (throw AccountingError('Could not create the backup file'));
      // 1 · on the phone (one file per store, replaced safely)
      final dir = await folder();
      final tmp = File(p.join(dir.path, '.live-${store.id}.tmp'));
      await tmp.writeAsBytes(zip, flush: true);
      await tmp.rename(p.join(dir.path, 'Hisab-AI-live-${store.id}.zip'));
      final now = DateTime.now();
      _liveLast = now;
      // 2 · to the cloud
      await Cloud.load();
      if (Cloud.user != null && Sub.can('cloud')) {
        live.value = LiveState('sending', now, 'Saving to cloud…');
        await Cloud.uploadLive(zip, storeId: store.id, storeName: store.name, counts: counts);
        live.value = LiveState('cloud', DateTime.now(), 'Saved to cloud');
      } else {
        live.value = LiveState('phone', now, Cloud.user == null ? 'Saved on phone · sign in for cloud' : 'Saved on phone');
      }
    } catch (e) {
      _liveDirty = true; // try again (internet back, next change or in 2 min)
      final msg = e is SocketException || '$e'.contains('internet') || '$e'.contains('Failed host lookup')
          ? 'Saved on phone · will send when the internet is back'
          : 'Cloud copy waiting: $e';
      live.value = LiveState('waiting', _liveLast, msg);
    } finally {
      _liveBusy = false;
      if (_liveDirty) {
        _liveWait?.cancel();
        _liveWait = Timer(const Duration(seconds: 30), _liveRun);
      }
    }
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// A backup zip of a store that is not open (its database file is idle).
  static Future<(File, Map<String, int>)?> _zipStore(Store store) async {
    final path = p.join(await getDatabasesPath(), store.file);
    final src = File(path);
    if (!await src.exists()) return null;
    final counts = await Stores.counts();
    final c = counts[store.id];
    if (c == null || (c.$1 == 0 && c.$2 == 0)) return null;
    final bytes = await src.readAsBytes();
    if (bytes.length < 100 || ascii.decode(bytes.sublist(0, 15), allowInvalid: true) != _magic) return null;
    final archive = Archive()..addFile(ArchiveFile('hisab.db', bytes.length, bytes));
    final meta = utf8.encode(jsonEncode({
      'app': 'Hisab AI',
      'created': DateTime.now().toIso8601String(),
      'schema': AppDb.schemaVersion,
      'store': store.id,
      'storeName': store.name,
      'products': c.$1,
      'sales': c.$2,
    }));
    archive.addFile(ArchiveFile('backup.json', meta.length, meta));
    final zip = ZipEncoder().encode(archive) ?? (throw AccountingError('Could not create the backup file'));
    final tmp = await getTemporaryDirectory();
    final f = File(p.join(tmp.path, 'Hisab-AI-${store.id}-auto.zip'));
    await f.writeAsBytes(zip, flush: true);
    return (f, {'products': c.$1, 'sales': c.$2, 'customers': 0});
  }

  /// Backs up every store now (phone + cloud), ignoring the schedule.
  static Future<void> forceAll() async {
    final st = await autoState();
    st['stores'] = <String, dynamic>{};
    await _saveState(st);
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await autoRun();
    final status = ((await autoState())['status'] as Map?)?.cast<String, dynamic>();
    if (status != null && status['ok'] == false) throw AccountingError('${status['msg']}');
  }

  /// Kept for older callers: runs the automatic backup once.
  static Future<void> autoDaily() => autoRun();

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
    if (db == null) throw AccountingError('This is not a Hisab AI backup');
    final info = meta == null ? <String, dynamic>{} : jsonDecode(utf8.decode(meta.content as List<int>)) as Map<String, dynamic>;
    return info;
  }

  /// Replaces the books on this phone with [zip]. A safety backup of the
  /// current data is made first.
  static Future<void> restore(File zip) async {
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final db = archive.findFile('hisab.db');
    if (db == null) throw AccountingError('This is not a Hisab AI backup');
    final bytes = db.content as List<int>;
    if (bytes.length < 100 || ascii.decode(bytes.sublist(0, 15), allowInvalid: true) != _magic) {
      throw AccountingError('The backup database is damaged');
    }
    try {
      await create(auto: true); // safety copy of what is being replaced
    } catch (_) {}
    final docs = await _docs();
    // swap the database file while nothing can open it
    await AppDb.exclusive((dbPath) async {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) await f.delete();
      }
      await File(dbPath).parent.create(recursive: true);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    });
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('files/')) continue;
      final rel = f.name.substring(6);
      if (rel.contains('..')) continue;
      final out = File(p.join(docs.path, rel));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
    }
    // reopen (runs upgrades for older backups) and check the books are readable
    final books = await AppDb.instance;
    final ok = await books.rawQuery('PRAGMA quick_check');
    if (ok.isEmpty || '${ok.first.values.first}' != 'ok') {
      throw AccountingError('The restored books are damaged — your previous data is in the latest automatic backup');
    }
    await Books.setSetting('last_restore_at', DateTime.now().toIso8601String());
    Books.notifyChanged();
  }

  static String size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Runs the automatic backup when the app comes back to the foreground.
class _AutoObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Backup.autoRun();
      Backup._liveRetryNow();
    }
    // leaving the app: send the last change at once
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) Backup.liveNow();
  }
}

/// Live backup status: kind = idle | off | phone | sending | cloud | waiting.
class LiveState {
  final String kind;
  final DateTime? at;
  final String text;
  const LiveState(this.kind, this.at, this.text);
}
