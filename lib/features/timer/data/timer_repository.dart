import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/timer_dao.dart';
import '../../../core/models/timer_session.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';

/// CRUD for timer sessions (planner.md Chunk 6 #4).
class TimerRepository {
  final AppDatabase _db;

  TimerRepository(this._db);

  TimerDao get _dao => _db.timerDao;

  /// The running session (if any) plus its task's title — drives the block
  /// chip and the desktop overlay.
  Stream<ActiveTimer?> watchActiveTimer() =>
      _dao.watchActiveTimerWithTask().map(
        (row) => row == null
            ? null
            : ActiveTimer(
                session: fromRow(row.session),
                taskTitle: row.taskTitle,
              ),
      );

  Future<List<TimerSession>> getSessionsForTask(String taskId) async =>
      (await _dao.getSessionsForTask(taskId)).map(fromRow).toList();

  Future<int> getTotalDurationSecForTask(String taskId) =>
      _dao.getTotalDurationSecForTask(taskId);

  Future<TimerSession> insertSession(TimerSession session) async {
    final now = DateTime.now();
    final effective = session.copyWith(
      id: session.id.isEmpty ? generateUuidV7() : session.id,
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction(() async {
      await _dao.insertSession(_toCompanion(effective));
      await _invalidateTaskDates(effective.taskId);
    });
    return effective;
  }

  Future<void> updateSession(TimerSession session) async {
    final row = await _dao.getSessionById(session.id);
    if (row == null) throw StateError('Timer session ${session.id} not found');
    await _db.transaction(() async {
      await _dao.updateSession(
        _toRow(
          session.copyWith(updatedAt: DateTime.now()),
          syncStatus: row.syncStatus,
          revision: row.revision,
        ),
      );
      await _invalidateTaskDates(row.taskId);
    });
  }

  Future<void> deleteSession(String sessionId) async {
    final row = await _dao.getSessionById(sessionId);
    await _db.transaction(() async {
      await _dao.softDeleteSession(sessionId, DateTime.now());
      if (row != null) await _invalidateTaskDates(row.taskId);
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
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  static TimerSessionsCompanion _toCompanion(TimerSession s) =>
      TimerSessionsCompanion.insert(
        id: s.id,
        taskId: s.taskId,
        startedAt: s.startedAt,
        endedAt: Value(s.endedAt),
        durationSec: Value(s.durationSec),
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        deletedAt: Value(s.deletedAt),
      );

  static TimerSessionRow _toRow(
    TimerSession s, {
    required int syncStatus,
    required int revision,
  }) => TimerSessionRow(
    id: s.id,
    taskId: s.taskId,
    startedAt: s.startedAt,
    endedAt: s.endedAt,
    durationSec: s.durationSec,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    deletedAt: s.deletedAt,
    syncStatus: syncStatus,
    revision: revision,
  );
}

/// The running session together with its task title.
class ActiveTimer {
  final TimerSession session;
  final String taskTitle;

  const ActiveTimer({required this.session, required this.taskTitle});
}
