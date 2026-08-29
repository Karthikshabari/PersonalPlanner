import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../data/task_repository.dart';

/// The task-owned rows that must move together for reversible creation and
/// deletion. Timer sessions deliberately remain historical records; deleting
/// a task hides them through the task join but never erases tracked time.
class TaskAggregateSnapshot {
  final TaskRow task;
  final List<SubtaskRow> subtasks;
  final List<TaskTagRow> taskTags;

  const TaskAggregateSnapshot({
    required this.task,
    required this.subtasks,
    required this.taskTags,
  });

  static Future<TaskAggregateSnapshot?> capture(
    AppDatabase db,
    String taskId,
  ) async {
    final task = await db.taskDao.getTaskById(taskId);
    if (task == null) return null;
    final subtasks = await (db.select(
      db.subtasks,
    )..where((row) => row.taskId.equals(taskId))).get();
    final links = await (db.select(
      db.taskTags,
    )..where((row) => row.taskId.equals(taskId))).get();
    return TaskAggregateSnapshot(
      task: task,
      subtasks: subtasks,
      taskTags: links,
    );
  }

  Future<void> softDelete(AppDatabase db) async {
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    await db.customUpdate(
      'UPDATE tasks SET deleted_at = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE id = ? AND deleted_at IS NULL',
      variables: [
        Variable<String>(nowIso),
        Variable<String>(nowIso),
        Variable<String>(task.id),
      ],
      updates: {db.tasks},
    );
    await db.customUpdate(
      'UPDATE subtasks SET deleted_at = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE task_id = ? AND deleted_at IS NULL',
      variables: [
        Variable<String>(nowIso),
        Variable<String>(nowIso),
        Variable<String>(task.id),
      ],
      updates: {db.subtasks},
    );
    await db.customUpdate(
      'UPDATE task_tags SET deleted_at = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE task_id = ? AND deleted_at IS NULL',
      variables: [
        Variable<String>(nowIso),
        Variable<String>(nowIso),
        Variable<String>(task.id),
      ],
      updates: {db.taskTags},
    );
  }

  Future<void> restore(AppDatabase db) async {
    final now = DateTime.now().toUtc();
    final repository = TaskRepository(db);
    final currentTask = await db.taskDao.getTaskById(task.id);
    if (currentTask == null) {
      await repository.insertTask(TaskRepository.fromRow(task));
    } else {
      await repository.updateTask(
        TaskRepository.fromRow(task).copyWith(deletedAt: null),
        allowStatusTransition: true,
      );
    }

    for (final snapshot in subtasks.where((row) => row.deletedAt == null)) {
      final current = await db.subtaskDao.getSubtaskById(snapshot.id);
      if (current == null) {
        await db
            .into(db.subtasks)
            .insert(
              snapshot
                  .toCompanion(false)
                  .copyWith(
                    updatedAt: Value(now),
                    deletedAt: const Value(null),
                    syncStatus: const Value(1),
                    revision: const Value(1),
                    serverVersion: const Value.absent(),
                  ),
            );
      } else {
        await db.subtaskDao.updateSubtask(
          snapshot.copyWith(
            updatedAt: now,
            deletedAt: const Value(null),
            syncStatus: 1,
            revision: current.revision + 1,
          ),
        );
      }
    }

    for (final snapshot in taskTags.where((row) => row.deletedAt == null)) {
      final current =
          await (db.select(db.taskTags)..where(
                (row) =>
                    row.taskId.equals(snapshot.taskId) &
                    row.tagId.equals(snapshot.tagId),
              ))
              .getSingleOrNull();
      if (current == null) {
        await db
            .into(db.taskTags)
            .insert(
              snapshot
                  .toCompanion(false)
                  .copyWith(
                    updatedAt: Value(now),
                    deletedAt: const Value(null),
                    syncStatus: const Value(1),
                    revision: const Value(1),
                    serverVersion: const Value.absent(),
                  ),
            );
      } else {
        await (db.update(db.taskTags)..where(
              (row) =>
                  row.taskId.equals(snapshot.taskId) &
                  row.tagId.equals(snapshot.tagId),
            ))
            .write(
              TaskTagsCompanion(
                updatedAt: Value(now),
                deletedAt: const Value(null),
                syncStatus: const Value(1),
                revision: Value(current.revision + 1),
              ),
            );
      }
    }
  }
}
