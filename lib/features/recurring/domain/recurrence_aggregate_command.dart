import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../../core/utils/uuid.dart';
import '../../task_editor/domain/plan_title_history.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import '../../timeline/domain/commands/scheduling_command.dart';
import 'rrule_utils.dart';

/// Snapshot of a recurring rule and every materialized task aggregate that it
/// owns. Recurrence edits/deletes use this as one reversible history entry.
class RecurrenceAggregateSnapshot {
  final RecurringRuleRow rule;
  final List<TaskRow> tasks;
  final List<SubtaskRow> subtasks;
  final List<TaskTagRow> taskTags;

  const RecurrenceAggregateSnapshot({
    required this.rule,
    required this.tasks,
    required this.subtasks,
    required this.taskTags,
  });

  static Future<RecurrenceAggregateSnapshot?> capture(
    AppDatabase db,
    String ruleId, {
    Set<String> extraTaskIds = const <String>{},
  }) async {
    final rule = await db.recurringRuleDao.getRuleById(ruleId);
    if (rule == null) return null;
    final tasks =
        await (db.select(db.tasks)..where(
              (task) =>
                  task.recurringRuleId.equals(ruleId) |
                  task.id.isIn(extraTaskIds),
            ))
            .get();
    final taskIds = tasks.map((task) => task.id).toSet();
    final subtasks = taskIds.isEmpty
        ? <SubtaskRow>[]
        : await (db.select(
            db.subtasks,
          )..where((row) => row.taskId.isIn(taskIds))).get();
    final taskTags = taskIds.isEmpty
        ? <TaskTagRow>[]
        : await (db.select(
            db.taskTags,
          )..where((row) => row.taskId.isIn(taskIds))).get();
    return RecurrenceAggregateSnapshot(
      rule: rule,
      tasks: tasks,
      subtasks: subtasks,
      taskTags: taskTags,
    );
  }

