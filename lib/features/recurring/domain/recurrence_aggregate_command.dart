import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../task_editor/domain/plan_title_history.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import '../../timeline/domain/commands/scheduling_command.dart';

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
    final currentRule = await db.recurringRuleDao.getRuleById(rule.id);
    if (after == null || currentRule == null || currentRule == after.rule) {
      await db
          .into(db.recurringRules)
          .insertOnConflictUpdate(
            rule
                .toCompanion(false)
                .copyWith(serverVersion: const Value.absent()),
          );
    }

    final beforeTasks = {for (final row in tasks) row.id: row};
    final afterTasks = {
      for (final row in after?.tasks ?? const <TaskRow>[]) row.id: row,
    };
    final taskIds = {...beforeTasks.keys, ...afterTasks.keys};
    final currentTasks = taskIds.isEmpty
        ? <TaskRow>[]
        : await (db.select(
            db.tasks,
          )..where((row) => row.id.isIn(taskIds))).get();
    final currentTaskById = {for (final row in currentTasks) row.id: row};
    final now = DateTime.now().toUtc();
    for (final entry in beforeTasks.entries) {
      final current = currentTaskById[entry.key];
      final afterRow = afterTasks[entry.key];
      if (current == null) {
        final normalized = entry.value.copyWith(
          estimatedDurationMin: Value(
            entry.value.isInbox
                ? null
                : TaskTimeMetrics.plannedMinutes(
                    entry.value.startTime,
                    entry.value.endTime,
                  ),
          ),
        );
        await db
            .into(db.tasks)
            .insertOnConflictUpdate(
              normalized
                  .toCompanion(false)
                  .copyWith(serverVersion: const Value.absent()),
            );
        continue;
      }
      if (after == null || afterRow == null || current == afterRow) {
        final history = after == null || afterRow == null
            ? PlanTitleHistory.decodeJson(entry.value.planTitleHistoryJson)
            : PlanTitleHistory.revertedForUndo(
                before: PlanTitleHistory.decodeJson(
                  entry.value.planTitleHistoryJson,
                ),
                after: PlanTitleHistory.decodeJson(
                  afterRow.planTitleHistoryJson,
                ),
                current: PlanTitleHistory.decodeJson(
                  current.planTitleHistoryJson,
                ),
                now: now,
              );
        final normalized = entry.value.copyWith(
          estimatedDurationMin: Value(
            entry.value.isInbox
                ? null
                : TaskTimeMetrics.plannedMinutes(
                    entry.value.startTime,
                    entry.value.endTime,
                  ),
          ),
          planTitleHistoryJson: PlanTitleHistory.encodeJson(history),
        );
        await db
            .into(db.tasks)
            .insertOnConflictUpdate(
              normalized
                  .toCompanion(false)
                  .copyWith(serverVersion: const Value.absent()),
            );
        continue;
      }

      // Timer/cache or an unrelated edit may have changed this materialized
      // row after the aggregate command ran. Restore only the title and its
      // visible pointer when they are still owned by this command, while
      // retaining all newer measured/manual data and unioning history.
      final titleStillOwned =
          current.title == afterRow.title &&
          current.displayPlanChangeId == afterRow.displayPlanChangeId;
      if (titleStillOwned) {
        final history = PlanTitleHistory.revertedForUndo(
          before: PlanTitleHistory.decodeJson(entry.value.planTitleHistoryJson),
          after: PlanTitleHistory.decodeJson(afterRow.planTitleHistoryJson),
          current: PlanTitleHistory.decodeJson(current.planTitleHistoryJson),
          now: now,
        );
        await db.taskDao.updateTask(
          current.copyWith(
            title: entry.value.title,
            planTitleHistoryJson: PlanTitleHistory.encodeJson(history),
            displayPlanChangeId: Value(entry.value.displayPlanChangeId),
            updatedAt: now,
            syncStatus: 1,
            revision: current.revision + 1,
          ),
        );
      }
    }
    for (final entry in afterTasks.entries) {
      if (beforeTasks.containsKey(entry.key)) continue;
      final current = currentTaskById[entry.key];
      if (current == entry.value) {
        await (db.update(
          db.tasks,
        )..where((row) => row.id.equals(entry.key))).write(
          entry.value
              .toCompanion(false)
              .copyWith(
                deletedAt: Value(now),
                updatedAt: Value(now),
                syncStatus: const Value(1),
                revision: Value(entry.value.revision + 1),
                serverVersion: const Value.absent(),
              ),
        );
      }
    }

    final beforeSubtasks = {for (final row in subtasks) row.id: row};
    final afterSubtasks = {
      for (final row in after?.subtasks ?? const <SubtaskRow>[]) row.id: row,
    };
    final currentSubtasks = afterSubtasks.isEmpty
        ? <SubtaskRow>[]
        : await (db.select(
            db.subtasks,
          )..where((row) => row.id.isIn(afterSubtasks.keys))).get();
    final currentSubtaskById = {for (final row in currentSubtasks) row.id: row};
    for (final entry in beforeSubtasks.entries) {
      final current = await (db.select(
        db.subtasks,
      )..where((row) => row.id.equals(entry.key))).getSingleOrNull();
      final afterRow = afterSubtasks[entry.key];
      if (after == null ||
          current == null ||
          afterRow == null ||
          current == afterRow) {
        await db
            .into(db.subtasks)
            .insertOnConflictUpdate(
              entry.value
                  .toCompanion(false)
                  .copyWith(serverVersion: const Value.absent()),
            );
      }
    }
    for (final entry in afterSubtasks.entries) {
      if (beforeSubtasks.containsKey(entry.key)) continue;
      final current = currentSubtaskById[entry.key];
      if (current == entry.value) {
        await (db.update(
          db.subtasks,
        )..where((row) => row.id.equals(entry.key))).write(
          entry.value
              .toCompanion(false)
              .copyWith(
                deletedAt: Value(now),
                updatedAt: Value(now),
                syncStatus: const Value(1),
                revision: Value(entry.value.revision + 1),
                serverVersion: const Value.absent(),
              ),
        );
      }
    }

    final beforeTags = {
      for (final row in taskTags) '${row.taskId}:${row.tagId}': row,
    };
    final afterTags = {
      for (final row in after?.taskTags ?? const <TaskTagRow>[])
        '${row.taskId}:${row.tagId}': row,
    };
    final currentTags = taskIds.isEmpty
        ? <TaskTagRow>[]
        : await (db.select(
            db.taskTags,
          )..where((row) => row.taskId.isIn(taskIds))).get();
    final currentTagByKey = {
      for (final row in currentTags) '${row.taskId}:${row.tagId}': row,
    };
    for (final entry in beforeTags.entries) {
      final current = currentTagByKey[entry.key];
      final afterRow = afterTags[entry.key];
      if (after == null ||
          current == null ||
          afterRow == null ||
          current == afterRow) {
        await db
            .into(db.taskTags)
            .insertOnConflictUpdate(
              entry.value
                  .toCompanion(false)
                  .copyWith(serverVersion: const Value.absent()),
            );
      }
    }
    for (final entry in afterTags.entries) {
      if (beforeTags.containsKey(entry.key)) continue;
      final current = currentTagByKey[entry.key];
      if (current == entry.value) {
        await (db.update(db.taskTags)..where(
              (row) =>
                  row.taskId.equals(entry.value.taskId) &
                  row.tagId.equals(entry.value.tagId),
            ))
            .write(
              entry.value
                  .toCompanion(false)
                  .copyWith(
                    deletedAt: Value(now),
                    updatedAt: Value(now),
                    syncStatus: const Value(1),
                    revision: Value(entry.value.revision + 1),
                    serverVersion: const Value.absent(),
                  ),
            );
      }
    }
    // Snapshot rows contain a historical cache value. Restore source/task
    // identity first, then derive it from all retained finished sessions.
    await TaskActualDurationService(db).recomputeTasks(taskIds);
  }
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
      tasks.putIfAbsent(row.id, () => row);
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
}
