import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/task_dao.dart';
import '../../../core/models/enums/priority.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/acyclic_links.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';

class TaskRepository {
  final AppDatabase _db;

  TaskRepository(this._db);

  TaskDao get _dao => _db.taskDao;

  AppDatabase get database => _db;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Future<Task> insertTask(Task task) async {
    final now = DateTime.now();
    final effective = _normalizeScheduling(task).copyWith(
      id: task.id.isEmpty ? generateUuidV7() : task.id,
      createdAt: task.createdAt,
      updatedAt: now,
    );
    _validate(effective);
    await _db.transaction(() async {
      await _validateHistoryLinks(effective);
      await _dao.insertTask(_toCompanion(effective));
      await _invalidateStatsForIntervals([
        (effective.startTime, effective.endTime),
      ]);
    });
    return effective;
  }

  Future<Task> updateTask(
    Task task, {
    bool allowRescheduledTransition = false,
    bool allowStatusTransition = false,
  }) async {
    final now = DateTime.now();
    final effective = _normalizeScheduling(task).copyWith(updatedAt: now);
    final row = await _dao.getTaskById(effective.id);
    if (row == null) {
      throw StateError('Task ${effective.id} not found');
    }
    final previousStatus = TaskStatus.fromDb(row.status);
    if (!allowStatusTransition &&
        !previousStatus.canTransitionTo(effective.status) &&
        !(allowRescheduledTransition &&
            effective.status == TaskStatus.rescheduled)) {
      throw StateError(
        'Cannot change ${previousStatus.label} to ${effective.status.label}',
      );
    }
    _validate(effective);
    await _db.transaction(() async {
      await _validateHistoryLinks(effective);
      await _dao.updateTask(
        _toRow(effective, syncStatus: 1, revision: row.revision + 1),
      );
      await _invalidateStatsForIntervals([
        (row.startTime, row.endTime),
        (effective.startTime, effective.endTime),
      ]);
    });
    return effective;
  }

