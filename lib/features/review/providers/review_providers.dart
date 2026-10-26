import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/models/daily_review.dart';
import '../../../core/models/daily_stats.dart';
import '../../../core/models/weekly_review.dart';
import '../../../core/providers/brief_keep_alive.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../../core/utils/date_utils.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../settings/providers/week_start_provider.dart';
import '../../day_context/providers/day_context_presets_provider.dart';
import '../data/review_repository.dart';
import '../domain/daily_stats_service.dart';
import '../domain/review_insights.dart';
import '../domain/review_overview.dart';
import '../domain/review_result_equality.dart';
import '../domain/task_outcome.dart';
import '../domain/task_outcome_service.dart';
import '../domain/weekly_review_history.dart';
import '../domain/weekly_review_numbers.dart';
import '../domain/weekly_review_service.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
});

final dailyStatsServiceProvider = Provider<DailyStatsService>((ref) {
  return DailyStatsService(ref.watch(appDatabaseProvider));
});

final reviewInsightsServiceProvider = Provider<ReviewInsightsService>((ref) {
  return ReviewInsightsService(ref.watch(appDatabaseProvider));
});

/// Date shown on the Daily Review screen (defaults to today).
final selectedReviewDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return startOfDay(now);
});

/// First day of the week shown on the Weekly Review / Week View screens.
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  // Re-derived when the week-start setting changes.
  ref.watch(weekStartDayProvider);
  return startOfWeek(DateTime.now());
});

/// The day Overview › Days has selected (defaults to today).
final overviewSelectedDayProvider = StateProvider<DateTime>((ref) {
  return startOfDay(DateTime.now());
});

/// The week start Overview › Weeks has selected (defaults to this week).
/// Held here, not in the strips, so it survives switching Days and Weeks.
final overviewSelectedWeekProvider = StateProvider<DateTime>((ref) {
  ref.watch(weekStartDayProvider);
  return startOfWeek(DateTime.now());
});

/// The day Daily opens for the week shown on Weekly: today when the week
/// contains it, otherwise the week's first day.
DateTime dailyDateForWeek(DateTime weekStart, DateTime today) {
  final day = startOfDay(today);
  return startOfWeek(day) == weekStart ? day : weekStart;
}

/// Moves each Review selection to the new today (or this week) when the
/// planner day changes, but only a selection that was on the old one; a
/// deliberately browsed date is left alone. Rides the Insights midnight and
/// resume clock, so it adds no timer. Watched by the Review screens.
final reviewRolloverProvider = Provider.autoDispose<void>((ref) {
  ref.listen(insightsNowProvider.select(startOfDay), (previous, today) {
    if (previous == null) return;
    for (final days in [
      selectedReviewDateProvider,
      overviewSelectedDayProvider,
    ]) {
      if (ref.read(days) == previous) ref.read(days.notifier).state = today;
    }
    final week = startOfWeek(previous);
    for (final weeks in [
      selectedWeekStartProvider,
      overviewSelectedWeekProvider,
    ]) {
      if (ref.read(weeks) == week) {
        ref.read(weeks.notifier).state = startOfWeek(today);
      }
    }
  });
});

/// The saved review for a date (null when none yet).
final dailyReviewProvider = StreamProvider.autoDispose
    .family<DailyReview?, DateTime>((ref, date) {
      keepAliveBriefly(ref);
      return ref.watch(reviewRepositoryProvider).watchReviewForDate(date);
    });

/// The saved review for the Mon–Sun week starting at [weekStart].
final weeklyReviewProvider = StreamProvider.autoDispose
    .family<WeeklyReview?, DateTime>((ref, weekStart) {
      keepAliveBriefly(ref);
      return ref
          .watch(reviewRepositoryProvider)
          .watchWeeklyReviewForWeek(weekStart);
    });

/// Live-computed aggregates for one calendar day.
final dailyStatsProvider = StreamProvider.autoDispose
    .family<DailyStats, DateTime>((ref, date) {
      keepAliveBriefly(ref);
      final normalized = startOfDay(date);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(dailyStatsServiceProvider).computeForDate(normalized),
        isSame: sameDailyStats,
      );
    });

