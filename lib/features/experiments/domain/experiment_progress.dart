import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../core/models/experiment.dart';
import '../../../core/utils/date_utils.dart';
import 'experiment_days.dart';

/// Turns whole minutes into text ("5h 25m", "1h", "45m", "0m"). The domain
/// code takes it as a parameter so it needs no Flutter import; the app passes
/// `formatMinutes` from the Insights widgets.
typedef DurationFormatter = String Function(int minutes);

/// Everything the experiment row shows as numbers or sentences (section 2.4
/// and 2.5, ED28, ED29). Wording is neutral: never "failed" or "late".
class ExperimentProgress {
  const ExperimentProgress({
    required this.totalMin,
    required this.expectedMin,
    required this.doneMin,
    required this.paceMin,
    required this.paceLabel,
    required this.daysAtTargetDone,
    required this.daysAtTargetTotal,
    required this.daysAtTargetLabel,
    required this.hasTodayLine,
    required this.todayDoneMin,
    required this.todayStillPlannedMin,
    required this.todayTargetMin,
    required this.todayIsLeaveOrHoliday,
    required this.shortfallMin,
    required this.todayLine,
    required this.shortfallHint,
    required this.fillFraction,
    required this.tickFraction,
    required this.statusChip,
    required this.headline,
    required this.showExtraLegendLine,
  });

  /// Sum of the targets over the whole window.
  final int totalMin;

  /// Minutes expected so far.
  final int expectedMin;

  /// Minutes done on the days that count so far.
  final int doneMin;

  /// Done minus expected.
  final int paceMin;

  /// "Not started", "On pace", "{duration} ahead" or "{duration} behind".
  final String paceLabel;

  /// Finished days at or above their target (x) of the finished days that
  /// had a target (y), with today added once it has reached its target.
  final int daysAtTargetDone;
  final int daysAtTargetTotal;

  /// "x of y", or "None yet" when y is 0.
  final String daysAtTargetLabel;

  /// Running experiment with today inside its window.
  final bool hasTodayLine;
  final int todayDoneMin;
  final int todayStillPlannedMin;
  final int todayTargetMin;
  final bool todayIsLeaveOrHoliday;

  /// Target minus (done plus still planned) when positive, else 0.
  final int shortfallMin;
  final String todayLine;
  final String? shortfallHint;

  /// Filled part of the bar and the "expected by now" tick, 0..1.
  final double fillFraction;
  final double tickFraction;

  final String statusChip;
  final String headline;

  /// "Today's target only counts against you once the day is over." is shown
  /// only for a running experiment whose window contains today (ED29).
  final bool showExtraLegendLine;
}

