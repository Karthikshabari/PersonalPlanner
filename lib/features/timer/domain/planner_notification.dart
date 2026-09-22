import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/timer_session.dart';
import '../data/timer_repository.dart';
import 'timer_service.dart';

enum PlannerNotificationKind { timer, taskReminder, review }

enum PlannerNotificationAction { pause, resume, stop, startNow, dismiss, open }

/// Immutable identity carried by an OS notification. It is only an action
/// precondition: SQLite remains authoritative and every mutation below is
/// performed by the existing domain services.
class PlannerNotificationPayload {
  const PlannerNotificationPayload({
    required this.kind,
    this.accountId,
    this.taskId,
    this.sessionId,
    this.ownerDeviceId,
    this.expectedState,
    this.expectedRunningSince,
    this.expectedDurationSec,
    this.expectedRevision,
    this.expectedTaskStart,
  });

  final PlannerNotificationKind kind;
  final String? accountId;
  final String? taskId;
  final String? sessionId;
  final String? ownerDeviceId;
  final TimerSessionState? expectedState;
  final DateTime? expectedRunningSince;
  final int? expectedDurationSec;
  final int? expectedRevision;
  final DateTime? expectedTaskStart;

  String encode() => jsonEncode(<String, Object?>{
    'kind': kind.name,
    'account_id': accountId,
    'task_id': taskId,
    'session_id': sessionId,
    'owner_device_id': ownerDeviceId,
    'expected_state': expectedState?.dbValue,
    'expected_running_since': expectedRunningSince
        ?.toUtc()
        .millisecondsSinceEpoch,
    'expected_duration_sec': expectedDurationSec,
    'expected_revision': expectedRevision,
    'expected_task_start': expectedTaskStart?.toUtc().millisecondsSinceEpoch,
  });

  static PlannerNotificationPayload? tryDecode(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final json = Map<String, Object?>.from(decoded);
      final kindName = json['kind'];
      final kind = PlannerNotificationKind.values
          .where((value) => value.name == kindName)
          .firstOrNull;
      if (kind == null) return null;
      final stateValue = json['expected_state'];
      final state = stateValue is String
          ? TimerSessionState.values
                .where((value) => value.dbValue == stateValue)
                .firstOrNull
          : null;
      DateTime? instant(String key) {
        final raw = json[key];
        return raw is int
            ? DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true)
            : null;
      }

      return PlannerNotificationPayload(
        kind: kind,
        accountId: json['account_id'] as String?,
        taskId: json['task_id'] as String?,
        sessionId: json['session_id'] as String?,
        ownerDeviceId: json['owner_device_id'] as String?,
        expectedState: state,
        expectedRunningSince: instant('expected_running_since'),
        expectedDurationSec: json['expected_duration_sec'] as int?,
        expectedRevision: json['expected_revision'] as int?,
        expectedTaskStart: instant('expected_task_start'),
      );
    } on Object {
      return null;
    }
  }
}

class TimerNotificationSnapshot {
  const TimerNotificationSnapshot({
    required this.accountId,
    required this.taskTitle,
    required this.sessionId,
    required this.taskId,
    required this.ownerDeviceId,
    required this.state,
    required this.durationSec,
    required this.revision,
    this.runningSince,
  });

  final String? accountId;
  final String taskTitle;
  final String sessionId;
  final String taskId;
  final String ownerDeviceId;
  final TimerSessionState state;
  final DateTime? runningSince;
  final int durationSec;
  final int revision;

  PlannerNotificationPayload get payload => PlannerNotificationPayload(
    kind: PlannerNotificationKind.timer,
    accountId: accountId,
    taskId: taskId,
    sessionId: sessionId,
    ownerDeviceId: ownerDeviceId,
    expectedState: state,
    expectedRunningSince: runningSince,
    expectedDurationSec: durationSec,
    expectedRevision: revision,
  );
}

