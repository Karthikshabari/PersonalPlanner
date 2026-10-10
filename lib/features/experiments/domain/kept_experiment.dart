import 'dart:math' as math;

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';

import '../../../core/models/experiment.dart';
import '../../../core/utils/date_utils.dart';
import 'experiment_progress.dart' show DurationFormatter;
import 'experiment_target_changes.dart';

part 'kept_experiment.freezed.dart';

/// 8 earlier weeks plus this week.
const keptWeekBarCount = 9;

/// A day column is full at 90 minutes.
const keptDayFullScaleMinutes = 90;

/// The colour family of the status chip: green or muted amber, never red.
enum KeptTone { positive, caution }

/// Which of the four planned-strip texts applies (7.3).
enum KeptPlanState {
  targetReached,
  reachesMinimum,
  shortOfMinimum,
  nothingPlanned,
}

/// One weekly bar of a kept experiment.
@freezed
abstract class KeptWeekBar with _$KeptWeekBar {
  const factory KeptWeekBar({
    required String weekStart,
    required String label,
    required int doneMin,
    required int targetMin,
    required int heightPercent,
    int? percent,
    required bool isCurrent,
    int? targetThenMin,
    required String semanticsLabel,
  }) = _KeptWeekBar;
}

/// One of the seven day columns of this week.
@freezed
abstract class KeptDayColumn with _$KeptDayColumn {
  const factory KeptDayColumn({
    required String date,
    required String dayName,
    required int doneMin,
    required double fillFraction,
    required bool isToday,
    required String valueLabel,
    required bool dim,
  }) = _KeptDayColumn;
}

/// Everything one kept row shows. Immutable with value equality, so a reload
/// that changes nothing notifies nobody.
@freezed
abstract class KeptExperimentView with _$KeptExperimentView {
  const factory KeptExperimentView({
    required String experimentId,
    required String name,
    required int revision,

    /// `yyyy-MM-dd`: the day the experiment was concluded with Keep it.
    required String keptSince,
    required String subtitle,
    String? why,

    /// The planner date the numbers were computed for.
    required String today,
    required String weekStart,
    required String nextWeekStart,
    required int weekdayTargetMin,
    required int weekendTargetMin,
    required int weekdayCount,
    required int weekendCount,
    required int targetMin,
    required int doneMin,
    required int plannedMin,
    required int expectedMin,
    required int paceMin,
    required String chipText,
    required KeptTone chipTone,
    required KeptPlanState planState,
    required int remainingMin,
    required int shortMin,
    required double doneFraction,
    required double plannedEndFraction,
    required double tickFraction,
    ExperimentTargetChange? pendingChange,
    required List<KeptWeekBar> bars,
    required String axisStartLabel,
    required List<KeptDayColumn> days,
  }) = _KeptExperimentView;
}

/// The kept rows, most recently kept first.
@freezed
abstract class KeptSegment with _$KeptSegment {
  const factory KeptSegment({
    @Default(<KeptExperimentView>[]) List<KeptExperimentView> views,
  }) = _KeptSegment;
}

const emptyKeptSegment = KeptSegment();

/// The weekday or weekend value for [date] (`yyyy-MM-dd`); the weekend value
/// on Saturday and Sunday.
int keptDayTargetMin(KeptTargets targets, String date) {
  final weekday = parseIsoDate(date).weekday;
  return weekday == DateTime.saturday || weekday == DateTime.sunday
      ? targets.weekendMin
      : targets.weekdayMin;
}

/// The dates of the week from [weekStart] that count for [experiment]: not
/// before its start date, and (when [before] is given) before that date.
List<String> _countedDates(
  Experiment experiment,
  String weekStart, {
  String? before,
}) {
  final first = parseIsoDate(weekStart);
  final dates = <String>[];
  for (var i = 0; i < 7; i++) {
    final date = isoDateString(addDays(first, i));
    if (date.compareTo(experiment.startDate) < 0) continue;
    if (before != null && date.compareTo(before) >= 0) continue;
    dates.add(date);
  }
  return dates;
}

int _sumTargets(KeptTargets targets, List<String> dates) =>
    dates.fold(0, (sum, date) => sum + keptDayTargetMin(targets, date));

