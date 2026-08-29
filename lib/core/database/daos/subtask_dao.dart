import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/subtasks_table.dart';

part 'subtask_dao.g.dart';

@DriftAccessor(tables: [Subtasks])
class SubtaskDao extends DatabaseAccessor<AppDatabase> with _$SubtaskDaoMixin {
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

  /// Counts active subtasks for every task in one grouped query. Timeline
  /// blocks use this stream so a long day does not create one query per block.
  Stream<Map<String, String>> watchSubtaskCounts() =>
      customSelect(
        'SELECT task_id, COUNT(*) AS subtask_count, '
        'SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) AS completed_count '
        'FROM subtasks WHERE deleted_at IS NULL GROUP BY task_id',
        readsFrom: {subtasks},
      ).watch().map(
        (rows) => {
          for (final row in rows)
            row.read<String>(
              'task_id',
            ): '${row.read<int>('completed_count')}/${row.read<int>('subtask_count')}',
        },
      );

  Future<SubtaskRow?> getSubtaskById(String id) =>
      (select(subtasks)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> insertSubtask(SubtasksCompanion entry) =>
      into(subtasks).insert(entry);

  Future<bool> updateSubtask(SubtaskRow row) async {
    final count =
        await (update(
          subtasks,
        )..where((subtask) => subtask.id.equals(row.id))).write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

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
    String taskId,
    List<(String id, int sortOrder)> ordered,
  ) {
    final now = DateTime.now().toUtc();
    return transaction(() async {
      for (final (id, sortOrder) in ordered) {
        final current = await getSubtaskById(id);
        if (current == null ||
            current.taskId != taskId ||
            current.deletedAt != null) {
          throw StateError('Subtask $id does not belong to task $taskId');
        }
        await (update(
          subtasks,
        )..where((s) => s.id.equals(id) & s.taskId.equals(taskId))).write(
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
