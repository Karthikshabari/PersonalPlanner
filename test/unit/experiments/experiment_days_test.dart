import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/daos/experiment_dao.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/domain/experiment_days.dart';

import '../../helpers/experiment_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  tearDown(() => PlannerTimeZone.initialize(identifier: 'Asia/Kolkata'));

  group('buildExperimentDays', () {
    test('weekday and weekend targets, Monday to Sunday', () {
      final days = buildExperimentDays(testExperiment(), const {});
      expect(days.map((d) => d.date).first, '2026-10-05');
      expect(days.map((d) => d.date).last, '2026-10-11');
      expect(days.map((d) => d.targetMin), [60, 60, 60, 60, 60, 90, 90]);
      expect(days.map((d) => d.isWeekend), [
        false,
        false,
        false,
        false,
        false,
        true,
        true,
      ]);
    });

    test('Leave and Holiday days have target 0 and keep their flag', () {
      final days = buildExperimentDays(testExperiment(), const {
        '2026-10-06',
        '2026-10-10',
      });
      expect(days[1].targetMin, 0);
      expect(days[1].isLeaveOrHoliday, isTrue);
      expect(days[5].targetMin, 0);
      expect(days[0].isLeaveOrHoliday, isFalse);
    });

    test('a window of one day', () {
      final days = buildExperimentDays(
        testExperiment(start: '2026-10-05', end: '2026-10-05'),
        const {},
      );
      expect(days, hasLength(1));
    });

    test('a window across the America/New_York fall-back day', () {
      PlannerTimeZone.initialize(identifier: 'America/New_York');
      // Sunday 2026-11-01 has 25 hours.
      final days = buildExperimentDays(
        testExperiment(start: '2026-10-30', end: '2026-11-03'),
        const {},
      );
      expect(days.map((d) => d.date), [
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
        '2026-11-02',
        '2026-11-03',
      ]);
      expect(days[2].isWeekend, isTrue);
    });

    test('a window across the spring-forward day', () {
      PlannerTimeZone.initialize(identifier: 'America/New_York');
      // Sunday 2026-03-08 has 23 hours.
      final days = buildExperimentDays(
        testExperiment(start: '2026-03-06', end: '2026-03-10'),
        const {},
      );
      expect(days, hasLength(5));
      expect(calendarDaysBetween('2026-03-06', '2026-03-10'), 4);
    });
  });

  group('calendarDaysBetween', () {
    test('counts date parts, not elapsed hours', () {
      expect(calendarDaysBetween('2026-10-05', '2026-10-05'), 0);
      expect(calendarDaysBetween('2026-10-05', '2026-11-04'), 30);
      expect(calendarDaysBetween('2026-12-31', '2027-01-01'), 1);
    });
  });

  group('groupBlocksByDay', () {
    Map<String, DayMinutes> group(
      List<TaggedBlockRow> rows, {
      String start = '2026-10-05',
      String end = '2026-10-11',
    }) => groupBlocksByDay(rows, startDate: start, endDate: end);

    test('a block at 23:30 planner time lands on its planner date', () {
      PlannerTimeZone.initialize(identifier: 'America/New_York');
      // 23:30 in New York on Oct 6 is already Oct 7 in UTC.
      final rows = [testBlock('2026-10-06', hour: 23, minute: 30, actual: 20)];
      expect(rows.single.startTime.toUtc().day, 7);
      final result = group(rows);
      expect(result.keys, ['2026-10-06']);
      expect(result['2026-10-06']!.doneMin, 20);
    });

    test('a block that crosses midnight counts on its start date', () {
      final result = group([testBlock('2026-10-06', hour: 23, actual: 90)]);
      expect(result['2026-10-06']!.doneMin, 90);
      expect(result.containsKey('2026-10-07'), isFalse);
    });

    test('rows outside the window are ignored', () {
      final result = group([
        testBlock('2026-10-04', actual: 10),
        testBlock('2026-10-12', actual: 10),
        testBlock('2026-10-11', actual: 5),
      ]);
      expect(result.keys, ['2026-10-11']);
    });

    test('completed with Actual, without Actual and with explicit 0', () {
      final result = group([
        testBlock('2026-10-05', actual: 50, planned: 60),
        testBlock('2026-10-06', planned: 45),
        testBlock('2026-10-07', actual: 0, planned: 60),
        testBlock('2026-10-08', planned: null),
      ]);
      expect(result['2026-10-05']!.doneMin, 50);
      expect(result['2026-10-06']!.doneMin, 45);
      expect(result['2026-10-07']!.doneMin, 0);
      expect(result['2026-10-08']!.doneMin, 0);
    });

    test('planned and in-progress are still planned, others add nothing', () {
      final result = group([
        testBlock('2026-10-05', status: 'planned', planned: 30),
        testBlock('2026-10-05', status: 'in_progress', planned: 20),
        testBlock('2026-10-05', status: 'skipped', planned: 99),
        testBlock('2026-10-05', status: 'cancelled', planned: 99),
        testBlock('2026-10-05', status: 'rescheduled', planned: 99),
      ]);
      expect(result['2026-10-05']!.stillPlannedMin, 50);
      expect(result['2026-10-05']!.doneMin, 0);
    });

    test('sums several blocks on one day', () {
      final result = group([
        testBlock('2026-10-05', actual: 20),
        testBlock('2026-10-05', hour: 14, actual: 25),
      ]);
      expect(result['2026-10-05']!.doneMin, 45);
    });
  });
}
