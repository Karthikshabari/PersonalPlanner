import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/daos/tag_dao.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../analytics/providers/analytics_providers.dart';
import '../../task_editor/data/tag_repository.dart';
import '../../task_editor/providers/tag_providers.dart';
import '../data/experiment_repository.dart';
import '../../day_context/domain/break_day.dart';
import '../../day_context/providers/day_context_presets_provider.dart';
import '../../settings/providers/week_start_provider.dart';
import '../domain/experiment_dashboard.dart';
import '../domain/kept_experiment.dart';

/// Set by the Inbox ("See in Insights") to the id of the experiment to show.
/// The Experiments card reads it once, picks the segment the experiment is in
/// (Running, Kept or Concluded), scrolls its row into view and clears it.
final experimentFocusProvider = StateProvider<String?>((ref) => null);

/// An experiment that was just deleted, shown as a one-line message with Undo
/// on the Experiments card. [revision] is the one the delete produced.
typedef ExperimentDeletedEntry = ({
  String experimentId,
  String name,
  int revision,
});

/// The experiment deleted last. Auto-disposed, so it is forgotten when
/// Insights is left; a newer delete replaces it.
final experimentDeletedProvider =
    StateProvider.autoDispose<ExperimentDeletedEntry?>((ref) => null);

/// An experiment that was just ended early ("End today"), shown as a one-line
/// message with Undo on the Experiments card. [previousEndDate] is the end
/// date to put back; [revision] is the one the write produced.
typedef ExperimentEndedEntry = ({
  String experimentId,
  String previousEndDate,
  int revision,
});

/// The experiment ended early last. Auto-disposed like
/// [experimentDeletedProvider]; a newer one replaces it.
final experimentEndedProvider =
    StateProvider.autoDispose<ExperimentEndedEntry?>((ref) => null);

/// An experiment that was just concluded from its end panel, shown as a
/// one-line message with Undo on the Experiments card. [revision] is the one
/// the conclusion produced.
typedef ExperimentConcludedEntry = ({String experimentId, int revision});

/// The experiment concluded last. Auto-disposed like
/// [experimentDeletedProvider]; a newer one replaces it.
final experimentConcludedProvider =
    StateProvider.autoDispose<ExperimentConcludedEntry?>((ref) => null);

final experimentRepositoryProvider = Provider<ExperimentRepository>((ref) {
  return ExperimentRepository(ref.watch(appDatabaseProvider));
});

/// Counts, without running any query, how often a table the Experiments card
/// reads has changed (ED24). Not auto-disposed, so it keeps counting while
/// Insights is hidden. Bursts of notifications in one event-loop turn
/// increment it once (ED53). It reads the database only through
/// `appDatabaseProvider`, so a new account database restarts it at 0 (ED44).
class ExperimentSourceRevision extends Notifier<int> {
  @override
  int build() {
    final db = ref.watch(appDatabaseProvider);
    Timer? pending;
    final subscription = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            db.tasks,
            db.tags,
            db.experiments,
            db.experimentCheckIns,
            db.dayContexts,
          ]),
        )
        .listen((_) {
          if (pending != null) return;
          pending = Timer(Duration.zero, () {
            pending = null;
            state = state + 1;
          });
        });
    ref.onDispose(() {
      pending?.cancel();
      subscription.cancel();
    });
    return 0;
  }
}

final experimentSourceRevisionProvider =
    NotifierProvider<ExperimentSourceRevision, int>(
      ExperimentSourceRevision.new,
    );

/// The last dashboard with the revision and date it was computed for.
class ExperimentDashboardCacheEntry {
  const ExperimentDashboardCacheEntry({
    required this.dashboard,
    required this.revision,
    required this.today,
    this.breakDays,
    this.weekStart = WeekStartDay.monday,
  });

  final ExperimentDashboard dashboard;
  final int revision;

  /// The break-day rule the dashboard was computed with.
  final BreakDayRule? breakDays;