class TaskReminderSnapshot {
  const TaskReminderSnapshot({
    required this.accountId,
    required this.taskId,
    required this.taskTitle,
    required this.plannedStart,
  });

  final String? accountId;
  final String taskId;
  final String taskTitle;
  final DateTime plannedStart;

  DateTime get remindAt => plannedStart.add(const Duration(minutes: 5));

  TaskReminderIdentity get identity => TaskReminderIdentity(
    accountId: accountId,
    taskId: taskId,
    plannedStart: plannedStart,
  );

  PlannerNotificationPayload get payload => PlannerNotificationPayload(
    kind: PlannerNotificationKind.taskReminder,
    accountId: accountId,
    taskId: taskId,
    expectedTaskStart: plannedStart,
  );
}

/// Stable local presentation identity for one planned occurrence.
///
/// Including account and planned start prevents account switches and stale
/// reschedules from addressing a different reminder that happens to share a
/// task id.
class TaskReminderIdentity {
  const TaskReminderIdentity({
    required this.accountId,
    required this.taskId,
    required this.plannedStart,
  });

  final String? accountId;
  final String taskId;
  final DateTime plannedStart;

  String get ledgerKey =>
      '${accountId ?? '<anonymous>'}:$taskId:'
      '${plannedStart.toUtc().microsecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is TaskReminderIdentity &&
      other.accountId == accountId &&
      other.taskId == taskId &&
      other.plannedStart.toUtc() == plannedStart.toUtc();

  @override
  int get hashCode => Object.hash(
    accountId,
    taskId,
    plannedStart.toUtc().microsecondsSinceEpoch,
  );
}

abstract interface class PlannerNotificationGateway {
  Future<void> showTimer(TimerNotificationSnapshot snapshot);
  Future<void> cancelTimer();
  Future<bool> scheduleTaskReminder(TaskReminderSnapshot snapshot);
  Future<void> showTaskReminder(TaskReminderSnapshot snapshot);
  Future<bool> cancelTaskReminder(TaskReminderIdentity identity);
}

