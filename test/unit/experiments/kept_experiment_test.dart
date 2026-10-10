import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/experiments/domain/experiment_target_changes.dart';
import 'package:personal_planner/features/experiments/domain/kept_copy.dart';
import 'package:personal_planner/features/experiments/domain/kept_experiment.dart';

import '../../helpers/experiment_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

const _monday = '2026-10-05';
const _saturday = '2026-10-10';

/// V1's day minutes: Mon 60, Tue 0, Wed 90, Thu 90, Fri 90, Sat 0 (today).
const _v1Days = {0: 60, 1: 0, 2: 90, 3: 90, 4: 90, 5: 0};

KeptExperimentView build(
  Experiment experiment, {
  String today = _saturday,
  Map<int, int> doneByWeek = const {8: 330},
  Map<int, int> doneByDay = _v1Days,
  int planned = 150,
}) => buildKeptExperimentView(
  experiment: experiment,
  today: today,
  doneByWeek: doneByWeek,
  doneByDay: doneByDay,
  plannedMin: planned,
  formatDuration: formatMinutes,
);

String strip(KeptExperimentView view) => keptPartsText(
  keptPlannedStripParts(
    view.planState,
    planned: view.plannedMin,
    short: view.shortMin,
    remaining: view.remainingMin,
    formatDuration: formatMinutes,
  ),
);

