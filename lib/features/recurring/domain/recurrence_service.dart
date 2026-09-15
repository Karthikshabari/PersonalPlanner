import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/priority.dart';
import '../../../core/models/enums/recurrence_removal_reason.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/recurring_rule.dart';
import '../../../core/models/plan_title_change.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../../core/utils/uuid.dart';
import '../../timeline/data/task_repository.dart';
import '../../task_editor/domain/plan_title_history.dart';
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
    final nextDayUtcIso = addDays(dayStart, 1).toUtc().toIso8601String();

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
        final occurrenceId = _occurrenceId(rule.id, dateIso);
        // A user may move an occurrence away from its original date. The
        // current start-day query then misses it, so identity must be checked
        // by the stable rule/date ID before creating a replacement.
        final identified = await _db.taskDao.getTaskById(occurrenceId);
        if (identified != null) {
          if (!await _canReactivate(identified, rule)) return false;
          await _reactivateInstance(identified, rule, dayStart);
          return true;
        }
        final existing = await _db.recurringRuleDao.getInstancesForDay(
          rule.id,
          dayStartUtcIso,
          nextDayUtcIso,
        );
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
    DateTime boundary, {
    String? excludeTaskId,
    String? planTitleChangeIntentId,
    DateTime? planTitleChangedAt,
    bool preservePlanTitleChange = false,
    bool clearPlanTitleDisplay = false,
  }) async {
    final boundaryIso = startOfDay(boundary).toUtc().toIso8601String();
    final rows =
        await (_db.select(_db.tasks)..where(
              (task) =>
                  task.recurringRuleId.equals(rule.id) &
                  task.deletedAt.isNull() &
                  task.startTime.isBiggerOrEqualValue(boundaryIso),
            ))
            .get();
    final activeTagIds = <String>{};
    for (final tagId in rule.tags) {
      final tag =
          await (_db.select(_db.tags)
                ..where((tag) => tag.id.equals(tagId) & tag.deletedAt.isNull()))
              .getSingleOrNull();
      if (tag != null) activeTagIds.add(tagId);
    }
    for (final row in rows) {
      if (row.id == excludeTaskId) continue;
      final status = TaskStatus.fromDb(row.status);
      if (status != TaskStatus.planned && status != TaskStatus.inProgress) {
        continue;
      }
      final current = TaskRepository.fromRow(row);
      final day = startOfDay(current.startTime!);
      final dayIso = isoDateString(day);
      // A moved occurrence retains the deterministic identity of its original
      // slot. Never infer that identity from its displayed day and never let a
      // series reconciliation move or tombstone it as if it belonged there.
      if (row.id != _occurrenceId(rule.id, dayIso)) continue;
      final stillInSeries =
          !rule.exceptions.contains(dayIso) &&
          (rule.endDate == null ||
              dayIso.compareTo(isoDateString(rule.endDate!)) <= 0) &&
          RruleUtils.occursOnDate(rule.rrule, rule.startDate, day);
      if (!stillInSeries) {
        // The new rule no longer produces this future slot. Keep the row as a
        // tombstone so history and sync identity remain intact.
        await _tasks.deleteTask(
          current.id,
          recurrenceRemovalReason: RecurrenceRemovalReason.ruleExcluded,
        );
        continue;
      }
      final (hour, minute) = _parseStartTimeOfDay(rule.startTimeOfDay);
      final start = PlannerTimeZone.calendarDate(
        day.year,
        day.month,
        day.day,
        hour: hour,
        minute: minute,
      );
      final titleChanged =
          PlanTitleHistory.normalizeTitle(current.title) !=
          PlanTitleHistory.normalizeTitle(rule.taskTitle);
      var history = current.planTitleHistory;
      var displayPlanChangeId = current.displayPlanChangeId;
      if (titleChanged && preservePlanTitleChange) {
        final intentId = planTitleChangeIntentId;
        final changedAt = planTitleChangedAt;
        if (intentId == null || changedAt == null) {
          throw StateError(
            'Missing stable title-change intent for recurrence update',
          );
        }
        final event = PlanTitleChange(
          id: generateDeterministicUuid(
            'plan-title-change:$intentId:${current.id}',
          ),
          previousTitle: current.title,
          newTitle: rule.taskTitle,
          changedAt: changedAt,
        );
        history = PlanTitleHistory.appendOrRestore(history, event);
        displayPlanChangeId = event.id;
      } else if (titleChanged && clearPlanTitleDisplay) {
        displayPlanChangeId = null;
      }
      final updated = current.copyWith(
        title: rule.taskTitle,
        description: rule.taskDescription,
        estimatedDurationMin: rule.durationMin,
        categoryId: rule.categoryId,
        priority: Priority.fromDb(rule.priority),
        startTime: start,
        endTime: start.add(Duration(minutes: rule.durationMin)),
        planTitleHistory: history,
        displayPlanChangeId: displayPlanChangeId,
        recurrenceRemovalReason: null,
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
    final rows =
        await (_db.select(_db.tasks)..where(
              (task) =>
                  task.recurringRuleId.equals(ruleId) &
                  task.deletedAt.isNull() &
                  task.startTime.isBiggerOrEqualValue(boundaryIso),
            ))
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
    final current =
        await (_db.select(_db.taskTags)..where(
              (link) => link.taskId.equals(taskId) & link.deletedAt.isNull(),
            ))
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
    final startTime = PlannerTimeZone.calendarDate(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      hour: hour,
      minute: minute,
    );
    final now = DateTime.now();
    final instance = await _tasks.insertTask(
      Task(
        // Rule/date is the logical occurrence identity. Existing materialized
        // rows are found by date above and are never renamed, so this only
        // makes new local/remote materializations converge.
        id: _occurrenceId(rule.id, isoDateString(dayStart)),
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
      ),
    );
    // Attach the rule's tags (only those that still exist).
    for (final tagId in rule.tags) {
      final tag =
          await (_db.select(_db.tags)
                ..where((t) => t.id.equals(tagId) & t.deletedAt.isNull()))
              .getSingleOrNull();
      if (tag != null) {
        await _db.tagDao.linkTaskTag(instance.id, tagId, now);
      }
    }
    return instance;
  }

  Future<bool> _canReactivate(TaskRow row, RecurringRule rule) async {
    if (row.deletedAt == null ||
        row.recurrenceRemovalReason != RecurrenceRemovalReason.ruleExcluded ||
        row.recurringRuleId != rule.id ||
        row.rescheduledFromId != null ||
        row.rescheduledToId != null) {
      return false;
    }
    final status = TaskStatus.fromDb(row.status);
    if (status != TaskStatus.planned && status != TaskStatus.inProgress) {
      return false;
    }
    if (row.actualDurationMin != null ||
        row.manualActualSet ||
        row.manualDurationAdjustmentMin != 0) {
      return false;
    }
    final timer =
        await (_db.select(_db.timerSessions)
              ..where((session) => session.taskId.equals(row.id))
              ..limit(1))
            .getSingleOrNull();
    return timer == null;
  }

  Future<void> _reactivateInstance(
    TaskRow row,
    RecurringRule rule,
    DateTime originalDay,
  ) async {
    final (hour, minute) = _parseStartTimeOfDay(rule.startTimeOfDay);
    final start = PlannerTimeZone.calendarDate(
      originalDay.year,
      originalDay.month,
      originalDay.day,
      hour: hour,
      minute: minute,
    );
    final current = TaskRepository.fromRow(row);
    await _tasks.updateTask(
      current.copyWith(
        title: rule.taskTitle,
        description: rule.taskDescription,
        startTime: start,
        endTime: start.add(Duration(minutes: rule.durationMin)),
        estimatedDurationMin: rule.durationMin,
        categoryId: rule.categoryId,
        priority: Priority.fromDb(rule.priority),
        recurringRuleId: rule.id,
        recurrenceRemovalReason: null,
        displayPlanChangeId: current.title == rule.taskTitle
            ? current.displayPlanChangeId
            : null,
        deletedAt: null,
      ),
      allowStatusTransition: true,
    );
    final activeTagIds = <String>{};
    for (final tagId in rule.tags) {
      final tag =
          await (_db.select(_db.tags)..where(
                (candidate) =>
                    candidate.id.equals(tagId) & candidate.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (tag != null) activeTagIds.add(tagId);
    }
    await _replaceTags(row.id, activeTagIds);
  }

  static String _occurrenceId(String ruleId, String dateIso) =>
      generateDeterministicUuid('recurring-occurrence:$ruleId:$dateIso');

  static (int, int) _parseStartTimeOfDay(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (hour.clamp(0, 23), minute.clamp(0, 59));
  }
}
