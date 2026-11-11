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
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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

  /// Notification ids for a due: day-before and on-the-day.
  static int _id(int dueId, int slot) => dueId * 10 + slot;

  /// Schedules reminders at 10:00 on the day before and on the due date.
  static Future<int> scheduleDue({
    required int dueId,
    required DateTime dueDate,
    required String title,
    required String body,
  }) async {
    try {
      await init();
      final now = tz.TZDateTime.now(tz.local);
      var count = 0;
      for (final (slot, day, prefix) in [(1, dueDate.subtract(const Duration(days: 1)), 'Tomorrow: '), (2, dueDate, 'Today: ')]) {
        final at = tz.TZDateTime(tz.local, day.year, day.month, day.day, 10);
        if (at.isBefore(now)) continue;
        await _plugin.zonedSchedule(
          _id(dueId, slot),
          '$prefix$title',
          body,
          at,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
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
}
