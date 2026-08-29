import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/subtask_dao.dart';
import '../../../core/models/subtask.dart';
import '../../../core/utils/uuid.dart';

class SubtaskRepository {
  final AppDatabase _db;

  SubtaskRepository(this._db);

  SubtaskDao get _dao => _db.subtaskDao;

  Future<Subtask> insertSubtask(Subtask subtask) async {
    final now = DateTime.now();
    final maxOrder = _db.subtasks.sortOrder.max();
    final row =
        await (_db.selectOnly(_db.subtasks)
              ..addColumns([maxOrder])
              ..where(
                _db.subtasks.taskId.equals(subtask.taskId) &
                    _db.subtasks.deletedAt.isNull(),
              ))
            .getSingle();
    final sortOrder = (row.read(maxOrder) ?? -1) + 1;
    final effective = subtask.copyWith(
      id: subtask.id.isEmpty ? generateUuidV7() : subtask.id,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    await _dao.insertSubtask(_toCompanion(effective));
    return effective;
  }

  Future<Subtask> updateSubtask(Subtask subtask) async {
    final now = DateTime.now();
    final effective = subtask.copyWith(updatedAt: now);
    final row = await _dao.getSubtaskById(effective.id);
    if (row == null) {
      throw StateError('Subtask ${effective.id} not found');
    }
    await _dao.updateSubtask(
      _toRow(effective, syncStatus: 1, revision: row.revision + 1),
    );
    return effective;
  }

  Future<void> deleteSubtask(String id) async {
    final row = await _dao.getSubtaskById(id);
    if (row == null || row.deletedAt != null) return;
    final now = DateTime.now();
    await _dao.updateSubtask(
      row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        syncStatus: 1,
        revision: row.revision + 1,
      ),
    );
  }

  Stream<List<Subtask>> watchSubtasksForTask(String taskId) => _dao
      .watchSubtasksForTask(taskId)
      .map((rows) => rows.map(_fromRow).toList());

  Future<List<Subtask>> getSubtasksForTask(String taskId) async =>
      (await _dao.getSubtasksForTask(taskId)).map(_fromRow).toList();

  Stream<Map<String, String>> watchSubtaskCounts() => _dao.watchSubtaskCounts();

  /// Toggles `isCompleted` and returns the updated subtask.
  Future<Subtask> toggleSubtask(String id) async {
    final row = await _dao.getSubtaskById(id);
    if (row == null) throw StateError('Subtask $id not found');
    final current = _fromRow(row);
    return updateSubtask(current.copyWith(isCompleted: !current.isCompleted));
  }

  /// Persists a new sort order for all subtasks of [taskId].
  Future<void> reorderSubtasks(String taskId, List<String> orderedIds) async {
    final current = await _dao.getSubtasksForTask(taskId);
    if (current.length != orderedIds.length ||
        current
            .map((row) => row.id)
            .toSet()
            .difference(orderedIds.toSet())
            .isNotEmpty ||
        orderedIds.toSet().length != orderedIds.length) {
      throw StateError(
        'Reorder must contain every active subtask exactly once',
      );
    }
    await _dao.reorderSubtasks(taskId, [
      for (var i = 0; i < orderedIds.length; i++) (orderedIds[i], i),
    ]);
  }

  static Subtask _fromRow(SubtaskRow row) => Subtask(
    id: row.id,
    taskId: row.taskId,
    title: row.title,
    isCompleted: row.isCompleted,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  static SubtasksCompanion _toCompanion(Subtask s) => SubtasksCompanion.insert(
    id: s.id,
    taskId: s.taskId,
    title: s.title,
    isCompleted: Value(s.isCompleted),
    sortOrder: Value(s.sortOrder),
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    deletedAt: Value(s.deletedAt),
    syncStatus: const Value(1),
    revision: const Value(1),
  );

  static SubtaskRow _toRow(Subtask s, {int syncStatus = 0, int revision = 1}) =>
      SubtaskRow(
        id: s.id,
        taskId: s.taskId,
        title: s.title,
        isCompleted: s.isCompleted,
        sortOrder: s.sortOrder,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        deletedAt: s.deletedAt,
        syncStatus: syncStatus,
        revision: revision,
      );
}