  Future<void> restore(
    AppDatabase db, {
    RecurrenceAggregateSnapshot? after,
  }) async {
    if (after == null) {
      throw StateError('Recurrence Undo is missing its post-command snapshot');
    }
    final beforeTasks = {for (final row in tasks) row.id: row};
    final afterTasks = {for (final row in after.tasks) row.id: row};
    final taskIds = {...beforeTasks.keys, ...afterTasks.keys};
    final currentTasks = taskIds.isEmpty
        ? <TaskRow>[]
        : await (db.select(
            db.tasks,
          )..where((row) => row.id.isIn(taskIds))).get();
    final currentTaskById = {for (final row in currentTasks) row.id: row};

    final beforeSubtasks = {for (final row in subtasks) row.id: row};
    final afterSubtasks = {for (final row in after.subtasks) row.id: row};
    final subtaskIds = {...beforeSubtasks.keys, ...afterSubtasks.keys};
    final currentSubtasks = subtaskIds.isEmpty
        ? <SubtaskRow>[]
        : await (db.select(
            db.subtasks,
          )..where((row) => row.id.isIn(subtaskIds))).get();
    final currentSubtaskById = {for (final row in currentSubtasks) row.id: row};

    String tagKey(TaskTagRow row) => '${row.taskId}:${row.tagId}';
    final beforeTags = {for (final row in taskTags) tagKey(row): row};
    final afterTags = {for (final row in after.taskTags) tagKey(row): row};
    final currentTags = taskIds.isEmpty
        ? <TaskTagRow>[]
        : await (db.select(
            db.taskTags,
          )..where((row) => row.taskId.isIn(taskIds))).get();
    final currentTagByKey = {for (final row in currentTags) tagKey(row): row};

    final currentRule = await db.recurringRuleDao.getRuleById(rule.id);
    final conflicts = <String>[];
    if (currentRule == null ||
        !_ruleOwnedFieldsMatch(currentRule, rule, after.rule)) {
      conflicts.add('recurring rule ${rule.id}');
    }
    for (final id in taskIds) {
      final current = currentTaskById[id];
      final beforeRow = beforeTasks[id];
      final afterRow = afterTasks[id];
      if (current == null || afterRow == null) {
        conflicts.add('task $id');
      } else if (beforeRow == null
          ? !_sameTaskCreationSemantics(current, afterRow)
          : !_taskOwnedFieldsMatch(current, beforeRow, afterRow)) {
        conflicts.add('task $id');
      }
    }
    for (final id in subtaskIds) {
      final current = currentSubtaskById[id];
      final beforeRow = beforeSubtasks[id];
      final afterRow = afterSubtasks[id];
      if (current == null || afterRow == null) {
        conflicts.add('subtask $id');
      } else if (beforeRow == null &&
          !beforeTasks.containsKey(afterRow.taskId)) {
        conflicts.add('subtask $id');
      } else if (beforeRow == null
          ? !_sameSubtaskSemantics(current, afterRow)
          : !_subtaskOwnedFieldsMatch(current, beforeRow, afterRow)) {
        conflicts.add('subtask $id');
      }
    }
    for (final key in {...beforeTags.keys, ...afterTags.keys}) {
      final current = currentTagByKey[key];
      final beforeRow = beforeTags[key];
      final afterRow = afterTags[key];
      if (current == null || afterRow == null) {
        conflicts.add('task tag $key');
      } else if (beforeRow == null &&
          !beforeTasks.containsKey(afterRow.taskId) &&
          !JsonListUtils.decode(after.rule.tagsJson).contains(afterRow.tagId)) {
        conflicts.add('task tag $key');
      } else if (beforeRow == null
          ? !_sameTaskTagSemantics(current, afterRow)
          : !_taskTagOwnedFieldsMatch(current, beforeRow, afterRow)) {
        conflicts.add('task tag $key');
      }
    }
    if (conflicts.isNotEmpty) {
      throw StateError(
        'Cannot undo recurrence change because newer user edits affect: '
        '${conflicts.join(', ')}',
      );
    }

    final now = DateTime.now().toUtc();
    if (_ruleHasOwnedChanges(rule, after.rule)) {
      await db.recurringRuleDao.updateRule(
        _mergeRuleForUndo(currentRule!, rule, after.rule, now),
      );
    }
    for (final entry in beforeTasks.entries) {
      final current = currentTaskById[entry.key]!;
      final afterRow = afterTasks[entry.key]!;
      if (_taskHasOwnedChanges(entry.value, afterRow)) {
        await db.taskDao.updateTask(
          _mergeTaskForUndo(current, entry.value, afterRow, now),
        );
      }
    }
    for (final entry in afterTasks.entries) {
      if (beforeTasks.containsKey(entry.key)) continue;
      final current = currentTaskById[entry.key]!;
      if (RecurrenceAggregateCommand._ruleIncludesOccurrence(rule, current)) {
        await db.taskDao.updateTask(
          RecurrenceAggregateCommand._expectedLateTask(current, rule).copyWith(
            updatedAt: now,
            syncStatus: 1,
            revision: current.revision + 1,
          ),
        );
        continue;
      }
      await db.taskDao.updateTask(
        current.copyWith(
          deletedAt: Value(now),
          recurrenceRemovalReason: const Value('rule_excluded'),
          updatedAt: now,
          syncStatus: 1,
          revision: current.revision + 1,
        ),
      );
    }
    for (final entry in beforeSubtasks.entries) {
      final current = currentSubtaskById[entry.key]!;
      final afterRow = afterSubtasks[entry.key]!;
      if (_subtaskHasOwnedChanges(entry.value, afterRow)) {
        await db.subtaskDao.updateSubtask(
          _mergeSubtaskForUndo(current, entry.value, afterRow, now),
        );
      }
    }
    for (final entry in afterSubtasks.entries) {
      if (beforeSubtasks.containsKey(entry.key)) continue;
      final current = currentSubtaskById[entry.key]!;
      await db.subtaskDao.updateSubtask(
        current.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          syncStatus: 1,
          revision: current.revision + 1,
        ),
      );
    }
    for (final entry in beforeTags.entries) {
      final current = currentTagByKey[entry.key]!;
      final afterRow = afterTags[entry.key]!;
      if (_taskTagHasOwnedChanges(entry.value, afterRow)) {
        await _writeTaskTag(
          db,
          _mergeTaskTagForUndo(current, entry.value, afterRow, now),
        );
      }
    }
    for (final entry in afterTags.entries) {
      if (beforeTags.containsKey(entry.key)) continue;
      final current = currentTagByKey[entry.key]!;
      final lateTask = !beforeTasks.containsKey(current.taskId);
      if (lateTask &&
          RecurrenceAggregateCommand._ruleIncludesOccurrence(
            rule,
            currentTaskById[current.taskId]!,
          ) &&
          JsonListUtils.decode(rule.tagsJson).contains(current.tagId)) {
        continue;
      }
      await _writeTaskTag(
        db,
        current.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          syncStatus: 1,
          revision: current.revision + 1,
        ),
      );
    }
    // Actual Duration is a derived cache. Timer rows are never snapshotted or
    // replaced; recalculate only after the semantic task sources are restored.
    await TaskActualDurationService(db).recomputeTasks(taskIds);
  }

  static bool _owned<T>(T current, T before, T after) =>
      before == after || current == after;

  static T _undoValue<T>(T current, T before, T after) =>
      before == after ? current : before;

  static bool _ruleOwnedFieldsMatch(
    RecurringRuleRow current,
    RecurringRuleRow before,
    RecurringRuleRow after,
  ) =>
      _owned(current.rrule, before.rrule, after.rrule) &&
      _owned(current.taskTitle, before.taskTitle, after.taskTitle) &&
      _owned(
        current.taskDescription,
        before.taskDescription,
        after.taskDescription,
      ) &&
      _owned(current.durationMin, before.durationMin, after.durationMin) &&
      _owned(current.categoryId, before.categoryId, after.categoryId) &&
      _owned(current.priority, before.priority, after.priority) &&
      _owned(current.tagsJson, before.tagsJson, after.tagsJson) &&
      _owned(
        current.startTimeOfDay,
        before.startTimeOfDay,
        after.startTimeOfDay,
      ) &&
      _owned(current.startDate, before.startDate, after.startDate) &&
      _owned(current.endDate, before.endDate, after.endDate) &&
      _owned(current.isActive, before.isActive, after.isActive) &&
      _owned(
        current.exceptionsJson,
        before.exceptionsJson,
        after.exceptionsJson,
      ) &&
      _owned(current.deletedAt, before.deletedAt, after.deletedAt);

  static bool _ruleHasOwnedChanges(
    RecurringRuleRow before,
    RecurringRuleRow after,
  ) => !_ruleOwnedFieldsMatch(before, before, after);

  static RecurringRuleRow _mergeRuleForUndo(
    RecurringRuleRow current,
    RecurringRuleRow before,
    RecurringRuleRow after,
    DateTime now,
  ) => current.copyWith(
    rrule: _undoValue(current.rrule, before.rrule, after.rrule),
    taskTitle: _undoValue(current.taskTitle, before.taskTitle, after.taskTitle),
    taskDescription: Value(
      _undoValue(
        current.taskDescription,
        before.taskDescription,
        after.taskDescription,
      ),
    ),
    durationMin: _undoValue(
      current.durationMin,
      before.durationMin,
      after.durationMin,
    ),
    categoryId: Value(
      _undoValue(current.categoryId, before.categoryId, after.categoryId),
    ),
    priority: _undoValue(current.priority, before.priority, after.priority),
    tagsJson: Value(
      _undoValue(current.tagsJson, before.tagsJson, after.tagsJson),
    ),
    startTimeOfDay: _undoValue(
      current.startTimeOfDay,
      before.startTimeOfDay,
      after.startTimeOfDay,
    ),
    startDate: _undoValue(current.startDate, before.startDate, after.startDate),
    endDate: Value(_undoValue(current.endDate, before.endDate, after.endDate)),
    isActive: _undoValue(current.isActive, before.isActive, after.isActive),
    exceptionsJson: Value(
      _undoValue(
        current.exceptionsJson,
        before.exceptionsJson,
        after.exceptionsJson,
      ),
    ),
    deletedAt: Value(
      _undoValue(current.deletedAt, before.deletedAt, after.deletedAt),
    ),
    updatedAt: now,
    syncStatus: 1,
    revision: current.revision + 1,
  );

  static bool _taskOwnedFieldsMatch(TaskRow c, TaskRow b, TaskRow a) =>
      _owned(c.title, b.title, a.title) &&
      _owned(c.description, b.description, a.description) &&
      _owned(c.startTime, b.startTime, a.startTime) &&
      _owned(c.endTime, b.endTime, a.endTime) &&
      _owned(
        c.manualDurationAdjustmentMin,
        b.manualDurationAdjustmentMin,
        a.manualDurationAdjustmentMin,
      ) &&
      _owned(c.manualActualSet, b.manualActualSet, a.manualActualSet) &&
      _owned(c.categoryId, b.categoryId, a.categoryId) &&
      _owned(c.priority, b.priority, a.priority) &&
      _owned(c.status, b.status, a.status) &&
      _owned(c.notes, b.notes, a.notes) &&
      _owned(c.recurringRuleId, b.recurringRuleId, a.recurringRuleId) &&
      _owned(
        c.recurrenceRemovalReason,
        b.recurrenceRemovalReason,
        a.recurrenceRemovalReason,
      ) &&
      _owned(c.rescheduledFromId, b.rescheduledFromId, a.rescheduledFromId) &&
      _owned(c.rescheduledToId, b.rescheduledToId, a.rescheduledToId) &&
      _owned(c.isInbox, b.isInbox, a.isInbox) &&
      _owned(
        c.inboxContentVersion,
        b.inboxContentVersion,
        a.inboxContentVersion,
      ) &&
      _owned(c.dueDate, b.dueDate, a.dueDate) &&
      _owned(c.missedAt, b.missedAt, a.missedAt) &&
      _owned(
        c.displayPlanChangeId,
        b.displayPlanChangeId,
        a.displayPlanChangeId,
      ) &&
      _owned(c.deletedAt, b.deletedAt, a.deletedAt);

  static bool _taskHasOwnedChanges(TaskRow b, TaskRow a) =>
      !_taskOwnedFieldsMatch(b, b, a) ||
      b.planTitleHistoryJson != a.planTitleHistoryJson;

  static bool _sameTaskCreationSemantics(TaskRow c, TaskRow a) =>
      c.title == a.title &&
      c.description == a.description &&
      c.startTime == a.startTime &&
      c.endTime == a.endTime &&
      c.manualDurationAdjustmentMin == a.manualDurationAdjustmentMin &&
      c.manualActualSet == a.manualActualSet &&
      c.categoryId == a.categoryId &&
      c.priority == a.priority &&
      c.status == a.status &&
      c.notes == a.notes &&
      c.recurringRuleId == a.recurringRuleId &&
      c.recurrenceRemovalReason == a.recurrenceRemovalReason &&
      c.rescheduledFromId == a.rescheduledFromId &&
      c.rescheduledToId == a.rescheduledToId &&
      c.isInbox == a.isInbox &&
      c.inboxContentVersion == a.inboxContentVersion &&
      c.dueDate == a.dueDate &&
      c.missedAt == a.missedAt &&
      c.planTitleHistoryJson == a.planTitleHistoryJson &&
      c.displayPlanChangeId == a.displayPlanChangeId &&
      c.deletedAt == a.deletedAt;

  static TaskRow _mergeTaskForUndo(
    TaskRow c,
    TaskRow b,
    TaskRow a,
    DateTime now,
  ) {
    final history = b.planTitleHistoryJson == a.planTitleHistoryJson
        ? PlanTitleHistory.decodeJson(c.planTitleHistoryJson)
        : PlanTitleHistory.revertedForUndo(
            before: PlanTitleHistory.decodeJson(b.planTitleHistoryJson),
            after: PlanTitleHistory.decodeJson(a.planTitleHistoryJson),
            current: PlanTitleHistory.decodeJson(c.planTitleHistoryJson),
            now: now,
          );
    final start = _undoValue(c.startTime, b.startTime, a.startTime);
    final end = _undoValue(c.endTime, b.endTime, a.endTime);
    final isInbox = _undoValue(c.isInbox, b.isInbox, a.isInbox);
    return c.copyWith(
      title: _undoValue(c.title, b.title, a.title),
      description: Value(
        _undoValue(c.description, b.description, a.description),
      ),
      startTime: Value(start),
      endTime: Value(end),
      estimatedDurationMin: Value(
        isInbox ? null : TaskTimeMetrics.plannedMinutes(start, end),
      ),
      manualDurationAdjustmentMin: _undoValue(
        c.manualDurationAdjustmentMin,
        b.manualDurationAdjustmentMin,
        a.manualDurationAdjustmentMin,
      ),
      manualActualSet: _undoValue(
        c.manualActualSet,
        b.manualActualSet,
        a.manualActualSet,
      ),
      categoryId: Value(_undoValue(c.categoryId, b.categoryId, a.categoryId)),
      priority: _undoValue(c.priority, b.priority, a.priority),
      status: _undoValue(c.status, b.status, a.status),
      notes: Value(_undoValue(c.notes, b.notes, a.notes)),
      recurringRuleId: Value(
        _undoValue(c.recurringRuleId, b.recurringRuleId, a.recurringRuleId),
      ),
      recurrenceRemovalReason: Value(
        _undoValue(
          c.recurrenceRemovalReason,
          b.recurrenceRemovalReason,
          a.recurrenceRemovalReason,
        ),
      ),
      rescheduledFromId: Value(
        _undoValue(
          c.rescheduledFromId,
          b.rescheduledFromId,
          a.rescheduledFromId,
        ),
      ),
      rescheduledToId: Value(
        _undoValue(c.rescheduledToId, b.rescheduledToId, a.rescheduledToId),
      ),
      isInbox: isInbox,
      inboxContentVersion: _undoValue(
        c.inboxContentVersion,
        b.inboxContentVersion,
        a.inboxContentVersion,
      ),
      dueDate: Value(_undoValue(c.dueDate, b.dueDate, a.dueDate)),
      missedAt: Value(_undoValue(c.missedAt, b.missedAt, a.missedAt)),
      planTitleHistoryJson: PlanTitleHistory.encodeJson(history),
      displayPlanChangeId: Value(
        _undoValue(
          c.displayPlanChangeId,
          b.displayPlanChangeId,
          a.displayPlanChangeId,
        ),
      ),
      deletedAt: Value(_undoValue(c.deletedAt, b.deletedAt, a.deletedAt)),
      updatedAt: now,
      syncStatus: 1,
      revision: c.revision + 1,
    );
  }

  static bool _subtaskOwnedFieldsMatch(
    SubtaskRow c,
    SubtaskRow b,
    SubtaskRow a,
  ) =>
      _owned(c.taskId, b.taskId, a.taskId) &&
      _owned(c.title, b.title, a.title) &&
      _owned(c.isCompleted, b.isCompleted, a.isCompleted) &&
      _owned(c.sortOrder, b.sortOrder, a.sortOrder) &&
      _owned(c.deletedAt, b.deletedAt, a.deletedAt);

  static bool _subtaskHasOwnedChanges(SubtaskRow b, SubtaskRow a) =>
      !_subtaskOwnedFieldsMatch(b, b, a);

  static bool _sameSubtaskSemantics(SubtaskRow c, SubtaskRow a) =>
      c.taskId == a.taskId &&
      c.title == a.title &&
      c.isCompleted == a.isCompleted &&
      c.sortOrder == a.sortOrder &&
      c.deletedAt == a.deletedAt;

  static SubtaskRow _mergeSubtaskForUndo(
    SubtaskRow c,
    SubtaskRow b,
    SubtaskRow a,
    DateTime now,
  ) => c.copyWith(
    taskId: _undoValue(c.taskId, b.taskId, a.taskId),
    title: _undoValue(c.title, b.title, a.title),
    isCompleted: _undoValue(c.isCompleted, b.isCompleted, a.isCompleted),
    sortOrder: _undoValue(c.sortOrder, b.sortOrder, a.sortOrder),
    deletedAt: Value(_undoValue(c.deletedAt, b.deletedAt, a.deletedAt)),
    updatedAt: now,
    syncStatus: 1,
    revision: c.revision + 1,
  );

  static bool _taskTagOwnedFieldsMatch(
    TaskTagRow c,
    TaskTagRow b,
    TaskTagRow a,
  ) => _owned(c.deletedAt, b.deletedAt, a.deletedAt);

  static bool _taskTagHasOwnedChanges(TaskTagRow b, TaskTagRow a) =>
      !_taskTagOwnedFieldsMatch(b, b, a);

  static bool _sameTaskTagSemantics(TaskTagRow c, TaskTagRow a) =>
      c.taskId == a.taskId && c.tagId == a.tagId && c.deletedAt == a.deletedAt;

  static TaskTagRow _mergeTaskTagForUndo(
    TaskTagRow c,
    TaskTagRow b,
    TaskTagRow a,
    DateTime now,
  ) => c.copyWith(
    deletedAt: Value(_undoValue(c.deletedAt, b.deletedAt, a.deletedAt)),
    updatedAt: now,
    syncStatus: 1,
    revision: c.revision + 1,
  );

  static Future<void> _writeTaskTag(AppDatabase db, TaskTagRow row) =>
      (db.update(db.taskTags)..where(
            (candidate) =>
                candidate.taskId.equals(row.taskId) &
                candidate.tagId.equals(row.tagId),
          ))
          .write(
            row
                .toCompanion(false)
                .copyWith(serverVersion: const Value.absent()),
          );
}

