import '../../../core/database/app_database.dart';
import '../../../core/database/daos/experiment_dao.dart';
import '../../../core/models/experiment.dart';
import '../../../core/models/experiment_check_in.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../day_context/data/day_context_repository.dart';
import '../../day_context/domain/break_day.dart';
import '../data/experiment_repository.dart';
import 'experiment_check_in_schedule.dart';
import 'experiment_days.dart';
import 'experiment_progress.dart';
import 'kept_experiment.dart';

/// One experiment together with everything its row shows.
class ExperimentView {
  const ExperimentView({
    required this.experiment,
    required this.days,
    required this.minutesByDay,
    required this.today,
    required this.progress,
    this.checkIns = const [],
    this.pendingDates = const [],
    this.missedCount = 0,
    this.dueToday = false,
    this.checkInStatistic = '0 written',
    this.showsEndPanel = false,
    this.extensionLine,
  });

  final Experiment experiment;

  /// The window, one entry per day.
  final List<ExperimentDay> days;

  /// Sums per day for the days that have tagged blocks.
  final Map<String, DayMinutes> minutesByDay;

  /// The planner date the numbers were computed for (`yyyy-MM-dd`).
  final String today;

  final ExperimentProgress progress;

  /// The written check-ins, newest slot first.
  final List<ExperimentCheckIn> checkIns;

  /// Slots dated today or earlier with no check-in, earliest first. Empty for
  /// a concluded experiment: its unwritten slots are not asked for any more.
  final List<String> pendingDates;

  /// Unwritten slots dated before today. For a concluded experiment every
  /// unwritten slot counts, because none of them can be written any more.
  final int missedCount;

  /// Whether a pending slot is dated today.
  final bool dueToday;

  /// The "Check-ins" statistic text (R23).
  final String checkInStatistic;

  /// Running and today is on or after the end date (R25).
  final bool showsEndPanel;

  /// "Extended n time(s). Last reason: ...", or null when never extended.
  final String? extensionLine;
}

/// The Experiments card's data: views sorted as ED25 and the two counts.
class ExperimentDashboard {
  const ExperimentDashboard({
    required this.views,
    required this.runningCount,
    required this.concludedCount,
    this.kept = emptyKeptSegment,
  });

  static const empty = ExperimentDashboard(
    views: [],
    runningCount: 0,
    concludedCount: 0,
  );

  final List<ExperimentView> views;
  final int runningCount;
  final int concludedCount;

  /// The kept rows (concluded with Keep it and not retired), most recently
  /// kept first. Empty when no experiment is kept.
  final KeptSegment kept;

  /// The number in the Kept segment label.
  int get keptCount => kept.views.length;

  bool get isEmpty => views.isEmpty;
}

/// Loads the dashboard: one experiments query, one day-context query over
/// the union of all windows (break days via [BreakDayRule]), and one indexed
/// range query per experiment
/// (ED41), all in one read transaction. Nothing is stored.
class ExperimentDashboardService {
  ExperimentDashboardService(this._db, {required this.formatDuration});

  final AppDatabase _db;
  final DurationFormatter formatDuration;

