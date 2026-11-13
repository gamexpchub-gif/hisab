import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local, offline reminders for payment due dates. The phone shows a
/// high-priority notification with sound on the due date (and the day before).
class Alarms {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    final impl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
    _ready = true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'payment_dues',
      'Payment due reminders',
      channelDescription: 'Reminds you when a customer or supplier payment is due',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      playSound: true,
      enableVibration: true,
    ),
  );

  /// On the due day: rings like an alarm (alarm sound, repeats until the
  /// notification is opened or swiped) so a collection is never missed.
  static final _ring = NotificationDetails(
    android: AndroidNotificationDetails(
      'payment_due_ring',
      'Payment due — ringing alarm',
      channelDescription: 'Rings on the day a customer promised to pay (or a payment is due)',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 900, 500, 900, 500, 900]),
      additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT: keep ringing
      ticker: 'Payment due',
      visibility: NotificationVisibility.public,
    ),
  );

  static Future<void> _schedule(int id, String title, String body, tz.TZDateTime at, NotificationDetails d) async {
    try {
      await _plugin.zonedSchedule(id, title, body, at, d,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    } catch (_) {
      // exact alarms not allowed on this phone: a few minutes' slack is fine
      await _plugin.zonedSchedule(id, title, body, at, d,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    }
  }

  /// Notification ids for a due: day-before and on-the-day.
  static int _id(int dueId, int slot) => dueId * 10 + slot;

  /// Schedules a reminder the day before and a ringing alarm on the due
  /// date, both at [hour]:[minute] (10:00 by default).
  static Future<int> scheduleDue({
    required int dueId,
    required DateTime dueDate,
    required String title,
    required String body,
    int hour = 10,
    int minute = 0,
    bool ring = true,
  }) async {
    try {
      await init();
      final now = tz.TZDateTime.now(tz.local);
      var count = 0;
      for (final (slot, day, prefix) in [(1, dueDate.subtract(const Duration(days: 1)), 'Kal: '), (2, dueDate, 'Aaj: ')]) {
        final at = tz.TZDateTime(tz.local, day.year, day.month, day.day, hour, minute);
        if (at.isBefore(now)) continue;
        await _schedule(_id(dueId, slot), '$prefix$title', body, at, slot == 2 && ring ? _ring : _details);
        count++;
      }
      return count;
    } catch (_) {
      return 0; // reminders are a convenience; never block saving
    }
  }

  static Future<void> cancelDue(int dueId) async {
    try {
      await init();
      await _plugin.cancel(_id(dueId, 1));
      await _plugin.cancel(_id(dueId, 2));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- daily AI report
  static const _dailyBase = 900000;

  static Future<void> scheduleDaily(int slot, DateTime when, String title, String body) async {
    try {
      await init();
      final at = tz.TZDateTime(tz.local, when.year, when.month, when.day, when.hour, when.minute);
      if (at.isBefore(tz.TZDateTime.now(tz.local))) return;
      await _schedule(
        _dailyBase + slot,
        title,
        body,
        at,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_ai_report',
            'Daily AI report',
            channelDescription: 'Every evening: sales, profit, collection, tomorrow\'s payments and what to reorder',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body, contentTitle: title),
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> cancelDaily() async {
    try {
      await init();
      await _plugin.cancel(_dailyBase);
      await _plugin.cancel(_dailyBase + 1);
    } catch (_) {}
  }
}