/// Executes a recurrence mutation as one history item. The callback is
/// replayed on Redo; Undo restores the complete pre-mutation snapshot.
class RecurrenceAggregateCommand implements SchedulingCommand {
  final AppDatabase database;
  final String ruleId;
  final Future<void> Function() mutation;

  /// Additional task aggregates mutated inside [mutation] (for example,
  /// neighboring blocks shifted by the shared conflict policy). They are
  /// captured here so one editor save remains fully undoable.
  final Set<String> extraTaskIds;
  @override
  final String description;

  RecurrenceAggregateSnapshot? _before;
  RecurrenceAggregateSnapshot? _after;

  RecurrenceAggregateCommand({
    required this.database,
    required this.ruleId,
    required this.mutation,
    required this.description,
    this.extraTaskIds = const <String>{},
  });

  @override
  Future<void> execute() async {
    _before ??= await RecurrenceAggregateSnapshot.capture(
      database,
      ruleId,
      extraTaskIds: extraTaskIds,
    );
    if (_before == null) throw StateError('Recurring rule $ruleId not found');
    await database.transaction(mutation);
    _after = await RecurrenceAggregateSnapshot.capture(
      database,
      ruleId,
      extraTaskIds: {...extraTaskIds, ..._before!.tasks.map((task) => task.id)},
    );
  }