/// Computes the numbers of one experiment. [days] is the window,
/// [minutesByDay] the sums of `groupBlocksByDay`, [today] a `yyyy-MM-dd` date.
ExperimentProgress computeExperimentProgress({
  required Experiment experiment,
  required List<ExperimentDay> days,
  required Map<String, DayMinutes> minutesByDay,
  required String today,
  required DurationFormatter formatDuration,
}) {
  final concluded = experiment.status == ExperimentStatus.concluded;
  final started = concluded || today.compareTo(experiment.startDate) >= 0;
  final todayInWindow =
      !concluded &&
      today.compareTo(experiment.startDate) >= 0 &&
      today.compareTo(experiment.endDate) <= 0;

  var total = 0;
  var expected = 0;
  var done = 0;
  var targetDays = 0;
  var targetDaysMet = 0;
  var todayDone = 0;
  var todayStillPlanned = 0;
  var todayTarget = 0;
  var todayLeave = false;

  for (final day in days) {
    final minutes = minutesByDay[day.date] ?? DayMinutes.zero;
    total += day.targetMin;
    if (concluded || day.date.compareTo(today) < 0) {
      expected += day.targetMin;
      done += minutes.doneMin;
      if (day.targetMin > 0) {
        targetDays++;
        if (minutes.doneMin >= day.targetMin) targetDaysMet++;
      }
    } else if (day.date == today) {
      // Today's target counts against pace only once the day is over.
      expected += math.min(day.targetMin, minutes.doneMin);
      done += minutes.doneMin;
      todayDone = minutes.doneMin;
      todayStillPlanned = minutes.stillPlannedMin;
      todayTarget = day.targetMin;
      todayLeave = day.isLeaveOrHoliday;
      if (day.targetMin > 0 && minutes.doneMin >= day.targetMin) {
        targetDays++;
        targetDaysMet++;
      }
    }
  }

  final pace = done - expected;
  final paceLabel = !started
      ? 'Not started'
      : pace == 0
      ? 'On pace'
      : pace > 0
      ? '${formatDuration(pace)} ahead'
      : '${formatDuration(-pace)} behind';

  final shortfall = todayInWindow && todayTarget > todayDone + todayStillPlanned
      ? todayTarget - (todayDone + todayStillPlanned)
      : 0;

  final todayLine = todayInWindow
      ? 'Today: ${formatDuration(todayDone)} done · '
            '${formatDuration(todayStillPlanned)} still planned · '
            '${todayLeave ? 'Leave, no target' : 'target ${formatDuration(todayTarget)}'}'
      : '';

  return ExperimentProgress(
    totalMin: total,
    expectedMin: expected,
    doneMin: done,
    paceMin: pace,
    paceLabel: paceLabel,
    daysAtTargetDone: targetDaysMet,
    daysAtTargetTotal: targetDays,
    daysAtTargetLabel: targetDays == 0
        ? 'None yet'
        : '$targetDaysMet of $targetDays',
    hasTodayLine: todayInWindow,
    todayDoneMin: todayDone,
    todayStillPlannedMin: todayStillPlanned,
    todayTargetMin: todayTarget,
    todayIsLeaveOrHoliday: todayLeave,
    shortfallMin: shortfall,
    todayLine: todayLine,
    shortfallHint: shortfall > 0
        ? "Your plan is ${formatDuration(shortfall)} short of today's target."
        : null,
    fillFraction: _fraction(done, total),
    tickFraction: _fraction(expected, total),
    statusChip: _statusChip(experiment, days.length, today),
    headline: expected == 0 && done == 0
        ? 'Nothing is expected yet. Complete a block with the tag '
              '${experiment.tagName} and it shows up here.'
        : 'Done ${formatDuration(done)} of ${formatDuration(expected)} '
              'expected so far',
    showExtraLegendLine: todayInWindow,
  );
}

double _fraction(int part, int total) =>
    total <= 0 ? 0.0 : math.min(1.0, part / total);

String _statusChip(Experiment experiment, int windowDays, String today) {
  if (experiment.status == ExperimentStatus.concluded) {
    return 'Concluded ${_monthDay(experiment.concludedOn ?? experiment.endDate)}';
  }
  if (today.compareTo(experiment.startDate) < 0) {
    return 'Starts ${_monthDay(experiment.startDate)}';
  }
  // ED28: day number counted from the date parts, capped at the window.
  final day = math.min(
    calendarDaysBetween(experiment.startDate, today) + 1,
    windowDays,
  );
  return 'Running · Day $day of $windowDays';
}

String _monthDay(String isoDate) =>
    DateFormat('MMM d').format(parseIsoDate(isoDate));

/// "Every day", "Every 3 days", "Every week", "Every 10 days", "Every 15 days".
String experimentFrequencyLabel(int everyDays) => switch (everyDays) {
  1 => 'Every day',
  7 => 'Every week',
  _ => 'Every $everyDays days',
};

/// "Oct 3 to Nov 5 · 60 min weekdays · 90 min weekends · every day check-in".
String experimentDatesLine(Experiment experiment) =>
    '${_monthDay(experiment.startDate)} to ${_monthDay(experiment.endDate)} · '
    '${experiment.weekdayTargetMin} min weekdays · '
    '${experiment.weekendTargetMin} min weekends · '
    '${experimentFrequencyLabel(experiment.checkInEveryDays).toLowerCase()} '
    'check-in';

/// "Extended 1 time. Last reason: ..." or "Extended {n} times. Last reason:
/// ...", or null when the experiment was never extended.
String? experimentExtensionLine(Experiment experiment) {
  final extensions = experiment.extensions;
  if (extensions.isEmpty) return null;
  final n = extensions.length;
  return 'Extended $n ${n == 1 ? 'time' : 'times'}. '
      'Last reason: ${extensions.last.reason}';
}
