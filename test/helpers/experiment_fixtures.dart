import 'package:personal_planner/core/database/daos/experiment_dao.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

/// A running (or concluded) experiment for pure-domain tests. Dates are
/// `yyyy-MM-dd`.
Experiment testExperiment({
  String id = 'exp-1',
  String tagName = 'Learn C',
  String start = '2026-10-05',
  String end = '2026-10-11',
  int weekday = 60,
  int weekend = 90,
  int every = 1,
  ExperimentStatus status = ExperimentStatus.running,
  String? concludedOn,
  String? purpose,
  List<ExperimentExtension> extensions = const [],
  ExperimentOutcome? outcome,
  DateTime? retiredAt,
  List<ExperimentTargetChange> targetChanges = const [],
}) {
  final now = DateTime.utc(2026, 10, 1);
  return Experiment(
    id: id,
    tagId: 'tag-$id',
    tagName: tagName,
    purpose: purpose,
    startDate: start,
    endDate: end,
    weekdayTargetMin: weekday,
    weekendTargetMin: weekend,
    checkInEveryDays: every,
    status: status,
    extensions: extensions,
    outcome:
        outcome ??
        (status == ExperimentStatus.concluded ? ExperimentOutcome.drop : null),
    concludedOn: concludedOn,
    retiredAt: retiredAt,
    targetChanges: targetChanges,
    createdAt: now,
    updatedAt: now,
  );
}

/// A concluded experiment with the keep outcome, kept since [concludedOn].
Experiment testKeptExperiment({
  String id = 'kept-1',
  String tagName = 'Morning pages',
  String start = '2026-09-04',
  String end = '2026-10-03',
  String concludedOn = '2026-10-09',
  int weekday = 60,
  int weekend = 90,
  String? why,
  List<ExperimentTargetChange> targetChanges = const [],
}) => testExperiment(
  id: id,
  tagName: tagName,
  start: start,
  end: end,
  weekday: weekday,
  weekend: weekend,
  every: 7,
  status: ExperimentStatus.concluded,
  concludedOn: concludedOn,
  outcome: ExperimentOutcome.keep,
  targetChanges: targetChanges,
).copyWith(conclusionNote: why);

/// A tagged block row starting at [hour]:[minute] planner time on [date].
TaggedBlockRow testBlock(
  String date, {
  int hour = 9,
  int minute = 0,
  String status = 'completed',
  int? actual,
  int? planned = 60,
}) {
  final p = date.split('-').map(int.parse).toList();
  return TaggedBlockRow(
    startTime: PlannerTimeZone.calendarDate(
      p[0],
      p[1],
      p[2],
      hour: hour,
      minute: minute,
    ),
    status: status,
    actualDurationMin: actual,
    estimatedDurationMin: planned,
  );
}
