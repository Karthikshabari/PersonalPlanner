import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        ComparableExpr,
        CustomExpression,
        OrderingTerm;
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/task.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/duration_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../timeline/data/task_repository.dart';
import 'review_plan_change.dart';

/// A small, deterministic description of a final plan difference.
///
/// Review deliberately derives these from the final task rows. It does not
/// replay every intermediate edit, which keeps a move such as 10:00 → 10:15
/// → 10:00 out of the review.
enum ReviewChangeKind { moved, added, status, duration, planChanged }

class ReviewChange {
  final String taskTitle;
  final String detail;
  final ReviewChangeKind kind;

  const ReviewChange({
    required this.taskTitle,
    required this.detail,
    required this.kind,
  });
}

class ReviewCarryover {
  final String title;
  final DateTime? startTime;

  const ReviewCarryover({required this.title, required this.startTime});
}

class ReviewInsights {
  final List<ReviewChange> changes;
  final List<ReviewCarryover> carryover;

  const ReviewInsights({this.changes = const [], this.carryover = const []});

  int get movedCount =>
      changes.where((change) => change.kind == ReviewChangeKind.moved).length;

  int get addedCount =>
      changes.where((change) => change.kind == ReviewChangeKind.added).length;

  int get statusChangeCount =>
      changes.where((change) => change.kind == ReviewChangeKind.status).length;
}

/// Derives the useful, final differences shown by Daily and Weekly Review.
///
/// There is no reliable persisted before/after schedule for ordinary drag or
/// resize edits. Those edits are therefore intentionally not guessed at. The
/// service uses durable reschedule links, final status, creation time and the
/// canonical actual-duration field where those comparisons are safe.
class ReviewInsightsService {
  final AppDatabase _db;

  ReviewInsightsService(this._db);

  Future<ReviewInsights> forDay(DateTime date) async {
    final day = startOfDay(date);
    final end = addDays(day, 1);
    final (tasks, byId) = await _loadTasksAroundDay(day, end);
    final relevant = tasks.where((task) => _scheduledIn(task, day, end));
    final changes = <ReviewChange>[];
    for (final task in relevant) {
      changes.addAll(_changesForTask(task, day, end, byId));
    }
    return ReviewInsights(
      changes: changes,
      carryover: _carryoverFor(
        tasks,
        end,
        addDays(end, 1),
        byId,
        sourceStart: day,
      ),
    );
  }

  /// One row per task: every change of a task is merged into one detail line
  /// (`Moved → … · Plan changed from “…”`), so a task never shows twice.
  Future<ReviewInsights> forWeek(DateTime weekStart) async {
    final start = startOfWeek(weekStart);
    final end = addDays(start, 7);
    final nextEnd = addDays(end, 7);
    final tasks = await _loadTasks();
    final byId = {for (final task in tasks) task.id: task};
    final changes = <ReviewChange>[];
    for (final task in tasks) {
      if (!_scheduledIn(task, start, end)) continue;
      final perTask = _changesForTask(task, start, end, byId);
      if (perTask.isEmpty) continue;
      changes.add(
        ReviewChange(
          taskTitle: task.title,
          detail: perTask.map((change) => change.detail).join(' · '),
          kind: perTask.first.kind,
        ),
      );
    }
    return ReviewInsights(
      changes: changes,
      carryover: _carryoverFor(tasks, end, nextEnd, byId, sourceStart: start),
    );
  }

  /// The tasks [forDay] can actually look at, instead of the whole table:
  /// the ones scheduled on [day], the ones starting on the next day (carry-over
  /// candidates), and the reschedule targets/sources those two sets point to.
  ///
  /// The SQL ranges are widened by a day as a prefilter; every exact range test
  /// stays in Dart (`_scheduledIn`, `_inRange`), and rows come back in rowid
  /// order, which is the order a full scan produced. The result is therefore
  /// the same as filtering the full list.
  Future<(List<Task>, Map<String, Task>)> _loadTasksAroundDay(
    DateTime day,
    DateTime end,
  ) async {
    String iso(DateTime instant) => instant.toUtc().toIso8601String();
    final windowStart = iso(addDays(day, -1));
    final scheduledBefore = iso(addDays(end, 1));
    final nextStart = iso(addDays(end, -1));
    final nextBefore = iso(addDays(end, 2));
    final rows =
        await (_db.select(_db.tasks)
              ..where(
                (task) =>
                    task.deletedAt.isNull() &
                    task.isInbox.equals(false) &
                    ((task.startTime.isSmallerThanValue(scheduledBefore) &
                            task.endTime.isBiggerThanValue(windowStart)) |
                        (task.startTime.isBiggerOrEqualValue(nextStart) &
                            task.startTime.isSmallerThanValue(nextBefore))),
              )
              ..orderBy([
                (task) =>
                    OrderingTerm.asc(const CustomExpression<int>('rowid')),
              ]))
            .get();
    final tasks = rows.map(TaskRepository.fromRow).toList(growable: false);
    final byId = {for (final task in tasks) task.id: task};
    final linkedIds = <String>{
      for (final task in tasks) ...[
        if (task.rescheduledToId != null) task.rescheduledToId!,
        if (task.rescheduledFromId != null) task.rescheduledFromId!,
      ],
    }..removeAll(byId.keys);
    if (linkedIds.isNotEmpty) {
      final linked =
          await (_db.select(_db.tasks)..where(
                (task) =>
                    task.id.isIn(linkedIds) &
                    task.deletedAt.isNull() &
                    task.isInbox.equals(false),
              ))
              .get();
      for (final row in linked) {
        final task = TaskRepository.fromRow(row);
        byId[task.id] = task;
      }
    }
    return (tasks, byId);
  }

