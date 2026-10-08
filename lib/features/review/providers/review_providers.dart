import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/models/daily_review.dart';
import '../../../core/models/daily_stats.dart';
import '../../../core/models/weekly_review.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../../core/utils/date_utils.dart';
import '../data/review_repository.dart';
import '../domain/daily_stats_service.dart';
import '../domain/review_insights.dart';
import '../domain/review_overview.dart';
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

/// Monday of the week shown on the Weekly Review / Week View screens.
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  return startOfWeek(DateTime.now());
});

/// The saved review for a date (null when none yet).
final dailyReviewProvider = StreamProvider.autoDispose
    .family<DailyReview?, DateTime>((ref, date) {
      return ref.watch(reviewRepositoryProvider).watchReviewForDate(date);
    });

/// The saved review for the Mon–Sun week starting at [weekStart].
final weeklyReviewProvider = StreamProvider.autoDispose
    .family<WeeklyReview?, DateTime>((ref, weekStart) {
      return ref
          .watch(reviewRepositoryProvider)
          .watchWeeklyReviewForWeek(weekStart);
    });

/// Live-computed aggregates for one calendar day.
final dailyStatsProvider = StreamProvider.autoDispose
    .family<DailyStats, DateTime>((ref, date) {
      final normalized = startOfDay(date);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(dailyStatsServiceProvider).computeForDate(normalized),
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
      );
    });

final dailyReviewInsightsProvider = StreamProvider.autoDispose
    .family<ReviewInsights, DateTime>((ref, date) {
      final normalized = startOfDay(date);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(reviewInsightsServiceProvider).forDay(normalized),
      );
    });

final taskOutcomeServiceProvider = Provider<TaskOutcomeService>((ref) {
  return TaskOutcomeService(ref.watch(appDatabaseProvider));
});

/// One row per task starting on [date], ordered by start time.
final taskOutcomesProvider = StreamProvider.autoDispose
    .family<List<TaskOutcomeRow>, DateTime>((ref, date) {
      final normalized = startOfDay(date);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(taskOutcomeServiceProvider).forDay(normalized),
      );
    });

final reviewOverviewServiceProvider = Provider<ReviewOverviewService>((ref) {
  return ReviewOverviewService(ref.watch(appDatabaseProvider));
});

/// The last [dayCount] days ending today, newest first. Reacts to task,
/// review and day-context writes.
final reviewOverviewWindowProvider = StreamProvider.autoDispose
    .family<List<ReviewOverviewDay>, int>((ref, dayCount) {
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref
            .read(reviewOverviewServiceProvider)
            .window(today: DateTime.now(), dayCount: dayCount),
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
    .family<List<WeeklyHistoryWeek>, DateTime>((ref, weekStart) {
      return ref
          .watch(weeklyReviewHistoryServiceProvider)
          .load(startOfWeek(weekStart));
    });

final weeklyReviewServiceProvider = Provider<WeeklyReviewService>((ref) {
  return WeeklyReviewService(ref.watch(appDatabaseProvider));
});

/// The seven days of the week starting at [weekStart] with their tasks,
/// reasons, moods and day contexts. Recomputed only when a task, review or
/// day-context row changes (no timers).
final weeklyDaysProvider = StreamProvider.autoDispose
    .family<List<WeeklyDayInput>, DateTime>((ref, weekStart) {
      final normalized = startOfWeek(weekStart);
      return watchReactiveStats(
        ref.read(appDatabaseProvider),
        () => ref.read(weeklyReviewServiceProvider).loadWeek(normalized),
      );
    });
