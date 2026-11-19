import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cloud/cloud.dart';
import 'backup.dart';
import 'books.dart';
import 'plan.dart';
import 'stores.dart';

/// Live backup status: kind = idle | off | phone | sending | cloud | waiting.
class LiveState {
  final String kind;
  final DateTime? at;
  final String text;
  final int pending; // changes not yet in the cloud
  const LiveState(this.kind, this.at, this.text, {this.pending = 0});
}

/// Real-time backup. Every change to the books is sent to the cloud within
/// about two seconds — only the pieces that changed:
///   · the database is cut into 128 KB pieces, each stored once by its hash
///     (a sale changes a few pieces, so only those few go up);
///   · photos and documents go up once, when they are new or changed;
///   · a small manifest (written last, in one of two slots) says which
///     pieces make the copy, so a cut connection never spoils the last
///     good copy.
/// Offline it keeps the phone copy and sends everything when the internet
/// is back. Pieces nothing uses any more are deleted.
class LiveSync {
  static const piece = 128 * 1024;
  static final state = ValueNotifier<LiveState>(const LiveState('idle', null, 'Live backup starts after your next change'));

  static Timer? _wait, _retry;
  static bool _busy = false, _again = false, _started = false;

  /// Set while the whole account is being restored (no upload in between).
  static bool paused = false;
  static int _pending = 0;
  static Map<String, dynamic>? _st;

