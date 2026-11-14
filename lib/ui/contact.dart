import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/books.dart';
import '../core/money.dart';

/// Phone, WhatsApp and message helpers.
class Contact {
  /// Digits with country code for wa.me (assumes India for 10-digit numbers).
  static String waNumber(String? phone) {
    var p = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('0') && p.length == 11) p = p.substring(1);
    if (p.length == 10) p = '91$p';
    return p;
  }

  static Future<bool> call(String? phone) async {
    final p = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.isEmpty) return false;
    return _open(Uri(scheme: 'tel', path: p));
  }

  /// Opens WhatsApp with [text] ready to send. Without a number WhatsApp
  /// asks which chat to use. Falls back to copying the text.
  static Future<bool> whatsapp(String? phone, String text) async {
    final n = waNumber(phone);
    final ok = await _open(Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}'));
    if (!ok) await Clipboard.setData(ClipboardData(text: text));
    return ok;
  }

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

enum ReminderTone { friendly, firm, finalNotice }

/// Builds payment reminders. The tone is suggested from how old the dues are.
class Reminders {
  static ReminderTone suggest(int oldestDays) =>
      oldestDays > 60 ? ReminderTone.finalNotice : oldestDays > 30 ? ReminderTone.firm : ReminderTone.friendly;

  static String label(ReminderTone t, {bool bangla = false}) => switch (t) {
        ReminderTone.friendly => bangla ? 'বিনীত' : 'Friendly',
        ReminderTone.firm => bangla ? 'দৃঢ়' : 'Firm',
        ReminderTone.finalNotice => bangla ? 'শেষ নোটিশ' : 'Final notice',
      };

  static String message({
    required ReminderTone tone,
    required bool bangla,
    required String name,
    required int due,
    required int days,
    required Map<String, String> settings,
  }) {
    final shop = (settings['business_name'] ?? 'our shop').replaceAll('GAMEX', 'GameX');
    final phone = settings['phone'] ?? '';
    final upi = (settings['upi_id'] ?? '').trim();
    final amt = Money.rs(due);
    if (bangla) {
      final upiLine = upi.isEmpty ? '' : '\nUPI: $upi';
      return switch (tone) {
        ReminderTone.friendly => 'নমস্কার $name,\n$shop থেকে একটি ছোট্ট অনুস্মারক — আপনার বকেয়া $amt।'
            '$upiLine\nসুবিধামতো পরিশোধ করে দিলে খুশি হব। ধন্যবাদ 🙏',
        ReminderTone.firm => 'প্রিয় $name,\n$shop-এ আপনার $amt বকেয়া $days দিন ধরে বাকি আছে। '
            'অনুগ্রহ করে শীঘ্রই পরিশোধ করুন।$upiLine\n— $shop${phone.isEmpty ? '' : ', $phone'}',
        ReminderTone.finalNotice => 'প্রিয় $name,\nআপনার $amt বকেয়া $days দিন পেরিয়ে গেছে। '
            '৩ দিনের মধ্যে পরিশোধ না হলে বাকিতে বিক্রি বন্ধ থাকবে।$upiLine\n— $shop${phone.isEmpty ? '' : ', $phone'}',
      };
    }
    final upiLine = upi.isEmpty ? '' : '\nPay by UPI: $upi';
    return switch (tone) {
      ReminderTone.friendly => 'Hi $name,\nA friendly reminder from $shop — your outstanding balance is $amt.'
          '$upiLine\nPlease pay at your convenience. Thank you! 🙏',
      ReminderTone.firm => 'Dear $name,\nYour payment of $amt to $shop has been pending for $days days. '
          'Kindly clear it at the earliest.$upiLine\n— $shop${phone.isEmpty ? '' : ', $phone'}',
      ReminderTone.finalNotice => 'Dear $name,\n$amt has been overdue for $days days. Please settle it within 3 days, '
          'otherwise credit will be paused.$upiLine\n— $shop${phone.isEmpty ? '' : ', $phone'}',
    };
  }

  /// Plain-text account statement with the last [limit] entries.
  static String statement({
    required String name,
    required List<Rec> rows,
    required int balance,
    required bool customer,
    required Map<String, String> settings,
    int limit = 12,
  }) {
    final shop = (settings['business_name'] ?? '').replaceAll('GAMEX', 'GameX');
    final b = StringBuffer()
      ..writeln('*Account statement*')
      ..writeln('$name — $shop')
      ..writeln('As on ${prettyDate(ymd(DateTime.now()))}')
      ..writeln('');
    final recent = rows.length > limit ? rows.sublist(rows.length - limit) : rows;
    for (final r in recent) {
      // "+" raises the balance (a bill), "−" lowers it (a payment)
      final up = customer ? asInt(r['debit']) : asInt(r['credit']);
      final down = customer ? asInt(r['credit']) : asInt(r['debit']);
      final amt = up > 0 ? '+${Money.rs(up)}' : '−${Money.rs(down)}';
      b.writeln('${prettyDate(r['date'] as String)} · ${r['narration'] ?? ''}  $amt');
    }
    b
      ..writeln('')
      ..writeln(customer
          ? (balance > 0 ? '*Balance due: ${Money.rs(balance)}*' : '*No dues — thank you!*')
          : (balance > 0 ? '*We owe you: ${Money.rs(balance)}*' : '*Account settled*'));
    final upi = (settings['upi_id'] ?? '').trim();
    if (customer && balance > 0 && upi.isNotEmpty) b.writeln('UPI: $upi');
    return b.toString();
  }
}
