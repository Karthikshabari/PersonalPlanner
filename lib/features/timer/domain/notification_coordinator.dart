import 'dart:async';
import 'dart:convert';

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
    Future<bool> Function()? ensureNotificationPermission,
  }) : _clock = clock ?? DateTime.now,
       _ensureNotificationPermission =
           ensureNotificationPermission ?? _permissionAlreadyAvailable;

  final AppDatabase database;
  final PlannerNotificationGateway notifications;
  final String? accountId;
  final DateTime Function() _clock;
  final Future<bool> Function() _ensureNotificationPermission;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<String, TaskReminderSnapshot> _scheduled = {};
  Future<void> _tail = Future<void>.value();
  String? _timerFingerprint;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _scheduled.addAll(
      await ReminderPresentationLedger(database, accountId: accountId).read(),
    );
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
          // A switch can pause A and start B with the same injected `now`.
          // State priority must therefore precede timestamps: a locally owned
          // running session is always the notification source, and paused is
          // only a fallback when no running session exists.
          ..orderBy([
            OrderingTerm.desc(database.timerSessions.state),
            OrderingTerm.desc(database.timerSessions.updatedAt),
            OrderingTerm.desc(database.timerSessions.startedAt),
            OrderingTerm.desc(database.timerSessions.id),
          ])
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
          if (!await _ensureNotificationPermission()) return;
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
          _timerFingerprint = fingerprint;
        });
      }),
    );
    _subscriptions.add(
      database.select(database.tasks).watch().listen((rows) {
        _enqueue(() => _reconcileReminders(rows));
      }),
    );
    // Timer rows are watched separately because imported/synced data may be
    // applied in more than one transaction. A timer session is independently
    // sufficient evidence that the task has started, even if its task status
    // has not arrived yet.
    _subscriptions.add(
      database.select(database.timerSessions).watch().listen((_) {
        _enqueue(() async {
          await _reconcileReminders(
            await database.select(database.tasks).get(),
          );
        });
      }),
    );
    await _tail;
  }

  Future<void> _reconcileReminders(List<TaskRow> rows) async {
    final now = _clock();
    final startedTaskIds = (await database.select(database.timerSessions).get())
        .where((row) => row.deletedAt == null)
        .map((row) => row.taskId)
        .toSet();
    final wanted = <String, TaskReminderSnapshot>{};
    for (final row in rows) {
      final start = row.startTime;
      if (row.deletedAt != null ||
          row.isInbox ||
          TaskStatus.fromDb(row.status) != TaskStatus.planned ||
          startedTaskIds.contains(row.id) ||
          start == null) {
        continue;
      }
      final snapshot = TaskReminderSnapshot(
        accountId: accountId,
        taskId: row.id,
        taskTitle: row.title,
        plannedStart: start,
      );
      if (snapshot.remindAt.isAfter(now)) {
        wanted[snapshot.identity.ledgerKey] = snapshot;
      }
    }

    final replacementFailures = <String>{};
    for (final entry in wanted.entries) {
      if (_scheduled.containsKey(entry.key)) continue;
      final next = entry.value;
      final permitted = await _ensureNotificationPermission();
      final scheduled =
          permitted && await notifications.scheduleTaskReminder(next);
      if (!scheduled) {
        replacementFailures.add(next.taskId);
        continue;
      }
      _scheduled[entry.key] = next;
      await _persistReminderLedger();
    }

    // Schedule a replacement first. If that fails, retain the previous known
    // presentation record so an ordinary later reconciliation retries instead
    // of caching the failed replacement as successful.
    for (final entry in _scheduled.entries.toList(growable: false)) {
      if (wanted.containsKey(entry.key) ||
          replacementFailures.contains(entry.value.taskId)) {
        continue;
      }
      if (await notifications.cancelTaskReminder(entry.value.identity)) {
        _scheduled.remove(entry.key);
        await _persistReminderLedger();
      }
    }
  }

  Future<void> _persistReminderLedger() => ReminderPresentationLedger(
    database,
    accountId: accountId,
  ).write(_scheduled.values);

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
      for (final entry in _scheduled.entries.toList(growable: false)) {
        if (await notifications.cancelTaskReminder(entry.value.identity)) {
          _scheduled.remove(entry.key);
          await _persistReminderLedger();
        }
      }
      await notifications.cancelTimer();
    }
    _started = false;
  }
}

Future<bool> _permissionAlreadyAvailable() async => true;

/// Durable, local-only presentation bookkeeping. `app_settings` belongs to
/// the currently open account database and is excluded from sync and portable
/// backup settings, so no reminder state crosses an account or cloud boundary.
class ReminderPresentationLedger {
  ReminderPresentationLedger(this._database, {required this.accountId});

  static const String settingKey = 'local.notification.task_reminder_ledger.v1';

  final AppDatabase _database;
  final String? accountId;

  Future<Map<String, TaskReminderSnapshot>> read() async {
    final encoded = await _database.syncDao.getSetting(settingKey);
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return {};
      final result = <String, TaskReminderSnapshot>{};
      for (final value in decoded) {
        if (value is! Map) continue;
        final row = Map<String, Object?>.from(value);
        final storedAccount = row['account_id'] as String?;
        final taskId = row['task_id'];
        final plannedMicros = row['planned_start_utc_micros'];
        if (storedAccount != accountId ||
            taskId is! String ||
            plannedMicros is! int) {
          continue;
        }
        final snapshot = TaskReminderSnapshot(
          accountId: storedAccount,
          taskId: taskId,
          // The ledger needs identity only; task content stays authoritative
          // in the tasks table and is deliberately not duplicated here.
          taskTitle: '',
          plannedStart: DateTime.fromMicrosecondsSinceEpoch(
            plannedMicros,
            isUtc: true,
          ),
        );
        result[snapshot.identity.ledgerKey] = snapshot;
      }
      return result;
    } on Object {
      return {};
    }
  }

  Future<void> write(Iterable<TaskReminderSnapshot> snapshots) async {
    final ordered = snapshots.toList()
      ..sort((a, b) => a.identity.ledgerKey.compareTo(b.identity.ledgerKey));
    if (ordered.isEmpty) {
      await _database.syncDao.deleteSetting(settingKey);
      return;
    }
    await _database.syncDao.setSetting(
      settingKey,
      jsonEncode([
        for (final snapshot in ordered)
          <String, Object?>{
            'account_id': snapshot.accountId,
            'task_id': snapshot.taskId,
            'planned_start_utc_micros': snapshot.plannedStart
                .toUtc()
                .microsecondsSinceEpoch,
          },
      ]),
    );
  }
}
