import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tasks_table.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  Stream<List<TaskRow>> watchTasksForDay(DateTime day) =>
      (select(tasks)..where((t) => _dayFilter(t, day, dayEnd: _nextDay(day))))
          .watch();

  /// One-shot variant of [watchTasksForDay] used by stats computation
  /// (planner.md Chunk 5 #9).
  Future<List<TaskRow>> getTasksForDay(DateTime day) =>
      (select(tasks)..where((t) => _dayFilter(t, day, dayEnd: _nextDay(day))))
          .get();

  /// Scheduled non-deleted tasks starting within [start, end) — used for
  /// week-level aggregation.
  Future<List<TaskRow>> getTasksBetween(DateTime start, DateTime end) =>
      (select(tasks)
            ..where((t) => _dayFilter(t, start, dayEnd: end))
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .get();

  Expression<bool> _dayFilter(
    Tasks t,
    DateTime dayStart, {
    required DateTime dayEnd,
  }) =>
      t.deletedAt.isNull() &
      t.isInbox.equals(false) &
      t.startTime.isBiggerOrEqualValue(_iso(dayStart)) &
      t.startTime.isSmallerThanValue(_iso(dayEnd));

  DateTime _nextDay(DateTime day) => day.add(const Duration(days: 1));

  Future<TaskRow?> getTaskById(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertTask(TasksCompanion entry) => into(tasks).insert(entry);

  Future<bool> updateTask(TaskRow row) => update(tasks).replace(row);

  Future<int> softDeleteTask(String id, DateTime deletedAt) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
        ),
      );

  /// Permanently removes the row. Used by CreateTaskCommand.undo so that a
  /// redo can re-insert the same UUIDv7 id without a primary-key conflict.
  Future<int> hardDeleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  String _iso(DateTime local) =>
      DateTime(local.year, local.month, local.day).toUtc().toIso8601String();
}
