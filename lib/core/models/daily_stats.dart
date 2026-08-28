import 'package:freezed_annotation/freezed_annotation.dart';

part 'daily_stats.freezed.dart';

/// Computed aggregates for one day — mirrors `daily_stats_cache`
/// (architecture.md §3). Not synced.
@freezed
abstract class DailyStats with _$DailyStats {
  const factory DailyStats({
    required DateTime date,
    @Default(0) int totalTasks,
    @Default(0) int completedTasks,
    @Default(0) int plannedTasks,
    @Default(0) int inProgressTasks,
    @Default(0) int missedTasks,
    @Default(0) int skippedTasks,
    @Default(0) int cancelledTasks,
    @Default(0) int rescheduledTasks,
    @Default(0) int plannedDurationMin,
    @Default(0) int actualDurationMin,
    @Default(0) int focusDurationMin,
    int? energyLevel,
    int? productivityRating,
    double? planningAccuracyPct,
    required DateTime computedAt,
  }) = _DailyStats;
}

extension DailyStatsX on DailyStats {
  /// Completion rate = completed / (total − cancelled) × 100
  /// (architecture.md §10 metric #1). Null when nothing is rateable.
  double? get completionRatePct {
    final denominator = totalTasks - cancelledTasks;
    if (denominator <= 0) return null;
    return completedTasks / denominator * 100;
  }
}
