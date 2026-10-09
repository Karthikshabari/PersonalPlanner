import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/experiment_dao.dart';
import '../../../core/models/experiment.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import 'experiment_days.dart';
import 'experiment_progress.dart';

/// One experiment together with everything its row shows.
class ExperimentView {
  const ExperimentView({
    required this.experiment,
    required this.days,
    required this.minutesByDay,
    required this.today,
    required this.progress,
  });

  final Experiment experiment;

  /// The window, one entry per day.
  final List<ExperimentDay> days;

  /// Sums per day for the days that have tagged blocks.
  final Map<String, DayMinutes> minutesByDay;

  /// The planner date the numbers were computed for (`yyyy-MM-dd`).
  final String today;

  final ExperimentProgress progress;
}

/// The Experiments card's data: views sorted as ED25 and the two counts.
class ExperimentDashboard {
  const ExperimentDashboard({
    required this.views,
    required this.runningCount,
    required this.concludedCount,
  });

  static const empty = ExperimentDashboard(
    views: [],
    runningCount: 0,
    concludedCount: 0,
  );

  final List<ExperimentView> views;
  final int runningCount;
  final int concludedCount;

  bool get isEmpty => views.isEmpty;
}

/// Loads the dashboard: one experiments query, one Leave/Holiday query over
/// the union of all windows, and one indexed range query per experiment
/// (ED41), all in one read transaction. Nothing is stored.
class ExperimentDashboardService {
  ExperimentDashboardService(this._db, {required this.formatDuration});

  final AppDatabase _db;
  final DurationFormatter formatDuration;

  Future<ExperimentDashboard> load({required String today}) {
    final dao = _db.experimentDao;
    return _db.transaction(() async {
      final rows = await dao.getExperiments();
      if (rows.isEmpty) return ExperimentDashboard.empty;

      final experiments = [
        for (final r in rows) _toExperiment(r.experiment, r.tag.name),
      ];
      final firstDate = experiments
          .map((e) => e.startDate)
          .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      final lastDate = experiments
          .map((e) => e.endDate)
          .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      final leaveDates = await dao.leaveOrHolidayDates(firstDate, lastDate);

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
            leaveOrHolidayDates: leaveDates,
            blocks: blocks,
            today: today,
            formatDuration: formatDuration,
          ),
        );
      }
      views.sort(_compareViews);
      return ExperimentDashboard(
        views: List.unmodifiable(views),
        runningCount: experiments
            .where((e) => e.status == ExperimentStatus.running)
            .length,
        concludedCount: experiments
            .where((e) => e.status == ExperimentStatus.concluded)
            .length,
      );
    });
  }
}

/// Builds the view of one experiment from its tagged blocks.
ExperimentView buildExperimentView({
  required Experiment experiment,
  required Set<String> leaveOrHolidayDates,
  required Iterable<TaggedBlockRow> blocks,
  required String today,
  required DurationFormatter formatDuration,
}) {
  final days = buildExperimentDays(experiment, leaveOrHolidayDates);
  final minutesByDay = groupBlocksByDay(
    blocks,
    startDate: experiment.startDate,
    endDate: experiment.endDate,
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

/// Mirrors `ExperimentRepository` row mapping, which is private there.
Experiment _toExperiment(ExperimentRow row, String tagName) => Experiment(
  id: row.id,
  tagId: row.tagId,
  tagName: tagName,
  purpose: row.purpose,
  startDate: row.startDate,
  endDate: row.endDate,
  weekdayTargetMin: row.weekdayTargetMin,
  weekendTargetMin: row.weekendTargetMin,
  checkInEveryDays: row.checkInEveryDays,
  status: ExperimentStatus.fromDb(row.status),
  extensions: _decodeExtensions(row.extensionsJson),
  outcome: ExperimentOutcome.fromDb(row.outcome),
  conclusionNote: row.conclusionNote,
  concludedOn: row.concludedOn,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  revision: row.revision,
);

List<ExperimentExtension> _decodeExtensions(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      ExperimentExtension.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
}
