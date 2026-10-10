import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/providers/brief_keep_alive.dart'
    show briefKeepAliveDuration;
import '../../../core/utils/date_utils.dart';
import '../../day_context/providers/day_context_providers.dart';
import 'review_providers.dart';

/// Providers the Daily Review is likely to need next: the previous and next
/// day, and the week the day belongs to (the Weekly tab).
List<ProviderListenable<Object?>> dailyReviewWarmTargets(DateTime date) {
  final day = startOfDay(date);
  final week = startOfWeek(day);
  return [
    for (final d in [addDays(day, -1), addDays(day, 1)]) ...[
      dailyStatsProvider(d),
      dailyReviewInsightsProvider(d),
      taskOutcomesProvider(d),
      dailyReviewProvider(d),
      dayContextForDateProvider(d),
    ],
    weeklyDaysProvider(week),
    weeklyReviewProvider(week),
  ];
}

/// Providers the Weekly Review is likely to need next: the previous and next
/// week, and the Monday of this week (the Daily tab).
List<ProviderListenable<Object?>> weeklyReviewWarmTargets(DateTime weekStart) {
  final week = startOfWeek(weekStart);
  return [
    for (final w in [addDays(week, -7), addDays(week, 7)]) ...[
      weeklyDaysProvider(w),
      weeklyReviewProvider(w),
    ],
    dailyStatsProvider(week),
    dailyReviewInsightsProvider(week),
    taskOutcomesProvider(week),
    dailyReviewProvider(week),
    dayContextForDateProvider(week),
  ];
}

/// Holds quiet listeners on providers that are likely needed next so their
/// data is already there when the user steps to them. The providers are kept
/// alive only while a listener exists plus a short grace period
/// ([briefKeepAliveDuration]), so the set stays small. Nothing here rebuilds
/// the widget.
class ReviewWarmup {
  final _subscriptions = <ProviderSubscription<Object?>>[];

  /// Switches to [targets]. The new listeners are added before the old ones
  /// are closed, so a provider in both sets is never released in between.
  void replace(WidgetRef ref, Iterable<ProviderListenable<Object?>> targets) {
    final next = [
      for (final target in targets)
        ref.listenManual<Object?>(target, (_, _) {}),
    ];
    for (final old in _subscriptions) {
      old.close();
    }
    _subscriptions
      ..clear()
      ..addAll(next);
  }
}
