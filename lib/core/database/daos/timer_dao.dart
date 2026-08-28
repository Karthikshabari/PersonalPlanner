import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tasks_table.dart';
import '../tables/timer_sessions_table.dart';

part 'timer_dao.g.dart';

@DriftAccessor(tables: [TimerSessions, Tasks])
class TimerDao extends DatabaseAccessor<AppDatabase> with _$TimerDaoMixin {
  TimerDao(super.db);

  /// The currently running session (if any) together with its task title,
  /// for the overlay / block display.
  Stream<ActiveTimerRow?> watchActiveTimerWithTask() {
    final query = select(timerSessions).join([
      innerJoin(tasks, tasks.id.equalsExp(timerSessions.taskId)),
    ])
      ..where(timerSessions.endedAt.isNull() &
          timerSessions.deletedAt.isNull() &
          tasks.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(timerSessions.startedAt)])
      ..limit(1);
    return query.watchSingleOrNull().map((row) => row == null
        ? null
        : ActiveTimerRow(
            session: row.readTable(timerSessions),
            taskTitle: row.read(tasks.title)!,
            taskStatus: row.read(tasks.status)!,
          ));
  }

  Future<TimerSessionRow?> getActiveTimerForTask(String taskId) =>
      (select(timerSessions)
            ..where((s) =>
                s.taskId.equals(taskId) &
                s.endedAt.isNull() &
                s.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<TimerSessionRow>> getSessionsForTask(String taskId) =>
      (select(timerSessions)
            ..where((s) => s.taskId.equals(taskId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
          .get();

  /// Sum of all finished-session durations for [taskId], in seconds.
  Future<int> getTotalDurationSecForTask(String taskId) async {
    final durationSum = timerSessions.durationSec.sum();
    final query = selectOnly(timerSessions)
      ..addColumns([durationSum])
      ..where(timerSessions.taskId.equals(taskId) &
          timerSessions.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row?.read(durationSum) ?? 0;
  }

  Future<TimerSessionRow?> getSessionById(String id) =>
      (select(timerSessions)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertSession(TimerSessionsCompanion entry) =>
      into(timerSessions).insert(entry);

  Future<bool> updateSession(TimerSessionRow row) =>
      update(timerSessions).replace(row);

  Future<int> softDeleteSession(String id, DateTime deletedAt) async {
    final current = await getSessionById(id);
    if (current == null || current.deletedAt != null) return 0;
    return (update(timerSessions)..where((s) => s.id.equals(id))).write(
      TimerSessionsCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
        syncStatus: const Value(1),
        revision: Value(current.revision + 1),
      ),
    );
  }
}

/// The running session plus the fields of its task needed by the UI.
class ActiveTimerRow {
  final TimerSessionRow session;
  final String taskTitle;
  final String taskStatus;

  const ActiveTimerRow({
    required this.session,
    required this.taskTitle,
    required this.taskStatus,
  });
}
