import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/priority.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/recurring_rule.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../timeline/data/task_repository.dart';
import '../data/recurring_repository.dart';
import 'rrule_utils.dart';

/// Materializes recurring rules into concrete task rows
/// (planner.md Chunk 4 #3; architecture.md §8 "Recurring task materialization").
class RecurrenceService {
  final AppDatabase _db;

  RecurrenceService(this._db);

  RecurringRepository get _rules => RecurringRepository(_db);
  TaskRepository get _tasks => TaskRepository(_db);

  /// Creates missing recurring-task instances for [date] and returns how
  /// many were created. Idempotent: an instance that already exists for a
  /// rule on this day is never duplicated. The dedupe-check + insert runs
  /// inside a transaction so concurrent triggers cannot double-create.
  Future<int> materializeForDate(DateTime date) async {
    final dayStart = startOfDay(date);
    final dateIso = isoDateString(dayStart);
    final dayStartUtcIso = dayStart.toUtc().toIso8601String();
    final nextDayUtcIso =
        dayStart.add(const Duration(days: 1)).toUtc().toIso8601String();

    var created = 0;
    for (final rule in await _rules.getActiveRules()) {
      if (isoDateString(rule.startDate).compareTo(dateIso) > 0) continue;
      if (rule.endDate != null &&
          isoDateString(rule.endDate!).compareTo(dateIso) < 0) {
        continue;
      }
      if (rule.exceptions.contains(dateIso)) continue;
      if (!RruleUtils.occursOnDate(rule.rrule, rule.startDate, dayStart)) {
        continue;
      }
      final inserted = await _db.transaction(() async {
        final existing = await _db.recurringRuleDao.getInstancesForDay(
            rule.id, dayStartUtcIso, nextDayUtcIso);
        if (existing.isNotEmpty) return false;
        await _createInstance(rule, dayStart);
        return true;
      });
      if (inserted) created++;
    }
    return created;
  }

  /// Reconciles materialized future work after an all-future rule edit.
  /// Historical states are intentionally left untouched.
  Future<void> reconcileMaterializedFuture(
    RecurringRule rule,
    DateTime boundary,
  ) async {
    final boundaryIso = startOfDay(boundary).toUtc().toIso8601String();
    final rows = await (_db.select(_db.tasks)
          ..where((task) =>
              task.recurringRuleId.equals(rule.id) &
              task.deletedAt.isNull() &
              task.startTime.isBiggerOrEqualValue(boundaryIso)))
        .get();
    final activeTagIds = <String>{};
    for (final tagId in rule.tags) {
      final tag = await (_db.select(_db.tags)
            ..where((tag) => tag.id.equals(tagId) & tag.deletedAt.isNull()))
          .getSingleOrNull();
      if (tag != null) activeTagIds.add(tagId);
    }
    for (final row in rows) {
      final status = TaskStatus.fromDb(row.status);
      if (status != TaskStatus.planned && status != TaskStatus.inProgress) {
        continue;
      }
      final current = TaskRepository.fromRow(row);
      final day = startOfDay(current.startTime!);
      final (hour, minute) = _parseStartTimeOfDay(rule.startTimeOfDay);
      final start = DateTime(day.year, day.month, day.day, hour, minute);
      final updated = current.copyWith(
        title: rule.taskTitle,
        description: rule.taskDescription,
        estimatedDurationMin: rule.durationMin,
        categoryId: rule.categoryId,
        priority: Priority.fromDb(rule.priority),
        startTime: start,
        endTime: start.add(Duration(minutes: rule.durationMin)),
      );
      await _tasks.updateTask(updated);
      await _replaceTags(current.id, activeTagIds);
    }
  }

  /// Soft-deletes only unfinished materialized instances at or after a
  /// recurrence boundary. Completed and other historical states remain.
  Future<void> deleteMaterializedFuture(
    String ruleId,
    DateTime boundary, {
    String? keepTaskId,
  }) async {
    final boundaryIso = startOfDay(boundary).toUtc().toIso8601String();
    final rows = await (_db.select(_db.tasks)
          ..where((task) =>
              task.recurringRuleId.equals(ruleId) &
              task.deletedAt.isNull() &
              task.startTime.isBiggerOrEqualValue(boundaryIso)))
        .get();
    for (final row in rows) {
      if (row.id == keepTaskId) continue;
      final status = TaskStatus.fromDb(row.status);
      if (status == TaskStatus.planned || status == TaskStatus.inProgress) {
        await _tasks.deleteTask(row.id);
      }
    }
  }

  Future<void> _replaceTags(String taskId, Set<String> tagIds) async {
    final current = await (_db.select(_db.taskTags)
          ..where((link) =>
              link.taskId.equals(taskId) & link.deletedAt.isNull()))
        .get();
    final currentIds = current.map((link) => link.tagId).toSet();
    for (final tagId in currentIds.difference(tagIds)) {
      await _db.tagDao.unlinkTaskTag(taskId, tagId);
    }
    for (final tagId in tagIds.difference(currentIds)) {
      await _db.tagDao.linkTaskTag(taskId, tagId, DateTime.now());
    }
  }

  Future<Task> _createInstance(RecurringRule rule, DateTime dayStart) async {
    final (hour, minute) = _parseStartTimeOfDay(rule.startTimeOfDay);
    final startTime = DateTime(
        dayStart.year, dayStart.month, dayStart.day, hour, minute);
    final now = DateTime.now();
    final instance = await _tasks.insertTask(Task(
      id: '',
      title: rule.taskTitle,
      description: rule.taskDescription,
      startTime: startTime,
      endTime: startTime.add(Duration(minutes: rule.durationMin)),
      estimatedDurationMin: rule.durationMin,
      categoryId: rule.categoryId,
      priority: Priority.fromDb(rule.priority),
      status: TaskStatus.planned,
      isInbox: false,
      recurringRuleId: rule.id,
      createdAt: now,
      updatedAt: now,
    ));
    // Attach the rule's tags (only those that still exist).
    for (final tagId in rule.tags) {
      final tag = await (_db.select(_db.tags)
            ..where((t) => t.id.equals(tagId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (tag != null) {
        await _db.tagDao.linkTaskTag(instance.id, tagId, now);
      }
    }
    return instance;
  }

  static (int, int) _parseStartTimeOfDay(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (hour.clamp(0, 23), minute.clamp(0, 59));
  }
}