void main() {
  setupSqliteForTests();

  final v1 = testKeptExperiment();

  group('V1 Morning pages', () {
    test('numbers, chip, strip and fractions', () {
      final view = build(v1);
      expect(view.targetMin, 480);
      expect(formatMinutes(view.targetMin), '8h');
      expect(view.doneMin, 330);
      expect(formatMinutes(view.doneMin), '5h 30m');
      expect(view.expectedMin, 300);
      expect(formatMinutes(view.expectedMin), '5h');
      expect(view.paceMin, 30);
      expect(view.chipText, '30m ahead');
      expect(view.chipTone, KeptTone.positive);
      expect(view.planState, KeptPlanState.reachesMinimum);
      expect(
        strip(view),
        'Planned: 2h 30m more this week. That reaches the minimum.',
      );
      expect(view.doneFraction, 0.6875);
      expect(view.plannedEndFraction, 1.0);
      expect(view.tickFraction, 0.625);
      expect(view.weekdayCount, 5);
      expect(view.weekendCount, 2);
      expect(view.weekdayTargetMin, 60);
      expect(view.weekendTargetMin, 90);
      expect(view.weekStart, _monday);
      expect(view.nextWeekStart, '2026-10-12');
      expect(view.pendingChange, isNull);
    });

    test('the current bar and its detail text', () {
      final bar = build(v1).bars.last;
      expect(bar.isCurrent, isTrue);
      expect(bar.heightPercent, 69);
      expect(bar.percent, 69);
      expect(
        keptBarDetailText(bar, formatMinutes),
        '5h 30m of 8h · 69% so far',
      );
      expect(bar.targetThenMin, isNull);
      expect(keptTargetThenText(bar, formatMinutes), isNull);
    });

    test('titles, subtitle and week labels', () {
      final view = build(v1);
      expect(view.name, 'Morning pages');
      expect(view.keptSince, '2026-10-09');
      expect(view.subtitle, 'Kept since Oct 9 · #Morning pages');
      expect(view.bars.last.label, 'This week · Oct 5 – 11');
      expect(
        view.bars.last.semanticsLabel,
        'This week · Oct 5 – 11: 5h 30m of 8h',
      );
      expect(view.bars[view.bars.length - 2].label, 'Sep 28 – Oct 4');
      expect(view.bars[1].label, 'Sep 7 – 13');
      expect(view.why, isNull);
    });

    test('the why text is the conclusion note', () {
      final view = build(testKeptExperiment(why: 'Mornings beat evenings.'));
      expect(view.why, 'Mornings beat evenings.');
    });

    test('two builds from identical inputs are equal', () {
      final a = build(v1);
      final b = build(testKeptExperiment());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(build(v1, planned: 151), isNot(a));
    });
  });

  test('V2 Evening walk is behind with a short plan', () {
    final walk = testKeptExperiment(
      tagName: 'Evening walk',
      weekday: 30,
      weekend: 30,
    );
    final view = build(
      walk,
      doneByWeek: const {8: 100},
      doneByDay: const {0: 30, 1: 30, 2: 0, 3: 30, 4: 10, 5: 0},
      planned: 60,
    );
    expect(view.targetMin, 210);
    expect(formatMinutes(view.targetMin), '3h 30m');
    expect(view.doneMin, 100);
    expect(view.expectedMin, 150);
    expect(view.paceMin, -50);
    expect(view.chipText, '50m behind');
    expect(view.chipTone, KeptTone.caution);
    expect(view.remainingMin, 110);
    expect(formatMinutes(view.remainingMin), '1h 50m');
    expect(view.shortMin, 50);
    expect(view.planState, KeptPlanState.shortOfMinimum);
    expect(
      strip(view),
      'Planned: 1h more this week. 50m short of the minimum.',
    );
  });

  test('V3 Reading is over target', () {
    final reading = testKeptExperiment(
      tagName: 'Reading',
      weekday: 30,
      weekend: 30,
    );
    final view = build(
      reading,
      doneByWeek: const {8: 250},
      doneByDay: const {0: 50, 1: 40, 2: 45, 3: 60, 4: 55},
      planned: 0,
    );
    expect(view.targetMin, 210);
    expect(view.doneMin, 250);
    expect(view.chipText, '40m over target');
    expect(view.chipTone, KeptTone.positive);
    expect(view.planState, KeptPlanState.targetReached);
    expect(
      strip(view),
      'Target reached for this week. Anything more is extra.',
    );
    final bar = view.bars.last;
    expect(bar.heightPercent, 100);
    expect(bar.percent, 119);
    expect(
      keptBarDetailText(bar, formatMinutes),
      '4h 10m of 3h 30m · 119% so far',
    );
  });

  group('V4 target changes', () {
    test('V4a from this week', () {
      final changes = applyKeptTargetChange(
        experiment: v1,
        draft: (weekdayMin: 75, weekendMin: 90),
        fromNextWeek: false,
        currentWeekStart: _monday,
        madeOn: _saturday,
      );
      expect(changes, [
        const ExperimentTargetChange(
          effectiveWeekStart: _monday,
          weekdayTargetMin: 75,
          weekendTargetMin: 90,
          madeOn: _saturday,
        ),
      ]);
      final changed = testKeptExperiment(targetChanges: changes);
      final view = build(changed);
      expect(view.targetMin, 555);
      expect(formatMinutes(view.targetMin), '9h 15m');
      expect(view.expectedMin, 375);
      expect(view.chipText, '45m behind');
      expect(keptWeekTargetMin(changed, '2026-09-28'), 480);
      final previous = view.bars.firstWhere((b) => b.weekStart == '2026-09-28');
      expect(previous.targetThenMin, 480);
      expect(keptTargetThenText(previous, formatMinutes), 'Target then: 8h');
      expect(view.bars.first.weekStart, '2026-08-31');
      expect(view.bars.first.targetMin, 240);
    });

    test('V4b from next Monday', () {
      final changes = applyKeptTargetChange(
        experiment: v1,
        draft: (weekdayMin: 75, weekendMin: 90),
        fromNextWeek: true,
        currentWeekStart: _monday,
        madeOn: _saturday,
      );
      expect(changes, [
        const ExperimentTargetChange(
          effectiveWeekStart: '2026-10-12',
          weekdayTargetMin: 75,
          weekendTargetMin: 90,
          madeOn: _saturday,
        ),
      ]);
      final view = build(testKeptExperiment(targetChanges: changes));
      expect(view.targetMin, 480);
      final pending = view.pendingChange!;
      expect(
        keptPartsText(keptPendingNoteParts(pending, formatMinutes)),
        'From Mon Oct 12 the minimum becomes 9h 15m a week '
        '(5 × 75m + 2 × 90m).',
      );
    });

    test(
      'V4c a second draft equal to the current values removes the entry',
      () {
        final first = applyKeptTargetChange(
          experiment: v1,
          draft: (weekdayMin: 75, weekendMin: 90),
          fromNextWeek: true,
          currentWeekStart: _monday,
          madeOn: _saturday,
        );
        final second = applyKeptTargetChange(
          experiment: testKeptExperiment(targetChanges: first),
          draft: (weekdayMin: 60, weekendMin: 90),
          fromNextWeek: true,
          currentWeekStart: _monday,
          madeOn: _saturday,
        );
        expect(second, isEmpty);
        expect(
          build(testKeptExperiment(targetChanges: second)).pendingChange,
          isNull,
        );
      },
    );
  });

  test('V5 an experiment that starts on Friday counts only its days', () {
    final friday = testKeptExperiment(
      start: '2026-10-09',
      end: '2026-10-09',
      concludedOn: '2026-10-09',
    );
    expect(keptWeekTargetMin(friday, _monday), 240);
    expect(
      keptExpectedByTodayMin(friday, weekStart: _monday, today: _saturday),
      60,
    );
  });

  test('V6 steppers', () {
    expect(keptStepDown(15), 15);
    expect(keptStepUp(240), 240);
    expect(keptStepUp(75), 90);
    expect(keptClampTarget(0), 15);
    expect(keptClampTarget(300), 240);
  });

  test('E1 an empty week on Monday', () {
    final view = build(
      v1,
      today: _monday,
      doneByWeek: const {},
      doneByDay: const {},
      planned: 0,
    );
    expect(view.expectedMin, 0);
    expect(view.paceMin, 0);
    expect(view.chipText, 'On pace');
    expect(view.planState, KeptPlanState.nothingPlanned);
    expect(
      strip(view),
      'Nothing planned for the rest of the week. 8h left to reach the minimum.',
    );
    expect(view.bars.every((b) => b.heightPercent == 0), isTrue);
  });

  test('E2 a week that starts on a Sunday', () {
    expect(keptWeekTargetMin(v1, '2026-10-04'), 480);
  });

  test('E3 across the New York DST change', () {
    PlannerTimeZone.initialize(identifier: 'America/New_York');
    addTearDown(() => PlannerTimeZone.initialize(identifier: 'Asia/Kolkata'));
    final starts = keptWeekStarts('2026-10-31');
    expect(starts, hasLength(9));
    expect(starts.last, '2026-10-26');
    expect(starts[starts.length - 2], '2026-10-19');
    final view = build(
      v1,
      today: '2026-10-31',
      doneByWeek: const {},
      doneByDay: const {},
      planned: 0,
    );
    expect(view.weekStart, '2026-10-26');
    expect(view.nextWeekStart, '2026-11-02');
    expect(
      [for (final d in view.days) d.date],
      [
        '2026-10-26',
        '2026-10-27',
        '2026-10-28',
        '2026-10-29',
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
      ],
    );
  });

  test('E4 today is not part of expected-by-today', () {
    final view = build(
      v1,
      today: '2026-10-07',
      doneByWeek: const {8: 160},
      doneByDay: const {0: 60, 1: 60, 2: 40},
      planned: 0,
    );
    expect(view.expectedMin, 120);
    expect(view.doneMin, 160);
    expect(view.chipText, '40m ahead');
  });

  test('E5 exactly on target', () {
    final view = build(v1, doneByWeek: const {8: 480});
    expect(view.chipText, 'Target reached');
    expect(view.chipTone, KeptTone.positive);
  });

  test('E6 over target with plans left', () {
    final view = build(v1, doneByWeek: const {8: 500}, planned: 60);
    expect(view.planState, KeptPlanState.targetReached);
    expect(view.doneFraction, 1.0);
    expect(view.plannedEndFraction, view.doneFraction);
  });

  test('E7 an old experiment shows nine bars', () {
    final view = build(testKeptExperiment(start: '2026-06-01'));
    expect(view.bars, hasLength(9));
    expect(view.bars.first.weekStart, '2026-08-10');
    expect(view.axisStartLabel, 'Aug 10');
  });

  test('E8 a recent experiment shows the weeks since its start', () {
    final view = build(v1);
    expect(view.bars, hasLength(6));
    expect(view.bars.first.weekStart, '2026-08-31');
    expect(view.bars.last.weekStart, '2026-10-05');
    expect(view.axisStartLabel, 'Sep 4');
  });

  test('E9 zero targets', () {
    final view = build(
      testKeptExperiment(weekday: 0, weekend: 0),
      doneByWeek: const {},
      doneByDay: const {},
      planned: 0,
    );
    expect(view.targetMin, 0);
    expect(view.chipText, 'Target reached');
    final bar = view.bars.last;
    expect(bar.percent, isNull);
    expect(bar.heightPercent, 0);
    expect(view.doneFraction, 0);
    expect(keptBarDetailText(bar, formatMinutes), '0m of 0m so far');
  });

  test('E10 the day columns of V1', () {
    final days = build(v1).days;
    expect(
      [for (final d in days) d.valueLabel],
      ['60m', '0m', '90m', '90m', '90m', 'today', '–'],
    );
    final fills = [for (final d in days) d.fillFraction];
    final expected = [0.6667, 0, 1, 1, 1, 0, 0];
    for (var i = 0; i < 7; i++) {
      expect(fills[i], closeTo(expected[i], 0.00005), reason: 'day $i');
    }
    expect(
      [for (final d in days) d.dim],
      [false, false, false, false, false, true, true],
    );
    expect(days.first.dayName, 'Mon');
    expect(days[5].isToday, isTrue);
  });

  group('copy', () {
    test('labels', () {
      expect(keptSegmentLabel(2), 'Kept (2)');
      expect(
        keptEmptyText(),
        'Nothing kept yet. Conclude an experiment with Keep it and it shows '
        'up here.',
      );
      expect(keptFromNextWeekLabel('2026-10-12'), 'From next Monday, Oct 12');
      expect(keptExplainToggle(false), 'How this is counted');
      expect(keptExplainToggle(true), 'Hide how this is counted');
      expect(keptRetireHeading('Reading'), 'Retire Reading?');
      expect(
        keptRetiredLine('Reading', noteSaved: true),
        'Reading retired. Note saved. Its record is under Concluded.',
      );
      expect(
        keptRetiredLine('Reading', noteSaved: false),
        'Reading retired. Its record is under Concluded.',
      );
      expect(keptNowUnderText(), 'Now under Kept');
      expect(keptRetiredChip(DateTime.utc(2026, 10, 9, 12)), 'Retired Oct 9');
      expect(
        keptMathMinimum(
          weekdayCount: 5,
          weekdayMin: 60,
          weekendCount: 2,
          weekendMin: 90,
        ),
        'Weekly minimum · 5 × 60m + 2 × 90m',
      );
      expect(
        keptMathDone('Reading'),
        'Done · completed blocks tagged #Reading',
      );
      expect(keptThisWeekSuffix('8h'), 'of 8h this week');
      expect(
        keptPartsText(keptNewMinimumParts(75, 90, formatMinutes)),
        'New weekly minimum: 5 × 75m + 2 × 90m = 9h 15m',
      );
    });

    test('no user-facing text says habit', () {
      final texts = <String>[
        keptEmptyText(),
        keepOutcomeLabel,
        keptName,
        keptRetireExplanation,
        keptEarlierWeeksNote,
        ...[
          for (final state in KeptPlanState.values)
            keptPartsText(
              keptPlannedStripParts(
                state,
                planned: 30,
                short: 10,
                remaining: 40,
                formatDuration: formatMinutes,
              ),
            ),
        ],
      ];
      for (final text in texts) {
        expect(text.toLowerCase(), isNot(contains('habit')));
      }
    });
  });
}
