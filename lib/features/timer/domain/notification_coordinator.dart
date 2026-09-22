import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/timer_session.dart';
import '../data/timer_repository.dart';
import 'planner_notification.dart';

/// Reconciles OS presentation from authoritative Drift streams. It has no
/// timer loop and owns no task/timer state.
class PlannerNotificationCoordinator {
  PlannerNotificationCoordinator({
    required this.database,
    required this.notifications,
    required this.accountId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final PlannerNotificationGateway notifications;
  final String? accountId;
  final DateTime Function() _clock;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<String, TaskReminderSnapshot> _scheduled = {};
  Future<void> _tail = Future<void>.value();
  String? _timerFingerprint;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final owner = await TimerRepository(database).localDeviceId();
    final timerQuery =
        database.select(database.timerSessions).join([
            innerJoin(
              database.tasks,
              database.tasks.id.equalsExp(database.timerSessions.taskId),
            ),
          ])
          ..where(
            database.timerSessions.ownerDeviceId.equals(owner) &
                database.timerSessions.state.isIn(const ['running', 'paused']) &
                database.timerSessions.deletedAt.isNull() &
                database.tasks.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.desc(database.timerSessions.updatedAt)])
          ..limit(1);
    _subscriptions.add(
      timerQuery.watchSingleOrNull().listen((row) {
        _enqueue(() async {
          if (row == null) {
            await notifications.cancelTimer();
            _timerFingerprint = null;
            return;
          }
          final session = row.readTable(database.timerSessions);
          final task = row.readTable(database.tasks);
          final fingerprint =
              '${session.id}:${session.state}:'
              '${session.runningSince?.microsecondsSinceEpoch}:'
              '${session.durationSec}:${session.revision}:${task.title}';
          if (_timerFingerprint == fingerprint) return;
          _timerFingerprint = fingerprint;
          await notifications.showTimer(
            TimerNotificationSnapshot(
              accountId: accountId,
              taskTitle: task.title,
              sessionId: session.id,
              taskId: session.taskId,
              ownerDeviceId: session.ownerDeviceId!,
              state: TimerSessionState.fromDb(session.state),
              runningSince: session.runningSince,
              durationSec: session.durationSec,
              revision: session.revision,
            ),
          );
        });
      }),
    );
    _subscriptions.add(
      database.select(database.tasks).watch().listen((rows) {
        _enqueue(() => _reconcileReminders(rows));
      }),
    );
    await _tail;
  }

  Future<void> _reconcileReminders(List<TaskRow> rows) async {
    final now = _clock();
    final wanted = <String, TaskReminderSnapshot>{};
    for (final row in rows) {
      final start = row.startTime;
      if (row.deletedAt != null ||
          row.isInbox ||
          TaskStatus.fromDb(row.status) != TaskStatus.planned ||
          start == null) {
        continue;
      }
      final snapshot = TaskReminderSnapshot(
        accountId: accountId,
        taskId: row.id,
        taskTitle: row.title,
        plannedStart: start,
      );
      if (snapshot.remindAt.isAfter(now)) wanted[row.id] = snapshot;
    }

    for (final taskId in _scheduled.keys.toList(growable: false)) {
      if (!wanted.containsKey(taskId)) {
        await notifications.cancelTaskReminder(taskId);
        _scheduled.remove(taskId);
      }
    }
    for (final entry in wanted.entries) {
      final previous = _scheduled[entry.key];
      final next = entry.value;
      if (previous != null &&
          previous.taskTitle == next.taskTitle &&
          previous.plannedStart == next.plannedStart &&
          previous.accountId == next.accountId) {
        continue;
      }
      if (previous != null) {
        await notifications.cancelTaskReminder(entry.key);
      }
      await notifications.scheduleTaskReminder(next);
      _scheduled[entry.key] = next;
    }
  }

  void _enqueue(Future<void> Function() action) {
    _tail = _tail.then((_) => action(), onError: (_) => action());
  }

  Future<void> dispose({bool cancelScheduled = false}) async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _tail;
    if (cancelScheduled) {
      for (final taskId in _scheduled.keys) {
        await notifications.cancelTaskReminder(taskId);
      }
      _scheduled.clear();
      await notifications.cancelTimer();
    }
    _started = false;
  }
}