  // ---------------------------------------------------------------- state file
  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'live_sync.json'));
  }

  static Future<Map<String, dynamic>> _state() async {
    if (_st != null) return _st!;
    try {
      final f = await _file();
      if (await f.exists()) return _st = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    final r = Random.secure();
    return _st = {
      'install': List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join(),
      'uid': null,
      'uploaded': <String>[],
      'files': <String, dynamic>{},
      'refs': <String, dynamic>{},
      'slot': <String, dynamic>{},
    };
  }

  /// The last copy that reached the cloud: (time, sales, products, customers).
  static Future<Map<String, dynamic>?> lastCloud() async => ((await _state())['last'] as Map?)?.cast<String, dynamic>();

  static Future<void> _save() async {
    try {
      await (await _file()).writeAsString(jsonEncode(_st));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- start / triggers
  static void start() {
    if (_started) return;
    _started = true;
    Books.changes.addListener(_changed);
    _retry = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_pending > 0) run();
    });
    _state().then((s) {
      final last = (s['status'] as Map?)?.cast<String, dynamic>();
      if (last != null && state.value.kind == 'idle') {
        state.value = LiveState('${last['kind']}', DateTime.tryParse('${last['at']}'), '${last['text']}', pending: _pending);
      }
    });
  }

  static void stop() {
    Books.changes.removeListener(_changed);
    _wait?.cancel();
    _retry?.cancel();
    _started = false;
  }

  /// Leaving or returning to the app: send what is waiting.
  static void flush() {
    if (_pending > 0) run();
  }

  static void _changed() {
    _pending++;
    _wait?.cancel();
    // a save writes a few rows in a row; wait a moment for it to finish
    _wait = Timer(const Duration(milliseconds: 1500), run);
  }

  /// Sends everything now (leaving the app, or the "Back up now" button).
  static Future<void> now() async {
    _wait?.cancel();
    _pending = max(_pending, 1);
    await run();
  }

  static void _status(String kind, String text, {DateTime? at}) {
    state.value = LiveState(kind, at ?? DateTime.now(), text, pending: _pending);
    final s = _st;
    if (s != null && kind != 'sending') s['status'] = {'kind': kind, 'at': (at ?? DateTime.now()).toIso8601String(), 'text': text};
  }

  // ---------------------------------------------------------------- one pass
  static Future<void> run() async {
    if (paused) return;
    if (_busy) {
      _again = true; // send again right after this pass
      return;
    }
    _busy = true;
    final taken = _pending;
    try {
      final settings = await Books.settings();
      if (settings['live_backup'] == '0') {
        _status('off', 'Live backup is off');
        return;
      }
      if (await Backup.phoneIsEmpty()) return;
      final st = await _state();
      final store = Stores.active;
      final counts = <String, int>{
        for (final t in ['sales', 'products', 'customers']) t: asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']),
      };
      final db = await Backup.snapshot();
      // the store was switched while copying: this copy is not that store's
      if (Stores.current != store.id || paused) {
        _again = true;
        return;
      }
      // 1 · the phone copy (instant, works offline)
      await _phoneCopy(db, store.id);
      await Cloud.load();
      if (Cloud.user == null || !Sub.can('cloud')) {
        _pending = max(0, _pending - taken);
        _status('phone',
            Cloud.user == null ? 'Saved on phone · sign in for the cloud copy' : 'Saved on phone · cloud copy needs the ${Sub.need('cloud')} plan (Menu → Plans)');
        return;
      }
      // a different account on this phone: start a fresh upload list
      if (st['uid'] != Cloud.user!.uid) {
        st['uid'] = Cloud.user!.uid;
        st['uploaded'] = <String>[];
        st['files'] = <String, dynamic>{};
        st['refs'] = <String, dynamic>{};
      }
      _status('sending', 'Saving to cloud…');
      final uploaded = <String>{...(st['uploaded'] as List).cast<String>()};
      final install = '${st['install']}';
      var sent = 0;

      Future<List<String>> pieces(List<int> bytes) async {
        final keys = <String>[];
        final todo = <(String, List<int>)>[];
        for (var i = 0; i < bytes.length || (i == 0 && bytes.isEmpty); i += piece) {
          final part = bytes.sublist(i, min(i + piece, bytes.length));
          final key = '${install}_${sha1.convert(part)}';
          if (!uploaded.contains(key) && !todo.any((t) => t.$1 == key)) todo.add((key, part));
          keys.add(key);
          if (bytes.isEmpty) break;
        }
        // 4 pieces at a time: a change reaches the cloud in a second or two
        for (var i = 0; i < todo.length; i += 4) {
          await Future.wait([
            for (final (key, part) in todo.skip(i).take(4))
              Cloud.putBlob(key, GZipEncoder().encode(part)!).then((_) {
                uploaded.add(key);
                sent += part.length;
              }),
          ]);
          st['uploaded'] = uploaded.toList();
        }
        return keys;
      }

      // 2 · books: only the changed pieces — and the manifest right away, so
      //     the books are safe in the cloud within seconds, before any photo
      final dbKeys = await pieces(db);
      final files = (st['files'] as Map).cast<String, dynamic>();
      final slots = (st['slot'] as Map).cast<String, dynamic>();
      // a fresh install does not know which slot is newer: ask the cloud and
      // write over the OLDER one, so the newest copy is never lost
      if (slots[store.id] == null) {
        final ta = await Cloud.liveSlotTime('live_${store.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}_a');
        final tb = await Cloud.liveSlotTime('live_${store.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}_b');
        // slots[] holds the slot written LAST; the next write goes to the other
        slots[store.id] = (ta != null && (tb == null || ta.isAfter(tb))) ? 'a' : 'b';
      }
      final slot = slots[store.id] == 'a' ? 'b' : 'a';
      final key = store.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      Future<void> writeManifest(Map<String, List<String>> withFiles) async {
        final manifest = jsonEncode({
          'v': 2,
          'db': {'size': db.length, 'keys': dbKeys},
          'files': withFiles,
        });
        await Cloud.putLiveManifest('live_${key}_$slot',
            manifest: manifest, storeId: store.id, storeName: store.name, counts: counts, bytes: db.length);
      }

      // photos already in the cloud go into the first manifest too
      final ready = <String, List<String>>{
        for (final e in files.entries)
          if (((e.value as Map)['keys'] as List).every((k) => uploaded.contains(k))) e.key: ((e.value as Map)['keys'] as List).cast<String>(),
      };
      await writeManifest(ready);
      slots[store.id] = slot;
      st['uploaded'] = uploaded.toList();
      st['last'] = {'at': DateTime.now().toIso8601String(), ...counts};
      _pending = max(0, _pending - taken);
      _status('cloud', 'Books saved to cloud${sent == 0 ? '' : ' · ${_size(sent)} sent'}');
      await _save();

      // 3 · photos & documents: only new or changed files, then the manifest again
      final manifestFiles = <String, List<String>>{};
      final docs = await getApplicationDocumentsDirectory();
      var newFiles = 0;
      await for (final e in docs.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: docs.path);
        if (rel.startsWith('backups') || rel.startsWith('flutter_assets') || rel.endsWith('.db') || rel.endsWith('.tmp')) continue;
        final stat = await e.stat();
        final sig = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
        final known = (files[rel] as Map?)?.cast<String, dynamic>();
        List<String> keys;
        if (known != null && known['sig'] == sig && ((known['keys'] as List).cast<String>()).every(uploaded.contains)) {
          keys = (known['keys'] as List).cast<String>();
        } else {
          keys = await pieces(await e.readAsBytes());
          newFiles++;
        }
        files[rel] = {'sig': sig, 'keys': keys};
        manifestFiles[rel] = keys;
        if (newFiles > 0 && newFiles % 10 == 0) await _save(); // long first sync: keep progress
      }
      files.removeWhere((k, _) => !manifestFiles.containsKey(k));
      final changedFiles = newFiles > 0 || manifestFiles.length != ready.length;
      if (changedFiles) await writeManifest(manifestFiles);
      // 5 · forget pieces no copy uses any more (this store's last two + other stores)
      final refs = (st['refs'] as Map).cast<String, dynamic>();
      final prev = ((refs[store.id] as Map?)?['cur'] as List?)?.cast<String>() ?? const <String>[];
      final cur = [...dbKeys, for (final v in manifestFiles.values) ...v];
      refs[store.id] = {'cur': cur, 'prev': prev};
      final used = <String>{for (final r in refs.values) ...((r as Map)['cur'] as List).cast<String>(), for (final r in refs.values) ...((r as Map)['prev'] as List).cast<String>()};
      final unused = uploaded.where((k) => !used.contains(k)).take(40).toList();
      for (final k in unused) {
        try {
          await Cloud.deleteBlob(k);
          uploaded.remove(k);
        } catch (_) {}
      }
      st['uploaded'] = uploaded.toList();
      _status('cloud', 'Saved to cloud${sent == 0 ? ' · up to date' : ' · ${_size(sent)} sent'}${newFiles > 0 ? ' · $newFiles photo${newFiles == 1 ? '' : 's'}' : ''}');
    } catch (e) {
      final offline = e is SocketException || '$e'.contains('internet') || '$e'.contains('host lookup') || '$e'.contains('Connection');
      _status('waiting', offline ? 'Saved on phone · will send when the internet is back' : 'Cloud copy waiting: $e');
    } finally {
      await _save();
      _busy = false;
      if (_again) {
        _again = false;
        Timer(const Duration(milliseconds: 300), run);
      }
    }
  }

  static String _size(int b) => b < 1024 ? '$b B' : b < 1024 * 1024 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB';

  /// The phone copy: one zip per store, replaced safely.
  static Future<void> _phoneCopy(List<int> db, String storeId) async {
    final archive = Archive()..addFile(ArchiveFile('hisab.db', db.length, db));
    final meta = utf8.encode(jsonEncode({'app': 'Hisab AI', 'created': DateTime.now().toIso8601String(), 'store': storeId, 'live': true}));
    archive.addFile(ArchiveFile('backup.json', meta.length, meta));
    final zip = ZipEncoder().encode(archive)!;
    final dir = await Backup.folder();
    final tmp = File(p.join(dir.path, '.live-$storeId.tmp'));
    await tmp.writeAsBytes(zip, flush: true);
    await tmp.rename(p.join(dir.path, 'Hisab-AI-live-$storeId.zip'));
  }
}