  Future<ExperimentDashboard> load({
    required String today,
    BreakDayRule? breakDays,
  }) {
    final dao = _db.experimentDao;
    return _db.transaction(() async {
      final rows = await dao.getExperiments();
      if (rows.isEmpty) return ExperimentDashboard.empty;

      final experiments = [
        for (final r in rows)
          ExperimentRepository.fromRow(r.experiment, r.tag.name),
      ];
      final firstDate = experiments
          .map((e) => e.startDate)
          .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      final lastDate = experiments
          .map((e) => e.endDate)
          .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      // Also covers the Kept weeks: 8 weeks back to the next week start.
      final keptFirst = keptWeekStarts(today).first;
      final keptLast = isoDateString(
        addDays(startOfIsoWeek(parseIsoDate(today)), 6),
      );
      final contextRows = await dao.dayContextsBetween(
        firstDate.compareTo(keptFirst) <= 0 ? firstDate : keptFirst,
        lastDate.compareTo(keptLast) >= 0 ? lastDate : keptLast,
      );
      final breakDates = (breakDays ?? BreakDayRule.defaults).breakDates(
        contextRows.map(DayContextRepository.fromRow),
      );
      final checkInRows = await dao.getCheckInsForExperiments([
        for (final e in experiments) e.id,
      ]);
      final checkInsByExperiment = <String, List<ExperimentCheckIn>>{};
      for (final row in checkInRows) {
        checkInsByExperiment
            .putIfAbsent(row.experimentId, () => [])
            .add(_toCheckIn(row));
      }

      final views = <ExperimentView>[];
      for (final experiment in experiments) {
        final rangeStart = PlannerTimeZone.dayBounds(
          parseIsoDate(experiment.startDate),
        ).$1;
        final rangeEnd = PlannerTimeZone.dayBounds(
          parseIsoDate(experiment.endDate),
        ).$2;
        final blocks = await dao.taggedBlocksInRange(
          experiment.tagId,
          rangeStart,
          rangeEnd,
        );
        views.add(
          buildExperimentView(
            experiment: experiment,
            breakDates: breakDates,
            blocks: blocks,
            today: today,
            formatDuration: formatDuration,
            checkIns: checkInsByExperiment[experiment.id] ?? const [],
          ),
        );
      }
      views.sort(_compareViews);
      final keptExperiments = [
        for (final e in experiments)
          if (e.isKept) e,
      ];
      final kept = keptExperiments.isEmpty
          ? emptyKeptSegment
          : await _loadKept(
              dao,
              keptExperiments,
              today,
              breakDates.keys.toSet(),
            );
      return ExperimentDashboard(
        views: List.unmodifiable(views),
        runningCount: experiments
            .where((e) => e.status == ExperimentStatus.running)
            .length,
        concludedCount: experiments
            .where((e) => e.status == ExperimentStatus.concluded)
            .length,
        kept: kept,
      );
    });
  }

  /// Three indexed aggregates for all kept experiments at once: completed
  /// minutes per week, completed minutes per day of this week, and planned
  /// minutes from the start of today to the next week start. When a break day
  /// falls in those weeks, completed minutes are read per day (63 buckets)
  /// and summed without the break days, and planned minutes are read per
  /// remaining day that is not a break.
  Future<KeptSegment> _loadKept(
    ExperimentDao dao,
    List<Experiment> kept,
    String today,
    Set<String> breakDates,
  ) async {
    final weekStarts = keptWeekStarts(today);
    final firstWeek = parseIsoDate(weekStarts.first);
    final weekStart = parseIsoDate(weekStarts.last);
    final nextWeekStart = addDays(weekStart, 7);
    final windows = [
      for (final e in kept)
        (tagId: e.tagId, countedFrom: parseIsoDate(e.startDate)),
    ];
    final allDays = [
      for (var i = 0; i < 7 * keptWeekBarCount; i++) addDays(firstWeek, i),
    ];
    final hasBreak = allDays.any(
      (day) => breakDates.contains(isoDateString(day)),
    );
    final Map<String, Map<int, int>> byWeek;
    final Map<String, Map<int, int>> byDay;
    if (!hasBreak) {
      final weekBuckets = [
        for (final start in weekStarts)
          (parseIsoDate(start), addDays(parseIsoDate(start), 7)),
      ];
      final dayBuckets = [
        for (var i = 0; i < 7; i++)
          PlannerTimeZone.dayBounds(addDays(weekStart, i)),
      ];
      byWeek = await dao.keptCompletedMinutes(windows, weekBuckets);
      byDay = await dao.keptCompletedMinutes(windows, dayBuckets);
    } else {
      final perDay = await dao.keptCompletedMinutes(windows, [
        for (final day in allDays) PlannerTimeZone.dayBounds(day),
      ]);
      byWeek = {};
      byDay = {};
      for (final entry in perDay.entries) {
        final weeks = byWeek[entry.key] = <int, int>{};
        final days = byDay[entry.key] = <int, int>{};
        for (final bucket in entry.value.entries) {
          if (breakDates.contains(isoDateString(allDays[bucket.key]))) {
            continue;
          }
          final week = bucket.key ~/ 7;
          weeks[week] = (weeks[week] ?? 0) + bucket.value;
          if (week == keptWeekBarCount - 1) days[bucket.key % 7] = bucket.value;
        }
      }
    }
    final tagIds = [for (final e in kept) e.tagId];
    final todayDate = parseIsoDate(today);
    final remaining = [
      for (
        var day = todayDate;
        day.isBefore(nextWeekStart);
        day = addDays(day, 1)
      )
        day,
    ];
    final Map<String, int> planned;
    if (!remaining.any((day) => breakDates.contains(isoDateString(day)))) {
      planned = await dao.keptPlannedMinutes(
        tagIds,
        from: PlannerTimeZone.dayBounds(todayDate).$1,
        to: nextWeekStart,
      );
    } else {
      planned = {};
      for (final day in remaining) {
        if (breakDates.contains(isoDateString(day))) continue;
        final bounds = PlannerTimeZone.dayBounds(day);
        final dayPlanned = await dao.keptPlannedMinutes(
          tagIds,
          from: bounds.$1,
          to: bounds.$2,
        );
        for (final entry in dayPlanned.entries) {
          planned[entry.key] = (planned[entry.key] ?? 0) + entry.value;
        }
      }
    }
    final views = [
      for (final e in kept)
        buildKeptExperimentView(
          experiment: e,
          today: today,
          doneByWeek: byWeek[e.tagId] ?? const {},
          doneByDay: byDay[e.tagId] ?? const {},
          plannedMin: planned[e.tagId] ?? 0,
          formatDuration: formatDuration,
          breakDates: breakDates,
        ),
    ]..sort(_compareKeptViews);
    return KeptSegment(views: List.unmodifiable(views));
  }
}

