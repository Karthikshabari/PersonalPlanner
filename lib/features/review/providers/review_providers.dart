import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/models/daily_review.dart';
import '../../../core/models/daily_stats.dart';
import '../../../core/models/weekly_review.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../data/review_repository.dart';
import '../domain/daily_stats_service.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
});

final dailyStatsServiceProvider = Provider<DailyStatsService>((ref) {
  return DailyStatsService(ref.watch(appDatabaseProvider));
});

/// Date shown on the Daily Review screen (defaults to today).
final selectedReviewDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Monday of the week shown on the Weekly Review / Week View screens.
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  return startOfWeek(DateTime.now());
});

/// The saved review for a date (null when none yet).
final dailyReviewProvider =
    StreamProvider.autoDispose.family<DailyReview?, DateTime>((ref, date) {
  return ref.watch(reviewRepositoryProvider).watchReviewForDate(date);
});

/// The saved review for the Mon–Sun week starting at [weekStart].
final weeklyReviewProvider =
    StreamProvider.autoDispose.family<WeeklyReview?, DateTime>((ref, weekStart) {
  return ref.watch(reviewRepositoryProvider).watchWeeklyReviewForWeek(weekStart);
});

/// Live-computed aggregates for one calendar day.
final dailyStatsProvider =
    StreamProvider.autoDispose.family<DailyStats, DateTime>((ref, date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return _reactiveStatsStream(
    ref,
    () => ref.read(dailyStatsServiceProvider).computeForDate(normalized),
  );
});

/// Aggregated task stats across the Mon–Sun week starting at [weekStart]
/// (sums of counts/durations; averages where noted on the screen).
final weeklyStatsProvider =
    StreamProvider.autoDispose.family<DailyStats, DateTime>((ref, weekStart) {
  final start = startOfWeek(weekStart);
  final end = start.add(const Duration(days: 7));
  return _reactiveStatsStream(
    ref,
    () => ref.read(dailyStatsServiceProvider).computeRange(start, end),
  );
});

Stream<DailyStats> _reactiveStatsStream(
  Ref ref,
  Future<DailyStats> Function() compute,
) {
  final db = ref.read(appDatabaseProvider);
  return Stream<DailyStats>.multi((controller) {
    var disposed = false;
    Timer? pending;
    final subscriptions = <StreamSubscription<dynamic>>[];

    Future<void> refresh() async {
      try {
        final value = await compute();
        if (!disposed) controller.add(value);
      } catch (error, stack) {
        if (!disposed) controller.addError(error, stack);
      }
    }

    void scheduleRefresh([Object? _]) {
      pending?.cancel();
      pending = Timer(Duration.zero, refresh);
    }

    subscriptions.add(db.select(db.tasks).watch().listen(scheduleRefresh));
    subscriptions
        .add(db.select(db.categories).watch().listen(scheduleRefresh));
    subscriptions
        .add(db.select(db.timerSessions).watch().listen(scheduleRefresh));
    subscriptions
        .add(db.select(db.dailyReviews).watch().listen(scheduleRefresh));
    subscriptions
        .add(db.select(db.weeklyReviews).watch().listen(scheduleRefresh));
    scheduleRefresh();

    controller.onCancel = () async {
      disposed = true;
      pending?.cancel();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
  });
}
