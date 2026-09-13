import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/daily_stats.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../timer/domain/task_actual_duration_service.dart';

/// Computes per-day aggregates and maintains the `daily_stats_cache` table
/// (planner.md Chunk 5 #9). Review save currently refreshes the cache; live
/// review and analytics screens compute from source rows.
class DailyStatsService {
  final AppDatabase _db;

  DailyStatsService(this._db);

  /// Computes the aggregates for [date] from live data.
  Future<DailyStats> computeForDate(DateTime date) =>
      _computeRange(startOfDay(date), addDays(startOfDay(date), 1));

  /// Computes aggregates over [start, end) (used for weekly totals).
  Future<DailyStats> computeRange(DateTime start, DateTime end) =>
      _computeRange(startOfDay(start), startOfDay(end));

  /// Computes the day's aggregates and stores them in `daily_stats_cache`,
  /// replacing any previous snapshot. Returns the stored value.
  Future<DailyStats> computeAndCache(DateTime date) async {
    final stats = await computeForDate(date);
    final dayIso = isoDateString(startOfDay(date));
    await _db.statsDao.upsertStats(
      DailyStatsCacheCompanion.insert(
        date: dayIso,
        totalTasks: Value(stats.totalTasks),
        completedTasks: Value(stats.completedTasks),
        plannedTasks: Value(stats.plannedTasks),
        inProgressTasks: Value(stats.inProgressTasks),
        missedTasks: Value(stats.missedTasks),
        skippedTasks: Value(stats.skippedTasks),
        cancelledTasks: Value(stats.cancelledTasks),
        rescheduledTasks: Value(stats.rescheduledTasks),
        plannedDurationMin: Value(stats.plannedDurationMin),
        actualDurationMin: Value(stats.actualDurationMin),
        focusDurationMin: Value(stats.focusDurationMin),
        energyLevel: Value(stats.energyLevel),
        productivityRating: Value(stats.productivityRating),
        planningAccuracyPct: Value(stats.planningAccuracyPct),
        computedAt: stats.computedAt,
      ),
    );
    return stats;
  }

  /// Computes every day in [start, end) from one bounded source snapshot.
  /// Analytics uses this to avoid rereading the same tasks, categories and
  /// timer history once per day while retaining the established day formulas.
  Future<List<DailyStats>> computeRangeDays(
    DateTime start,
    DateTime end,
  ) async {
    final startInclusive = startOfDay(start);
    final endExclusive = startOfDay(end);
    if (!startInclusive.isBefore(endExclusive)) return const <DailyStats>[];

    final tasks = await _db.taskDao.getTasksBetween(
      startInclusive,
      endExclusive,
    );
    final categories = await (_db.select(_db.categories)).get();
    final focusIds = {for (final c in categories) c.id: c.isFocus};
    final tasksStartingInRange = tasks
        .where(
          (task) =>
              task.startTime != null &&
              !task.startTime!.isBefore(startInclusive) &&
              task.startTime!.isBefore(endExclusive),
        )
        .toList(growable: false);
    final actualByDate = await _actualMinutesByDate(
      startInclusive,
      endExclusive,
    );
    final reviews = await _db.reviewDao.getDailyReviewsBetween(
      isoDateString(startInclusive),
      isoDateString(endExclusive),
    );
    final reviewByDate = {for (final review in reviews) review.date: review};
    final now = DateTime.now();
    final result = <DailyStats>[];
    for (
      var day = startInclusive;
      day.isBefore(endExclusive);
      day = addDays(day, 1)
    ) {
      final dayEnd = addDays(day, 1);
      final dayTasksStarting = tasksStartingInRange
          .where(
            (task) =>
                task.startTime!.isBefore(dayEnd) &&
                !task.startTime!.isBefore(day),
          )
          .toList(growable: false);
      var plannedMin = 0;
      var focusMin = 0;
      var completed = 0;
      var planned = 0;
      var inProgress = 0;
      var missed = 0;
      var skipped = 0;
      var cancelled = 0;
      var rescheduled = 0;
      for (final task in tasks) {
        final startsInDay =
            task.startTime != null &&
            !task.startTime!.isBefore(day) &&
            task.startTime!.isBefore(dayEnd);
        if (startsInDay) {
          switch (TaskStatus.fromDb(task.status)) {
            case TaskStatus.completed:
              completed++;
            case TaskStatus.skipped:
              skipped++;
            case TaskStatus.cancelled:
              cancelled++;
            case TaskStatus.rescheduled:
              rescheduled++;
            case TaskStatus.planned:
              planned++;
              if (task.endTime != null && task.endTime!.isBefore(now)) {
                missed++;
              }
            case TaskStatus.inProgress:
              inProgress++;
              if (task.endTime != null && task.endTime!.isBefore(now)) {
                missed++;
              }
          }
        }
        if (task.startTime != null && task.endTime != null) {
          final overlapStart = task.startTime!.isAfter(day)
              ? task.startTime!
              : day;
          final overlapEnd = task.endTime!.isBefore(dayEnd)
              ? task.endTime!
              : dayEnd;
          if (overlapEnd.isAfter(overlapStart)) {
            final minutes = overlapEnd.difference(overlapStart).inMinutes;
            plannedMin += minutes;
            if (task.categoryId != null && focusIds[task.categoryId!] == true) {
              focusMin += minutes;
            }
          }
        }
      }

      final review = reviewByDate[isoDateString(day)];
      result.add(
        DailyStats(
          date: day,
          totalTasks: dayTasksStarting.length,
          completedTasks: completed,
          plannedTasks: planned,
          inProgressTasks: inProgress,
          missedTasks: missed,
          skippedTasks: skipped,
          cancelledTasks: cancelled,
          rescheduledTasks: rescheduled,
          plannedDurationMin: plannedMin,
          actualDurationMin: actualByDate[isoDateString(day)] ?? 0,
          focusDurationMin: focusMin,
          energyLevel: review?.energyLevel,
          productivityRating: review?.productivityRating,
          planningAccuracyPct: DailyStatsCalculator.planningAccuracyPct(
            dayTasksStarting,
            estimatedDurationMin: (task) =>
                TaskTimeMetrics.plannedMinutes(task.startTime, task.endTime),
            actualDurationMin: (task) => task.actualDurationMin,
          ),
          computedAt: DateTime.now(),
        ),
      );
    }
    return result;
  }

