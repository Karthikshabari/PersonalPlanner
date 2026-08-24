import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tasks_table.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  Stream<List<TaskRow>> watchTasksForDay(DateTime day) {
    final dayStartUtc = _iso(day);
    final dayEndUtc = _iso(day.add(const Duration(days: 1)));
    return (select(tasks)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.isInbox.equals(false) &
              t.startTime.isBiggerOrEqualValue(dayStartUtc) &
              t.startTime.isSmallerThanValue(dayEndUtc))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

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
