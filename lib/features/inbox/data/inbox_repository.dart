import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/inbox_item.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/uuid.dart';
import '../../../core/utils/date_utils.dart';
import '../../timeline/data/task_repository.dart';

/// Inbox data access per architecture.md §3 "Inbox representation" and the
/// Inbox Overdue Surfacing data flow.
class InboxRepository {
  final AppDatabase _db;

  InboxRepository(this._db);

  TaskRepository get _tasks => TaskRepository(_db);

  AppDatabase get database => _db;

  /// Stream of everything the inbox shows:
  /// - explicit inbox items (`is_inbox = 1`, unscheduled)
  /// - overdue tasks (`DATE(start_time) < today`, still planned/in-progress,
  ///   scheduled rows) surfaced query-side without moving them.
  Stream<List<InboxItem>> watchInboxItems([DateTime? asOf]) {
    final effectiveNow = asOf ?? DateTime.now();
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            ((t.isInbox.equals(true) &
                    t.startTime.isNull() &
                    t.status.isNotIn([
                      TaskStatus.completed.dbValue,
                      TaskStatus.cancelled.dbValue,
                      TaskStatus.skipped.dbValue,
                    ])) |
                (t.isInbox.equals(false) &
                    t.endTime.isNotNull() &
                    t.endTime.isSmallerThanValue(_utcIso(effectiveNow)) &
                    t.status.isIn([
                      TaskStatus.planned.dbValue,
                      TaskStatus.inProgress.dbValue,
                    ]))),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startTime)]);

    return query.watch().map((rows) {
      final items = <InboxItem>[];
      for (final row in rows) {
        final task = TaskRepository.fromRow(row);
        if (task.isInbox && task.startTime == null) {
          items.add(InboxItem.explicit(task));
        } else if (!task.isInbox &&
            task.startTime != null &&
            task.endTime != null &&
            task.endTime!.isBefore(effectiveNow) &&
            (task.status == TaskStatus.planned ||
                task.status == TaskStatus.inProgress)) {
          items.add(InboxItem.overdue(task));
        }
      }
      // Explicit inbox first, then overdue by original date.
      items.sort((a, b) {
        if (a.isOverdue != b.isOverdue) return a.isOverdue ? 1 : -1;
        return a.task.createdAt.compareTo(b.task.createdAt);
      });
      return items;
    });
  }

  Future<Task> addToInbox(String content, {String? dueDate}) {
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }
    if (dueDate != null && !isValidIsoDate(dueDate)) {
      throw ArgumentError.value(
        dueDate,
        'dueDate',
        'must be a valid yyyy-MM-dd date',
      );
    }
    final now = DateTime.now();
    return _tasks.insertTask(
      Task(
        id: '',
        // The title is an internal compatibility value. The raw capture is
        // authoritative in description and is never trimmed or truncated.
        title: 'Inbox capture',
        description: content,
        isInbox: true,
        inboxContentVersion: 1,
        dueDate: dueDate,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// First-detection stamping: any scheduled task whose end time has passed
  /// while still planned/in-progress gets `missed_at` set once.
  /// Format: `YYYY-MM-DDTHH:mm` (UTC), per architecture.md §3.
  Future<int> stampOverdue([DateTime? asOf]) async {
    final now = (asOf ?? DateTime.now()).toUtc();
    final stamp = now.toIso8601String().substring(0, 16);
    return _db.customUpdate(
      'UPDATE tasks SET missed_at = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE deleted_at IS NULL AND is_inbox = 0 '
      'AND missed_at IS NULL AND end_time IS NOT NULL AND end_time < ? '
      "AND status IN ('planned', 'in_progress')",
      variables: [
        Variable<String>(stamp),
        Variable<String>(now.toIso8601String()),
        Variable<String>(_utcIso(now)),
      ],
      updates: {_db.tasks},
    );
  }

  /// Schedules an explicit inbox item at the drop position (Flow 5).
  /// Duration comes from the caller (one grid slot).
  Future<Task> scheduleItem(
    String taskId,
    DateTime start,
    DateTime end, {
    String? title,
    String? description,
    bool replaceDescription = false,
    int? expectedRevision,
  }) async => (await scheduleItemDetailed(
    taskId,
    start,
    end,
    title: title,
    description: description,
    replaceDescription: replaceDescription,
    expectedRevision: expectedRevision,
  )).after;

  /// Reads, validates and converts an explicit Inbox row in the same
  /// transaction as its update. The result is also used by the scheduling
  /// command to retain an owned-field snapshot for guarded Undo.
  Future<InboxScheduleResult> scheduleItemDetailed(
    String taskId,
    DateTime start,
    DateTime end, {
    String? title,
    String? description,
    bool replaceDescription = false,
    int? expectedRevision,
  }) {
    return _db.transaction(() async {
      final currentSnapshot = await _tasks.getTaskWithRevision(taskId);
      final current = currentSnapshot?.$1;
      final currentRevision = currentSnapshot?.$2;
      if (current == null || currentRevision == null) {
        throw StateError('Task $taskId not found');
      }
      final desiredTitle = title ?? current.title;
      final desiredDescription = replaceDescription
          ? description
          : current.description;
      if (current.deletedAt != null) {
        throw StateError('Inbox item $taskId is no longer available');
      }
      if (!current.isInbox) {
        final sameRequest =
            current.title == desiredTitle &&
            current.description == desiredDescription &&
            current.startTime == start &&
            current.endTime == end;
        if (sameRequest) {
          return InboxScheduleResult(
            before: current,
            after: current,
            changed: false,
          );
        }
        throw StateError(
          'This item was already scheduled; open the task to review.',
        );
      }
      if (current.status == TaskStatus.completed ||
          current.status == TaskStatus.cancelled ||
          current.status == TaskStatus.skipped ||
          current.status == TaskStatus.rescheduled) {
        throw StateError('Only an active Inbox capture can be scheduled');
      }
      if (expectedRevision != null && expectedRevision != currentRevision) {
        throw StateError(
          'Inbox item $taskId changed while it was being scheduled; retry the same draft.',
        );
      }
      final after = await _tasks.updateTask(
        current.copyWith(
          title: desiredTitle,
          description: desiredDescription,
          isInbox: false,
          startTime: start,
          endTime: end,
        ),
        expectedRevision: currentRevision,
      );
      return InboxScheduleResult(before: current, after: after, changed: true);
    });
  }

  /// Marks an inbox/overdue item as skipped without scheduling it
  /// (Flow 6 "Mark as Skipped").
  Future<Task> scheduleStatus(String taskId, TaskStatus status) async {
    final task = await _tasks.getTaskById(taskId);
    if (task == null) throw StateError('Task $taskId not found');
    return _tasks.updateTask(task.copyWith(status: status));
  }

  /// Reschedules an overdue task (Flow 6): the original row becomes
  /// `rescheduled` and links to a newly created task at the drop position.
  Future<Task> rescheduleOverdue(
    String originalId,
    DateTime newStart,
    DateTime newEnd, {
    String? successorId,
    String? title,
    String? description,
    bool replaceDescription = false,
  }) {
    return _db.transaction(() async {
      final original = await _tasks.getTaskById(originalId);
      if (original == null || original.deletedAt != null) {
        throw StateError('Task $originalId not found');
      }
      if (original.status != TaskStatus.planned &&
          original.status != TaskStatus.inProgress) {
        throw StateError('Only unfinished tasks can be rescheduled');
      }

      final now = DateTime.now();
      final newTask = await _tasks.insertTask(
        original.copyWith(
          id: successorId ?? generateUuidV7(),
          title: title ?? original.title,
          description: replaceDescription ? description : original.description,
          isInbox: false,
          startTime: newStart,
          endTime: newEnd,
          actualDurationMin: null,
          manualDurationAdjustmentMin: 0,
          manualActualSet: false,
          planTitleHistory: const [],
          displayPlanChangeId: null,
          status: TaskStatus.planned,
          recurringRuleId: original.recurringRuleId,
          rescheduledFromId: original.id,
          rescheduledToId: null,
          missedAt: null,
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
        ),
      );

      final links =
          await (_db.select(_db.taskTags)..where(
                (row) =>
                    row.taskId.equals(original.id) & row.deletedAt.isNull(),
              ))
              .get();
      for (final link in links) {
        await _db.tagDao.linkTaskTag(newTask.id, link.tagId, now);
      }

      final unfinished =
          await (_db.select(_db.subtasks)
                ..where(
                  (row) =>
                      row.taskId.equals(original.id) &
                      row.deletedAt.isNull() &
                      row.isCompleted.equals(false),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
              .get();
      for (var index = 0; index < unfinished.length; index++) {
        await _db
            .into(_db.subtasks)
            .insert(
              SubtasksCompanion.insert(
                id: generateUuidV7(),
                taskId: newTask.id,
                title: unfinished[index].title,
                isCompleted: const Value(false),
                sortOrder: Value(index),
                createdAt: now,
                updatedAt: now,
                syncStatus: const Value(1),
                revision: const Value(1),
              ),
            );
      }

      await _tasks.markRescheduled(original.id, newTask.id);
      return newTask;
    });
  }

  static String _utcIso(DateTime local) => local.toUtc().toIso8601String();
}

class InboxScheduleResult {
  final Task before;
  final Task after;
  final bool changed;

  const InboxScheduleResult({
    required this.before,
    required this.after,
    required this.changed,
  });
}