  Future<DailyStats> _computeRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final tasks = await _db.taskDao.getTasksBetween(
      startInclusive,
      endExclusive,
    );
    // Keep deleted categories available for historical focus-minute
    // attribution; the category is still user-owned history.
    final categories = await (_db.select(_db.categories)).get();
    final focusIds = {for (final c in categories) c.id: c.isFocus};
    final now = DateTime.now();
    final tasksStartingInRange = tasks
        .where(
          (task) =>
              task.startTime != null &&
              !task.startTime!.isBefore(startInclusive) &&
              task.startTime!.isBefore(endExclusive),
        )
        .toList(growable: false);

    final actualByDate = await _actualMinutesByDate(
      startInclusive,
      endExclusive,
    );
    var plannedMin = 0;
    var actualMin = 0;
    var focusMin = 0;
    var completed = 0;
    var planned = 0;
    var inProgress = 0;
    var missed = 0;
    var skipped = 0;
    var cancelled = 0;
    var rescheduled = 0;
    for (final t in tasks) {
      final startsInRange =
          t.startTime != null &&
          !t.startTime!.isBefore(startInclusive) &&
          t.startTime!.isBefore(endExclusive);
      if (startsInRange) {
        switch (TaskStatus.fromDb(t.status)) {
          case TaskStatus.completed:
            completed++;
          case TaskStatus.skipped:
            skipped++;
          case TaskStatus.cancelled:
            cancelled++;
          case TaskStatus.rescheduled:
            rescheduled++;
          case TaskStatus.planned:
            planned++;
            if (t.endTime != null && t.endTime!.isBefore(now)) missed++;
          case TaskStatus.inProgress:
            inProgress++;
            // "Missed" matches the inbox overdue semantics: the end time has
            // passed while the task was never finished.
            if (t.endTime != null && t.endTime!.isBefore(now)) missed++;
        }
      }
      if (t.startTime != null && t.endTime != null) {
        final overlapStart = t.startTime!.isAfter(startInclusive)
            ? t.startTime!
            : startInclusive;
        final overlapEnd = t.endTime!.isBefore(endExclusive)
            ? t.endTime!
            : endExclusive;
        final minutes = overlapEnd.isAfter(overlapStart)
            ? overlapEnd.difference(overlapStart).inMinutes
            : 0;
        plannedMin += minutes;
        final isFocus = t.categoryId != null && focusIds[t.categoryId!] == true;
        if (isFocus) focusMin += minutes;
      }
    }

