import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';
import 'package:personal_planner/features/day_context/domain/break_day.dart';
import 'package:personal_planner/features/day_context/domain/day_context_presets.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';

void main() {
  PlannerTimeZone.initialize(identifier: 'UTC');
  final monday = PlannerTimeZone.calendarDate(2026, 9, 21);

  group('streak', () {
    ConsistencyDay day(int offset, int completed, {String? breakLabel}) =>
        ConsistencyDay(
          date: addDays(monday, offset),
          plannedMinutes: 100,
          completedPlannedMinutes: completed,
          actualMinutes: 0,
          breakLabel: breakLabel,
          isFuture: false,
        );

    test('a break day neither adds nor resets', () {
      // Success, Break with nothing done (would be Missed), Success.
      final streaks = InsightsCalculator.calculateStreaks([
        day(0, 100),
        day(1, 0, breakLabel: 'Leave'),
        day(2, 100),
      ]);
      expect(streaks.current, 2);
      expect(streaks.best, 2);
    });

    test('a fully done break day does not add either', () {
      final streaks = InsightsCalculator.calculateStreaks([
        day(0, 100, breakLabel: 'Leave'),
        day(1, 100, breakLabel: 'Leave'),
      ]);
      expect(streaks.best, 0);
      expect(
        classifyDay(day(0, 100, breakLabel: 'Leave'), target: 0.6),
        DayResult.breakDay,
      );
    });
  });

  group('weekly numbers', () {
    WeeklyTaskInput task(String id, TaskOutcome outcome, {String? reason}) =>
        WeeklyTaskInput(
          taskId: id,
          title: id,
          outcome: outcome,
          endTime: DateTime.utc(2026, 9, 21, 10),
          reason: reason,
        );

    List<WeeklyDayInput> week({String? wednesdayBreak}) => [
      for (var i = 0; i < 7; i++)
        WeeklyDayInput(
          date: addDays(monday, i),
          reviewed: false,
          breakLabel: i == 2 ? wednesdayBreak : null,
          tasks: switch (i) {
            0 => [task('mon', TaskOutcome.completed)],
            1 => [
              task('tue-1', TaskOutcome.completed),
              task('tue-2', TaskOutcome.notStarted, reason: 'Low energy'),
            ],
            2 => [
              task('wed-1', TaskOutcome.skipped, reason: 'Blocked'),
              task('wed-2', TaskOutcome.notStarted),
            ],
            _ => const [],
          },
        ),
    ];
    final now = DateTime.utc(2026, 9, 28);

    test('an ordinary Wednesday counts everywhere', () {
      final numbers = computeWeeklyNumbers(week(), now: now);
      expect(numbers.total, 5);
      expect(numbers.completed, 2);
      expect(numbers.percent, 40);
      expect(numbers.skipped, 1);
      expect(numbers.noReasonCount, 1);
      expect(numbers.reasonCounts.map((r) => r.reason), [
        'Low energy',
        'Blocked',
      ]);
    });

    test('a break Wednesday counts in nothing', () {
      final numbers = computeWeeklyNumbers(
        week(wednesdayBreak: 'Leave'),
        now: now,
      );
      expect(numbers.total, 3);
      expect(numbers.completed, 2);
      expect(numbers.percent, 67);
      expect(numbers.skipped, 0);
      expect(numbers.noReasonCount, 0);
      expect(numbers.reasonCounts.map((r) => r.reason), ['Low energy']);
      expect(numbers.outcomeRows, isEmpty);
      final wednesday = numbers.days[2];
      expect(wednesday.isBreak, isTrue);
      expect(wednesday.percent, isNull);
      // The counted days add up to the week.
      final counted = numbers.days.where((d) => !d.isBreak);
      expect(counted.fold<int>(0, (s, d) => s + d.total), numbers.total);
      expect(
        counted.fold<int>(0, (s, d) => s + d.completed),
        numbers.completed,
      );
      expect(numbers.allBreak, isFalse);
    });

    test('a week of break days is a break week', () {
      final numbers = computeWeeklyNumbers([
        for (var i = 0; i < 7; i++)
          WeeklyDayInput(
            date: addDays(monday, i),
            reviewed: false,
            breakLabel: 'Leave',
            tasks: [task('t$i', TaskOutcome.notStarted)],
          ),
      ], now: now);
      expect(numbers.allBreak, isTrue);
      expect(numbers.total, 0);
      expect(numbers.percent, isNull);
    });
  });

  test('Insights week totals leave out the break day, even worked', () {
    Task block(String id, int dayOffset, TaskStatus status) {
      final start = addDays(monday, dayOffset).add(const Duration(hours: 9));
      return Task(
        id: id,
        title: id,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        status: status,
        createdAt: monday,
        updatedAt: monday,
      );
    }

    final tasks = [
      block('mon', 0, TaskStatus.completed),
      block('tue', 1, TaskStatus.planned),
      block('wed', 2, TaskStatus.completed),
    ];
    final leave = DayContext(
      id: 'leave',
      date: isoDateString(addDays(monday, 2)),
      kind: DayContextKind.leave,
      createdAt: monday,
      updatedAt: monday,
    );
    InsightsSnapshot calculate(BreakDayRule rule) =>
        InsightsCalculator.calculate(
          source: InsightsSourceData(
            plannedTasks: tasks,
            actualTasks: tasks,
            actualSlices: [
              for (final (i, t) in tasks.indexed)
                ActualTimeSlice(
                  taskId: t.id,
                  date: addDays(monday, i),
                  minutes: 60,
                ),
            ],
            categories: const [],
            dayContexts: [leave],
          ),
          now: addDays(monday, 6).add(const Duration(hours: 20)),
          selectedWeekStart: monday,
          consistencyStart: monday,
          breakDays: rule,
        );

    final withBreak = calculate(BreakDayRule(defaultDayContextPresets));
    expect(withBreak.plannedMinutes, 120);
    expect(withBreak.completedPlannedMinutes, 60);
    expect(withBreak.actualMinutes, 120);
    expect(withBreak.consistencyDays[2].breakLabel, 'Leave');
    expect(withBreak.consistencyDays[2].followThrough, isNull);

    final leaveOff = calculate(
      BreakDayRule([
        for (final p in defaultDayContextPresets)
          p.name == 'Leave' ? p.copyWith(isBreak: false) : p,
      ]),
    );
    expect(leaveOff.plannedMinutes, 180);
    expect(leaveOff.completedPlannedMinutes, 120);
    expect(leaveOff.actualMinutes, 180);
    expect(leaveOff.consistencyDays[2].breakLabel, isNull);
  });
}