/// 5 × weekday + 2 × weekend for the week from [weekStart], counting only the
/// days on or after the experiment's start date. Day contexts are ignored.
int keptWeekTargetMin(Experiment experiment, String weekStart) => _sumTargets(
  keptTargetsForWeek(experiment, weekStart),
  _countedDates(experiment, weekStart),
);

/// The same sum over the days of the week that are already finished: from
/// [weekStart] up to, but not including, [today].
int keptExpectedByTodayMin(
  Experiment experiment, {
  required String weekStart,
  required String today,
}) => _sumTargets(
  keptTargetsForWeek(experiment, weekStart),
  _countedDates(experiment, weekStart, before: today),
);

/// The Mondays of the 9 weeks ending with the one that contains [today],
/// oldest first.
List<String> keptWeekStarts(String today) {
  final thisWeek = startOfWeek(parseIsoDate(today));
  return [
    for (var i = keptWeekBarCount - 1; i >= 0; i--)
      isoDateString(addDays(thisWeek, -7 * i)),
  ];
}

/// "Sep 7 – 13", "Sep 28 – Oct 4"; for the current week
/// "This week · Oct 5 – 11".
String keptWeekLabel(String weekStart, {required bool current}) {
  final first = parseIsoDate(weekStart);
  final last = addDays(first, 6);
  final month = DateFormat('MMM d');
  final range = first.month == last.month
      ? '${month.format(first)} – ${last.day}'
      : '${month.format(first)} – ${month.format(last)}';
  return current ? 'This week · $range' : range;
}

/// "On pace", "{x} ahead" or "{x} behind" for [paceMin].
String keptPaceText(int paceMin, DurationFormatter formatDuration) {
  if (paceMin == 0) return 'On pace';
  return paceMin > 0
      ? '${formatDuration(paceMin)} ahead'
      : '${formatDuration(-paceMin)} behind';
}

/// The chip under the title (7.2).
({String text, KeptTone tone}) keptStatusChip({
  required int doneMin,
  required int targetMin,
  required int paceMin,
  required DurationFormatter formatDuration,
}) {
  if (doneMin >= targetMin) {
    return (
      text: doneMin > targetMin
          ? '${formatDuration(doneMin - targetMin)} over target'
          : 'Target reached',
      tone: KeptTone.positive,
    );
  }
  return (
    text: keptPaceText(paceMin, formatDuration),
    tone: paceMin >= 0 ? KeptTone.positive : KeptTone.caution,
  );
}

/// Which planned-strip text applies (7.3).
KeptPlanState keptPlanState({
  required int doneMin,
  required int targetMin,
  required int plannedMin,
}) {
  if (doneMin >= targetMin) return KeptPlanState.targetReached;
  final remaining = targetMin - doneMin;
  if (plannedMin >= remaining) return KeptPlanState.reachesMinimum;
  if (plannedMin > 0) return KeptPlanState.shortOfMinimum;
  return KeptPlanState.nothingPlanned;
}

