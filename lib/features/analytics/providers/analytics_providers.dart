import 'dart:async';

import 'package:drift/drift.dart'
    show ResultSetImplementation, TableUpdateQuery;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../../core/utils/date_utils.dart';
import '../../settings/providers/week_start_provider.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../day_context/domain/break_day.dart';
import '../../day_context/providers/day_context_presets_provider.dart';
import '../domain/analytics_models.dart';
import '../domain/analytics_service.dart';
import '../domain/follow_through_target.dart';

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

/// Settings "Follow-through target": the share of planned time a day needs
/// to count as a Success. Stored per device in `app_settings`; not synced and
/// not part of portable backup.
final followThroughTargetProvider =
    AsyncNotifierProvider<FollowThroughTargetNotifier, double>(
      FollowThroughTargetNotifier.new,
    );

class FollowThroughTargetNotifier extends AsyncNotifier<double> {
  @override
  Future<double> build() async {
    final db = ref.watch(appDatabaseProvider);
    final raw = await db.syncDao.getSetting(followThroughTargetSettingKey);
    return decodeFollowThroughTarget(raw);
  }

  Future<void> setTarget(double target) async {
    final previous = state.value ?? defaultFollowThroughTarget;
    state = AsyncData(target);
    try {
      await ref
          .read(appDatabaseProvider)
          .syncDao
          .setSetting(
            followThroughTargetSettingKey,
            encodeFollowThroughTarget(target),
          );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

/// The target while the stored one loads is the default; a different stored
/// value then recalculates once.
final _selectedFollowThroughTargetProvider = Provider.autoDispose<double>(
  (ref) => ref.watch(
    followThroughTargetProvider.select(
      (value) => value.value ?? defaultFollowThroughTarget,
    ),
  ),
);

final selectedInsightsWeekProvider = StateProvider<DateTime>((ref) {
  // This is initialization only. The selected week must not follow later
  // clock emissions, because those must preserve deliberate history browsing.
  // Only a change of the week-start setting re-derives it.
  ref.watch(weekStartDayProvider);
  return startOfWeek(ref.read(insightsNowFactoryProvider)());
});

/// Counts, without running any query, how often a table Insights reads has
/// changed. Not auto-disposed, so it keeps counting while Insights is hidden.
/// It counts synchronously, in the same turn as Drift's notification: a
/// deferred count would leave a window in which the cache looks current right
/// after a write. It reads the database only through `appDatabaseProvider`, so
/// a new account database restarts it at 0.
class InsightsSourceRevision extends Notifier<int> {
  @override
  int build() {
    final db = ref.watch(appDatabaseProvider);
    final subscription = db
        .tableUpdates(TableUpdateQuery.onAllTables(_insightsTables(db)))
        .listen((_) => state = state + 1);
    ref.onDispose(subscription.cancel);
    return 0;
  }
}

final insightsSourceRevisionProvider =
    NotifierProvider<InsightsSourceRevision, int>(InsightsSourceRevision.new);

/// The last snapshot with what it was computed for. It is only shown again
/// when no Insights source table changed since (same revision), the selected
/// week is the same and it is still the same planner day.
class InsightsSnapshotCacheEntry {
  const InsightsSnapshotCacheEntry({
    required this.snapshot,
    required this.revision,
    required this.weekStart,
    required this.today,
    this.breakDays,
  });

  final InsightsSnapshot snapshot;

  /// The break-day rule the snapshot was computed with.
  final BreakDayRule? breakDays;
  final int revision;
  final DateTime weekStart;

  /// `yyyy-MM-dd`.
  final String today;

  bool isCurrent({
    required int revision,
    required DateTime weekStart,
    required String today,
  }) =>
      this.revision == revision &&
      this.weekStart == weekStart &&
      this.today == today;
}

/// One entry, so memory stays bounded. Watches the database so an account
/// switch empties it.
class InsightsSnapshotCache extends Notifier<InsightsSnapshotCacheEntry?> {
  @override
  InsightsSnapshotCacheEntry? build() {
    ref.watch(appDatabaseProvider);
    return null;
  }

  void store(InsightsSnapshotCacheEntry entry) {
    final current = state;
    if (current != null && current.revision > entry.revision) return;
    state = entry;
  }
}

final insightsSnapshotCacheProvider =
    NotifierProvider<InsightsSnapshotCache, InsightsSnapshotCacheEntry?>(
      InsightsSnapshotCache.new,
    );

/// The cached snapshot when it is still exactly what a fresh calculation would
/// return, otherwise null. Lets the screen show it in the first frame.
final insightsCachedSnapshotProvider = Provider.autoDispose<InsightsSnapshot?>((
  ref,
) {
  final entry = ref.watch(insightsSnapshotCacheProvider);
  final revision = ref.watch(insightsSourceRevisionProvider);
  final weekStart = ref.watch(selectedInsightsWeekProvider);
  final today = ref.watch(
    insightsNowProvider.select((now) => isoDateString(now)),
  );
  final target = ref.watch(_selectedFollowThroughTargetProvider);
  if (entry == null) return null;
  return entry.isCurrent(
            revision: revision,
            weekStart: weekStart,
            today: today,
          ) &&
          entry.snapshot.followThroughTarget == target
      ? entry.snapshot
      : null;
});

List<ResultSetImplementation<dynamic, dynamic>> _insightsTables(
  AppDatabase db,
) => [db.tasks, db.timerSessions, db.categories, db.dayContexts];

final insightsSnapshotProvider = StreamProvider.autoDispose<InsightsSnapshot>((
  ref,
) {
  final service = ref.watch(insightsServiceProvider);
  final weekStart = ref.watch(selectedInsightsWeekProvider);
  // Rebuilds only when the planner day changes. The clock stream delivers its
  // first value just after the first build; depending on the instant itself
  // would rebuild (and recalculate) the snapshot a second time on every open.
  final today = ref.watch(
    insightsNowProvider.select((now) => isoDateString(now)),
  );
  final target = ref.watch(_selectedFollowThroughTargetProvider);
  final breakDays = ref.watch(breakDayRuleProvider);
  final now = ref.read(insightsNowProvider);
  final database = ref.read(appDatabaseProvider);
  final cacheNotifier = ref.read(insightsSnapshotCacheProvider.notifier);
  final cached = ref.read(insightsSnapshotCacheProvider);
  final initial =
      cached != null &&
          cached.isCurrent(
            revision: ref.read(insightsSourceRevisionProvider),
            weekStart: weekStart,
            today: today,
          ) &&
          cached.snapshot.followThroughTarget == target &&
          cached.breakDays == breakDays
      ? cached.snapshot
      : null;
  return watchReactiveStats(
    database,
    () async {
      // Read before the calculation starts: a write that lands during it
      // makes the stored entry older than the current revision, so it is not
      // reused.
      final revision = ref.read(insightsSourceRevisionProvider);
      // The stored target, not the default shown while it loads.
      final storedTarget = await ref.read(followThroughTargetProvider.future);
      final storedBreakDays = await readBreakDayRule(ref);
      final snapshot = await service.compute(
        weekStart: weekStart,
        now: now,
        followThroughTarget: storedTarget,
        breakDays: storedBreakDays,
      );
      if (ref.mounted) {
        cacheNotifier.store(
          InsightsSnapshotCacheEntry(
            snapshot: snapshot,
            revision: revision,
            weekStart: weekStart,
            today: today,
            breakDays: storedBreakDays,
          ),
        );
      }
      return snapshot;
    },
    tables: _insightsTables(database),
    initial: initial,
    isSame: sameInsightsSnapshot,
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