    actualMin = actualByDate.values.fold<int>(0, (sum, value) => sum + value);

    final review = await _db.reviewDao.getDailyReviewByDate(
      isoDateString(startInclusive),
    );

    return DailyStats(
      date: startInclusive,
      totalTasks: tasksStartingInRange.length,
      completedTasks: completed,
      plannedTasks: planned,
      inProgressTasks: inProgress,
      missedTasks: missed,
      skippedTasks: skipped,
      cancelledTasks: cancelled,
      rescheduledTasks: rescheduled,
      plannedDurationMin: plannedMin,
      actualDurationMin: actualMin,
      focusDurationMin: focusMin,
      energyLevel: review?.energyLevel,
      productivityRating: review?.productivityRating,
      planningAccuracyPct: DailyStatsCalculator.planningAccuracyPct(
        tasksStartingInRange,
        estimatedDurationMin: (task) =>
            TaskTimeMetrics.plannedMinutes(task.startTime, task.endTime),
        actualDurationMin: (task) => task.actualDurationMin,
      ),
      computedAt: DateTime.now(),
    );
  }

  /// Loads each relevant Task's complete finished history once, then delegates
  /// all day/range allocation to the canonical R12 algorithm. This avoids the
  /// old wall-span and per-day-floor paths diverging from Task Actual totals.
  Future<Map<String, int>> _actualMinutesByDate(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final overlapping = await (_db.select(_db.timerSessions)..where(
          (session) =>
              session.deletedAt.isNull() &
              session.state.equals('finished') &
              session.endedAt.isNotNull() &
              session.startedAt.isSmallerThanValue(
                endExclusive.toUtc().toIso8601String(),
              ) &
              session.endedAt.isBiggerThanValue(
                startInclusive.toUtc().toIso8601String(),
              ),
        ))
        .get();
    final taskRows = await (_db.select(_db.tasks)).get();
    final ids = <String>{for (final session in overlapping) session.taskId};
    for (final task in taskRows) {
      if (task.startTime != null &&
          !task.startTime!.isBefore(startInclusive) &&
          task.startTime!.isBefore(endExclusive)) {
        ids.add(task.id);
      }
    }
    if (ids.isEmpty) return const <String, int>{};
    final history = await (_db.select(_db.timerSessions)..where(
          (session) =>
              session.deletedAt.isNull() &
              session.state.equals('finished') &
              session.endedAt.isNotNull() &
              session.taskId.isIn(ids),
        ))
        .get();
    final byTask = <String, List<TimerSessionRow>>{};
    for (final session in history) {
      byTask.putIfAbsent(session.taskId, () => <TimerSessionRow>[]).add(session);
    }
    final result = <String, int>{};
    for (final task in taskRows.where((row) => ids.contains(row.id))) {
      final allocation = TaskActualDurationService.allocateActualByDate(
        task,
        byTask[task.id] ?? const <TimerSessionRow>[],
      );
      for (final entry in allocation.entries) {
        if (entry.key.compareTo(isoDateString(startInclusive)) >= 0 &&
            entry.key.compareTo(isoDateString(endExclusive)) < 0) {
          result[entry.key] = (result[entry.key] ?? 0) + entry.value;
        }
      }
    }
    return result;
  }
}

/// Pure task-level statistics shared by daily review and analytics. Keeping
/// this formula in one place prevents range analytics from drifting from the
/// existing DailyStats semantics.
abstract final class DailyStatsCalculator {
  static double? planningAccuracyPct<T>(
    Iterable<T> tasks, {
    required int? Function(T task) estimatedDurationMin,
    required int? Function(T task) actualDurationMin,
  }) {
    final ratios = <double>[];
    for (final task in tasks) {
      final estimated = estimatedDurationMin(task);
      final actual = actualDurationMin(task);
      if (estimated == null || estimated <= 0 || actual == null) continue;
      ratios.add(actual / estimated);
    }
    return ratios.isEmpty ? null : ratios.average * 100;
  }
}

extension _AvgX on List<double> {
  double get average => isEmpty ? 0 : reduce((a, b) => a + b) / length;
}
