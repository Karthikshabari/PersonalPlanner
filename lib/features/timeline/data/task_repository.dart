import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/task_dao.dart';
import '../../../core/models/enums/priority.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/uuid.dart';

class TaskRepository {
  final AppDatabase _db;

  TaskRepository(this._db);

  TaskDao get _dao => _db.taskDao;

  Future<Task> insertTask(Task task) async {
    final now = DateTime.now();
    final effective = task.copyWith(
      id: task.id.isEmpty ? generateUuidV7() : task.id,
      createdAt: task.createdAt,
      updatedAt: now,
    );
    await _dao.insertTask(_toCompanion(effective));
    return effective;
  }

  Future<Task> updateTask(Task task) async {
    final now = DateTime.now();
    final effective = task.copyWith(updatedAt: now);
    final row = await _dao.getTaskById(effective.id);
    if (row == null) {
      throw StateError('Task ${effective.id} not found');
    }
    await _dao.updateTask(_toRow(effective, syncStatus: row.syncStatus, revision: row.revision));
    return effective;
  }

  Future<void> deleteTask(String taskId) async {
    await _dao.softDeleteTask(taskId, DateTime.now());
  }

  /// Permanently removes the row (used to undo task creation).
  Future<void> hardDeleteTask(String taskId) async {
    await _dao.hardDeleteTask(taskId);
  }

  Stream<List<Task>> watchTasksForDay(DateTime date) =>
      _dao.watchTasksForDay(date).map((rows) => rows.map(_fromRow).toList());

  Future<Task?> getTaskById(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    return row == null ? null : _fromRow(row);
  }

  static Task _fromRow(TaskRow row) => Task(
        id: row.id,
        title: row.title,
        description: row.description,
        startTime: row.startTime,
        endTime: row.endTime,
        estimatedDurationMin: row.estimatedDurationMin,
        actualDurationMin: row.actualDurationMin,
        categoryId: row.categoryId,
        priority: Priority.fromDb(row.priority),
        status: TaskStatus.fromDb(row.status),
        notes: row.notes,
        recurringRuleId: row.recurringRuleId,
        rescheduledFromId: row.rescheduledFromId,
        rescheduledToId: row.rescheduledToId,
        isInbox: row.isInbox,
        missedAt: row.missedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  static TasksCompanion _toCompanion(Task t) => TasksCompanion.insert(
        id: t.id,
        title: t.title,
        description: Value(t.description),
        startTime: Value(t.startTime),
        endTime: Value(t.endTime),
        estimatedDurationMin: Value(t.estimatedDurationMin),
        actualDurationMin: Value(t.actualDurationMin),
        categoryId: Value(t.categoryId),
        priority: Value(t.priority.dbValue),
        status: Value(t.status.dbValue),
        notes: Value(t.notes),
        recurringRuleId: Value(t.recurringRuleId),
        rescheduledFromId: Value(t.rescheduledFromId),
        rescheduledToId: Value(t.rescheduledToId),
        isInbox: Value(t.isInbox),
        missedAt: Value(t.missedAt),
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: Value(t.deletedAt),
      );

  static TaskRow _toRow(Task t, {int syncStatus = 0, int revision = 1}) =>
      TaskRow(
        id: t.id,
        title: t.title,
        description: t.description,
        startTime: t.startTime,
        endTime: t.endTime,
        estimatedDurationMin: t.estimatedDurationMin,
        actualDurationMin: t.actualDurationMin,
        categoryId: t.categoryId,
        priority: t.priority.dbValue,
        status: t.status.dbValue,
        notes: t.notes,
        recurringRuleId: t.recurringRuleId,
        rescheduledFromId: t.rescheduledFromId,
        rescheduledToId: t.rescheduledToId,
        isInbox: t.isInbox,
        missedAt: t.missedAt,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: t.deletedAt,
        syncStatus: syncStatus,
        revision: revision,
      );
}
