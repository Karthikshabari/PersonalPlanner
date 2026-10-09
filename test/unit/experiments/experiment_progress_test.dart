import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/daos/experiment_dao.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/experiments/domain/experiment_dashboard.dart';
import 'package:personal_planner/features/experiments/domain/experiment_days.dart';
import 'package:personal_planner/features/experiments/domain/experiment_progress.dart';

import '../../helpers/experiment_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  // Weekday 60, weekend 90, Mon Oct 5 to Sun Oct 11 2026, Tuesday is Leave.
  ExperimentProgress progressFor({
    required String today,
    List<TaggedBlockRow> blocks = const [],
    Experiment? experiment,
    Set<String> leave = const {'2026-10-06'},
  }) {
    final e = experiment ?? testExperiment();
    return buildExperimentView(
      experiment: e,
      leaveOrHolidayDates: leave,
      blocks: blocks,
      today: today,
      formatDuration: formatMinutes,
    ).progress;
  }

  final workedExample = [
    testBlock('2026-10-05', actual: 50),
    testBlock('2026-10-06', actual: 30),
    testBlock('2026-10-07', actual: 40),
    testBlock('2026-10-07', hour: 15, status: 'planned', planned: 30),
  ];

  test('the worked example from the plan', () {
    final p = progressFor(today: '2026-10-07', blocks: workedExample);
    expect(p.totalMin, 420);
    expect(p.expectedMin, 100);
    expect(p.doneMin, 120);
    expect(p.paceMin, 20);
    expect(p.paceLabel, '20m ahead');
    expect(p.daysAtTargetLabel, '0 of 1');
    expect(p.hasTodayLine, isTrue);
    expect(p.todayLine, 'Today: 40m done · 30m still planned · target 1h');
    expect(p.shortfallHint, isNull);
    expect(p.headline, 'Done 2h of 1h 40m expected so far');
    expect(p.fillFraction, closeTo(120 / 420, 1e-9));
    expect(p.tickFraction, closeTo(100 / 420, 1e-9));
    expect(p.statusChip, 'Running · Day 3 of 7');
    expect(p.showExtraLegendLine, isTrue);
  });

  group('day totals', () {
    test('a completed block without Actual counts its planned duration', () {
      final p = progressFor(
        today: '2026-10-08',
        blocks: [testBlock('2026-10-05', planned: 45)],
      );
      expect(p.doneMin, 45);
    });

    test('an explicit Actual of 0 counts 0', () {
      final p = progressFor(
        today: '2026-10-08',
        blocks: [testBlock('2026-10-05', actual: 0, planned: 60)],
      );
      expect(p.doneMin, 0);
    });

    test('in-progress, skipped and cancelled blocks add no done minutes', () {
      final p = progressFor(
        today: '2026-10-08',
        blocks: [
          testBlock('2026-10-05', status: 'in_progress'),
          testBlock('2026-10-05', status: 'skipped'),
          testBlock('2026-10-05', status: 'cancelled'),
        ],
      );
      expect(p.doneMin, 0);
    });

    test('blocks outside the window are ignored', () {
      final p = progressFor(
        today: '2026-10-08',
        blocks: [
          testBlock('2026-10-04', actual: 50),
          testBlock('2026-10-12', actual: 50),
        ],
      );
      expect(p.doneMin, 0);
    });
  });

  group('expected so far', () {
    test('Leave and Holiday days expect nothing but done still counts', () {
      final p = progressFor(
        today: '2026-10-08',
        blocks: [testBlock('2026-10-06', actual: 25)],
      );
      // Mon 60 + Tue 0 (Leave) + Wed 60.
      expect(p.expectedMin, 120);
      expect(p.doneMin, 25);
      expect(p.daysAtTargetLabel, '0 of 2');
    });

    test('today counts only the smaller of its target and its done', () {
      final p = progressFor(
        today: '2026-10-05',
        blocks: [testBlock('2026-10-05', actual: 100)],
      );
      expect(p.expectedMin, 60);
      expect(p.doneMin, 100);
      expect(p.paceLabel, '40m ahead');

      final low = progressFor(
        today: '2026-10-05',
        blocks: [testBlock('2026-10-05', actual: 20)],
      );
      expect(low.expectedMin, 20);
      expect(low.paceLabel, 'On pace');
    });

    test('days after today contribute nothing, even completed ones', () {
      final p = progressFor(
        today: '2026-10-05',
        blocks: [testBlock('2026-10-09', actual: 60)],
      );
      expect(p.expectedMin, 0);
      expect(p.doneMin, 0);
    });

    test('a concluded experiment counts every day as finished', () {
      final p = progressFor(
        today: '2026-10-20',
        experiment: testExperiment(
          status: ExperimentStatus.concluded,
          concludedOn: '2026-10-12',
        ),
        blocks: [testBlock('2026-10-05', actual: 60)],
      );
      expect(p.expectedMin, 420);
      expect(p.doneMin, 60);
      expect(p.paceLabel, '6h behind');
      expect(p.hasTodayLine, isFalse);
      expect(p.showExtraLegendLine, isFalse);
      expect(p.statusChip, 'Concluded Oct 12');
    });
  });

  group('pace', () {
    test('Not started before the start date', () {
      final p = progressFor(today: '2026-10-01');
      expect(p.paceLabel, 'Not started');
      expect(p.statusChip, 'Starts Oct 5');
      expect(p.daysAtTargetLabel, 'None yet');
      expect(p.hasTodayLine, isFalse);
      expect(p.showExtraLegendLine, isFalse);
      expect(
        p.headline,
        'Nothing is expected yet. Complete a block with the tag Learn C and '
        'it shows up here.',
      );
    });

    test('On pace when nothing has finished yet', () {
      expect(progressFor(today: '2026-10-05').paceLabel, 'On pace');
    });

    test('behind once a day is over with nothing done', () {
      final p = progressFor(today: '2026-10-06', leave: const {});
      expect(p.paceLabel, '1h behind');
      expect(p.headline, 'Done 0m of 1h expected so far');
    });

    test('never uses failed or late wording', () {
      final p = progressFor(today: '2026-10-11');
      final text = '${p.paceLabel} ${p.headline} ${p.statusChip}';
      expect(text.toLowerCase(), isNot(contains('failed')));
      expect(text.toLowerCase(), isNot(contains('late')));
    });
  });

  group('days at your target', () {
    test('counts finished days that reached their target', () {
      final p = progressFor(
        today: '2026-10-07',
        leave: const {},
        blocks: [
          testBlock('2026-10-05', actual: 60),
          testBlock('2026-10-06', actual: 59),
        ],
      );
      expect(p.daysAtTargetLabel, '1 of 2');
    });

    test('adds today once it has reached its target', () {
      final p = progressFor(
        today: '2026-10-06',
        leave: const {},
        blocks: [
          testBlock('2026-10-05', actual: 60),
          testBlock('2026-10-06', actual: 60),
        ],
      );
      expect(p.daysAtTargetLabel, '2 of 2');
    });

    test('does not add today while it is below its target', () {
      final p = progressFor(
        today: '2026-10-06',
        leave: const {},
        blocks: [
          testBlock('2026-10-05', actual: 60),
          testBlock('2026-10-06', actual: 59),
        ],
      );
      expect(p.daysAtTargetLabel, '1 of 1');
    });
  });

  group('today line', () {
    test('shows the shortfall hint when the plan is short of the target', () {
      final p = progressFor(
        today: '2026-10-07',
        blocks: [
          testBlock('2026-10-07', actual: 10),
          testBlock('2026-10-07', hour: 15, status: 'planned', planned: 20),
        ],
      );
      expect(p.shortfallMin, 30);
      expect(p.shortfallHint, "Your plan is 30m short of today's target.");
    });

    test('a Leave or Holiday day says there is no target', () {
      final p = progressFor(
        today: '2026-10-06',
        blocks: [testBlock('2026-10-06', actual: 15)],
      );
      expect(
        p.todayLine,
        'Today: 15m done · 0m still planned · Leave, no target',
      );
      expect(p.shortfallHint, isNull);
    });
  });

  group('bar and chip', () {
    test('total 0 gives empty bar and tick', () {
      final p = progressFor(
        today: '2026-10-07',
        experiment: testExperiment(weekday: 0, weekend: 0),
        blocks: [testBlock('2026-10-05', actual: 50)],
      );
      expect(p.totalMin, 0);
      expect(p.fillFraction, 0);
      expect(p.tickFraction, 0);
      expect(p.daysAtTargetLabel, 'None yet');
    });

    test('fractions are capped at 100 percent', () {
      final p = progressFor(
        today: '2026-10-11',
        leave: const {},
        blocks: [
          for (var d = 5; d <= 11; d++)
            testBlock('2026-10-${d.toString().padLeft(2, '0')}', actual: 500),
        ],
      );
      expect(p.fillFraction, 1.0);
      expect(p.tickFraction, closeTo(1.0, 1e-9));
    });

    test('the day number is capped at the window length', () {
      final p = progressFor(today: '2026-10-30');
      expect(p.statusChip, 'Running · Day 7 of 7');
      expect(p.hasTodayLine, isFalse);
      expect(p.showExtraLegendLine, isFalse);
    });

    test('a window of one day', () {
      final p = progressFor(
        today: '2026-10-05',
        experiment: testExperiment(end: '2026-10-05'),
      );
      expect(p.statusChip, 'Running · Day 1 of 1');
    });
  });

  group('texts', () {
    test('dates line', () {
      expect(
        experimentDatesLine(
          testExperiment(start: '2026-10-03', end: '2026-11-05'),
        ),
        'Oct 3 to Nov 5 · 60 min weekdays · 90 min weekends · '
        'every day check-in',
      );
      expect(
        experimentDatesLine(testExperiment(every: 7)),
        endsWith('every week check-in'),
      );
      expect(
        experimentDatesLine(testExperiment(every: 10)),
        endsWith('every 10 days check-in'),
      );
    });

    test('frequency labels', () {
      expect(experimentFrequencyLabel(1), 'Every day');
      expect(experimentFrequencyLabel(3), 'Every 3 days');
      expect(experimentFrequencyLabel(7), 'Every week');
      expect(experimentFrequencyLabel(10), 'Every 10 days');
      expect(experimentFrequencyLabel(15), 'Every 15 days');
    });

    test('extension line', () {
      ExperimentExtension ext(String reason) => ExperimentExtension(
        reason: reason,
        previousEndDate: '2026-10-11',
        newEndDate: '2026-10-25',
        madeOn: '2026-10-11',
      );
      expect(experimentExtensionLine(testExperiment()), isNull);
      expect(
        experimentExtensionLine(
          testExperiment(extensions: [ext('Travelling')]),
        ),
        'Extended 1 time. Last reason: Travelling',
      );
      expect(
        experimentExtensionLine(
          testExperiment(extensions: [ext('Travelling'), ext('Flu')]),
        ),
        'Extended 2 times. Last reason: Flu',
      );
    });
  });

  test('DayMinutes.zero is a real constant for missing days', () {
    expect(DayMinutes.zero.doneMin, 0);
    expect(DayMinutes.zero.stillPlannedMin, 0);
  });
}
