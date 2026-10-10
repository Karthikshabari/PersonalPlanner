import 'dart:convert';
import 'dart:math' as math;

import '../../../core/models/experiment.dart';
import '../../../core/utils/date_utils.dart';

const keptTargetMinMinutes = 15;
const keptTargetMaxMinutes = 240;
const keptTargetStepMinutes = 15;

/// The weekday and weekend minutes in force for one week.
typedef KeptTargets = ({int weekdayMin, int weekendMin});

const _changeKeys = {
  'effective_week_start',
  'weekday_target_min',
  'weekend_target_min',
  'made_on',
};

/// Decodes `experiments.target_changes_json`.
///
/// Throws [FormatException] for: text that is not a JSON array; an item that
/// is not an object with exactly the four keys; a wrong value type (a number
/// that is not an int is rejected); a bad date; a non-Monday
/// `effective_week_start`; a target outside 15..240; weeks that are not
/// strictly ascending.
List<ExperimentTargetChange> decodeTargetChangesJson(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List) {
    throw const FormatException('Target changes must be a JSON array');
  }
  final changes = <ExperimentTargetChange>[];
  for (final item in decoded) {
    if (item is! Map) {
      throw const FormatException('Each target change must be an object');
    }
    if (item.length != _changeKeys.length ||
        !_changeKeys.every(item.containsKey)) {
      throw const FormatException(
        'A target change needs exactly effective_week_start, '
        'weekday_target_min, weekend_target_min and made_on',
      );
    }
    final week = item['effective_week_start'];
    final weekday = item['weekday_target_min'];
    final weekend = item['weekend_target_min'];
    final madeOn = item['made_on'];
    if (week is! String ||
        weekday is! int ||
        weekend is! int ||
        madeOn is! String) {
      throw const FormatException(
        'A target change has a value of the wrong type',
      );
    }
    changes.add(
      ExperimentTargetChange(
        effectiveWeekStart: week,
        weekdayTargetMin: weekday,
        weekendTargetMin: weekend,
        madeOn: madeOn,
      ),
    );
  }
  validateTargetChanges(changes);
  return changes;
}

/// JSON text of [changes], in the given (ascending) order.
String encodeTargetChangesJson(List<ExperimentTargetChange> changes) =>
    jsonEncode([for (final change in changes) change.toJson()]);

/// Throws [FormatException] for a bad date, a non-Monday week start, a target
/// outside 15..240, or weeks that are not strictly ascending.
void validateTargetChanges(List<ExperimentTargetChange> changes) {
  for (final change in changes) {
    if (!isValidIsoDate(change.effectiveWeekStart) ||
        !isValidIsoDate(change.madeOn)) {
      throw const FormatException('A target change has a bad date');
    }
  }
  for (final change in changes) {
    final p = change.effectiveWeekStart.split('-');
    final weekday = DateTime.utc(
      int.parse(p[0]),
      int.parse(p[1]),
      int.parse(p[2]),
    ).weekday;
    if (weekday != DateTime.monday) {
      throw const FormatException('A target change must start on a Monday');
    }
  }
  for (final change in changes) {
    if (!_inRange(change.weekdayTargetMin) ||
        !_inRange(change.weekendTargetMin)) {
      throw const FormatException(
        'A target change must be between $keptTargetMinMinutes and '
        '$keptTargetMaxMinutes minutes',
      );
    }
  }
  for (var i = 1; i < changes.length; i++) {
    if (changes[i].effectiveWeekStart.compareTo(
          changes[i - 1].effectiveWeekStart,
        ) <=
        0) {
      throw const FormatException(
        'Target changes must be in strictly ascending weeks',
      );
    }
  }
}

bool _inRange(int minutes) =>
    minutes >= keptTargetMinMinutes && minutes <= keptTargetMaxMinutes;

/// The change with the greatest effectiveWeekStart <= [weekStart], else the
/// experiment's own weekday/weekend targets.
KeptTargets keptTargetsForWeek(Experiment experiment, String weekStart) {
  ExperimentTargetChange? current;
  for (final change in experiment.targetChanges) {
    if (change.effectiveWeekStart.compareTo(weekStart) <= 0) {
      current = change;
    } else {
      break;
    }
  }
  if (current == null) {
    return (
      weekdayMin: experiment.weekdayTargetMin,
      weekendMin: experiment.weekendTargetMin,
    );
  }
  return (
    weekdayMin: current.weekdayTargetMin,
    weekendMin: current.weekendTargetMin,
  );
}

/// The first change with effectiveWeekStart > [currentWeekStart], or null.
ExperimentTargetChange? keptPendingTargetChange(
  Experiment experiment,
  String currentWeekStart,
) {
  for (final change in experiment.targetChanges) {
    if (change.effectiveWeekStart.compareTo(currentWeekStart) > 0) {
      return change;
    }
  }
  return null;
}

/// The whole "target history" rule. Earlier weeks are never rewritten; a
/// pending change or this week's own change is replaced. Values equal to the
/// ones already in force add no entry (and remove any pending one).
List<ExperimentTargetChange> applyKeptTargetChange({
  required Experiment experiment,
  required KeptTargets draft,
  required bool fromNextWeek,
  required String currentWeekStart,
  required String madeOn,
}) {
  final nextWeekStart = isoDateString(
    addDays(parseIsoDate(currentWeekStart), 7),
  );
  final effective = fromNextWeek ? nextWeekStart : currentWeekStart;
  final kept = [
    for (final c in experiment.targetChanges)
      if (c.effectiveWeekStart.compareTo(effective) < 0) c,
  ];
  final base = keptTargetsForWeek(
    experiment.copyWith(targetChanges: kept),
    effective,
  );
  if (base.weekdayMin == draft.weekdayMin &&
      base.weekendMin == draft.weekendMin) {
    return kept;
  }
  return [
    ...kept,
    ExperimentTargetChange(
      effectiveWeekStart: effective,
      weekdayTargetMin: draft.weekdayMin,
      weekendTargetMin: draft.weekendMin,
      madeOn: madeOn,
    ),
  ];
}

int keptStepUp(int minutes) =>
    math.min(keptTargetMaxMinutes, minutes + keptTargetStepMinutes);

int keptStepDown(int minutes) =>
    math.max(keptTargetMinMinutes, minutes - keptTargetStepMinutes);

int keptClampTarget(int minutes) =>
    minutes.clamp(keptTargetMinMinutes, keptTargetMaxMinutes);