/// Builds the view of one kept experiment from the three aggregates.
///
/// [doneByWeek] is keyed by the index into [keptWeekStarts]; [doneByDay] by
/// the day of the current week (0 = week start). Missing keys mean 0.
KeptExperimentView buildKeptExperimentView({
  required Experiment experiment,
  required String today,
  required Map<int, int> doneByWeek,
  required Map<int, int> doneByDay,
  required int plannedMin,
  required DurationFormatter formatDuration,
}) {
  final weekStarts = keptWeekStarts(today);
  final weekStart = weekStarts.last;
  final nextWeekStart = isoDateString(addDays(parseIsoDate(weekStart), 7));
  final targets = keptTargetsForWeek(experiment, weekStart);
  final counted = _countedDates(experiment, weekStart);
  final weekendCount = counted.where(_isWeekend).length;
  final targetMin = _sumTargets(targets, counted);
  final doneMin = doneByWeek[keptWeekBarCount - 1] ?? 0;
  final expectedMin = keptExpectedByTodayMin(
    experiment,
    weekStart: weekStart,
    today: today,
  );
  final paceMin = doneMin - expectedMin;
  final chip = keptStatusChip(
    doneMin: doneMin,
    targetMin: targetMin,
    paceMin: paceMin,
    formatDuration: formatDuration,
  );
  final remainingMin = math.max(0, targetMin - doneMin);
  final startWeek = isoDateString(
    startOfWeek(parseIsoDate(experiment.startDate)),
  );
  final startLabel = DateFormat('MMM d');

  final bars = <KeptWeekBar>[];
  for (var i = 0; i < weekStarts.length; i++) {
    final barWeek = weekStarts[i];
    if (barWeek.compareTo(startWeek) < 0) continue;
    final isCurrent = i == weekStarts.length - 1;
    final done = doneByWeek[i] ?? 0;
    final target = keptWeekTargetMin(experiment, barWeek);
    final label = keptWeekLabel(barWeek, current: isCurrent);
    final rounded = target <= 0 ? null : (done * 100 / target).round();
    bars.add(
      KeptWeekBar(
        weekStart: barWeek,
        label: label,
        doneMin: done,
        targetMin: target,
        heightPercent: target <= 0
            ? (done > 0 ? 100 : 0)
            : math.min(100, rounded!),
        percent: rounded,
        isCurrent: isCurrent,
        targetThenMin: !isCurrent && target != targetMin ? target : null,
        semanticsLabel:
            '$label: ${formatDuration(done)} of ${formatDuration(target)}',
      ),
    );
  }
  final axisStartLabel = bars.isEmpty || bars.first.weekStart == startWeek
      ? startLabel.format(parseIsoDate(experiment.startDate))
      : startLabel.format(parseIsoDate(bars.first.weekStart));

  final days = <KeptDayColumn>[];
  final first = parseIsoDate(weekStart);
  final dayName = DateFormat('EEE');
  for (var i = 0; i < 7; i++) {
    final dayDate = addDays(first, i);
    final date = isoDateString(dayDate);
    final minutes = doneByDay[i] ?? 0;
    final isToday = date == today;
    final isFuture = date.compareTo(today) > 0;
    final beforeStart = date.compareTo(experiment.startDate) < 0;
    final outside = isFuture || beforeStart;
    days.add(
      KeptDayColumn(
        date: date,
        dayName: dayName.format(dayDate),
        doneMin: minutes,
        fillFraction: outside
            ? 0.0
            : math.min(minutes, keptDayFullScaleMinutes) /
                  keptDayFullScaleMinutes,
        isToday: isToday,
        valueLabel: outside ? '–' : (isToday ? 'today' : '${minutes}m'),
        dim: isToday || outside,
      ),
    );
  }

  return KeptExperimentView(
    experimentId: experiment.id,
    name: experiment.tagName,
    revision: experiment.revision,
    keptSince: experiment.concludedOn ?? experiment.endDate,
    subtitle:
        '$keptName since ${startLabel.format(parseIsoDate(experiment.concludedOn ?? experiment.endDate))}'
        ' · #${experiment.tagName}',
    why: _nonEmpty(experiment.conclusionNote),
    today: today,
    weekStart: weekStart,
    nextWeekStart: nextWeekStart,
    weekdayTargetMin: targets.weekdayMin,
    weekendTargetMin: targets.weekendMin,
    weekdayCount: counted.length - weekendCount,
    weekendCount: weekendCount,
    targetMin: targetMin,
    doneMin: doneMin,
    plannedMin: plannedMin,
    expectedMin: expectedMin,
    paceMin: paceMin,
    chipText: chip.text,
    chipTone: chip.tone,
    planState: keptPlanState(
      doneMin: doneMin,
      targetMin: targetMin,
      plannedMin: plannedMin,
    ),
    remainingMin: remainingMin,
    shortMin: math.max(0, remainingMin - plannedMin),
    doneFraction: targetMin <= 0
        ? (doneMin > 0 ? 1.0 : 0.0)
        : math.min(1.0, doneMin / targetMin),
    plannedEndFraction: targetMin <= 0
        ? (doneMin > 0 ? 1.0 : 0.0)
        : math.min(1.0, (doneMin + plannedMin) / targetMin),
    tickFraction: targetMin <= 0 ? 0.0 : math.min(1.0, expectedMin / targetMin),
    pendingChange: keptPendingTargetChange(experiment, weekStart),
    bars: List.unmodifiable(bars),
    axisStartLabel: axisStartLabel,
    days: List.unmodifiable(days),
  );
}

bool _isWeekend(String date) {
  final weekday = parseIsoDate(date).weekday;
  return weekday == DateTime.saturday || weekday == DateTime.sunday;
}

String? _nonEmpty(String? text) =>
    text == null || text.trim().isEmpty ? null : text;
