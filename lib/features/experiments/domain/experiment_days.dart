import '../../../core/database/daos/experiment_dao.dart';
import '../../../core/models/experiment.dart';
import '../../../core/utils/date_utils.dart';

/// One day of an experiment's window (section 2.4). [date] is `yyyy-MM-dd`.
class ExperimentDay {
  const ExperimentDay({
    required this.date,
    required this.isWeekend,
    required this.isLeaveOrHoliday,
    required this.targetMin,
  });

  final String date;
  final bool isWeekend;
  final bool isLeaveOrHoliday;

  /// Minutes expected on this day: the weekday or weekend target, 0 on a
  /// Leave or Holiday day.
  final int targetMin;
}

/// What the tagged blocks of one day add up to (ED10, ED12, ED45).
class DayMinutes {
  const DayMinutes({this.doneMin = 0, this.stillPlannedMin = 0});

  static const zero = DayMinutes();

  /// Completed blocks: the recorded Actual (an explicit 0 counts 0), else the
  /// planned duration.
  final int doneMin;

  /// Planned or in-progress blocks: their planned duration.
  final int stillPlannedMin;
}

/// Number of calendar days from [from] to [to] (`yyyy-MM-dd`), computed from
/// the date parts so a 23 or 25 hour DST day never skews it (section 2.4).
int calendarDaysBetween(String from, String to) {
  final a = _parts(from);
  final b = _parts(to);
  return DateTime.utc(
    b.$1,
    b.$2,
    b.$3,
  ).difference(DateTime.utc(a.$1, a.$2, a.$3)).inDays;
}

(int, int, int) _parts(String value) {
  final p = value.split('-');
  return (int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// The days from the start date to the end date, both inclusive.
List<ExperimentDay> buildExperimentDays(
  Experiment experiment,
  Set<String> leaveOrHolidayDates,
) {
  final start = parseIsoDate(experiment.startDate);
  final count =
      calendarDaysBetween(experiment.startDate, experiment.endDate) + 1;
  final days = <ExperimentDay>[];
  for (var i = 0; i < count; i++) {
    final date = addDays(start, i);
    final iso = isoDateString(date);
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final leave = leaveOrHolidayDates.contains(iso);
    days.add(
      ExperimentDay(
        date: iso,
        isWeekend: weekend,
        isLeaveOrHoliday: leave,
        targetMin: leave
            ? 0
            : (weekend
                  ? experiment.weekendTargetMin
                  : experiment.weekdayTargetMin),
      ),
    );
  }
  return days;
}

/// Sums the rows of `taggedBlocksInRange` per planner-local block date (ED41).
/// The date comes from the start instant converted to the planner time zone,
/// never from the UTC text. Rows outside [startDate]..[endDate] are ignored.
Map<String, DayMinutes> groupBlocksByDay(
  Iterable<TaggedBlockRow> rows, {
  required String startDate,
  required String endDate,
}) {
  final done = <String, int>{};
  final planned = <String, int>{};
  for (final row in rows) {
    final date = isoDateString(row.startTime);
    if (date.compareTo(startDate) < 0 || date.compareTo(endDate) > 0) continue;
    final estimated = _nonNegative(row.estimatedDurationMin);
    switch (row.status) {
      case 'completed':
        final actual = row.actualDurationMin;
        done[date] =
            (done[date] ?? 0) +
            (actual != null ? _nonNegative(actual) : estimated);
      case 'planned' || 'in_progress':
        planned[date] = (planned[date] ?? 0) + estimated;
    }
  }
  return {
    for (final date in {...done.keys, ...planned.keys})
      date: DayMinutes(
        doneMin: done[date] ?? 0,
        stillPlannedMin: planned[date] ?? 0,
      ),
  };
}

int _nonNegative(int? value) => value == null || value < 0 ? 0 : value;
