// Renders the real app screens (with demo data) to PNG files in screenshots/.
// Run: flutter test --update-goldens test_screens/
import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hisab/core/books.dart';
import 'package:hisab/core/db.dart';
import 'package:hisab/main.dart';
import 'package:hisab/screens/bank.dart';
import 'package:hisab/screens/account.dart';
import 'package:hisab/screens/backup_screen.dart';
import 'package:hisab/screens/login.dart';
import 'package:hisab/screens/emi.dart';
import 'package:hisab/screens/expenses.dart';
import 'package:hisab/screens/imei.dart';
import 'package:hisab/screens/security.dart';
import 'package:hisab/screens/sales.dart';
import 'package:hisab/screens/ledgers.dart';
import 'package:hisab/screens/parties.dart';
import 'package:hisab/screens/product_form.dart';
import 'package:hisab/screens/purchase_pos.dart';
import 'package:hisab/screens/sale_pos.dart';
import 'package:hisab/screens/sale_return.dart';
import 'package:hisab/print/invoice_pdf.dart';
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
    for (final e in {
      'business_name': 'GameX Pc Hub',
      'tagline': 'Computer · Gaming · Accessories · Mobiles',
      'address': 'Kaliachak Choudhary Market, Near Registry Office, Kaliachak, Malda — PIN 732201, West Bengal',
      'phone': '+91 86535 68180',
      'upi_id': '0946411127@ybl',
      'gstin': '19HAGPM5934J1Z3',
      'bank_branch': 'Kaliachak',
    }.entries) {
      await Books.setSetting(e.key, e.value);
    }
  });

  for (final (name, paper) in [('bill_a4', 'a4'), ('bill_80mm', '80mm')]) {
    test(name, () async {
      final d = await InvoiceData.load(6);
      final bytes = await buildInvoicePdf(d!, PrintOptions(paper: paper));
      Directory('screenshots').createSync(recursive: true);
      File('screenshots/$name.pdf').writeAsBytesSync(bytes);
      expect(bytes.length, greaterThan(1000));
    });
  }

  for (final (name, index) in [('home', 0), ('dashboard', 1), ('products', 2), ('menu', 3), ('add_product', -1), ('new_sale', -2), ('new_purchase', -3), ('ledgers', -4), ('customer_profile', -5), ('expenses', -6), ('customers', -7), ('sales', -8), ('bank', -9), ('add_card', -10), ('purchases', -11), ('supplier_profile', -12), ('sale_returns', -13), ('sale_return_form', -14), ('invoice_view', -15), ('sale_complete', -16), ('emi', -17), ('emi_plan', -18), ('imei', -19), ('backup', -20), ('security', -21), ('lock', -22), ('login', -23), ('account', -24)]) {
    testWidgets(name, (t) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: index >= 0
              ? Shell(initialIndex: index)
              : index == -1
                  ? const ProductForm()
                  : index == -2
                      ? const SaleForm()
                      : index == -3
                          ? const PurchaseForm(supplierId: 1)
                          : index == -4
                              ? const LedgersScreen()
                              : index == -5
                                  ? const PartyView(type: 'customer', id: 1)
                                  : index == -6
                                      ? const ExpensesScreen()
                                      : index == -7
                                          ? const PartiesScreen()
                                          : index == -8
                                              ? const SalesScreen()
                                              : index == -9
                                                  ? const BankScreen()
                                                  : index == -11
                                                      ? const PurchasesScreen()
                                                      : index == -12
                                                          ? const PartyView(type: 'supplier', id: 1)
                                                          : index == -13
                                                              ? const SaleReturnsScreen()
                                                              : index == -14
                                                                  ? const SaleReturnForm(saleId: 7)
                                                                  : index == -15
                                                                      ? const SaleView(id: 6)
                                                                      : index == -16
                                                                          ? const SaleSuccessScreen(saleId: 6)
                                                                          : index == -17
                                                                              ? const EmiScreen()
                                                                              : index == -18
                                                                                  ? const EmiPlanView(id: 1)
                                                                                  : index == -19
                                                                                      ? const ImeiScreen(initial: '356789104455667')
                                                                                      : index == -20
                                                                                          ? const BackupScreen()
                                                                                          : index == -21
                                                                                              ? const SecurityScreen()
                                                                                              : index == -22
                                                                                                  ? LockScreen(onUnlocked: () {})
                                                                                                  : index == -23
                                                                                                      ? LoginScreen(onDone: () {})
                                                                                                      : index == -24
                                                                                                          ? const AccountScreen()
                                                                  : const Scaffold(
                                                      backgroundColor: Color(0xFF8A8FAD),
                                                      body: Align(alignment: Alignment.bottomCenter, child: AccountSheet()),
                                                    ),
        ),
      ));
      if (index == -1) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await t.pump();
        await t.enterText(find.byType(TextField).first, 'iPhone 15 Pro 8GB 256GB Black');
      }
      if (index == -2) {
        for (var i = 0; i < 40; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
        final pick = find.text('AirPods Pro');
        if (pick.evaluate().isNotEmpty) {
          await t.tap(pick.first);
          await t.pump(const Duration(milliseconds: 300));
        }
      }
      // Each database query completes on a real isolate: keep letting real
      // time pass and pumping until no loading spinner is left.
      for (var i = 0; i < 400; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await t.pump(const Duration(milliseconds: 50));
        if (i > 20 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await t.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await t.pump(const Duration(seconds: 2));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.75);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = File('screenshots/$name.png')..createSync(recursive: true);
        out.writeAsBytesSync(png!.buffer.asUint8List());
      });
      // let pending database work finish so no timer outlives the test
      await t.pumpWidget(const SizedBox());
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(seconds: 1));
      }
    });
  }
}
