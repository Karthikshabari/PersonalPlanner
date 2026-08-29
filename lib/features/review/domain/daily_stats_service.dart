import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/daily_stats.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/date_utils.dart';

/// Computes per-day aggregates and maintains the `daily_stats_cache` table
/// (planner.md Chunk 5 #9). Triggered when a daily review is saved; Chunk 7's
/// analytics screen will trigger it on open through [computeAndCache].
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

    final sessions =
        await (_db.select(_db.timerSessions)..where(
              (session) =>
                  session.deletedAt.isNull() &
                  session.endedAt.isNotNull() &
                  session.startedAt.isSmallerThanValue(
                    endExclusive.toUtc().toIso8601String(),
                  ) &
                  session.endedAt.isBiggerThanValue(
                    startInclusive.toUtc().toIso8601String(),
                  ),
            ))
            .get();
    final sessionsByTask = <String, List<TimerSessionRow>>{};
    for (final session in sessions) {
      sessionsByTask.putIfAbsent(session.taskId, () => []).add(session);
    }
    final tasksStartingInRange = tasks
        .where(
          (task) =>
              task.startTime != null &&
              !task.startTime!.isBefore(startInclusive) &&
              task.startTime!.isBefore(endExclusive),
        )
        .toList(growable: false);

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
      if (startsInRange) {
        final taskSessions = sessionsByTask[t.id] ?? const <TimerSessionRow>[];
        final completedSeconds = taskSessions.fold<int>(0, (sum, session) {
          final endedAt = session.endedAt ?? now;
          final overlapStart = session.startedAt.isAfter(startInclusive)
              ? session.startedAt
              : startInclusive;
          final overlapEnd = endedAt.isBefore(endExclusive)
              ? endedAt
              : endExclusive;
          if (!overlapEnd.isAfter(overlapStart)) return sum;
          return sum + overlapEnd.difference(overlapStart).inSeconds;
        });
        final allCompletedSeconds = taskSessions.fold<int>(
          0,
          (sum, session) => sum + session.durationSec,
        );
        final recordedMinutes =
            t.actualDurationMin ??
            allCompletedSeconds ~/ Duration.secondsPerMinute +
                t.manualDurationAdjustmentMin;
        final inferredAdjustment =
            recordedMinutes - allCompletedSeconds ~/ Duration.secondsPerMinute;
        actualMin +=
            completedSeconds ~/ Duration.secondsPerMinute + inferredAdjustment;
      } else {
        final taskSessions = sessionsByTask[t.id] ?? const <TimerSessionRow>[];
        for (final session in taskSessions) {
          final endedAt = session.endedAt ?? now;
          final overlapStart = session.startedAt.isAfter(startInclusive)
              ? session.startedAt
              : startInclusive;
          final overlapEnd = endedAt.isBefore(endExclusive)
              ? endedAt
              : endExclusive;
          if (overlapEnd.isAfter(overlapStart)) {
            actualMin += overlapEnd.difference(overlapStart).inMinutes;
          }
        }
      }
    }

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
        estimatedDurationMin: (task) => task.estimatedDurationMin,
        actualDurationMin: (task) => task.actualDurationMin,
      ),
      computedAt: DateTime.now(),
    );
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
