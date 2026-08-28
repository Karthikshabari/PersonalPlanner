import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/utils/uuid.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';
import 'task_aggregate_snapshot.dart';

/// Creates a clean planning copy and carries only work that remains to be done.
class DuplicateTaskCommand implements SchedulingCommand {
  final TaskRepository repository;
  final Task source;
  final DateTime newStart;
  final DateTime newEnd;

  TaskAggregateSnapshot? _createdSnapshot;
  String? _createdId;

  DuplicateTaskCommand({
    required this.repository,
    required this.source,
    required this.newStart,
    required this.newEnd,
  });

  @override
  String get description => 'Duplicate "${source.title}"';

  @override
  Future<void> execute() async {
    final snapshot = _createdSnapshot;
    if (snapshot != null) {
      await snapshot.restore(repository.database);
      return;
    }

    final now = DateTime.now();
    final created = await repository.insertTask(source.copyWith(
      id: '',
      startTime: newStart,
      endTime: newEnd,
      actualDurationMin: null,
      status: TaskStatus.planned,
      recurringRuleId: null,
      rescheduledFromId: null,
      rescheduledToId: null,
      isInbox: false,
      missedAt: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    ));
    _createdId = created.id;

    final db = repository.database;
    final links = await (db.select(db.taskTags)
          ..where((row) =>
              row.taskId.equals(source.id) & row.deletedAt.isNull()))
        .get();
    for (final link in links) {
      await db.tagDao.linkTaskTag(created.id, link.tagId, now);
    }

    final unfinished = await (db.select(db.subtasks)
          ..where((row) =>
              row.taskId.equals(source.id) &
              row.deletedAt.isNull() &
              row.isCompleted.equals(false))
          ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
        .get();
    for (var index = 0; index < unfinished.length; index++) {
      final subtask = unfinished[index];
      await db.into(db.subtasks).insert(SubtasksCompanion.insert(
            id: generateUuidV7(),
            taskId: created.id,
            title: subtask.title,
            isCompleted: const Value(false),
            sortOrder: Value(index),
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value(1),
            revision: const Value(1),
          ));
    }
    _createdSnapshot = await TaskAggregateSnapshot.capture(db, created.id);
  }

  @override
  Future<void> undo() async {
    final id = _createdId;
    if (id == null) return;
    _createdSnapshot = await TaskAggregateSnapshot.capture(
      repository.database,
      id,
    );
    await _createdSnapshot?.softDelete(repository.database);
  }
}
