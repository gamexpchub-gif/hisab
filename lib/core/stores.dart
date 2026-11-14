import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'books.dart';
import 'db.dart';
import 'plan.dart';

class Store {
  final String id, file;
  String name;
  final String created;
  Store(this.id, this.name, this.file, this.created);
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'file': file, 'created': created};
  static Store from(Map<String, dynamic> m) => Store('${m['id']}', '${m['name']}', '${m['file']}', '${m['created'] ?? ''}');
}

/// Several shops in one account. Each store has its own books (its own
/// database file); the first store keeps the original 'hisab.db'.
class Stores {
  static final List<Store> all = [];
  static String current = 'main';
  static bool _loaded = false;

  static Store get active => all.isEmpty
      ? Store('main', 'My Store', 'hisab.db', '')
      : all.firstWhere((s) => s.id == current, orElse: () => all.first);

  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'stores.json'));
  }

  /// Reads the store list and points the database at the active store.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        all
          ..clear()
          ..addAll([for (final s in (m['stores'] as List? ?? const [])) Store.from(s as Map<String, dynamic>)]);
        current = '${m['current'] ?? 'main'}';
      }
    } catch (_) {}
    if (all.isEmpty) {
      String name = 'My Store';
      try {
        name = (await Books.settings())['business_name'] ?? name;
      } catch (_) {}
      all.add(Store('main', name, 'hisab.db', DateTime.now().toIso8601String()));
      await _save();
    }
    if (!all.any((s) => s.id == current)) current = all.first.id;
    AppDb.file = active.file;
  }

  static Future<void> _save() async {
    try {
      await (await _file()).writeAsString(jsonEncode({'current': current, 'stores': [for (final s in all) s.toJson()]}));
    } catch (_) {}
  }

  /// Opens another store's books.
  static Future<void> switchTo(String id) async {
    if (id == current || !all.any((s) => s.id == id)) return;
    await AppDb.close();
    current = id;
    AppDb.file = active.file;
    await _save();
    await AppDb.instance;
    Books.notifyChanged();
  }

  /// Adds a new, empty store and switches to it.
  static Future<Store> add(String name) async {
    name = name.trim();
    if (name.isEmpty) throw AccountingError('Store-er naam likhun');
    if (all.length >= Sub.storeLimit) {
      throw PlanLimitError('${Sub.label} plan-e ${Sub.storeLimit} ta store — aro store-er jonno upgrade korun', feature: 'multi_store');
    }
    final id = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final s = Store(id, name, 'store_$id.db', DateTime.now().toIso8601String());
    all.add(s);
    await _save();
    await switchTo(id);
    await Books.setSetting('business_name', name);
    return s;
  }

  static Future<void> rename(String id, String name) async {
    final s = all.firstWhere((x) => x.id == id);
    s.name = name.trim().isEmpty ? s.name : name.trim();
    await _save();
    if (id == current) await Books.setSetting('business_name', s.name);
    Books.notifyChanged();
  }

  /// Deletes a store and its books (not the one in use, not the last one).
  static Future<void> remove(String id) async {
    if (id == current) throw AccountingError('Ei store ekhon cholche — onno store-e giye delete korun');
    if (all.length <= 1) throw AccountingError('Kom-pokkhe ekta store thakte hobe');
    final s = all.firstWhere((x) => x.id == id);
    final path = p.join(await getDatabasesPath(), s.file);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    all.remove(s);
    await _save();
    Books.notifyChanged();
  }

  /// Quick numbers of every store (for the store list and the admin's cloud record).
  static Future<Map<String, (int, int)>> counts() async {
    final out = <String, (int, int)>{};
    for (final s in all) {
      if (s.id == current) {
        out[s.id] = (
          asInt((await Books.query('SELECT COUNT(*) AS c FROM products')).first['c']),
          asInt((await Books.query('SELECT COUNT(*) AS c FROM sales')).first['c']),
        );
        continue;
      }
      try {
        final path = p.join(await getDatabasesPath(), s.file);
        if (!await File(path).exists()) {
          out[s.id] = (0, 0);
          continue;
        }
        final db = await openDatabase(path, readOnly: true, singleInstance: false);
        try {
          out[s.id] = (
            asInt((await db.rawQuery('SELECT COUNT(*) AS c FROM products')).first['c']),
            asInt((await db.rawQuery('SELECT COUNT(*) AS c FROM sales')).first['c']),
          );
        } finally {
          await db.close();
        }
      } catch (_) {
        out[s.id] = (0, 0);
      }
    }
    return out;
  }
}
