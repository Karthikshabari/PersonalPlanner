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
      _computeRange(startOfDay(date), startOfDay(date).add(const Duration(days: 1)));

  /// Computes aggregates over [start, end) (used for weekly totals).
  Future<DailyStats> computeRange(DateTime start, DateTime end) =>
      _computeRange(startOfDay(start), startOfDay(end));

  /// Computes the day's aggregates and stores them in `daily_stats_cache`,
  /// replacing any previous snapshot. Returns the stored value.
  Future<DailyStats> computeAndCache(DateTime date) async {
    final stats = await computeForDate(date);
    final dayIso = isoDateString(startOfDay(date));
    await _db.statsDao.upsertStats(DailyStatsCacheCompanion.insert(
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
    ));
    return stats;
  }

  Future<DailyStats> _computeRange(DateTime startInclusive,
      DateTime endExclusive) async {
    final tasks = await _db.taskDao.getTasksBetween(startInclusive, endExclusive);
    final categories = await _db.categoryDao.getActiveCategories();
    final focusIds = {for (final c in categories) c.id: c.isFocus};
    final now = DateTime.now();

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
    final accuracyRatios = <double>[];

    for (final t in tasks) {
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
      if (t.startTime != null && t.endTime != null) {
        final minutes = t.endTime!.difference(t.startTime!).inMinutes;
        plannedMin += minutes;
        final isFocus =
            t.categoryId != null && focusIds[t.categoryId!] == true;
        if (isFocus) focusMin += minutes;
      }
      actualMin += t.actualDurationMin ?? 0;
      if (t.actualDurationMin != null &&
          t.estimatedDurationMin != null &&
          t.estimatedDurationMin! > 0) {
        accuracyRatios.add(t.actualDurationMin! / t.estimatedDurationMin!);
      }
    }

    final review =
        await _db.reviewDao.getDailyReviewByDate(isoDateString(startInclusive));

    return DailyStats(
      date: startInclusive,
      totalTasks: tasks.length,
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
      planningAccuracyPct: accuracyRatios.isEmpty
          ? null
          : accuracyRatios.average * 100,
      computedAt: DateTime.now(),
    );
  }
}

extension _AvgX on List<double> {
  double get average => isEmpty ? 0 : reduce((a, b) => a + b) / length;
}
