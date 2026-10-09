import 'package:intl/intl.dart';

import '../../../core/utils/date_utils.dart';
import 'experiment_days.dart';
import 'experiment_progress.dart';

/// How many days one bar stands for (R17, ED30).
enum ExperimentChartGrouping { days, weeks, months }

/// The least width, in logical pixels, a bar's slot may have before the chart
/// groups its days into weeks, and its weeks into months.
const minChartSlotWidth = 6.0;

/// One bar of the chart: a day, a Monday-to-Sunday week clipped to the window,
/// or a calendar month clipped to the window.
class ExperimentChartBucket {
  const ExperimentChartBucket({
    required this.firstDate,
    required this.lastDate,
    required this.dayCount,
    required this.doneMin,
    required this.targetMin,
    required this.isFuture,
    required this.isToday,
    required this.isLeaveOrHoliday,
    required this.label,
    required this.tapLine,
  });

  final String firstDate;
  final String lastDate;
  final int dayCount;
  final int doneMin;

  /// The target of the whole bucket, future days included.
  final int targetMin;

  /// A running experiment's bucket that starts after today: only an outline.
  final bool isFuture;

  /// A running experiment's bucket that contains today.
  final bool isToday;

  /// A single Leave or Holiday day (day buckets only).
  final bool isLeaveOrHoliday;

  /// "Oct 12 to 18", "Sep 28 to Oct 4", "Oct 12" or "October".
  final String label;

  /// The line shown on hover or tap, also the screen-reader label (ED50).
  final String tapLine;

  @override
  bool operator ==(Object other) =>
      other is ExperimentChartBucket &&
      other.firstDate == firstDate &&
      other.lastDate == lastDate &&
      other.dayCount == dayCount &&
      other.doneMin == doneMin &&
      other.targetMin == targetMin &&
      other.isFuture == isFuture &&
      other.isToday == isToday &&
      other.isLeaveOrHoliday == isLeaveOrHoliday &&
      other.label == label &&
      other.tapLine == tapLine;

  @override
  int get hashCode => Object.hash(
    firstDate,
    lastDate,
    dayCount,
    doneMin,
    targetMin,
    isFuture,
    isToday,
    isLeaveOrHoliday,
    label,
    tapLine,
  );
}

/// The chart for one available width.
class ExperimentChartData {
  const ExperimentChartData({
    required this.grouping,
    required this.buckets,
    required this.caption,
    required this.groupingNote,
    required this.windowDays,
  });

  final ExperimentChartGrouping grouping;
  final List<ExperimentChartBucket> buckets;

  /// "Minutes per day. The dashed outline is that day's target." and so on.
  final String caption;

  /// "Showing weeks because {N} days don't fit on this screen." or null.
  final String? groupingNote;
  final int windowDays;
}

/// Picks days when every day gets a slot of at least [minChartSlotWidth],
/// else weeks when every week does, else months. Months are used even when
/// their slots are narrower, so the whole window stays visible (ED30).
ExperimentChartGrouping chooseChartGrouping({
  required double width,
  required int dayCount,
  required int weekCount,
}) {
  if (width >= dayCount * minChartSlotWidth) {
    return ExperimentChartGrouping.days;
  }
  if (width >= weekCount * minChartSlotWidth) {
    return ExperimentChartGrouping.weeks;
  }
  return ExperimentChartGrouping.months;
}