  Future<void> deleteTask(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    if (row == null || row.deletedAt != null) return;
    final now = DateTime.now();
    await _db.transaction(() async {
      await _dao.updateTask(
        row.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          syncStatus: 1,
          revision: row.revision + 1,
        ),
      );
      await _invalidateStatsForIntervals([(row.startTime, row.endTime)]);
    });
  }

  Future<Task> restoreTask(Task task) =>
      updateTask(task.copyWith(deletedAt: null), allowStatusTransition: true);

  /// The only repository operation that may transition an unfinished task
  /// into the rescheduled state.
  Future<Task> markRescheduled(String taskId, String successorId) async {
    final row = await _dao.getTaskById(taskId);
    if (row == null) throw StateError('Task $taskId not found');
    final task = fromRow(row);
    if (task.status != TaskStatus.planned &&
        task.status != TaskStatus.inProgress) {
      throw StateError('Only unfinished tasks can be rescheduled');
    }
    return updateTask(
      task.copyWith(
        status: TaskStatus.rescheduled,
        rescheduledToId: successorId,
      ),
      allowRescheduledTransition: true,
    );
  }

  /// Permanently removes the row (used to undo task creation).
  Future<void> hardDeleteTask(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    await _db.transaction(() async {
      await _dao.hardDeleteTask(taskId);
      await _invalidateStatsForIntervals([(row?.startTime, row?.endTime)]);
    });
  }

  Stream<List<Task>> watchTasksForDay(DateTime date) => _dao
      .watchTasksForDay(date)
      .map((rows) => rows.map(TaskRepository.fromRow).toList());

  Future<Task?> getTaskById(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    return row == null ? null : fromRow(row);
  }

  /// Scheduled, active tasks intersecting the local interval [start, end).
  /// The DAO owns the interval and soft-delete predicates.
  Future<List<Task>> getScheduledTasksBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _dao.getTasksBetween(start, end);
    return rows.map(fromRow).toList(growable: false);
  }

  Future<void> _invalidateStatsForIntervals(
    Iterable<(DateTime? start, DateTime? end)> intervals,
  ) async {
    final dateIsos = <String>{};
    for (final (start, end) in intervals) {
      if (start == null) continue;
      if (end == null) {
        dateIsos.add(isoDateString(start));
        continue;
      }
      var day = startOfDay(start);
      while (day.isBefore(end)) {
        dateIsos.add(isoDateString(day));
        day = addDays(day, 1);
      }
    }
    for (final dateIso in dateIsos) {
      await _db.statsDao.invalidateForDate(dateIso);
    }
  }

  static Task fromRow(TaskRow row) => Task(
    id: row.id,
    title: row.title,
    description: row.description,
    startTime: row.startTime,
    endTime: row.endTime,
    estimatedDurationMin: row.estimatedDurationMin,
    actualDurationMin: row.actualDurationMin,
    manualDurationAdjustmentMin: row.manualDurationAdjustmentMin,
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
    manualDurationAdjustmentMin: Value(t.manualDurationAdjustmentMin),
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
    syncStatus: const Value(1),
    revision: const Value(1),
  );

  static void _validate(Task task) {
    if (task.title.trim().isEmpty) {
      throw ArgumentError.value(task.title, 'title', 'must not be blank');
    }
    if (task.estimatedDurationMin != null && task.estimatedDurationMin! <= 0) {
      throw ArgumentError.value(
        task.estimatedDurationMin,
        'estimatedDurationMin',
        'must be positive',
      );
    }
    if (task.actualDurationMin != null && task.actualDurationMin! < 0) {
      throw ArgumentError.value(
        task.actualDurationMin,
        'actualDurationMin',
        'must not be negative',
      );
    }
    if (task.endTime != null && task.startTime == null) {
      throw ArgumentError('endTime requires startTime');
    }
    if (task.startTime != null &&
        task.endTime != null &&
        !task.endTime!.isAfter(task.startTime!)) {
      throw ArgumentError('endTime must be later than startTime');
    }
  }

  /// Applies the Inbox invariant at the repository boundary. A scheduled
  /// task is never left marked as Inbox, and an Inbox task never retains stale
  /// schedule values from an earlier edit.
  static Task _normalizeScheduling(Task task) {
    if (task.isInbox) {
      return task.copyWith(startTime: null, endTime: null);
    }
    if (task.startTime != null || task.endTime != null) {
      return task.copyWith(isInbox: false);
    }
    return task;
  }

  /// History links form a single directed successor chain. Check the
  /// complete proposed graph in the same SQLite transaction so self-links,
  /// direct cycles, and longer remote/local cycles cannot be committed.
  Future<void> _validateHistoryLinks(Task proposed) async {
    final rows = await (_db.select(_db.tasks)).get();
    final graph = <String, Set<String>>{
      for (final row in rows) row.id: <String>{},
    };
    for (final row in rows) {
      if (row.rescheduledToId != null) {
        graph[row.id]!.add(row.rescheduledToId!);
      }
      if (row.rescheduledFromId != null) {
        graph.putIfAbsent(row.rescheduledFromId!, () => <String>{}).add(row.id);
      }
    }
    graph[proposed.id] = <String>{};
    if (proposed.rescheduledToId != null) {
      graph[proposed.id]!.add(proposed.rescheduledToId!);
    }
    if (proposed.rescheduledFromId != null) {
      graph
          .putIfAbsent(proposed.rescheduledFromId!, () => <String>{})
          .add(proposed.id);
    }
    validateAcyclicLinks(graph);
  }

  static TaskRow _toRow(Task t, {int syncStatus = 0, int revision = 1}) =>
      TaskRow(
        id: t.id,
        title: t.title,
        description: t.description,
        startTime: t.startTime,
        endTime: t.endTime,
        estimatedDurationMin: t.estimatedDurationMin,
        actualDurationMin: t.actualDurationMin,
        manualDurationAdjustmentMin: t.manualDurationAdjustmentMin,
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
