import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
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
    for (final entry in beforeTasks.entries) {
      final current = currentTaskById[entry.key];
      final afterRow = afterTasks[entry.key];
      if (after == null ||
          current == null ||
          afterRow == null ||
          current == afterRow) {
        await db
            .into(db.tasks)
            .insertOnConflictUpdate(
              entry.value
                  .toCompanion(false)
                  .copyWith(serverVersion: const Value.absent()),
            );
      }
    }
    final now = DateTime.now().toUtc();
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
  }
}

/// Executes a recurrence mutation as one history item. The callback is
/// replayed on Redo; Undo restores the complete pre-mutation snapshot.
class RecurrenceAggregateCommand implements SchedulingCommand {
  final AppDatabase database;
  final String ruleId;
  final Future<void> Function() mutation;
  @override
  final String description;

  RecurrenceAggregateSnapshot? _before;
  RecurrenceAggregateSnapshot? _after;

  RecurrenceAggregateCommand({
    required this.database,
    required this.ruleId,
    required this.mutation,
    required this.description,
  });

  @override
  Future<void> execute() async {
    _before ??= await RecurrenceAggregateSnapshot.capture(database, ruleId);
    if (_before == null) throw StateError('Recurring rule $ruleId not found');
    await database.transaction(mutation);
    _after = await RecurrenceAggregateSnapshot.capture(
      database,
      ruleId,
      extraTaskIds: _before!.tasks.map((task) => task.id).toSet(),
    );
  }

  @override
  Future<void> undo() async {
    await database.transaction(() async {
      await _before?.restore(database, after: _after);
    });
  }
}
