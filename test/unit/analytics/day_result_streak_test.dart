import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';
import 'package:personal_planner/features/analytics/domain/follow_through_target.dart';

void main() {
  PlannerTimeZone.initialize(identifier: 'UTC');
  final monday = PlannerTimeZone.calendarDate(2026, 9, 7);

  ConsistencyDay day(
    int offset,
    int completed, {
    int planned = 100,
    bool today = false,
    bool future = false,
    String? breakLabel,
  }) => ConsistencyDay(
    date: monday.add(Duration(days: offset)),
    plannedMinutes: planned,
    completedPlannedMinutes: completed,
    actualMinutes: 0,
    breakLabel: breakLabel,
    isFuture: future,
    isToday: today,
  );

  group('classifyDay', () {
    const target = defaultFollowThroughTarget;

    test('the four results of a finished day', () {
      expect(classifyDay(day(0, 60), target: target), DayResult.success);
      expect(classifyDay(day(0, 27), target: target), DayResult.started);
      expect(classifyDay(day(0, 0), target: target), DayResult.missed);
      expect(
        classifyDay(day(0, 0, planned: 0), target: target),
        DayResult.empty,
      );
      expect(
        classifyDay(day(0, 0, breakLabel: 'Leave'), target: target),
        DayResult.breakDay,
      );
    });

    test('today is undecided until it is a Success', () {
      expect(
        classifyDay(day(0, 80, today: true), target: target),
        DayResult.success,
      );
      expect(classifyDay(day(0, 30, today: true), target: target), isNull);
      expect(classifyDay(day(0, 0, today: true), target: target), isNull);
      expect(classifyDay(day(0, 0, future: true), target: target), isNull);
    });

    test('the shown whole percent decides the result', () {
      // 280 of 470 is 59.57%, shown as 60%: a Success at a 60% target.
      final shown60 = day(0, 280, planned: 470);
      expect(shown60.followThroughPercent, 60);
      expect(classifyDay(shown60, target: 0.6), DayResult.success);
      // 297 of 500 is 59.4%, shown as 59%: Started, since something was done.
      final shown59 = day(0, 297, planned: 500);
      expect(shown59.followThroughPercent, 59);
      expect(classifyDay(shown59, target: 0.6), DayResult.started);
      // Exactly half a point rounds up: 119 of 200 is 59.5%, shown as 60%.
      final half = day(0, 119, planned: 200);
      expect(half.followThroughPercent, 60);
      expect(classifyDay(half, target: 0.6), DayResult.success);
    });

    test('the default target is 60%', () {
      expect(defaultFollowThroughTarget, 0.6);
      expect(decodeFollowThroughTarget(null), 0.6);
      expect(decodeFollowThroughTarget('70'), 0.7);
      expect(decodeFollowThroughTarget('65'), 0.6);
      expect(encodeFollowThroughTarget(0.8), '80');
    });
  });

  group('calculateStreaks', () {
    test('Started keeps the streak: Success, Started, Success is 2', () {
      final streaks = InsightsCalculator.calculateStreaks([
        day(0, 100),
        day(1, 27),
        day(2, 83),
      ]);
      expect(streaks.current, 2);
      expect(streaks.best, 2);
    });

    test('Missed resets and Empty neither adds nor resets', () {
      final streaks = InsightsCalculator.calculateStreaks([
        day(0, 100),
        day(1, 100),
        day(2, 0),
        day(3, 0, planned: 0),
        day(4, 90),
      ]);
      expect(streaks.current, 1);
      expect(streaks.best, 2);
    });

    test('today is ignored unless it is already a Success', () {
      final pending = InsightsCalculator.calculateStreaks([
        day(0, 100),
        day(1, 100),
        day(2, 0, today: true),
      ]);
      expect(pending.current, 2);

      final success = InsightsCalculator.calculateStreaks([
        day(0, 100),
        day(1, 100),
        day(2, 70, today: true),
      ]);
      expect(success.current, 3);
      expect(success.best, 3);
    });

    test('a changed target changes which days are a Success', () {
      final days = [day(0, 55), day(1, 55), day(2, 0)];
      expect(InsightsCalculator.calculateStreaks(days, target: 0.5).best, 2);
      // At 60% the same days are Started: no streak, nothing to reset.
      expect(InsightsCalculator.calculateStreaks(days).best, 0);
      final strict = InsightsCalculator.calculateStreaks([
        day(0, 75),
        day(1, 75),
      ], target: 0.8);
      expect(strict.best, 0);
    });
  });
}
