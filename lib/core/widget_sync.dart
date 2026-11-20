import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'books.dart';
import 'money.dart';

/// Keeps the Hisab AI home-screen widget (today's sale, cash in hand, money
/// to collect) up to date: refreshed a moment after the books change.
class WidgetSync {
  static Timer? _wait;
  static bool _started = false;

  static void start() {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    Books.changes.addListener(_soon);
    _soon();
  }

  static void _soon() {
    _wait?.cancel();
    _wait = Timer(const Duration(seconds: 2), () => update().catchError((_) {}));
  }

  static Future<void> update() async {
    final m = await Books.homeMetrics();
    final s = await Books.settings();
    final cash = await Books.balanceByCode(cashCode);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final data = <String, String>{
      'shop': (s['business_name'] ?? '').trim().isEmpty ? 'Hisab AI' : s['business_name']!.trim(),
      'sale': Money.rs(m.todaySales),
      'bills': '${m.todayInvoices} bill${m.todayInvoices == 1 ? '' : 's'} today',
      'cash': Money.rs(cash),
      'due': Money.rs(m.totalDue),
      'updated': 'Updated ${two(now.hour)}:${two(now.minute)}',
    };
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
    await HomeWidget.updateWidget(androidName: 'HisabWidgetProvider');
  }
}