/// Builds the buckets of [days] for a plot [width] (logical pixels).
/// [running] is false for a concluded experiment, which has no future bars
/// and no today mark.
ExperimentChartData buildExperimentChart({
  required List<ExperimentDay> days,
  required Map<String, DayMinutes> minutesByDay,
  required String today,
  required bool running,
  required double width,
  required DurationFormatter formatDuration,
}) {
  final weekKeys = <String>{for (final d in days) _weekStart(d.date)};
  final grouping = chooseChartGrouping(
    width: width,
    dayCount: days.length,
    weekCount: weekKeys.length,
  );
  final groups = <List<ExperimentDay>>[];
  String? currentKey;
  for (final day in days) {
    final key = switch (grouping) {
      ExperimentChartGrouping.days => day.date,
      ExperimentChartGrouping.weeks => _weekStart(day.date),
      ExperimentChartGrouping.months => day.date.substring(0, 7),
    };
    if (key != currentKey) {
      groups.add([]);
      currentKey = key;
    }
    groups.last.add(day);
  }

  final buckets = [
    for (final group in groups)
      _bucket(group, grouping, minutesByDay, today, running, formatDuration),
  ];
  return ExperimentChartData(
    grouping: grouping,
    buckets: buckets,
    caption: switch (grouping) {
      ExperimentChartGrouping.days =>
        "Minutes per day. The dashed outline is that day's target.",
      ExperimentChartGrouping.weeks =>
        "Minutes per week. The dashed outline is that week's target.",
      ExperimentChartGrouping.months =>
        "Minutes per month. The dashed outline is that month's target.",
    },
    groupingNote: switch (grouping) {
      ExperimentChartGrouping.days => null,
      ExperimentChartGrouping.weeks =>
        "Showing weeks because ${days.length} days don't fit on this screen.",
      ExperimentChartGrouping.months =>
        "Showing months because ${days.length} days don't fit on this screen.",
    },
    windowDays: days.length,
  );
}

/// The label a screen reader gets for the whole chart (ED37).
String experimentChartSummary(
  String caption,
  String firstDate,
  String lastDate,
) => '$caption ${_monthDay(firstDate)} to ${_monthDay(lastDate)}.';

ExperimentChartBucket _bucket(
  List<ExperimentDay> group,
  ExperimentChartGrouping grouping,
  Map<String, DayMinutes> minutesByDay,
  String today,
  bool running,
  DurationFormatter formatDuration,
) {
  final first = group.first.date;
  final last = group.last.date;
  var done = 0;
  var target = 0;
  for (final day in group) {
    done += (minutesByDay[day.date] ?? DayMinutes.zero).doneMin;
    target += day.targetMin;
  }
  final leave =
      grouping == ExperimentChartGrouping.days && group.single.isLeaveOrHoliday;
  final amounts = '${formatDuration(done)} of ${formatDuration(target)}';
  final String label;
  final String tapLine;
  switch (grouping) {
    case ExperimentChartGrouping.days:
      final text = DateFormat('EEE MMM d').format(parseIsoDate(first));
      label = _monthDay(first);
      tapLine = leave ? '$text: Leave' : '$text: $amounts target';
    case ExperimentChartGrouping.weeks:
      label = _rangeLabel(first, last);
      tapLine = '$label: $amounts';
    case ExperimentChartGrouping.months:
      label = DateFormat('MMMM').format(parseIsoDate(first));
      tapLine = '$label: $amounts';
  }
  return ExperimentChartBucket(
    firstDate: first,
    lastDate: last,
    dayCount: group.length,
    doneMin: done,
    targetMin: target,
    isFuture: running && first.compareTo(today) > 0,
    isToday:
        running && first.compareTo(today) <= 0 && last.compareTo(today) >= 0,
    isLeaveOrHoliday: leave,
    label: label,
    tapLine: tapLine,
  );
}

/// "Oct 12 to 18" within a month, "Sep 28 to Oct 4" across months, "Oct 12"
/// for a one-day bucket.
String _rangeLabel(String first, String last) {
  if (first == last) return _monthDay(first);
  final a = parseIsoDate(first);
  final b = parseIsoDate(last);
  final end = a.month == b.month && a.year == b.year
      ? '${b.day}'
      : _monthDay(last);
  return '${_monthDay(first)} to $end';
}

String _monthDay(String isoDate) =>
    DateFormat('MMM d').format(parseIsoDate(isoDate));

/// The Monday on or before [isoDate], by calendar arithmetic.
String _weekStart(String isoDate) {
  final date = parseIsoDate(isoDate);
  return isoDateString(addDays(date, -(date.weekday - 1)));
}