/// Aggregated task stats across the Mon–Sun week starting at [weekStart]
/// (sums of counts/durations; averages where noted on the screen).
final weeklyStatsProvider = StreamProvider.autoDispose
    .family<DailyStats, DateTime>((ref, weekStart) {
      final start = startOfWeek(weekStart);
      final end = addDays(start, 7);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(dailyStatsServiceProvider).computeRange(start, end),
        isSame: sameDailyStats,
      );
    });

final dailyReviewInsightsProvider = StreamProvider.autoDispose
    .family<ReviewInsights, DateTime>((ref, date) {
      keepAliveBriefly(ref);
      final normalized = startOfDay(date);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(reviewInsightsServiceProvider).forDay(normalized),
        isSame: sameReviewInsights,
      );
    });

final taskOutcomeServiceProvider = Provider<TaskOutcomeService>((ref) {
  return TaskOutcomeService(ref.watch(appDatabaseProvider));
});

/// One row per task starting on [date], ordered by start time.
final taskOutcomesProvider = StreamProvider.autoDispose
    .family<List<TaskOutcomeRow>, DateTime>((ref, date) {
      keepAliveBriefly(ref);
      final normalized = startOfDay(date);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(taskOutcomeServiceProvider).forDay(normalized),
        isSame: sameTaskOutcomes,
      );
    });

final reviewOverviewServiceProvider = Provider<ReviewOverviewService>((ref) {
  return ReviewOverviewService(ref.watch(appDatabaseProvider));
});

/// The last [dayCount] days ending today, newest first. Reacts to task,
/// review and day-context writes.
final reviewOverviewWindowProvider = StreamProvider.autoDispose
    .family<List<ReviewOverviewDay>, int>((ref, dayCount) {
      keepAliveBriefly(ref);
      ref.watch(breakDayRuleProvider);
      // Re-read when the planner day rolls over, so "Today" moves on.
      final today = ref.watch(insightsNowProvider.select(startOfDay));
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () async => ref
            .read(reviewOverviewServiceProvider)
            .window(
              today: today,
              dayCount: dayCount,
              breakDays: await readBreakDayRule(ref),
            ),
        isSame: sameOverviewDays,
      );
    });

final weeklyReviewHistoryServiceProvider = Provider<WeeklyReviewHistoryService>(
  (ref) {
    return WeeklyReviewHistoryService(ref.watch(appDatabaseProvider));
  },
);

/// The 52 weeks before [weekStart], oldest first: saved mood, feeling, note
/// and completion. A one-off read (no stream); the Weekly screen invalidates
/// it after every save (WD13).
final weeklyReviewHistoryProvider = FutureProvider.autoDispose
    .family<List<WeeklyHistoryWeek>, DateTime>((ref, weekStart) async {
      ref.watch(breakDayRuleProvider);
      return ref
          .watch(weeklyReviewHistoryServiceProvider)
          .load(startOfWeek(weekStart), breakDays: await readBreakDayRule(ref));
    });

/// Overview › Weekly: the last [weekCount] weeks ending with this week,
/// newest first. A one-off read, invalidated after every weekly save.
final reviewOverviewWeekWindowProvider = FutureProvider.autoDispose
    .family<List<WeeklyHistoryWeek>, int>((ref, weekCount) async {
      ref.watch(breakDayRuleProvider);
      ref.watch(weekStartDayProvider);
      final today = ref.watch(insightsNowProvider.select(startOfDay));
      return ref
          .watch(weeklyReviewHistoryServiceProvider)
          .window(
            today: today,
            weekCount: weekCount,
            breakDays: await readBreakDayRule(ref),
          );
    });

final weeklyReviewServiceProvider = Provider<WeeklyReviewService>((ref) {
  return WeeklyReviewService(ref.watch(appDatabaseProvider));
});

/// The seven days of the week starting at [weekStart] with their tasks,
/// reasons, moods and day contexts. Recomputed only when a task, review or
/// day-context row changes (no timers).
final weeklyDaysProvider = StreamProvider.autoDispose
    .family<List<WeeklyDayInput>, DateTime>((ref, weekStart) {
      keepAliveBriefly(ref);
      final normalized = startOfWeek(weekStart);
      ref.watch(breakDayRuleProvider);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () async => ref
            .read(weeklyReviewServiceProvider)
            .loadWeek(normalized, breakDays: await readBreakDayRule(ref)),
        isSame: sameWeeklyDays,
      );
    });
