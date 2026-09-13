import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/timer_dao.dart';
import '../../../core/models/timer_session.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';
import '../domain/task_actual_duration_service.dart';

/// CRUD boundary for timer source rows. Every persisted source mutation
/// recomputes its affected Task cache in the same SQLite transaction.
class TimerRepository {
  TimerRepository(this._db);

  static const deviceIdSettingKey = 'timer.device_id';

  final AppDatabase _db;

  TimerDao get _dao => _db.timerDao;
  TaskActualDurationService get _actuals => TaskActualDurationService(_db);

  Future<String> localDeviceId() => _db.transaction(() async {
    final existing = await (_db.select(
      _db.appSettings,
    )..where((row) => row.key.equals(deviceIdSettingKey))).getSingleOrNull();
    if (existing != null && _isUuid(existing.value)) return existing.value;
    final id = generateUuidV7();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: deviceIdSettingKey, value: id),
        );
    return id;
  });

  Stream<ActiveTimer?> watchActiveTimer() async* {
    final deviceId = await localDeviceId();
    yield* _dao
        .watchActiveTimerWithTask(deviceId)
        .map(
          (row) => row == null
              ? null
              : ActiveTimer(
                  session: fromRow(row.session),
                  taskTitle: row.taskTitle,
                ),
        );
  }

  Stream<TimerSession?> watchUnfinishedForTask(String taskId) async* {
    final deviceId = await localDeviceId();
    yield* _dao
        .watchUnfinishedForTask(taskId, deviceId)
        .map((row) => row == null ? null : fromRow(row));
  }

  Stream<TimerSession?> watchRecoverableForTask(String taskId) => _dao
      .watchRecoverableForTask(taskId)
      .map((row) => row == null ? null : fromRow(row));

  Stream<TimerSession?> watchForeignUnfinishedForTask(String taskId) async* {
    final deviceId = await localDeviceId();
    yield* _dao
        .watchForeignUnfinishedForTask(taskId, deviceId)
        .map((row) => row == null ? null : fromRow(row));
  }

  Stream<TimerSession?> watchLatestPaused() async* {
    final deviceId = await localDeviceId();
    yield* _dao
        .watchLatestPausedForOwner(deviceId)
        .map((row) => row == null ? null : fromRow(row));
  }

  Stream<ActiveTimer?> watchLatestPausedTimer() async* {
    final deviceId = await localDeviceId();
    yield* _dao
        .watchLatestPausedWithTask(deviceId)
        .map(
          (row) => row == null
              ? null
              : ActiveTimer(
                  session: fromRow(row.session),
                  taskTitle: row.taskTitle,
                ),
        );
  }

  Future<List<TimerSession>> getSessionsForTask(String taskId) async =>
      (await _dao.getSessionsForTask(taskId)).map(fromRow).toList();

  Future<int> getTotalDurationSecForTask(String taskId) =>
      _dao.getTotalDurationSecForTask(taskId);

  Future<TimerSession> insertSession(TimerSession session) async {
    final now = DateTime.now();
    final effective = _normalizeSession(
      session.copyWith(
        id: session.id.isEmpty ? generateUuidV7() : session.id,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _db.transaction(() async {
      await _dao.insertSession(_toCompanion(effective));
      await _actuals.recomputeTaskInTransaction(effective.taskId);
      await _invalidateTaskDates(effective.taskId);
    });
    return effective;
  }

  Future<void> updateSession(TimerSession session) async {
    await _db.transaction(() async {
      final row = await _dao.getSessionById(session.id);
      if (row == null) {
        throw StateError('Timer session ${session.id} not found');
      }
      final effective = _normalizeSession(
        session.copyWith(updatedAt: DateTime.now()),
      );
      await _dao.updateSession(
        _toRow(
          effective,
          syncStatus: row.syncStatus,
          revision: row.revision,
          serverVersion: row.serverVersion,
        ),
      );
      await _actuals.recomputeTaskInTransaction(row.taskId);
      if (effective.taskId != row.taskId) {
        await _actuals.recomputeTaskInTransaction(effective.taskId);
      }
      await _invalidateTaskDates(row.taskId);
      if (effective.taskId != row.taskId) {
        await _invalidateTaskDates(effective.taskId);
      }
    });
  }

  Future<void> deleteSession(String sessionId) async {
    await _db.transaction(() async {
      final row = await _dao.getSessionById(sessionId);
      await _dao.softDeleteSession(sessionId, DateTime.now());
      if (row != null) {
        await _actuals.recomputeTaskInTransaction(row.taskId);
        await _invalidateTaskDates(row.taskId);
      }
    });
  }

  Future<void> _invalidateTaskDates(String taskId) async {
    final task = await _db.taskDao.getTaskById(taskId);
    final start = task?.startTime;
    final end = task?.endTime;
    if (start != null && end != null) {
      var day = startOfDay(start);
      while (day.isBefore(end)) {
        await _db.statsDao.invalidateForDate(isoDateString(day));
        day = addDays(day, 1);
      }
    } else if (start != null) {
      await _db.statsDao.invalidateForDate(isoDateString(start));
    }
  }

  static TimerSession fromRow(TimerSessionRow row) => TimerSession(
    id: row.id,
    taskId: row.taskId,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    durationSec: row.durationSec,
    state: TimerSessionState.fromDb(row.state),
    runningSince: row.runningSince,
    workIntervals: TaskActualDurationService.decodeIntervals(
      row.workIntervalsJson,
    ),
    ownerDeviceId: row.ownerDeviceId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  static TimerSession _normalizeSession(TimerSession session) {
    final inferredState = session.state;
    if (session.durationSec < 0) {
      throw ArgumentError('Timer duration cannot be negative.');
    }
    final intervals = session.workIntervals;
    var previousEnd = session.startedAt;
    var intervalSeconds = 0;
    for (final interval in intervals) {
      if (interval.durationSec < 0 ||
          interval.endAt.isBefore(interval.startAt) ||
          interval.startAt.isBefore(previousEnd) ||
          interval.durationSec !=
              interval.endAt.difference(interval.startAt).inSeconds) {
        throw ArgumentError('Timer work intervals must be chronological.');
      }
      previousEnd = interval.endAt;
      intervalSeconds += interval.durationSec;
    }
    if (intervals.isNotEmpty && intervalSeconds != session.durationSec) {
      throw ArgumentError(
        'Timer duration must equal its closed work intervals.',
      );
    }
    switch (inferredState) {
      case TimerSessionState.running:
        if (session.endedAt != null || session.runningSince == null) {
          throw ArgumentError(
            'Running timer sessions require runningSince only.',
          );
        }
      case TimerSessionState.paused:
        if (session.endedAt != null || session.runningSince != null) {
          throw ArgumentError(
            'Paused timer sessions cannot have active bounds.',
          );
        }
      case TimerSessionState.finished:
        if (session.endedAt == null || session.runningSince != null) {
          throw ArgumentError('Finished timer sessions require endedAt only.');
        }
    }
    return session.copyWith(state: inferredState);
  }

  static TimerSessionsCompanion _toCompanion(TimerSession s) =>
      TimerSessionsCompanion.insert(
        id: s.id,
        taskId: s.taskId,
        startedAt: s.startedAt,
        endedAt: Value(s.endedAt),
        durationSec: Value(s.durationSec),
        state: Value(s.state.dbValue),
        runningSince: Value(s.runningSince),
        workIntervalsJson: Value(
          TaskActualDurationService.encodeIntervals(s.workIntervals),
        ),
        ownerDeviceId: Value(s.ownerDeviceId),
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        deletedAt: Value(s.deletedAt),
      );

  static TimerSessionRow _toRow(
    TimerSession s, {
    required int syncStatus,
    required int revision,
    required int? serverVersion,
  }) => TimerSessionRow(
    id: s.id,
    taskId: s.taskId,
    startedAt: s.startedAt,
    endedAt: s.endedAt,
    durationSec: s.durationSec,
    state: s.state.dbValue,
    runningSince: s.runningSince,
    workIntervalsJson: TaskActualDurationService.encodeIntervals(
      s.workIntervals,
    ),
    ownerDeviceId: s.ownerDeviceId,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    deletedAt: s.deletedAt,
    syncStatus: syncStatus,
    revision: revision,
    serverVersion: serverVersion,
  );

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

class ActiveTimer {
  final TimerSession session;
  final String taskTitle;

  const ActiveTimer({required this.session, required this.taskTitle});
}