  Future<List<Task>> _loadTasks() async {
    final rows = await (_db.select(_db.tasks)).get();
    return rows
        .where((row) => row.deletedAt == null && !row.isInbox)
        .map(TaskRepository.fromRow)
        .toList(growable: false);
  }

  bool _scheduledIn(Task task, DateTime start, DateTime end) {
    final taskStart = task.startTime;
    final taskEnd = task.endTime;
    return taskStart != null &&
        taskEnd != null &&
        taskStart.isBefore(end) &&
        taskEnd.isAfter(start);
  }

  List<ReviewChange> _changesForTask(
    Task task,
    DateTime rangeStart,
    DateTime rangeEnd,
    Map<String, Task> byId,
  ) {
    final changes = <ReviewChange>[];
    final target = task.rescheduledToId == null
        ? null
        : byId[task.rescheduledToId!];
    if (task.status == TaskStatus.rescheduled && target?.startTime != null) {
      changes.add(
        ReviewChange(
          taskTitle: task.title,
          detail: 'Moved → ${_targetLabel(target!.startTime!, rangeStart)}',
          kind: ReviewChangeKind.moved,
        ),
      );
    }

    final planChange = ReviewPlanChange.forTask(task);
    if (planChange != null) {
      changes.add(
        ReviewChange(
          taskTitle: task.title,
          detail: 'Plan changed from “${planChange.oldValue}”',
          kind: ReviewChangeKind.planChanged,
        ),
      );
    }

    if (task.status == TaskStatus.skipped ||
        task.status == TaskStatus.cancelled) {
      changes.add(
        ReviewChange(
          taskTitle: task.title,
          detail: task.status == TaskStatus.skipped ? 'Skipped' : 'Cancelled',
          kind: ReviewChangeKind.status,
        ),
      );
    }

    final planned = TaskTimeMetrics.plannedMinutes(
      task.startTime,
      task.endTime,
    );
    final tracked = task.actualDurationMin;
    if (planned != null &&
        tracked != null &&
        tracked > 0 &&
        (tracked - planned).abs() >= 15) {
      changes.add(
        ReviewChange(
          taskTitle: task.title,
          detail:
              '${Duration(minutes: planned).shortLabel} planned → '
              '${Duration(minutes: tracked).shortLabel} tracked',
          kind: ReviewChangeKind.duration,
        ),
      );
    }
    return changes;
  }

  List<ReviewCarryover> _carryoverFor(
    List<Task> tasks,
    DateTime targetStart,
    DateTime targetEnd,
    Map<String, Task> byId, {
    DateTime? sourceStart,
  }) {
    final carryover = <ReviewCarryover>[];
    final seen = <String>{};
    for (final task in tasks) {
      final source = task.rescheduledFromId == null
          ? null
          : byId[task.rescheduledFromId!];
      final sourceDate = source?.startTime;
      if (sourceDate == null ||
          (sourceStart != null &&
              !_inRange(sourceDate, sourceStart, targetStart))) {
        continue;
      }
      if (!_inRange(task.startTime, targetStart, targetEnd)) continue;
      if (seen.add(task.id)) {
        carryover.add(
          ReviewCarryover(title: task.title, startTime: task.startTime),
        );
      }
    }
    carryover.sort((a, b) {
      if (a.startTime == null && b.startTime == null) return 0;
      if (a.startTime == null) return 1;
      if (b.startTime == null) return -1;
      return a.startTime!.compareTo(b.startTime!);
    });
    return carryover;
  }

  bool _inRange(DateTime? value, DateTime start, DateTime end) =>
      value != null && !value.isBefore(start) && value.isBefore(end);

  String _targetLabel(DateTime target, DateTime sourceDay) {
    final targetLocal = PlannerTimeZone.toPlannerLocal(target);
    final time = DateFormat('h:mm a').format(targetLocal);
    if (isSameDay(target, sourceDay)) return time;
    if (isSameDay(target, addDays(sourceDay, 1))) return 'Tomorrow · $time';
    return '${DateFormat('EEE, MMM d').format(targetLocal)} · $time';
  }
}