  @override
  Future<void> undo() async {
    await database.transaction(() async {
      final beforeTaskIds =
          _before?.tasks.map((task) => task.id).toSet() ?? const <String>{};
      final current = await RecurrenceAggregateSnapshot.capture(
        database,
        ruleId,
        extraTaskIds: {...extraTaskIds, ...beforeTaskIds},
      );
      // Observe materialized occurrences created after execute() before
      // restoring. Unchanged new rows are part of the edited aggregate and
      // are tombstoned by restore; rows edited independently are preserved by
      // its conditional comparison.
      await _before?.restore(database, after: _mergeLateRows(_after, current));
    });
  }

  static RecurrenceAggregateSnapshot? _mergeLateRows(
    RecurrenceAggregateSnapshot? baseline,
    RecurrenceAggregateSnapshot? current,
  ) {
    if (baseline == null) return current;
    if (current == null) return baseline;
    final tasks = {for (final row in baseline.tasks) row.id: row};
    for (final row in current.tasks) {
      tasks.putIfAbsent(row.id, () => _expectedLateTask(row, baseline.rule));
    }
    final subtasks = {for (final row in baseline.subtasks) row.id: row};
    for (final row in current.subtasks) {
      subtasks.putIfAbsent(row.id, () => row);
    }
    final tags = {
      for (final row in baseline.taskTags) '${row.taskId}:${row.tagId}': row,
    };
    for (final row in current.taskTags) {
      tags.putIfAbsent('${row.taskId}:${row.tagId}', () => row);
    }
    return RecurrenceAggregateSnapshot(
      rule: baseline.rule,
      tasks: tasks.values.toList(growable: false),
      subtasks: subtasks.values.toList(growable: false),
      taskTags: tags.values.toList(growable: false),
    );
  }

