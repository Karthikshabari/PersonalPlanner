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
    outcome: status == ExperimentStatus.concluded
        ? ExperimentOutcome.drop
        : null,
    concludedOn: concludedOn,
    createdAt: now,
    updatedAt: now,
  );
}

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