/// Shared action boundary for foreground, Android background-isolate and Linux
/// main-isolate notification responses.
class PlannerNotificationActionDispatcher {
  PlannerNotificationActionDispatcher({
    required this.database,
    required this.notifications,
    required this.accountId,
    DateTime Function()? clock,
    this.beforeAuthoritativeReminderStart,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final PlannerNotificationGateway notifications;
  final String? accountId;
  final DateTime Function() _clock;
  final Future<void> Function()? beforeAuthoritativeReminderStart;

  Future<bool> dispatch(
    PlannerNotificationAction action,
    PlannerNotificationPayload payload,
  ) async {
    if (payload.accountId != accountId) return false;
    return switch (payload.kind) {
      PlannerNotificationKind.timer => _timerAction(action, payload),
      PlannerNotificationKind.taskReminder => _reminderAction(action, payload),
      PlannerNotificationKind.review => Future<bool>.value(false),
    };
  }

  Future<bool> _timerAction(
    PlannerNotificationAction action,
    PlannerNotificationPayload payload,
  ) async {
    final sessionId = payload.sessionId;
    if (sessionId == null || payload.taskId == null) return false;
    final row = await database.timerDao.getSessionById(sessionId);
    if (row == null ||
        row.deletedAt != null ||
        row.taskId != payload.taskId ||
        row.ownerDeviceId != payload.ownerDeviceId ||
        row.state != payload.expectedState?.dbValue ||
        row.runningSince != payload.expectedRunningSince ||
        row.durationSec != payload.expectedDurationSec ||
        row.revision != payload.expectedRevision) {
      return false;
    }
    final localOwner = await TimerRepository(database).localDeviceId();
    if (row.ownerDeviceId != localOwner) return false;

    final service = TimerService(database, clock: _clock);
    final result = switch (action) {
      PlannerNotificationAction.pause => service.pauseSession(
        sessionId,
        expectedOwnerDeviceId: localOwner,
        expectedRunningSince: row.runningSince,
        expectedDurationSec: row.durationSec,
        expectedRevision: row.revision,
      ),
      PlannerNotificationAction.resume => service.resumeSession(
        sessionId,
        expectedOwnerDeviceId: localOwner,
        expectedDurationSec: row.durationSec,
        expectedRevision: row.revision,
      ),
      PlannerNotificationAction.stop => service.stopSession(
        sessionId,
        expectedOwnerDeviceId: localOwner,
        expectedRunningSince: row.runningSince,
        expectedDurationSec: row.durationSec,
        expectedRevision: row.revision,
      ),
      _ => Future<TimerTransitionResult>.value(
        const TimerTransitionResult(
          session: null,
          didChange: false,
          didFinish: false,
        ),
      ),
    };
    final transition = await result;
    if (!transition.didChange || transition.session == null) return false;
    if (action == PlannerNotificationAction.stop) {
      await notifications.cancelTimer();
      return true;
    }
    final updatedRow = await database.timerDao.getSessionById(sessionId);
    final task = await database.taskDao.getTaskById(row.taskId);
    if (updatedRow != null && task != null && task.deletedAt == null) {
      await notifications.showTimer(
        TimerNotificationSnapshot(
          accountId: accountId,
          taskTitle: task.title,
          sessionId: updatedRow.id,
          taskId: updatedRow.taskId,
          ownerDeviceId: localOwner,
          state: TimerSessionState.fromDb(updatedRow.state),
          runningSince: updatedRow.runningSince,
          durationSec: updatedRow.durationSec,
          revision: updatedRow.revision,
        ),
      );
    }
    return true;
  }

  Future<bool> _reminderAction(
    PlannerNotificationAction action,
    PlannerNotificationPayload payload,
  ) async {
    final taskId = payload.taskId;
    final expectedStart = payload.expectedTaskStart;
    if (taskId == null || expectedStart == null) return false;
    final reminderIdentity = TaskReminderIdentity(
      accountId: payload.accountId,
      taskId: taskId,
      plannedStart: expectedStart,
    );
    if (action == PlannerNotificationAction.dismiss) {
      await notifications.cancelTaskReminder(reminderIdentity);
      return true;
    }
    if (action != PlannerNotificationAction.startNow) return false;
    final row = await database.taskDao.getTaskById(taskId);
    if (!await reminderStillApplies(database, row, expectedStart)) {
      await notifications.cancelTaskReminder(reminderIdentity);
      return false;
    }
    await beforeAuthoritativeReminderStart?.call();
    final transition = await TimerService(
      database,
      clock: _clock,
    ).startFromReminder(taskId, expectedPlannedStart: expectedStart);
    final session = transition.session;
    await notifications.cancelTaskReminder(reminderIdentity);
    if (!transition.didChange ||
        session == null ||
        session.ownerDeviceId == null) {
      return false;
    }
    final refreshed = await database.timerDao.getSessionById(session.id);
    final task = await database.taskDao.getTaskById(taskId);
    if (refreshed == null || task == null) return false;
    await notifications.showTimer(
      TimerNotificationSnapshot(
        accountId: accountId,
        taskTitle: task.title,
        sessionId: refreshed.id,
        taskId: refreshed.taskId,
        ownerDeviceId: refreshed.ownerDeviceId!,
        state: TimerSessionState.fromDb(refreshed.state),
        runningSince: refreshed.runningSince,
        durationSec: refreshed.durationSec,
        revision: refreshed.revision,
      ),
    );
    return true;
  }
}

Future<bool> reminderStillApplies(
  AppDatabase database,
  TaskRow? row,
  DateTime expectedStart,
) async {
  if (row == null ||
      row.deletedAt != null ||
      row.isInbox ||
      TaskStatus.fromDb(row.status) != TaskStatus.planned ||
      row.startTime?.toUtc() != expectedStart.toUtc()) {
    return false;
  }
  return (await database.timerDao.getSessionsForTask(row.id)).isEmpty;
}
