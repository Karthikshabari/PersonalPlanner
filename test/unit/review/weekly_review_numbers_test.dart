import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/domain/weekly_review_text.dart';

import '../../helpers/weekly_review_fixtures.dart';

void main() {
  group('prototype fixtures', () {
    final expected =
        <
          String,
          ({
            int done,
            int percent,
            int rows,
            String? delta,
            List<String> highlights,
            String subline,
            List<String> reasons,
            String blocker,
            List<String> dayTypes,
          })
        >{
          'good': (
            done: 5,
            percent: 36,
            rows: 5,
            delta: null,
            highlights: [
              'Every missed task has a reason',
              'Reviewed 4 days',
              '5 tasks done',
            ],
            subline:
                '5 of 14 tasks · 2 skipped · 3 rescheduled · 1 plan changed',
            reasons: [
              'Low energy ×3',
              'Ran out of time ×2',
              'Interrupted ×2',
              'Blocked ×1',
            ],
            blocker: 'Most common blocker this week: Low energy (3 times).',
            dayTypes: ['Office 3 days 3 of 10', 'Leave 2 days 2 of 4'],
          ),
          'great': (
            done: 7,
            percent: 50,
            rows: 5,
            delta: 'Up 5 points from last week',
            highlights: [
              'Every missed task has a reason',
              'Reviewed 4 days',
              '7 tasks done',
            ],
            subline:
                '7 of 14 tasks · 2 skipped · 3 rescheduled · 1 plan changed',
            reasons: ['Low energy ×3', 'Interrupted ×2', 'Blocked ×1'],
            blocker: 'Most common blocker this week: Low energy (3 times).',
            dayTypes: ['Office 3 days 5 of 10', 'Leave 2 days 2 of 4'],
          ),
          'excellent': (
            done: 10,
            percent: 71,
            rows: 2,
            delta: 'Up 26 points from last week',
            highlights: [
              'All done on Tue',
              '3 days above 60%',
              'Every missed task has a reason',
            ],
            subline:
                '10 of 14 tasks · 1 skipped · 1 rescheduled · 1 plan changed',
            reasons: ['Low energy ×2', 'Interrupted ×1'],
            blocker: 'Most common blocker this week: Low energy (2 times).',
            dayTypes: ['Office 3 days 8 of 10', 'Leave 2 days 2 of 4'],
          ),
          'legendary': (
            done: 13,
            percent: 93,
            rows: 0,
            delta: 'New best week',
            highlights: [
              'All done on Mon and Tue',
              '4 days above 60%',
              'Reviewed 4 days',
            ],
            subline: '13 of 14 tasks · 1 plan changed',
            reasons: [],
            blocker: 'No blockers recorded this week.',
            dayTypes: ['Office 3 days 10 of 10', 'Leave 2 days 3 of 4'],
          ),
        };

    for (final MapEntry(key: scenario, value: want) in expected.entries) {
      test('$scenario week', () {
        final numbers = computeWeeklyNumbers(fixtureWeek(scenario));

        expect(numbers.total, 14);
        expect(numbers.completed, want.done);
        expect(numbers.percent, want.percent);
        expect(numbers.outcomeRows, hasLength(want.rows));
        expect(numbers.highlights, want.highlights);
        expect(numbers.glanceSubline, want.subline);
        expect(numbers.blockerLine, want.blocker);
        expect(numbers.noReasonCount, 1);
        expect(
          numbers.reasonCounts.map((r) => '${r.reason} ×${r.count}'),
          want.reasons,
        );
        expect(
          numbers.dayTypes.map(
            (t) => '${t.label} ${t.days} days ${t.completed} of ${t.total}',
          ),
          want.dayTypes,
        );
        expect(
          weeklyDeltaText(percent: numbers.percent, previous: fixtureHistory()),
          want.delta,
        );
      });
    }

    test(
      'outcome rows are Skipped or Rescheduled only, plan change merged',
      () {
        final rows = computeWeeklyNumbers(fixtureWeek('good')).outcomeRows;

        expect(rows.map((r) => r.title), [
          'Draft API doc',
          'Update onboarding doc',
          'Walk, 30 min',
          'Gym session',
          'Refactor sync tests',
        ]);
        expect(
          rows.every(
            (r) =>
                r.outcome == TaskOutcome.skipped ||
                r.outcome == TaskOutcome.rescheduled,
          ),
          isTrue,
        );
        final refactor = rows.last;
        expect(refactor.planChange!.oldValue, 'Refactor tests');
        expect(refactor.planChange!.reason, 'Scope grew');
        expect(refactor.reason, 'Low energy');
        expect(refactor.dayReviewed, isTrue);
      },
    );

    test('day stats follow the start-day rule', () {
      final days = computeWeeklyNumbers(fixtureWeek('great')).days;

      expect(days.map((d) => d.percent), [50, 67, 33, 50, 50, null, null]);
      expect(days.map((d) => d.reviewed), [
        true,
        true,
        true,
        true,
        false,
        false,
        false,
      ]);
      expect(days.first.contextLabel, 'Office');
      expect(days.first.mood, 1);
    });
  });

  group('dots', () {
    test('seven past weeks plus this week, gaps stay gaps', () {
      final dots = weeklyDots(fixtureHistory());

      expect(dots.map((d) => d.kind), [
        WeeklyDotKind.reviewed,
        WeeklyDotKind.reviewed,
        WeeklyDotKind.reviewed,
        WeeklyDotKind.gap,
        WeeklyDotKind.reviewed,
        WeeklyDotKind.reviewed,
        WeeklyDotKind.reviewed,
        WeeklyDotKind.current,
      ]);
      expect(dots.map((d) => d.mood), [2, 3, 3, null, 2, 4, 1, null]);
      expect(
        weeksReviewedLabel(weeklyReviewedDotCount(dots, currentSaved: false)),
        '6 of 8 weeks reviewed',
      );
      expect(
        weeksReviewedLabel(weeklyReviewedDotCount(dots, currentSaved: true)),
        '7 of 8 weeks reviewed',
      );
    });

    test('fewer than seven past weeks are padded with gaps', () {
      final dots = weeklyDots(fixtureHistory().sublist(5));

      expect(dots, hasLength(8));
      expect(dots.take(5).every((d) => d.kind == WeeklyDotKind.gap), isTrue);
    });
  });

  group('delta', () {
    test('no previous reviewed week: no delta, not even best', () {
      expect(weeklyDeltaText(percent: 80, previous: const []), isNull);
    });

    test('last week not reviewed: only New best week is possible', () {
      final history = fixtureHistory()..removeLast();
      expect(weeklyDeltaText(percent: 60, previous: history), isNull);
      expect(weeklyDeltaText(percent: 83, previous: history), 'New best week');
    });

    test('never negative and no delta for a week without tasks', () {
      expect(weeklyDeltaText(percent: 40, previous: fixtureHistory()), isNull);
      expect(weeklyDeltaText(percent: 45, previous: fixtureHistory()), isNull);
      expect(
        weeklyDeltaText(percent: null, previous: fixtureHistory()),
        isNull,
      );
    });
  });

  group('highlights edge cases', () {
    test('one task done reads "1 task done"; none done adds nothing', () {
      final one = computeWeeklyNumbers([
        WeeklyDayInput(
          date: DateTime(2026, 9, 28),
          reviewed: false,
          tasks: const [
            WeeklyTaskInput(
              taskId: 'a',
              title: 'A',
              outcome: TaskOutcome.completed,
            ),
            WeeklyTaskInput(
              taskId: 'b',
              title: 'B',
              outcome: TaskOutcome.notStarted,
            ),
          ],
        ),
      ]);
      expect(one.highlights, ['1 task done']);

      final none = computeWeeklyNumbers([
        WeeklyDayInput(
          date: DateTime(2026, 9, 28),
          reviewed: false,
          tasks: const [
            WeeklyTaskInput(
              taskId: 'b',
              title: 'B',
              outcome: TaskOutcome.notStarted,
            ),
          ],
        ),
      ]);
      expect(none.highlights, isEmpty);
      expect(none.percent, 0);
    });

    test('a week with no tasks has no percent', () {
      final numbers = computeWeeklyNumbers([
        WeeklyDayInput(
          date: DateTime(2026, 9, 28),
          reviewed: true,
          tasks: const [],
        ),
      ]);
      expect(numbers.percent, isNull);
      expect(numbers.hasMissedTasks, isFalse);
    });

    test('exactly 60% is not above 60%', () {
      final days = [
        for (var i = 0; i < 3; i++)
          WeeklyDayInput(
            date: DateTime(2026, 9, 28 + i),
            reviewed: false,
            tasks: [
              for (var j = 0; j < 5; j++)
                WeeklyTaskInput(
                  taskId: '$i-$j',
                  title: 'T',
                  outcome: j < 3
                      ? TaskOutcome.completed
                      : TaskOutcome.notStarted,
                ),
            ],
          ),
      ];
      expect(
        computeWeeklyNumbers(days).highlights,
        isNot(contains('3 days above 60%')),
      );
    });
  });

  group('text helpers', () {
    test('feeling chips append with the spec separators', () {
      expect(appendFeelingWord('', 'Focused'), 'Focused');
      expect(appendFeelingWord('   ', 'Calm'), 'Calm');
      expect(appendFeelingWord('Focused', 'Calm'), 'Focused, calm');
      expect(appendFeelingWord('Week 2', 'Busy'), 'Week 2, busy');
      expect(appendFeelingWord('Long week.', 'Tired'), 'Long week. tired');
      expect(appendFeelingWord('Wow!', 'Proud'), 'Wow! proud');
      expect(appendFeelingWord('Hmm?', 'Calm'), 'Hmm? calm');
      expect(appendFeelingWord('Calm,', 'Busy'), 'Calm, busy');
      expect(appendFeelingWord('Calm ', 'Busy'), 'Calm busy');
      expect(appendFeelingWord('x' * 195, 'Calm'), isNull);
      expect(appendFeelingWord('x' * 192, 'Busy'), '${'x' * 192}, busy');
    });

    test('starters fill only an empty note', () {
      expect(applyNoteStarter('', 'Start with '), 'Start with ');
      expect(applyNoteStarter('  ', 'Say no to '), 'Say no to ');
      expect(applyNoteStarter('Already here', 'Keep doing '), isNull);
      expect(weeklyNoteStarters.map((s) => s.label), [
        'Start with…',
        'Protect time for…',
        'Say no to…',
        'Keep doing…',
      ]);
    });

    test('mood messages and range labels', () {
      expect(weeklyMoodMessage(1), 'Steady progress. Showing up counts.');
      expect(weeklyMoodMessage(2), 'Solid work this week.');
      expect(weeklyMoodMessage(3), 'A strong week. Well done.');
      expect(weeklyMoodMessage(4), 'Your best kind of week.');
      expect(
        weekRangeLabel(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
        'Sep 28–Oct 4',
      );
      expect(
        weekRangeLabel(DateTime(2026, 8, 10), DateTime(2026, 8, 16)),
        'Aug 10–16',
      );
    });

    test('last week hints', () {
      expect(lastWeekMoodHint(fixtureHistory()), 'Last week: Good');
      expect(lastWeekMoodHint(const []), isNull);
      expect(fromLastWeekNote(fixtureHistory()), isNull);
    });
  });
}
