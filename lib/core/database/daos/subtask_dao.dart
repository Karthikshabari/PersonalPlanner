import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/subtasks_table.dart';

part 'subtask_dao.g.dart';

@DriftAccessor(tables: [Subtasks])
class SubtaskDao extends DatabaseAccessor<AppDatabase>
    with _$SubtaskDaoMixin {
  SubtaskDao(super.db);

  /// Active (non-deleted) subtasks of one task, ordered by sort order.
  Stream<List<SubtaskRow>> watchSubtasksForTask(String taskId) {
    return (select(subtasks)
          ..where((s) => s.taskId.equals(taskId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
        .watch();
  }

  Future<List<SubtaskRow>> getSubtasksForTask(String taskId) =>
      (select(subtasks)
            ..where((s) => s.taskId.equals(taskId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
          .get();

  Future<SubtaskRow?> getSubtaskById(String id) =>
      (select(subtasks)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> insertSubtask(SubtasksCompanion entry) =>
      into(subtasks).insert(entry);

  Future<bool> updateSubtask(SubtaskRow row) =>
      update(subtasks).replace(row);

  Future<int> softDeleteSubtask(String id, DateTime deletedAt) async {
    final current = await getSubtaskById(id);
    if (current == null || current.deletedAt != null) return 0;
    return (update(subtasks)..where((s) => s.id.equals(id))).write(
      SubtasksCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
        syncStatus: const Value(1),
        revision: Value(current.revision + 1),
      ),
    );
  }

  Future<void> reorderSubtasks(
      String taskId, List<(String id, int sortOrder)> ordered) {
    final now = DateTime.now().toUtc();
    return transaction(() async {
      for (final (id, sortOrder) in ordered) {
        final current = await getSubtaskById(id);
        if (current == null || current.taskId != taskId || current.deletedAt != null) {
          throw StateError('Subtask $id does not belong to task $taskId');
        }
        await (update(subtasks)
              ..where((s) => s.id.equals(id) & s.taskId.equals(taskId)))
            .write(
          SubtasksCompanion(
            sortOrder: Value(sortOrder),
            updatedAt: Value(now),
            syncStatus: const Value(1),
            revision: Value(current.revision + 1),
          ),
        );
      }
    });
  }
}
