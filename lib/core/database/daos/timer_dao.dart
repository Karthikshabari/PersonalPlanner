import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tasks_table.dart';
import '../tables/timer_sessions_table.dart';

part 'timer_dao.g.dart';

@DriftAccessor(tables: [TimerSessions, Tasks])
class TimerDao extends DatabaseAccessor<AppDatabase> with _$TimerDaoMixin {
  TimerDao(super.db);

  /// Locally owned running session with the fields needed by timer chrome.
  Stream<ActiveTimerRow?> watchActiveTimerWithTask([String? ownerDeviceId]) {
    final query =
        select(timerSessions)
            .join([innerJoin(tasks, tasks.id.equalsExp(timerSessions.taskId))])
          ..where(
            timerSessions.state.equals('running') &
                timerSessions.deletedAt.isNull() &
                tasks.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.desc(timerSessions.updatedAt)])
          ..limit(1);
    if (ownerDeviceId != null) {
      query.where(timerSessions.ownerDeviceId.equals(ownerDeviceId));
    }
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : ActiveTimerRow(
              session: row.readTable(timerSessions),
              taskTitle: row.read(tasks.title)!,
              taskStatus: row.read(tasks.status)!,
            ),
    );
  }

  Future<TimerSessionRow?> getRunningForOwner(String ownerDeviceId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.ownerDeviceId.equals(ownerDeviceId) &
                  s.state.equals('running') &
                  s.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<TimerSessionRow?> getUnfinishedForOwnerTask(
    String ownerDeviceId,
    String taskId,
  ) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.ownerDeviceId.equals(ownerDeviceId) &
                  s.taskId.equals(taskId) &
                  s.state.isIn(const ['running', 'paused']) &
                  s.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  Stream<TimerSessionRow?> watchUnfinishedForTask(
    String taskId,
    String ownerDeviceId,
  ) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.ownerDeviceId.equals(ownerDeviceId) &
                  s.taskId.equals(taskId) &
                  s.state.isIn(const ['running', 'paused']) &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  /// An imported or legacy unfinished session can be claimed only through an
  /// explicit Recover action. It is intentionally separate from local and
  /// foreign ownership reads so no ordinary Start path can take it over.
  Stream<TimerSessionRow?> watchRecoverableForTask(String taskId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.ownerDeviceId.isNull() &
                  s.state.isIn(const ['running', 'paused']) &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  Stream<TimerSessionRow?> watchForeignUnfinishedForTask(
    String taskId,
    String ownerDeviceId,
  ) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.ownerDeviceId.isNotNull() &
                  s.ownerDeviceId.equals(ownerDeviceId).not() &
                  s.state.isIn(const ['running', 'paused']) &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  Future<TimerSessionRow?> getRecoverableForTask(String taskId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.ownerDeviceId.isNull() &
                  s.state.isIn(const ['running', 'paused']) &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<TimerSessionRow?> getForeignUnfinishedForTask(
    String taskId,
    String ownerDeviceId,
  ) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.ownerDeviceId.isNotNull() &
                  s.ownerDeviceId.equals(ownerDeviceId).not() &
                  s.state.isIn(const ['running', 'paused']) &
                  s.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  Stream<TimerSessionRow?> watchLatestPausedForOwner(String ownerDeviceId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.ownerDeviceId.equals(ownerDeviceId) &
                  s.state.equals('paused') &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  Stream<ActiveTimerRow?> watchLatestPausedWithTask(String ownerDeviceId) {
    final query =
        select(timerSessions)
            .join([innerJoin(tasks, tasks.id.equalsExp(timerSessions.taskId))])
          ..where(
            timerSessions.ownerDeviceId.equals(ownerDeviceId) &
                timerSessions.state.equals('paused') &
                timerSessions.deletedAt.isNull() &
                tasks.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.desc(timerSessions.updatedAt)])
          ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : ActiveTimerRow(
              session: row.readTable(timerSessions),
              taskTitle: row.read(tasks.title)!,
              taskStatus: row.read(tasks.status)!,
            ),
    );
  }

  Future<TimerSessionRow?> getLatestPausedForOwner(String ownerDeviceId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.ownerDeviceId.equals(ownerDeviceId) &
                  s.state.equals('paused') &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  // Compatibility read helpers. New transitions must use owner-scoped APIs.
  Future<TimerSessionRow?> getActiveTimerForTask(String taskId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.state.equals('running') &
                  s.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<TimerSessionRow?> getActiveTimer() =>
      (select(timerSessions)
            ..where((s) => s.state.equals('running') & s.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  /// Compatibility task-terminal helper. New code uses the shared state
  /// machine, but this stays idempotent for older command paths.
  Future<bool> finalizeActiveForTask(String taskId, DateTime endedAt) async {
    final session =
        await (select(timerSessions)
              ..where(
                (s) =>
                    s.taskId.equals(taskId) &
                    s.state.isIn(const ['running', 'paused']) &
                    s.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (session == null) return false;
    final end = endedAt.isBefore(session.startedAt)
        ? session.startedAt
        : endedAt;
    await updateSession(
      session.copyWith(
        endedAt: Value(end),
        durationSec: session.state == 'paused'
            ? session.durationSec
            : end
                      .difference(session.runningSince ?? session.startedAt)
                      .inSeconds
                      .clamp(0, 1 << 31)
                      .toInt() +
                  session.durationSec,
        state: 'finished',
        runningSince: const Value(null),
        updatedAt: end,
      ),
    );
    return true;
  }

  Future<List<TimerSessionRow>> getSessionsForTask(String taskId) =>
      (select(timerSessions)
            ..where((s) => s.taskId.equals(taskId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
          .get();

  Future<List<TimerSessionRow>> getFinishedSessionsForTask(String taskId) =>
      (select(timerSessions)
            ..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.state.equals('finished') &
                  s.endedAt.isNotNull() &
                  s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
          .get();

  /// Sum only committed finished sources. Paused work cannot leak into Task
  /// Actual Duration.
  Future<int> getTotalDurationSecForTask(String taskId) async {
    final durationSum = timerSessions.durationSec.sum();
    final query = selectOnly(timerSessions)
      ..addColumns([durationSum])
      ..where(
        timerSessions.taskId.equals(taskId) &
            timerSessions.state.equals('finished') &
            timerSessions.endedAt.isNotNull() &
            timerSessions.deletedAt.isNull(),
      );
    final row = await query.getSingleOrNull();
    return row?.read(durationSum) ?? 0;
  }

  Future<TimerSessionRow?> getSessionById(String id) =>
      (select(timerSessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> insertSession(TimerSessionsCompanion entry) =>
      into(timerSessions).insert(entry);

  Future<bool> updateSession(TimerSessionRow row) async {
    final count =
        await (update(
          timerSessions,
        )..where((session) => session.id.equals(row.id))).write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

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
