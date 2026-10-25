import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/entities/maintenance_schedule.dart';

class LocalScheduleNotifications {
  LocalScheduleNotifications._();

  static final instance = LocalScheduleNotifications._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_isAndroid || _initialized) return;
    tz_data.initializeTimeZones();
    final localZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localZone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<void> replaceAll(
    List<MaintenanceSchedule> schedules, {
    bool enabled = true,
    int remindDaysBefore = 3,
    int remindHour = 7,
    int remindKmBefore = 200,
  }) async {
    if (!_isAndroid) return;
    await initialize();
    await _plugin.cancelAll();
    if (!enabled) return;
    final now = tz.TZDateTime.now(tz.local);
    for (final schedule in schedules) {
      final dueDate = schedule.status == ScheduleStatus.snoozed
          ? schedule.snoozedUntil
          : schedule.nextDueDate;
      if (dueDate == null) continue;
      final reminderDays =
          schedule.status == ScheduleStatus.snoozed
                ? const [0]
                : {remindDaysBefore, 3, 1, 0}.toList()
            ..sort((a, b) => b.compareTo(a));
      for (var index = 0; index < reminderDays.length; index++) {
        final fireDate = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
        ).subtract(Duration(days: reminderDays[index]));
        final scheduled = tz.TZDateTime(
          tz.local,
          fireDate.year,
          fireDate.month,
          fireDate.day,
          remindHour.clamp(0, 23),
        );
        if (!scheduled.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: _notificationId(schedule.id, index),
          title: 'Pengingat perawatan motor',
          body: reminderDays[index] == 0
              ? '${schedule.title} jatuh tempo hari ini.'
              : '${schedule.title} jatuh tempo dalam ${reminderDays[index]} hari.',
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'maintenance_reminders',
              'Pengingat perawatan',
              channelDescription: 'Pengingat jadwal perawatan motor',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: schedule.id,
        );
      }

      final kmLeft = schedule.kmLeft;
      if (kmLeft != null && kmLeft <= remindKmBefore && kmLeft >= 0) {
        await _plugin.show(
          id: _notificationId(schedule.id, 4),
          title: 'Perawatan motor hampir jatuh tempo',
          body: '${schedule.title} tersisa $kmLeft km.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'maintenance_reminders',
              'Pengingat perawatan',
              channelDescription: 'Pengingat jadwal perawatan motor',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: schedule.id,
        );
      }
    }
  }

  Future<void> cancelAll() async {
    if (!_isAndroid) return;
    await initialize();
    await _plugin.cancelAll();
  }

  int _notificationId(String uuid, int index) {
    final compact = uuid.replaceAll('-', '');
    final prefix = compact.length >= 7 ? compact.substring(0, 7) : compact;
    return (int.tryParse(prefix, radix: 16) ?? uuid.hashCode.abs()) * 4 + index;
  }
}