  static TaskRow _expectedLateTask(
    TaskRow current,
    RecurringRuleRow generatingRule,
  ) {
    final displayedStart = current.startTime;
    if (displayedStart == null) {
      throw StateError(
        'Cannot undo recurrence change because a late occurrence has no schedule',
      );
    }
    final day = startOfDay(displayedStart);
    final dateIso = isoDateString(day);
    final expectedId = generateDeterministicUuid(
      'recurring-occurrence:${generatingRule.id}:$dateIso',
    );
    if (current.id != expectedId) {
      throw StateError(
        'Cannot undo recurrence change because a late occurrence was moved',
      );
    }
    final parts = generatingRule.startTimeOfDay.split(':');
    final start = PlannerTimeZone.calendarDate(
      day.year,
      day.month,
      day.day,
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    return current.copyWith(
      title: generatingRule.taskTitle,
      description: Value(generatingRule.taskDescription),
      startTime: Value(start),
      endTime: Value(start.add(Duration(minutes: generatingRule.durationMin))),
      manualDurationAdjustmentMin: 0,
      manualActualSet: false,
      categoryId: Value(generatingRule.categoryId),
      priority: generatingRule.priority,
      status: 'planned',
      notes: const Value(null),
      recurringRuleId: Value(generatingRule.id),
      recurrenceRemovalReason: const Value(null),
      rescheduledFromId: const Value(null),
      rescheduledToId: const Value(null),
      isInbox: false,
      inboxContentVersion: 0,
      dueDate: const Value(null),
      missedAt: const Value(null),
      planTitleHistoryJson: '[]',
      displayPlanChangeId: const Value(null),
      deletedAt: const Value(null),
    );
  }

  static bool _ruleIncludesOccurrence(
    RecurringRuleRow candidateRule,
    TaskRow task,
  ) {
    if (!candidateRule.isActive || candidateRule.deletedAt != null) {
      return false;
    }
    final start = task.startTime;
    if (start == null) return false;
    final day = startOfDay(start);
    final dateIso = isoDateString(day);
    if (task.id !=
        generateDeterministicUuid(
          'recurring-occurrence:${candidateRule.id}:$dateIso',
        )) {
      return false;
    }
    if (dateIso.compareTo(candidateRule.startDate) < 0 ||
        candidateRule.endDate != null &&
            dateIso.compareTo(candidateRule.endDate!) > 0 ||
        JsonListUtils.decode(candidateRule.exceptionsJson).contains(dateIso)) {
      return false;
    }
    return RruleUtils.occursOnDate(
      candidateRule.rrule,
      parseIsoDate(candidateRule.startDate),
      day,
    );
  }
}
