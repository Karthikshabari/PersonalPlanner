import 'package:intl/intl.dart';

import '../../../core/models/experiment.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import 'experiment_progress.dart' show DurationFormatter;
import 'kept_experiment.dart';

/// Every user-facing string of the Kept feature (Appendix A of the plan),
/// except the view fields that `kept_experiment.dart` builds itself
/// (subtitle, week label, semantics label, value label, chip text). The
/// segment name and the outcome label live in `experiment.dart`.

/// A piece of a sentence. [bold] pieces carry the numbers.
class KeptTextPart {
  const KeptTextPart(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) =>
      other is KeptTextPart && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => bold ? '**$text**' : text;
}

/// The plain text of [parts].
String keptPartsText(List<KeptTextPart> parts) =>
    parts.map((part) => part.text).join();

String keptSegmentLabel(int n) => '$keptName ($n)';

String keptEmptyText() =>
    'Nothing ${keptName.toLowerCase()} yet. '
    'Conclude an experiment with $keepOutcomeLabel and it shows up here.';

const keptWhyLabel = 'Why';

/// "of {target} this week"; [target] is the formatted weekly minimum.
String keptThisWeekSuffix(String target) => 'of $target this week';

const keptLegendDone = 'Done';
const keptLegendPlanned = 'Planned';
const keptLegendExpected = 'Expected by today';

/// "From {EEE MMM d} the minimum becomes **{total}** a week
/// (5 × {a}m + 2 × {b}m)."
List<KeptTextPart> keptPendingNoteParts(
  ExperimentTargetChange change,
  DurationFormatter formatDuration,
) {
  final from = DateFormat('EEE MMM d')
      .format(parseIsoDate(change.effectiveWeekStart));
  final total = 5 * change.weekdayTargetMin + 2 * change.weekendTargetMin;
  return [
    KeptTextPart('From $from the minimum becomes '),
    KeptTextPart(formatDuration(total), bold: true),
    KeptTextPart(
      ' a week (5 × ${change.weekdayTargetMin}m + '
      '2 × ${change.weekendTargetMin}m).',
    ),
  ];
}

/// The planned strip (7.3). [planned], [short] and [remaining] are minutes.
List<KeptTextPart> keptPlannedStripParts(
  KeptPlanState state, {
  required int planned,
  required int short,
  required int remaining,
  required DurationFormatter formatDuration,
}) {
  switch (state) {
    case KeptPlanState.targetReached:
      return const [
        KeptTextPart('Target reached for this week. Anything more is extra.'),
      ];
    case KeptPlanState.reachesMinimum:
      return [
        const KeptTextPart('Planned: '),
        KeptTextPart(formatDuration(planned), bold: true),
        const KeptTextPart(' more this week. That reaches the minimum.'),
      ];
    case KeptPlanState.shortOfMinimum:
      return [
        const KeptTextPart('Planned: '),
        KeptTextPart(formatDuration(planned), bold: true),
        const KeptTextPart(' more this week. '),
        KeptTextPart(formatDuration(short), bold: true),
        const KeptTextPart(' short of the minimum.'),
      ];
    case KeptPlanState.nothingPlanned:
      return [
        const KeptTextPart('Nothing planned for the rest of the week. '),
        KeptTextPart(formatDuration(remaining), bold: true),
        const KeptTextPart(' left to reach the minimum.'),
      ];
  }
}

const keptPlanLink = 'Plan it in Day';

const keptWeeklyTotals = 'Weekly totals';
const keptFullHeight = "Full height = that week's target";
const keptThisWeekAxis = 'This week';

/// "{done} of {target} · {p}%", plus " so far" for the current week. The
/// percentage part is left out when the week has no target.
String keptBarDetailText(KeptWeekBar bar, DurationFormatter formatDuration) {
  final percent = bar.percent;
  final text =
      '${formatDuration(bar.doneMin)} of ${formatDuration(bar.targetMin)}'
      '${percent == null ? '' : ' · $percent%'}';
  return bar.isCurrent ? '$text so far' : text;
}

/// "Target then: {x}", or null when the bar has no different earlier target.
String? keptTargetThenText(KeptWeekBar bar, DurationFormatter formatDuration) {
  final then = bar.targetThenMin;
  return then == null ? null : 'Target then: ${formatDuration(then)}';
}

String keptExplainToggle(bool open) =>
    open ? 'Hide how this is counted' : 'How this is counted';

/// "Weekly minimum · {n} × {a}m + {k} × {b}m".
String keptMathMinimum({
  required int weekdayCount,
  required int weekdayMin,
  required int weekendCount,
  required int weekendMin,
}) =>
    'Weekly minimum · $weekdayCount × ${weekdayMin}m + '
    '$weekendCount × ${weekendMin}m';

String keptMathDone(String tag) => 'Done · completed blocks tagged #$tag';

const keptMathPlanned = 'Planned · scheduled blocks, today onward';
const keptMathExpected = 'Expected by today · days already finished';
const keptMathPace = 'Pace';

const keptAdjustLink = 'Adjust target';
const keptRetireLink = 'Retire';

const keptAdjustHeading = 'Adjust weekly minimum';
const keptWeekdaysLabel = 'Weekdays (minutes)';
const keptWeekendLabel = 'Weekend days (minutes)';

/// "New weekly minimum: 5 × {a}m + 2 × {b}m = **{total}**".
List<KeptTextPart> keptNewMinimumParts(
  int weekdayMin,
  int weekendMin,
  DurationFormatter formatDuration,
) => [
  KeptTextPart(
    'New weekly minimum: 5 × ${weekdayMin}m + 2 × ${weekendMin}m = ',
  ),
  KeptTextPart(formatDuration(5 * weekdayMin + 2 * weekendMin), bold: true),
];

/// "From next Monday, Oct 12"; [nextWeekStart] is `yyyy-MM-dd`.
String keptFromNextWeekLabel(String nextWeekStart) {
  final date = parseIsoDate(nextWeekStart);
  return 'From next ${DateFormat('EEEE').format(date)}, '
      '${DateFormat('MMM d').format(date)}';
}

const keptFromThisWeek = 'From this week';
const keptEarlierWeeksNote = 'Earlier weeks keep the target they had.';

const keptStepperLess = 'Less';
const keptStepperMore = 'More';

const keptCancel = 'Cancel';
const keptSave = 'Save';
const keptRetireButton = 'Retire';

String keptRetireHeading(String name) => 'Retire $name?';

const keptRetireExplanation =
    'Retire it when you no longer need to track it. That is a fine outcome. '
    'The record stays under Concluded.';

const keptRetireNoteLabel = 'What did you learn? (optional)';
const keptRetireNoteHint = 'One line is enough.';

String keptRetiredLine(String name, {required bool noteSaved}) => noteSaved
    ? '$name retired. Note saved. Its record is under Concluded.'
    : '$name retired. Its record is under Concluded.';

const keptUndo = 'Undo';

String keptNowUnderText() => 'Now under $keptName';
const keptSeeIt = 'See it';

/// "Retired {MMM d}" for the planner-local date of [retiredAt].
String keptRetiredChip(DateTime retiredAt) =>
    'Retired ${DateFormat('MMM d').format(PlannerTimeZone.toPlannerLocal(retiredAt))}';

const keptWhenRetiredLabel = 'When retired';