  /// The week-start setting the Kept weeks were computed with.
  final WeekStartDay weekStart;

  /// `yyyy-MM-dd`.
  final String today;
}

/// Keeps the last dashboard across tab switches. Not auto-disposed; it
/// watches the database so an account switch empties it (ED44).
class ExperimentDashboardCache
    extends Notifier<ExperimentDashboardCacheEntry?> {
  @override
  ExperimentDashboardCacheEntry? build() {
    ref.watch(appDatabaseProvider);
    return null;
  }

  void store(ExperimentDashboardCacheEntry entry) {
    final current = state;
    if (current != null && current.revision > entry.revision) return;
    state = entry;
  }
}

final experimentDashboardCacheProvider =
    NotifierProvider<ExperimentDashboardCache, ExperimentDashboardCacheEntry?>(
      ExperimentDashboardCache.new,
    );

/// The dashboard shown by the card. Alive only while Insights is shown.
///
/// The create function is not `async` (ED42): when the cache holds a
/// dashboard for the same revision and date it returns that dashboard itself,
/// so the provider starts in the data state with no query and no loading
/// frame. Otherwise it returns the `Future` of one load, which stores its
/// result in the cache. Automatic retry is off (ED43); the card shows a retry
/// button instead.
final experimentDashboardProvider =
    FutureProvider.autoDispose<ExperimentDashboard>((ref) {
      // Watched on a cache hit too, so a replaced account database always
      // rebuilds the provider (invariant 2, ED44).
      final db = ref.watch(appDatabaseProvider);
      final today = ref.watch(
        insightsNowProvider.select((now) => isoDateString(now)),
      );
      final revision = ref.watch(experimentSourceRevisionProvider);
      final breakDays = ref.watch(breakDayRuleProvider);
      // The Kept weeks follow the setting, which `startOfWeek` reads.
      final weekStart = ref.watch(
        weekStartDayProvider.select((v) => v.value ?? WeekStartDay.monday),
      );
      final cached = ref.read(experimentDashboardCacheProvider);
      if (cached != null &&
          cached.revision == revision &&
          cached.today == today &&
          cached.breakDays == breakDays &&
          cached.weekStart == weekStart) {
        return cached.dashboard;
      }
      final service = ExperimentDashboardService(
        db,
        formatDuration: formatMinutes,
      );
      return readBreakDayRule(ref).then((storedBreakDays) async {
        final dashboard = await service.load(
          today: today,
          breakDays: storedBreakDays,
        );
        if (ref.mounted) {
          ref
              .read(experimentDashboardCacheProvider.notifier)
              .store(
                ExperimentDashboardCacheEntry(
                  dashboard: dashboard,
                  revision: revision,
                  today: today,
                  breakDays: storedBreakDays,
                  weekStart: weekStart,
                ),
              );
        }
        return dashboard;
      });
    }, retry: (retryCount, error) => null);

/// The kept rows, taken from the dashboard value (or, before the first load
/// finishes, from the cached dashboard). It issues no query of its own and
/// reads no table. [KeptSegment] has deep value equality, so a reload that
/// changes nothing kept notifies nobody (a write to an untagged task reloads
/// the dashboard but does not rebuild the Kept list).
final keptSegmentProvider = Provider.autoDispose<KeptSegment>((ref) {
  final kept = ref.watch(
    experimentDashboardProvider.select((dashboard) => dashboard.value?.kept),
  );
  return kept ??
      ref.read(experimentDashboardCacheProvider)?.dashboard.kept ??
      emptyKeptSegment;
});

/// The active tags the start form matches the typed name against.
final experimentFormTagsProvider =
    FutureProvider.autoDispose<List<TagOptionRow>>(
      (ref) => ref.watch(tagOptionsProvider.future),
    );

/// How many blocks a tag has and the date of the first one (for the form).
final tagUsageProvider = FutureProvider.autoDispose.family<TagUsage, String>(
  (ref, tagId) => ref.watch(tagRepositoryProvider).getUsage(tagId),
);
