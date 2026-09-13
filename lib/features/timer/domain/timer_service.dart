import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/timer_session.dart';
import '../../../core/utils/uuid.dart';
import '../../timeline/data/task_repository.dart';
import '../data/timer_repository.dart';
import 'task_actual_duration_service.dart';

/// Result of a session-scoped transition. [didFinish] is deliberately
/// separate from [didChange] so duplicate Stop never creates a second
/// completion prompt or recounts the same measured source.
class TimerTransitionResult {
  const TimerTransitionResult({
    required this.session,
    required this.didChange,
    required this.didFinish,
  });

  final TimerSession? session;
  final bool didChange;
  final bool didFinish;
}

/// Serialized persisted Pause/Resume/Stop state machine. It owns no ticking
/// counter: TimerSession work intervals are the single source of measured
/// time, and TaskActualDurationService derives the Task cache only on Stop.
class TimerService {
  TimerService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  TimerRepository get _repository => TimerRepository(_db);
  TaskActualDurationService get _actuals => TaskActualDurationService(_db);

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<TimerTransitionResult> start(String taskId) => _serialize(() async {
    final owner = await _repository.localDeviceId();
    return _db.transaction(() => _startInTransaction(taskId, owner));
  });

  Future<TimerTransitionResult> _startInTransaction(
    String taskId,
    String owner,
  ) async {
    final task = await _db.taskDao.getTaskById(taskId);
    if (task == null ||
        task.deletedAt != null ||
        (TaskStatus.fromDb(task.status) != TaskStatus.planned &&
            TaskStatus.fromDb(task.status) != TaskStatus.inProgress)) {
      throw StateError(
        'Only an active planned or in-progress task can start a timer',
      );
    }
    final existing = await _db.timerDao.getUnfinishedForOwnerTask(
      owner,
      taskId,
    );
    if (existing != null) {
      if (existing.state == TimerSessionState.running.dbValue) {
        return TimerTransitionResult(
          session: TimerRepository.fromRow(existing),
          didChange: false,
          didFinish: false,
        );
      }
      return _resumeInTransaction(existing, owner, _now());
    }
    if (await _db.timerDao.getRecoverableForTask(taskId) != null) {
      throw StateError(
        'This imported timer must be recovered explicitly before it can run.',
      );
    }
    if (await _db.timerDao.getForeignUnfinishedForTask(taskId, owner) != null) {
      throw StateError('This timer belongs to another device.');
    }

    final now = _now();
    final running = await _db.timerDao.getRunningForOwner(owner);
    if (running != null) {
      await _pauseInTransaction(running, owner, now);
    }
    final id = generateUuidV7();
    await _db.timerDao.insertSession(
      TimerSessionsCompanion.insert(
        id: id,
        taskId: taskId,
        startedAt: now,
        durationSec: const Value(0),
        state: const Value('running'),
        runningSince: Value(now),
        workIntervalsJson: const Value('[]'),
        ownerDeviceId: Value(owner),
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (TaskStatus.fromDb(task.status) == TaskStatus.planned) {
      await TaskRepository(_db).updateTask(
        TaskRepository.fromRow(task).copyWith(status: TaskStatus.inProgress),
      );
    }
    final row = await _db.timerDao.getSessionById(id);
    return TimerTransitionResult(
      session: row == null ? null : TimerRepository.fromRow(row),
      didChange: true,
      didFinish: false,
    );
  }

  Future<TimerTransitionResult> pause() => _serialize(() async {
    final owner = await _repository.localDeviceId();
    return _db.transaction(() async {
      final running = await _db.timerDao.getRunningForOwner(owner);
      if (running == null) {
        return const TimerTransitionResult(
          session: null,
          didChange: false,
          didFinish: false,
        );
      }
      return _pauseInTransaction(running, owner, _now());
    });
  });

  Future<TimerTransitionResult> pauseAt(DateTime occurredAt) =>
      _serialize(() async {
        final owner = await _repository.localDeviceId();
        return _db.transaction(() async {
          final running = await _db.timerDao.getRunningForOwner(owner);
          if (running == null) {
            return const TimerTransitionResult(
              session: null,
              didChange: false,
              didFinish: false,
            );
          }
          return _pauseInTransaction(running, owner, occurredAt.toUtc());
        });
      });

  Future<TimerTransitionResult> pauseSession(
    String sessionId, {
    String? expectedOwnerDeviceId,
    DateTime? occurredAt,
    DateTime? expectedRunningSince,
  }) => _serialize(() async {
    final owner = expectedOwnerDeviceId ?? await _repository.localDeviceId();
    return _db.transaction(() async {
      final row = await _db.timerDao.getSessionById(sessionId);
      if (row == null || row.deletedAt != null || row.ownerDeviceId != owner) {
        return const TimerTransitionResult(
          session: null,
          didChange: false,
          didFinish: false,
        );
      }
      if (expectedRunningSince != null &&
          row.runningSince != expectedRunningSince) {
        return TimerTransitionResult(
          session: TimerRepository.fromRow(row),
          didChange: false,
          didFinish: false,
        );
      }
      return _pauseInTransaction(row, owner, (occurredAt ?? _now()).toUtc());
    });
  });

  Future<TimerTransitionResult> _pauseInTransaction(
    TimerSessionRow row,
    String owner,
    DateTime occurredAt,
  ) async {
    if (row.ownerDeviceId != owner || row.state != 'running') {
      return TimerTransitionResult(
        session: TimerRepository.fromRow(row),
        didChange: false,
        didFinish: false,
      );
    }
    final intervals = TaskActualDurationService.decodeIntervals(
      row.workIntervalsJson,
    );
    final lastEnd = intervals.isEmpty ? null : intervals.last.endAt;
    final began = row.runningSince ?? row.startedAt;
    var end = occurredAt;
    if (end.isBefore(began)) end = began;
    if (lastEnd != null && end.isBefore(lastEnd)) end = lastEnd;
    final seconds = end.difference(began).inSeconds.clamp(0, 1 << 31).toInt();
    if (seconds > 0) {
      intervals.add(
        TimerWorkInterval(startAt: began, endAt: end, durationSec: seconds),
      );
    }
    final duration = intervals.fold<int>(
      0,
      (sum, value) => sum + value.durationSec,
    );
    final updated = row.copyWith(
      durationSec: duration,
      state: 'paused',
      runningSince: const Value(null),
      workIntervalsJson: TaskActualDurationService.encodeIntervals(intervals),
      updatedAt: end,
    );
    await _db.timerDao.updateSession(updated);
    return TimerTransitionResult(
      session: TimerRepository.fromRow(updated),
      didChange: true,
      didFinish: false,
    );
  }

  Future<TimerTransitionResult> resume(String taskId) => _serialize(() async {
    final owner = await _repository.localDeviceId();
    return _db.transaction(() async {
      final row = await _db.timerDao.getUnfinishedForOwnerTask(owner, taskId);
      if (row == null) return _startInTransaction(taskId, owner);
      if (row.state == 'running') {
        return TimerTransitionResult(
          session: TimerRepository.fromRow(row),
          didChange: false,
          didFinish: false,
        );
      }
      return _resumeInTransaction(row, owner, _now());
    });
  });

  Future<TimerTransitionResult> resumeSession(String sessionId) =>
      _serialize(() async {
        final owner = await _repository.localDeviceId();
        return _db.transaction(() async {
          final row = await _db.timerDao.getSessionById(sessionId);
          if (row == null ||
              row.deletedAt != null ||
              row.ownerDeviceId != owner) {
            return const TimerTransitionResult(
              session: null,
              didChange: false,
              didFinish: false,
            );
          }
          return _resumeInTransaction(row, owner, _now());
        });
      });

  /// Explicitly adopts an ownerless imported/legacy session without changing
  /// its stable identity or its measured intervals. Foreign-owned sessions
  /// are deliberately not recoverable on this device.
  Future<TimerTransitionResult> recoverSession(String sessionId) =>
      _serialize(() async {
        final owner = await _repository.localDeviceId();
        return _db.transaction(() async {
          final row = await _db.timerDao.getSessionById(sessionId);
          if (row == null ||
              row.deletedAt != null ||
              row.ownerDeviceId != null ||
              (row.state != 'running' && row.state != 'paused')) {
            return const TimerTransitionResult(
              session: null,
              didChange: false,
              didFinish: false,
            );
          }
          final task = await _db.taskDao.getTaskById(row.taskId);
          if (task == null ||
              task.deletedAt != null ||
              (TaskStatus.fromDb(task.status) != TaskStatus.planned &&
                  TaskStatus.fromDb(task.status) != TaskStatus.inProgress)) {
            throw StateError(
              'Only an active planned or in-progress task can recover a timer',
            );
          }
          final existing = await _db.timerDao.getUnfinishedForOwnerTask(
            owner,
            row.taskId,
          );
          if (existing != null) {
            return TimerTransitionResult(
              session: TimerRepository.fromRow(existing),
              didChange: false,
              didFinish: false,
            );
          }
          final now = _now();
          if (row.state == 'running') {
            final running = await _db.timerDao.getRunningForOwner(owner);
            if (running != null && running.id != row.id) {
              await _pauseInTransaction(running, owner, now);
            }
          }
          final recovered = row.copyWith(
            ownerDeviceId: Value(owner),
            updatedAt: now,
          );
          await _db.timerDao.updateSession(recovered);
          return TimerTransitionResult(
            session: TimerRepository.fromRow(recovered),
            didChange: true,
            didFinish: false,
          );
        });
      });

  Future<TimerTransitionResult> _resumeInTransaction(
    TimerSessionRow row,
    String owner,
    DateTime now,
  ) async {
    if (row.ownerDeviceId != owner || row.state != 'paused') {
      return TimerTransitionResult(
        session: TimerRepository.fromRow(row),
        didChange: false,
        didFinish: false,
      );
    }
    final task = await _db.taskDao.getTaskById(row.taskId);
    if (task == null ||
        task.deletedAt != null ||
        (TaskStatus.fromDb(task.status) != TaskStatus.planned &&
            TaskStatus.fromDb(task.status) != TaskStatus.inProgress)) {
      throw StateError(
        'Only an active planned or in-progress task can resume a timer',
      );
    }
    final other = await _db.timerDao.getRunningForOwner(owner);
    if (other != null && other.id != row.id) {
      await _pauseInTransaction(other, owner, now);
    }
    final intervals = TaskActualDurationService.decodeIntervals(
      row.workIntervalsJson,
    );
    final lastEnd = intervals.isEmpty ? row.startedAt : intervals.last.endAt;
    final runningSince = now.isBefore(lastEnd) ? lastEnd : now;
    final updated = row.copyWith(
      state: 'running',
      runningSince: Value(runningSince),
      updatedAt: runningSince,
    );
    await _db.timerDao.updateSession(updated);
    return TimerTransitionResult(
      session: TimerRepository.fromRow(updated),
      didChange: true,
      didFinish: false,
    );
  }

  Future<TimerTransitionResult> stop() => _serialize(() async {
    final owner = await _repository.localDeviceId();
    return _db.transaction(() async {
      final running = await _db.timerDao.getRunningForOwner(owner);
      final paused = running == null
          ? await _db.timerDao.getLatestPausedForOwner(owner)
          : null;
      final row = running ?? paused;
      if (row == null) {
        return const TimerTransitionResult(
          session: null,
          didChange: false,
          didFinish: false,
        );
      }
      return _stopInTransaction(row, owner, _now());
    });
  });

  Future<TimerTransitionResult> stopAt(DateTime occurredAt) =>
      _serialize(() async {
        final owner = await _repository.localDeviceId();
        return _db.transaction(() async {
          final running = await _db.timerDao.getRunningForOwner(owner);
          final paused = running == null
              ? await _db.timerDao.getLatestPausedForOwner(owner)
              : null;
          final row = running ?? paused;
          if (row == null) {
            return const TimerTransitionResult(
              session: null,
              didChange: false,
              didFinish: false,
            );
          }
          return _stopInTransaction(row, owner, occurredAt.toUtc());
        });
      });

  Future<TimerTransitionResult> stopSession(
    String sessionId, {
    String? expectedOwnerDeviceId,
    DateTime? occurredAt,
    DateTime? expectedRunningSince,
  }) => _serialize(() async {
    final owner = expectedOwnerDeviceId ?? await _repository.localDeviceId();
    return _db.transaction(() async {
      final row = await _db.timerDao.getSessionById(sessionId);
      if (row == null || row.deletedAt != null || row.ownerDeviceId != owner) {
        return const TimerTransitionResult(
          session: null,
          didChange: false,
          didFinish: false,
        );
      }
      if (expectedRunningSince != null &&
          row.runningSince != expectedRunningSince) {
        return TimerTransitionResult(
          session: TimerRepository.fromRow(row),
          didChange: false,
          didFinish: false,
        );
      }
      return _stopInTransaction(row, owner, (occurredAt ?? _now()).toUtc());
    });
  });

  /// Used by task terminal/delete commands which already own a larger Drift
  /// transaction. It reuses the exact Stop transition while deliberately
  /// limiting the mutation to this database's device owner.
  Future<TimerTransitionResult> stopOwnedTaskInTransaction(
    String taskId,
    String ownerDeviceId,
    DateTime occurredAt,
  ) async {
    final row = await _db.timerDao.getUnfinishedForOwnerTask(
      ownerDeviceId,
      taskId,
    );
    if (row == null) {
      return const TimerTransitionResult(
        session: null,
        didChange: false,
        didFinish: false,
      );
    }
    return _stopInTransaction(row, ownerDeviceId, occurredAt.toUtc());
  }

  Future<TimerTransitionResult> _stopInTransaction(
    TimerSessionRow row,
    String owner,
    DateTime occurredAt,
  ) async {
    if (row.ownerDeviceId != owner) {
      return TimerTransitionResult(
        session: TimerRepository.fromRow(row),
        didChange: false,
        didFinish: false,
      );
    }
    if (row.state == 'finished') {
      await _actuals.recomputeTaskInTransaction(row.taskId);
      return TimerTransitionResult(
        session: TimerRepository.fromRow(row),
        didChange: false,
        didFinish: false,
      );
    }
    TimerSessionRow stopped = row;
    if (row.state == 'running') {
      final paused = await _pauseInTransaction(row, owner, occurredAt);
      stopped = await _db.timerDao.getSessionById(row.id) ?? row;
      if (!paused.didChange && stopped.state != 'paused') {
        return paused;
      }
    }
    final end = occurredAt.isBefore(stopped.startedAt)
        ? stopped.startedAt
        : occurredAt;
    final finished = stopped.copyWith(
      state: 'finished',
      runningSince: const Value(null),
      endedAt: Value(end),
      updatedAt: end,
    );
    await _db.timerDao.updateSession(finished);
    await _actuals.recomputeTaskInTransaction(finished.taskId);
    return TimerTransitionResult(
      session: TimerRepository.fromRow(finished),
      didChange: true,
      didFinish: true,
    );
  }

  Future<int?> syncActualDuration(String taskId) =>
      _actuals.recomputeTask(taskId);

  Future<int?> setManualActual(
    String taskId,
    int actualMinutes, {
    int? expectedRevision,
  }) => _actuals.setDisplayedTotal(
    taskId,
    actualMinutes,
    expectedRevision: expectedRevision,
  );

  DateTime _now() => _clock().toUtc();
}