/// Most recently kept first, then name (case-insensitive), then id.
int _compareKeptViews(KeptExperimentView a, KeptExperimentView b) {
  final bySince = b.keptSince.compareTo(a.keptSince);
  if (bySince != 0) return bySince;
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byName != 0 ? byName : a.experimentId.compareTo(b.experimentId);
}

/// Builds the view of one experiment from its tagged blocks.
ExperimentView buildExperimentView({
  required Experiment experiment,
  required Map<String, String> breakDates,
  required Iterable<TaggedBlockRow> blocks,
  required String today,
  required DurationFormatter formatDuration,
  Iterable<ExperimentCheckIn> checkIns = const [],
}) {
  final days = buildExperimentDays(experiment, breakDates);
  // A break day counts in nothing, even if a tagged block was done on it.
  final minutesByDay = groupBlocksByDay(
    blocks,
    startDate: experiment.startDate,
    endDate: experiment.endDate,
  )..removeWhere((date, _) => breakDates.containsKey(date));
  final running = experiment.status == ExperimentStatus.running;
  final newestFirst = checkIns.toList()
    ..sort((a, b) => b.slotDate.compareTo(a.slotDate));
  // A concluded experiment is read as of the day after its last slot, so every
  // unwritten slot is a missed one and none is still "due today" (R24).
  final status = experimentCheckInStatus(
    startDate: experiment.startDate,
    endDate: experiment.endDate,
    checkInEveryDays: experiment.checkInEveryDays,
    writtenSlotDates: [for (final c in newestFirst) c.slotDate],
    today: running
        ? today
        : isoDateString(addDays(parseIsoDate(experiment.endDate), 1)),
  );
  return ExperimentView(
    experiment: experiment,
    days: days,
    minutesByDay: minutesByDay,
    today: today,
    progress: computeExperimentProgress(
      experiment: experiment,
      days: days,
      minutesByDay: minutesByDay,
      today: today,
      formatDuration: formatDuration,
    ),
    checkIns: List.unmodifiable(newestFirst),
    pendingDates: running ? status.pendingDates : const [],
    missedCount: status.missedCount,
    dueToday: running && status.dueToday,
    checkInStatistic: experimentCheckInStatistic(
      written: newestFirst.length,
      missed: status.missedCount,
      running: running,
      nextSlot: status.nextSlot,
    ),
    showsEndPanel: running && today.compareTo(experiment.endDate) >= 0,
    extensionLine: experimentExtensionLine(experiment),
  );
}

/// ED25: running first (earlier start date first, then name), then concluded
/// (most recently concluded first, then name).
int _compareViews(ExperimentView a, ExperimentView b) {
  final ea = a.experiment;
  final eb = b.experiment;
  final aRunning = ea.status == ExperimentStatus.running;
  final bRunning = eb.status == ExperimentStatus.running;
  if (aRunning != bRunning) return aRunning ? -1 : 1;
  final byDate = aRunning
      ? ea.startDate.compareTo(eb.startDate)
      : (eb.concludedOn ?? eb.endDate).compareTo(ea.concludedOn ?? ea.endDate);
  if (byDate != 0) return byDate;
  final byName = ea.tagName.toLowerCase().compareTo(eb.tagName.toLowerCase());
  return byName != 0 ? byName : ea.id.compareTo(eb.id);
}

ExperimentCheckIn _toCheckIn(ExperimentCheckInRow row) => ExperimentCheckIn(
  id: row.id,
  experimentId: row.experimentId,
  slotDate: row.slotDate,
  note: row.note,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);
