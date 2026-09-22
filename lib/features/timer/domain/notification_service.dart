import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/utils/planner_time_zone.dart';
import 'planner_notification.dart';

typedef PlannerNotificationResponseHandler = Future<void> Function(
  PlannerNotificationAction action,
  PlannerNotificationPayload payload,
  DateTime occurredAt,
);

/// Thin OS adapter. Timer and task state never live here: payloads carry only
/// compare-and-act preconditions for the persisted domain state.
class NotificationService implements PlannerNotificationGateway {
  NotificationService({LinuxReminderScheduler? linuxScheduler})
    : _linuxScheduler = linuxScheduler ?? const LinuxReminderScheduler();

  static const int reviewReminderId = 4201;
  static const int activeTimerId = 4202;
  static const String reviewBody = 'Time to review your day! 📝';
  static const String reviewRoute = '/review';
  static const String _workerArgument = '--planner-reminder-worker';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final LinuxReminderScheduler _linuxScheduler;
  bool _initialized = false;

  Future<void> init({
    required void Function(String? payload) onSelect,
    PlannerNotificationResponseHandler? onPlannerAction,
  }) async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = PlannerNotificationPayload.tryDecode(
            response.payload,
          );
          if (payload == null ||
              payload.kind == PlannerNotificationKind.review) {
            onSelect(response.payload);
            return;
          }
          final action = _actionFrom(response.actionId);
          if (action != null && onPlannerAction != null) {
            unawaited(onPlannerAction(action, payload, DateTime.now()));
          }
        },
        onDidReceiveBackgroundNotificationResponse:
            plannerNotificationTapBackground,
      );
      if (Platform.isAndroid) {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          final response = launch?.notificationResponse;
          final payload = PlannerNotificationPayload.tryDecode(
            response?.payload,
          );
          final action = _actionFrom(response?.actionId);
          if (payload != null && action != null && onPlannerAction != null) {
            unawaited(onPlannerAction(action, payload, DateTime.now()));
          } else {
            onSelect(response?.payload);
          }
        }
      }
      _initialized = true;
    } on Object {
      // Notification availability must never affect persisted Planner state.
      _initialized = false;
    }
  }

  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    } on Object {
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
    } on Object {
      return false;
    }
  }

  bool get schedulingSupported => Platform.isAndroid;

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
    if (!next.isAfter(now)) next = PlannerTimeZone.addDays(next, 1);
    return next;
  }

  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    if (!schedulingSupported || !_initialized) return false;
    if (!await notificationsEnabled()) return false;
    try {
      await _plugin.zonedSchedule(
        id: reviewReminderId,
        title: 'Personal Planner',
        body: reviewBody,
        payload: reviewRoute,
        scheduledDate: tz.TZDateTime.from(
          nextOccurrence(DateTime.now(), hour, minute),
          tz.local,
        ),
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
    } on Object {
      return false;
    }
  }

  Future<void> cancelReminder() => _bestEffortCancel(reviewReminderId);

  @override
  Future<void> showTimer(TimerNotificationSnapshot snapshot) async {
    final running = snapshot.state.name == 'running';
    final base = running
        ? snapshot.runningSince!.subtract(
            Duration(seconds: snapshot.durationSec),
          )
        : null;
    final pausedDuration = _formatDuration(snapshot.durationSec);
    try {
      await _plugin.show(
        id: activeTimerId,
        title: snapshot.taskTitle,
        body: Platform.isLinux && running
            ? 'Running since ${_formatClock(snapshot.runningSince!)}'
            : running
            ? null
            : 'Paused • $pausedDuration',
        payload: snapshot.payload.encode(),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'personal_planner_timer',
            'Active timer',
            channelDescription: 'Shows and controls the active task timer',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: running,
            when: base?.millisecondsSinceEpoch,
            usesChronometer: running,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                running ? 'timer_pause' : 'timer_resume',
                running ? 'Pause' : 'Resume',
                cancelNotification: false,
              ),
              const AndroidNotificationAction(
                'timer_stop',
                'Stop',
                cancelNotification: false,
              ),
            ],
          ),
          linux: LinuxNotificationDetails(
            resident: true,
            suppressSound: true,
            timeout: const LinuxNotificationTimeout.expiresNever(),
            actions: <LinuxNotificationAction>[
              LinuxNotificationAction(
                key: running ? 'timer_pause' : 'timer_resume',
                label: running ? 'Pause' : 'Resume',
              ),
              const LinuxNotificationAction(key: 'timer_stop', label: 'Stop'),
            ],
          ),
        ),
      );
    } on Object {
      // Presentation failure never rolls back the valid timer transition.
    }
  }

  @override
  Future<void> cancelTimer() => _bestEffortCancel(activeTimerId);

  @override
  Future<void> scheduleTaskReminder(TaskReminderSnapshot snapshot) async {
    if (Platform.isLinux) {
      try {
        await _linuxScheduler.schedule(snapshot);
      } on Object {
        // Scheduling is presentation-only. Planner data remains authoritative.
      }
      return;
    }
    if (!Platform.isAndroid || !_initialized) return;
    try {
      await _plugin.zonedSchedule(
        id: taskReminderId(snapshot.taskId),
        title: '${snapshot.taskTitle} hasn\'t started',
        body: 'Planned for ${_formatClock(snapshot.plannedStart)}',
        payload: snapshot.payload.encode(),
        scheduledDate: tz.TZDateTime.from(snapshot.remindAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'planned_task_reminders',
            'Planned task reminders',
            channelDescription:
                'Reminds you when a planned task has not started',
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                'reminder_start_now',
                'Start now',
                cancelNotification: false,
              ),
              AndroidNotificationAction('reminder_dismiss', 'Dismiss'),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on Object {
      // Best effort; the coordinator will reconcile again on the next change.
    }
  }

  @override
  Future<void> showTaskReminder(TaskReminderSnapshot snapshot) async {
    try {
      await _plugin.show(
        id: taskReminderId(snapshot.taskId),
        title: '${snapshot.taskTitle} hasn\'t started',
        body: 'Planned for ${_formatClock(snapshot.plannedStart)}',
        payload: snapshot.payload.encode(),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'planned_task_reminders',
            'Planned task reminders',
            channelDescription:
                'Reminds you when a planned task has not started',
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                'reminder_start_now',
                'Start now',
                cancelNotification: false,
              ),
              AndroidNotificationAction('reminder_dismiss', 'Dismiss'),
            ],
          ),
          // A worker exits immediately, so Linux deliberately exposes no dead
          // action buttons. Clicking can open Planner where supported.
          linux: LinuxNotificationDetails(
            urgency: LinuxNotificationUrgency.normal,
            defaultActionName: 'Open Planner',
          ),
        ),
      );
    } on Object {
      // The worker is best effort and exits without changing task state.
    }
  }

  @override
  Future<void> cancelTaskReminder(String taskId) async {
    if (Platform.isLinux) {
      try {
        await _linuxScheduler.cancel(taskId);
      } on Object {
        // A missing user systemd manager must not affect Planner data.
      }
    }
    await _bestEffortCancel(taskReminderId(taskId));
  }

  Future<void> _bestEffortCancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object {
      // Cancellation is presentation cleanup; domain state already won.
    }
  }

  static int taskReminderId(String taskId) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(taskId)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 0x20000000 | (hash & 0x1fffffff);
  }

  static String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m '
          '${remaining.toString().padLeft(2, '0')}s';
    }
    return '${minutes}m ${remaining.toString().padLeft(2, '0')}s';
  }

  static String _formatClock(DateTime value) =>
      DateFormat.jm().format(PlannerTimeZone.toPlannerLocal(value));

  static PlannerNotificationAction? _actionFrom(String? id) => switch (id) {
    'timer_pause' => PlannerNotificationAction.pause,
    'timer_resume' => PlannerNotificationAction.resume,
    'timer_stop' => PlannerNotificationAction.stop,
    'reminder_start_now' => PlannerNotificationAction.startNow,
    'reminder_dismiss' => PlannerNotificationAction.dismiss,
    null || '' => PlannerNotificationAction.open,
    _ => null,
  };

  static bool isReminderWorker(List<String> arguments) =>
      arguments.length == 2 && arguments.first == _workerArgument;

  static Future<void> runReminderWorker(String encodedPayload) async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeTimezone();
    final raw = utf8.decode(
      base64Url.decode(base64Url.normalize(encodedPayload)),
    );
    final payload = PlannerNotificationPayload.tryDecode(raw);
    if (payload == null ||
        payload.kind != PlannerNotificationKind.taskReminder ||
        payload.taskId == null ||
        payload.expectedTaskStart == null) {
      return;
    }
    final database = await AppDatabase.open(accountId: payload.accountId);
    try {
      final row = await database.taskDao.getTaskById(payload.taskId!);
      if (!await reminderStillApplies(
        database,
        row,
        payload.expectedTaskStart!,
      )) {
        return;
      }
      final notifications = NotificationService();
      await notifications.init(onSelect: (_) {});
      await notifications.showTaskReminder(
        TaskReminderSnapshot(
          accountId: payload.accountId,
          taskId: row!.id,
          taskTitle: row.title,
          plannedStart: row.startTime!,
        ),
      );
    } finally {
      await database.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> plannerNotificationTapBackground(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  final occurredAt = DateTime.now();
  final payload = PlannerNotificationPayload.tryDecode(response.payload);
  final action = NotificationService._actionFrom(response.actionId);
  if (payload == null ||
      action == null ||
      action == PlannerNotificationAction.open) {
    return;
  }
  final database = await AppDatabase.open(accountId: payload.accountId);
  try {
    final notifications = NotificationService();
    await notifications.init(onSelect: (_) {});
    await PlannerNotificationActionDispatcher(
      database: database,
      notifications: notifications,
      accountId: payload.accountId,
      clock: () => occurredAt,
    ).dispatch(action, payload);
  } finally {
    await database.close();
  }
}

/// Fedora/GNOME closed-app reminder wake. `systemd-run` owns the wait; the
/// Planner process starts only at the due time, revalidates SQLite, notifies,
/// and exits. No daemon or polling process is created.
class LinuxReminderScheduler {
  const LinuxReminderScheduler({this.processRunner = Process.run});

  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  processRunner;

  Future<void> schedule(TaskReminderSnapshot snapshot) async {
    if (!Platform.isLinux || !snapshot.remindAt.isAfter(DateTime.now())) return;
    await cancel(snapshot.taskId);
    final payload = base64Url.encode(utf8.encode(snapshot.payload.encode()));
    final unit = _unit(snapshot.taskId);
    final at = DateFormat('yyyy-MM-dd HH:mm:ss')
        .format(snapshot.remindAt.toUtc());
    await processRunner('systemd-run', <String>[
      '--user',
      '--collect',
      '--unit=$unit',
      '--on-calendar=$at UTC',
      '--timer-property=AccuracySec=1min',
      '--property=Type=oneshot',
      '--',
      Platform.resolvedExecutable,
      NotificationService._workerArgument,
      payload,
    ]);
  }

  Future<void> cancel(String taskId) async {
    if (!Platform.isLinux) return;
    final unit = _unit(taskId);
    await processRunner('systemctl', <String>[
      '--user',
      'stop',
      '$unit.timer',
      '$unit.service',
    ]);
    await processRunner('systemctl', <String>[
      '--user',
      'reset-failed',
      '$unit.timer',
      '$unit.service',
    ]);
  }

  static String _unit(String taskId) =>
      'personal-planner-reminder-${NotificationService.taskReminderId(taskId)}';
}

Future<void> initializeTimezone() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
    PlannerTimeZone.initialize(identifier: info.identifier);
  } on Object {
    tz.setLocalLocation(tz.getLocation('UTC'));
    PlannerTimeZone.initialize(identifier: 'UTC');
  }
}
