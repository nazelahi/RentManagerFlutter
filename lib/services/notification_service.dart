import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Port of `src/utils/notificationService.ts` — channels rent-reminders /
/// work-orders / expenses / maintenance, rent-due T-1, daily 9am summary.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Android 13+ requires a runtime notification permission grant.
    try {
      await androidImpl?.requestNotificationsPermission();
    } catch (_) {}
    for (final c in [
      ('rent_reminders', 'Rent Reminders', Importance.high),
      ('work_orders', 'Work Orders', Importance.high),
      ('expenses', 'Expenses', Importance.defaultImportance),
      ('maintenance', 'Maintenance', Importance.low),
    ]) {
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(c.$1, c.$2,
            importance: c.$3, ledColor: const Color(0xFF4CAF50)),
      );
    }
    _ready = true;
  }

  static Future<void> rentDueReminder({
    required int id,
    required String tenant,
    required String unit,
  }) =>
      rentDueReminderAt(
        id: id,
        tenant: tenant,
        unit: unit,
        at: tz.TZDateTime.now(tz.local)
            .add(const Duration(days: 1)),
      );

  static Future<void> rentDueReminderAt({
    required int id,
    required String tenant,
    required String unit,
    required DateTime at,
  }) async {
    if (!_ready) return;
    try {
      final when = at.isBefore(DateTime.now())
          ? tz.TZDateTime.now(tz.local)
          : tz.TZDateTime.from(at, tz.local);
      await _plugin.zonedSchedule(
        id: id,
        title: 'Rent due tomorrow',
        body: '$tenant${unit.isEmpty ? '' : ' ($unit)'} — rent is due tomorrow.',
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'rent_reminders',
            'Rent Reminders',
            importance: Importance.high,
            color: Color(0xFF4CAF50),
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  static Future<void> immediate({
    required int id,
    required String channel,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(channel, channel),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  static Future<void> cancelById(int id) async => _plugin.cancel(id: id);
  static Future<void> cancelAll() async => _plugin.cancelAll();

  /// Deterministic 31-bit id derived from a record id. Dart's String.hashCode is
  /// randomly seeded per process, so reminder ids scheduled in one session could
  /// never be cancelled in the next one. FNV-1a produces the same value every run.
  static int stableIntId(String s) {
    var hash = 0x811c9dc5;
    for (final cu in s.codeUnits) {
      hash ^= cu;
      hash = (hash * 0x01000193) & 0x0fffffff;
      hash ^= (hash >>> 25);
      hash &= 0x7fffffff;
    }
    return hash;
  }
}
