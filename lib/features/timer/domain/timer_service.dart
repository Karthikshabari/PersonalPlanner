import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/uuid.dart';
import '../../timeline/data/task_repository.dart';

/// Start/pause/resume/stop engine (planner.md Chunk 6 #3). Each start/stop
/// span is its own session; only one timer may run globally — starting a
/// timer on task B auto-pauses the running session of task A.
class TimerService {
  final AppDatabase _db;

  TimerService(this._db);

  /// Starts a NEW session for [taskId], auto-pausing any other running
  /// session first. Also moves the task from planned → in progress
  /// (planner.md Chunk 6 #11). Idempotent when this task's timer already
  /// runs.
  Future<void> start(String taskId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final targetRow = await _db.taskDao.getTaskById(taskId);
      if (targetRow == null ||
          targetRow.deletedAt != null ||
          (TaskStatus.fromDb(targetRow.status) != TaskStatus.planned &&
              TaskStatus.fromDb(targetRow.status) != TaskStatus.inProgress)) {
        throw StateError(
          'Only an active planned or in-progress task can start a timer',
        );
      }
      final existing = await _db.timerDao.getActiveTimerForTask(taskId);
      if (existing != null) return; // already running for this task

      // Single active timer globally: finalize whoever else was running.
      final others = await (_db.select(
        _db.timerSessions,
      )..where((s) => s.endedAt.isNull() & s.deletedAt.isNull())).get();
      for (final other in others) {
        await _finalize(other, now);
        await _syncActualDurationInTransaction(other.taskId);
      }
      await _db.timerDao.insertSession(
        TimerSessionsCompanion.insert(
          id: generateUuidV7(),
          taskId: taskId,
          startedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      if (TaskStatus.fromDb(targetRow.status) == TaskStatus.planned) {
        await TaskRepository(_db).updateTask(
          TaskRepository.fromRow(targetRow)
              .copyWith(status: TaskStatus.inProgress),
        );
      }
    });
  }

  /// Ends the running session, computing its duration, and refreshes the
  /// task's `actual_duration_min` from all sessions (planner.md Chunk 6 #5).
  Future<void> pause() => pauseAt(DateTime.now());

  /// Finalizes at the time an external action actually occurred. This keeps
  /// process-death recovery from charging the user for restart delay.
  Future<void> pauseAt(DateTime occurredAt) async {
    await _db.transaction(() async {
      final running = await _runningSession();
      if (running == null) return;
      final endedAt = occurredAt.isBefore(running.startedAt)
          ? running.startedAt
          : occurredAt;
      await _finalize(running, endedAt);
      await _syncActualDurationInTransaction(running.taskId);
    });
  }

  /// `resume(taskId)` starts a fresh session (planner.md Chunk 6 #3).
  Future<void> resume(String taskId) => start(taskId);

  /// Ends the current session and finalizes its duration. The "Mark as
  /// Completed?" decision belongs to the caller (planner.md Chunk 6 #12).
  Future<void> stop() => pause();

  Future<void> stopAt(DateTime occurredAt) => pauseAt(occurredAt);

  Future<void> syncActualDuration(String taskId) async {
    await _db.transaction(() => _syncActualDurationInTransaction(taskId));
  }

  /// Updates the cached actual value while preserving the user's manual
  /// adjustment across future sessions.
  Future<void> _syncActualDurationInTransaction(String taskId) async {
    final totalSec = await _db.timerDao.getTotalDurationSecForTask(taskId);
    final task = await _db.taskDao.getTaskById(taskId);
    if (task == null) return;
    final computedMin = totalSec ~/ 60;
    final actual = (computedMin + task.manualDurationAdjustmentMin)
        .clamp(0, 1 << 31)
        .toInt();
    if (task.actualDurationMin == actual) return;
    await TaskRepository(_db).updateTask(
      TaskRepository.fromRow(task).copyWith(actualDurationMin: actual),
    );
  }

  /// Sets the desired displayed actual duration and stores only the delta
  /// from completed timer minutes, so later sessions retain the adjustment.
  Future<void> setManualActual(String taskId, int actualMinutes) async {
    if (actualMinutes < 0) {
      throw ArgumentError.value(
        actualMinutes,
        'actualMinutes',
        'must not be negative',
      );
    }
    await _db.transaction(() async {
      final task = await _db.taskDao.getTaskById(taskId);
      if (task == null || task.deletedAt != null) {
        throw StateError('Task $taskId not found');
      }
      final timerMinutes =
          (await _db.timerDao.getTotalDurationSecForTask(taskId)) ~/ 60;
      await TaskRepository(_db).updateTask(
        TaskRepository.fromRow(task).copyWith(
          actualDurationMin: actualMinutes,
          manualDurationAdjustmentMin: actualMinutes - timerMinutes,
        ),
      );
    });
  }

  Future<TimerSessionRow?> _runningSession() async {
    final rows =
        await (_db.select(_db.timerSessions)
              ..where((s) => s.endedAt.isNull() & s.deletedAt.isNull())
              ..limit(1))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _finalize(TimerSessionRow session, DateTime endedAt) async {
    final durationSec = endedAt
        .difference(session.startedAt)
        .inSeconds
        .clamp(0, 1 << 31);
    await _db.timerDao.updateSession(
      session.copyWith(
        endedAt: Value(endedAt),
        durationSec: durationSec,
        updatedAt: endedAt,
      ),
    );
  }
}
