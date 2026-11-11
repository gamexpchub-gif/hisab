// Renders the real app screens (with demo data) to PNG files in screenshots/.
// Run: flutter test --update-goldens test_screens/
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hisab/core/books.dart';
import 'package:hisab/core/db.dart';
import 'package:hisab/main.dart';
import 'package:hisab/ui/theme.dart';

Future<void> _assetFont(String family, String asset) async {
  final l = FontLoader(family)..addFont(rootBundle.load(asset));
  await l.load();
}

Future<void> _fileFont(String family, String? path) async {
  if (path == null || !File(path).existsSync()) return;
  final bytes = File(path).readAsBytesSync();
  final l = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
  await l.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _assetFont('Jakarta', 'assets/fonts/PlusJakartaSans.ttf');
    await _assetFont('Montserrat', 'assets/fonts/Montserrat.ttf');
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    await _fileFont('MaterialIcons', '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await _fileFont('Roboto', Platform.environment['ROBOTO_TTF']);
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: AppDb.schemaVersion, onConfigure: AppDb.configure, onCreate: AppDb.create, singleInstance: false));
    AppDb.useDatabase(db);
    await Books.loadDemo();
  });

  for (final (name, index) in [('home', 0), ('dashboard', 1), ('products', 2), ('menu', 3)]) {
    testWidgets(name, (t) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: Shell(initialIndex: index)));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await t.pump(const Duration(milliseconds: 400));
      }
      await t.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await t.pump(const Duration(seconds: 2));
      await expectLater(find.byType(Shell), matchesGoldenFile('../screenshots/$name.png'));
    });
  }
}
