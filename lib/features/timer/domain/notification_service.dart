import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/planner_time_zone.dart';

/// Daily-review reminder notifications (planner.md Chunk 6 #13/#14).
///
/// Scheduling uses OS-level daily matching (`DateTimeComponents.time`) and is
/// supported on Android/iOS/macOS; the Linux implementation of
/// flutter_local_notifications has no `zonedSchedule`, so there the setting
/// is persisted but no native alarm is armed (documented deviation).
class NotificationService {
  /// Fixed id so re-scheduling replaces instead of stacking.
  static const int reminderId = 4201;

  static const String reminderBody = 'Time to review your day! 📝';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Payload route requested by tapping the reminder.
  static const String reviewRoute = '/review';

  Future<void> init({required void Function(String? payload) onSelect}) async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings(
            '@drawable/ic_notification',
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        ),
        onDidReceiveNotificationResponse: (response) =>
            onSelect(response.payload),
      );
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          onSelect(launch?.notificationResponse?.payload);
        }
      }
      _initialized = true;
    } catch (_) {
      // Desktop environments without a notification daemon etc. The app
      // works without reminders; settings stay persisted.
      _initialized = false;
    }
  }

  /// Requests notification permission only from a user-initiated workflow.
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> notificationsEnabled() async {
    if (!_initialized || !Platform.isAndroid) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when this platform can arm native scheduled alarms.
  bool get schedulingSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Next wall-clock occurrence of [hour]:[minute] after [now].
  static DateTime nextOccurrence(DateTime now, int hour, int minute) {
    final local = PlannerTimeZone.toPlannerLocal(now);
    DateTime next = tz.TZDateTime(
      PlannerTimeZone.location,
      local.year,
      local.month,
      local.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) {
      next = PlannerTimeZone.addDays(next, 1);
    }
    return next;
  }

  /// Arms (or refreshes) the daily reminder. Returns false when the platform
  /// cannot schedule natively or initialization failed.
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    if (!schedulingSupported || !_initialized) return false;
    if (!await notificationsEnabled()) return false;
    try {
      final now = DateTime.now();
      final scheduled = tz.TZDateTime.from(
        nextOccurrence(now, hour, minute),
        tz.local,
      );
      await _plugin.zonedSchedule(
        id: reminderId,
        title: 'Personal Planner',
        body: reminderBody,
        payload: reviewRoute,
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'review_reminder',
            'Daily review reminder',
            channelDescription: 'Reminds you to fill in the daily review',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelReminder() async {
    if (!schedulingSupported || !_initialized) return;
    try {
      await _plugin.cancel(id: reminderId);
    } catch (_) {}
  }
}

/// Initializes the timezone database (required for scheduled notifications).
/// Falls back to UTC when the local IANA name cannot be resolved.
Future<void> initializeTimezone() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
    PlannerTimeZone.initialize(identifier: info.identifier);
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('UTC'));
    PlannerTimeZone.initialize(identifier: 'UTC');
  }
}
