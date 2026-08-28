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
    String ruleId,
  ) async {
    final rule = await db.recurringRuleDao.getRuleById(ruleId);
    if (rule == null) return null;
    final tasks = await (db.select(db.tasks)
          ..where((task) => task.recurringRuleId.equals(ruleId)))
        .get();
    final taskIds = tasks.map((task) => task.id).toSet();
    final subtasks = taskIds.isEmpty
        ? <SubtaskRow>[]
        : await (db.select(db.subtasks)
              ..where((row) => row.taskId.isIn(taskIds)))
            .get();
    final taskTags = taskIds.isEmpty
        ? <TaskTagRow>[]
        : await (db.select(db.taskTags)
              ..where((row) => row.taskId.isIn(taskIds)))
            .get();
    return RecurrenceAggregateSnapshot(
      rule: rule,
      tasks: tasks,
      subtasks: subtasks,
      taskTags: taskTags,
    );
  }

  Future<void> restore(AppDatabase db) async {
    await db.into(db.recurringRules).insertOnConflictUpdate(rule.toCompanion(true));
    for (final task in tasks) {
      await db.into(db.tasks).insertOnConflictUpdate(task.toCompanion(true));
    }
    for (final subtask in subtasks) {
      await db.into(db.subtasks).insertOnConflictUpdate(subtask.toCompanion(true));
    }
    for (final taskTag in taskTags) {
      await db.into(db.taskTags).insertOnConflictUpdate(taskTag.toCompanion(true));
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
    await mutation();
  }

  @override
  Future<void> undo() async {
    await _before?.restore(database);
  }
}
