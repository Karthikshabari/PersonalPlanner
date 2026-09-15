import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/task_dao.dart';
import '../../../core/models/enums/priority.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/acyclic_links.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import '../../timer/data/timer_repository.dart';
import '../../timer/domain/timer_service.dart';
import '../../task_editor/domain/plan_title_history.dart';

class TaskRepository {
  final AppDatabase _db;
  final DateTime Function() _clock;

  TaskRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  TaskDao get _dao => _db.taskDao;

  AppDatabase get database => _db;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Future<Task> insertTask(Task task) async {
    final now = _clock();
    // A caller that supplies an initial Actual value is creating a manual
    // source, not a second writable cache. This preserves older import/test
    // callers while keeping the source/cache invariant from the first row.
    final hasInitialManualSource =
        task.manualActualSet ||
        task.manualDurationAdjustmentMin != 0 ||
        task.actualDurationMin != null;
    // An explicit signed source (for example an imported legacy row) wins
    // over the compatibility cache. A cache with no source is adapted as an
    // initial desired manual total.
    final initialAdjustment =
        task.manualActualSet || task.manualDurationAdjustmentMin != 0
        ? task.manualDurationAdjustmentMin
        : (task.actualDurationMin ?? 0);
    final effective = _normalizeScheduling(task).copyWith(
      id: task.id.isEmpty ? generateUuidV7() : task.id,
      createdAt: task.createdAt,
      updatedAt: now,
      manualDurationAdjustmentMin: hasInitialManualSource
          ? initialAdjustment
          : 0,
      manualActualSet: hasInitialManualSource,
      actualDurationMin: hasInitialManualSource
          ? initialAdjustment.clamp(0, 1 << 31).toInt()
          : null,
    );
    _validate(effective);
    await _db.transaction(() async {
      await _validateHistoryLinks(effective);
      await _dao.insertTask(_toCompanion(effective));
      await TaskActualDurationService(_db)
          .recomputeTaskInTransaction(effective.id);
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
    int? expectedRevision,
  }) async {
    final now = _clock();
    final effective = _normalizeScheduling(task).copyWith(updatedAt: now);
    _validate(effective);
    final terminalStatus = _isTerminalStatus(effective.status);
    final ownerDeviceId = terminalStatus
        ? await TimerRepository(_db).localDeviceId()
        : null;
    late TaskRow row;
    late Task persisted;
    await _db.transaction(() async {
      final current = await _dao.getTaskById(effective.id);
      if (current == null) {
        throw StateError('Task ${effective.id} not found');
      }
      row = current;
      if (expectedRevision != null && current.revision != expectedRevision) {
        throw StateError(
          'Task ${effective.id} changed while it was being edited; reload it before saving.',
        );
      }
      // actual_duration_min is a derived cache and the manual source has a
      // dedicated desired-total API. Ordinary editor/status/schedule updates
      // must never replay an older cached aggregate over newly finished work.
      final canonical = effective.copyWith(
        actualDurationMin: current.actualDurationMin,
        manualDurationAdjustmentMin: current.manualDurationAdjustmentMin,
        manualActualSet: current.manualActualSet,
      );
      PlanTitleHistory.validateTransition(
        previous: PlanTitleHistory.decodeJson(current.planTitleHistoryJson),
        next: canonical.planTitleHistory,
      );
      final previousStatus = TaskStatus.fromDb(current.status);
      if (!allowStatusTransition &&
          !previousStatus.canTransitionTo(canonical.status) &&
          !(allowRescheduledTransition &&
              canonical.status == TaskStatus.rescheduled)) {
        throw StateError(
          'Cannot change ${previousStatus.label} to ${canonical.status.label}',
        );
      }
      await _validateHistoryLinks(canonical, previous: row);
      if (ownerDeviceId != null) {
        await TimerService(_db)
            .stopOwnedTaskInTransaction(canonical.id, ownerDeviceId, now);
      }
      // Stop recomputes the derived Actual cache from the now-finished timer
      // source. Reload it before the full task write so this status update
      // cannot replay the pre-stop cache captured above.
      final accounting = await _dao.getTaskById(effective.id) ?? current;
      final finalTask = canonical.copyWith(
        actualDurationMin: accounting.actualDurationMin,
        manualDurationAdjustmentMin: accounting.manualDurationAdjustmentMin,
        manualActualSet: accounting.manualActualSet,
      );
      await _dao.updateTask(
        _toRow(finalTask, syncStatus: 1, revision: row.revision + 1),
      );
      await _invalidateStatsForIntervals([
        (row.startTime, row.endTime),
        (canonical.startTime, canonical.endTime),
      ]);
      persisted = fromRow(
        await _dao.getTaskById(effective.id) ??
            _toRow(finalTask, syncStatus: 1, revision: row.revision + 1),
      );
    });
    return persisted;
  }

  Future<void> deleteTask(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    if (row == null || row.deletedAt != null) return;
    final now = _clock();
    final ownerDeviceId = await TimerRepository(_db).localDeviceId();
    await _db.transaction(() async {
      await TimerService(_db)
          .stopOwnedTaskInTransaction(taskId, ownerDeviceId, now);
      await TaskActualDurationService(_db).recomputeTaskInTransaction(taskId);
      final refreshed = await _dao.getTaskById(taskId) ?? row;
      await _dao.updateTask(
        refreshed.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          syncStatus: 1,
          revision: refreshed.revision + 1,
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

  static bool _isTerminalStatus(TaskStatus status) =>
      status == TaskStatus.completed ||
      status == TaskStatus.skipped ||
      status == TaskStatus.cancelled ||
      status == TaskStatus.rescheduled;

  Stream<List<Task>> watchTasksForDay(DateTime date) => _dao
      .watchTasksForDay(date)
      .map((rows) => rows.map(TaskRepository.fromRow).toList());

  Future<Task?> getTaskById(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    return row == null ? null : fromRow(row);
  }

  /// Reads the domain task and its persistence revision as one snapshot. UI
  /// editors use the revision for an optimistic compare-and-swap at save time.
  Future<(Task task, int revision)?> getTaskWithRevision(String taskId) async {
    final row = await _dao.getTaskById(taskId);
    return row == null ? null : (fromRow(row), row.revision);
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

  Future<Map<String, int>> getTaskRevisions(Iterable<String> taskIds) async {
    final ids = taskIds.toSet();
    if (ids.isEmpty) return const <String, int>{};
    final rows = await (_db.select(
      _db.tasks,
    )..where((task) => task.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row.revision};
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
    manualActualSet: row.manualActualSet,
    categoryId: row.categoryId,
    priority: Priority.fromDb(row.priority),
    status: TaskStatus.fromDb(row.status),
    notes: row.notes,
    recurringRuleId: row.recurringRuleId,
    rescheduledFromId: row.rescheduledFromId,
    rescheduledToId: row.rescheduledToId,
    isInbox: row.isInbox,
    inboxContentVersion: row.inboxContentVersion,
    dueDate: row.dueDate,
    missedAt: row.missedAt,
    planTitleHistory: PlanTitleHistory.decodeJson(row.planTitleHistoryJson),
    displayPlanChangeId: row.displayPlanChangeId,
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
    manualActualSet: Value(t.manualActualSet),
    categoryId: Value(t.categoryId),
    priority: Value(t.priority.dbValue),
    status: Value(t.status.dbValue),
    notes: Value(t.notes),
    recurringRuleId: Value(t.recurringRuleId),
    rescheduledFromId: Value(t.rescheduledFromId),
    rescheduledToId: Value(t.rescheduledToId),
    isInbox: Value(t.isInbox),
    inboxContentVersion: Value(t.inboxContentVersion),
    dueDate: Value(t.dueDate),
    missedAt: Value(t.missedAt),
    planTitleHistoryJson: Value(
      PlanTitleHistory.encodeJson(t.planTitleHistory),
    ),
    displayPlanChangeId: Value(t.displayPlanChangeId),
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
    if (task.inboxContentVersion != 0 && task.inboxContentVersion != 1) {
      throw ArgumentError.value(
        task.inboxContentVersion,
        'inboxContentVersion',
        'must be 0 or 1',
      );
    }
    if (task.dueDate != null && !isValidIsoDate(task.dueDate!)) {
      throw ArgumentError.value(
        task.dueDate,
        'dueDate',
        'must be a valid yyyy-MM-dd date',
      );
    }
    PlanTitleHistory.validate(
      task.planTitleHistory,
      displayPlanChangeId: task.displayPlanChangeId,
      currentTitle: task.title,
    );
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
      return task.copyWith(
        startTime: null,
        endTime: null,
        estimatedDurationMin: null,
      );
    }
    final projection = TaskTimeMetrics.plannedMinutes(
      task.startTime,
      task.endTime,
    );
    if (task.startTime != null || task.endTime != null) {
      return task.copyWith(isInbox: false, estimatedDurationMin: projection);
    }
    return task.copyWith(estimatedDurationMin: null);
  }

  /// History links form a single directed successor chain. Check the
  /// complete proposed graph in the same SQLite transaction so self-links,
  /// direct cycles, and longer remote/local cycles cannot be committed.
  Future<void> _validateHistoryLinks(Task proposed, {TaskRow? previous}) async {
    // Title/status/schedule edits do not change the relationship graph. Do
    // not rescan unrelated history for those ordinary mutations; relationship
    // changes still validate the complete graph in the same transaction.
    if (previous != null &&
        previous.rescheduledFromId == proposed.rescheduledFromId &&
        previous.rescheduledToId == proposed.rescheduledToId) {
      return;
    }
    if (previous == null &&
        proposed.rescheduledFromId == null &&
        proposed.rescheduledToId == null) {
      return;
    }
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
        manualActualSet: t.manualActualSet,
        categoryId: t.categoryId,
        priority: t.priority.dbValue,
        status: t.status.dbValue,
        notes: t.notes,
        recurringRuleId: t.recurringRuleId,
        rescheduledFromId: t.rescheduledFromId,
        rescheduledToId: t.rescheduledToId,
        isInbox: t.isInbox,
        inboxContentVersion: t.inboxContentVersion,
        dueDate: t.dueDate,
        missedAt: t.missedAt,
        planTitleHistoryJson: PlanTitleHistory.encodeJson(t.planTitleHistory),
        displayPlanChangeId: t.displayPlanChangeId,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: t.deletedAt,
        syncStatus: syncStatus,
        revision: revision,
      );
}
