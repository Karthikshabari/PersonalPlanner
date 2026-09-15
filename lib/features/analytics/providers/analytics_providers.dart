import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../domain/analytics_models.dart';
import '../domain/analytics_service.dart';

typedef InsightsClockFactory = Stream<DateTime> Function();
typedef InsightsNowFactory = DateTime Function();

final insightsNowFactoryProvider = Provider<InsightsNowFactory>((ref) {
  return DateTime.now;
});

/// Emits the current instant once, then once at each planner-calendar
/// midnight. Resume checks repair a missed timer while the app was paused.
final insightsClockFactoryProvider = Provider<InsightsClockFactory>((ref) {
  final now = ref.watch(insightsNowFactoryProvider);
  return () => _plannerCalendarClock(now);
});

final insightsClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return ref.watch(insightsClockFactoryProvider)();
});

/// Explicit planner clock consumed by all Insights calculations and the
/// current-week navigation boundary. Keeping this provider auto-disposed
/// makes its timer and lifecycle observer screen-scoped.
final insightsNowProvider = Provider.autoDispose<DateTime>((ref) {
  final clock = ref.watch(insightsClockProvider);
  return clock.value ?? ref.watch(insightsNowFactoryProvider)();
});

final insightsServiceProvider = Provider<InsightsService>((ref) {
  return InsightsService(ref.watch(appDatabaseProvider));
});

final selectedInsightsWeekProvider = StateProvider<DateTime>((ref) {
  // This is initialization only. The selected week must not follow later
  // clock emissions, because those must preserve deliberate history browsing.
  return startOfWeek(ref.read(insightsNowFactoryProvider)());
});

final insightsSnapshotProvider = StreamProvider.autoDispose<InsightsSnapshot>((
  ref,
) {
  final service = ref.watch(insightsServiceProvider);
  final weekStart = ref.watch(selectedInsightsWeekProvider);
  final now = ref.watch(insightsNowProvider);
  return watchReactiveStats(
    ref.read(appDatabaseProvider),
    () => service.compute(weekStart: weekStart, now: now),
  );
});

// Retained as a source-compatible invalidation hook for backup restore code.
final analyticsSnapshotProvider = insightsSnapshotProvider;
final analyticsProvider = insightsSnapshotProvider;

Stream<DateTime> _plannerCalendarClock(DateTime Function() nowFactory) {
  return Stream<DateTime>.multi((controller) {
    var disposed = false;
    Timer? rollover;
    String? plannerDay;

    DateTime currentNow() => nowFactory();

    void emitIfPlannerDayChanged(DateTime now, {bool force = false}) {
      if (disposed) return;
      final day = isoDateString(now);
      if (force || day != plannerDay) {
        plannerDay = day;
        controller.add(now);
      }
    }

    void scheduleNextMidnight() {
      if (disposed) return;
      final now = currentNow();
      final local = PlannerTimeZone.toPlannerLocal(now);
      final nextMidnight = PlannerTimeZone.calendarDate(
        local.year,
        local.month,
        local.day + 1,
      );
      final delay = nextMidnight.difference(now);
      rollover = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (disposed) return;
        emitIfPlannerDayChanged(currentNow());
        scheduleNextMidnight();
      });
    }

    final lifecycleObserver = _InsightsCalendarLifecycleObserver(() {
      if (disposed) return;
      // A timer may not run while backgrounded. Compare planner dates on
      // resume, then always schedule from the newly observed instant.
      emitIfPlannerDayChanged(currentNow());
      rollover?.cancel();
      scheduleNextMidnight();
    });

    WidgetsBinding.instance.addObserver(lifecycleObserver);
    emitIfPlannerDayChanged(currentNow(), force: true);
    scheduleNextMidnight();

    controller.onCancel = () {
      disposed = true;
      rollover?.cancel();
      WidgetsBinding.instance.removeObserver(lifecycleObserver);
    };
  });
}

class _InsightsCalendarLifecycleObserver with WidgetsBindingObserver {
  _InsightsCalendarLifecycleObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
