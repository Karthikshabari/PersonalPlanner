import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/domain/experiment_check_in_schedule.dart';

List<String> slots(String start, String end, int every) => experimentSlotDates(
  startDate: start,
  endDate: end,
  checkInEveryDays: every,
);

ExperimentCheckInStatus status({
  String start = '2026-10-01',
  String end = '2026-10-30',
  int every = 7,
  List<String> written = const [],
  required String today,
}) => experimentCheckInStatus(
  startDate: start,
  endDate: end,
  checkInEveryDays: every,
  writtenSlotDates: written,
  today: today,
);

void main() {
  setUp(() => PlannerTimeZone.initialize(identifier: 'UTC'));
  tearDown(() => PlannerTimeZone.initialize(identifier: 'UTC'));

  group('slot dates', () {
    test('a daily experiment has a slot on the start day', () {
      expect(slots('2026-10-05', '2026-10-08', 1), [
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
        '2026-10-08',
      ]);
    });

    test('every 3 days: first slot on day 3', () {
      expect(slots('2026-10-01', '2026-10-10', 3), [
        '2026-10-03',
        '2026-10-06',
        '2026-10-09',
      ]);
    });

    test('weekly: the first slot is on day 7 of the window', () {
      expect(slots('2026-10-01', '2026-10-21', 7), [
        '2026-10-07',
        '2026-10-14',
        '2026-10-21',
      ]);
    });

    test('every 10 and every 15 days', () {
      expect(slots('2026-10-01', '2026-11-05', 10), [
        '2026-10-10',
        '2026-10-20',
        '2026-10-30',
      ]);
      expect(slots('2026-10-01', '2026-11-30', 15), [
        '2026-10-15',
        '2026-10-30',
        '2026-11-14',
        '2026-11-29',
      ]);
    });

    test('a slot dated on the end date is included, one after is not', () {
      expect(slots('2026-10-01', '2026-10-07', 7), ['2026-10-07']);
      expect(slots('2026-10-01', '2026-10-06', 7), isEmpty);
    });

    test('a window shorter than the frequency has no slot', () {
      expect(slots('2026-10-01', '2026-10-01', 3), isEmpty);
      expect(slots('2026-10-01', '2026-10-05', 15), isEmpty);
    });

    test('a later end date adds slots and keeps the earlier ones', () {
      final before = slots('2026-10-01', '2026-10-14', 7);
      final after = slots('2026-10-01', '2026-10-28', 7);
      expect(after.take(before.length), before);
      expect(after, ['2026-10-07', '2026-10-14', '2026-10-21', '2026-10-28']);
    });

    test('crosses month and year ends by calendar days', () {
      expect(slots('2026-12-29', '2027-01-02', 1), [
        '2026-12-29',
        '2026-12-30',
        '2026-12-31',
        '2027-01-01',
        '2027-01-02',
      ]);
    });

    test('calendar-day arithmetic across the fall-back day', () {
      // 2026-11-01 is 25 hours long in New York; adding 24-hour durations
      // would put the slot on 2026-10-31.
      PlannerTimeZone.initialize(identifier: 'America/New_York');
      expect(slots('2026-10-25', '2026-11-03', 1), [
        '2026-10-25',
        '2026-10-26',
        '2026-10-27',
        '2026-10-28',
        '2026-10-29',
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
        '2026-11-02',
        '2026-11-03',
      ]);
      expect(slots('2026-10-25', '2026-11-15', 7), [
        '2026-10-31',
        '2026-11-07',
        '2026-11-14',
      ]);
    });

    test('a frequency below 1 is refused', () {
      expect(() => slots('2026-10-01', '2026-10-05', 0), throwsArgumentError);
    });
  });

  group('status', () {
    test('nothing is pending before the first slot', () {
      final s = status(today: '2026-10-06');
      expect(s.pendingDates, isEmpty);
      expect(s.missedCount, 0);
      expect(s.dueToday, isFalse);
      expect(s.nextSlot, '2026-10-07');
    });

    test('due today when the slot date is today', () {
      final s = status(today: '2026-10-07');
      expect(s.pendingDates, ['2026-10-07']);
      expect(s.dueToday, isTrue);
      expect(s.missedCount, 0);
      expect(s.nextSlot, '2026-10-14');
    });

    test('a slot dated before today and not written is missed', () {
      final s = status(today: '2026-10-09');
      expect(s.pendingDates, ['2026-10-07']);
      expect(s.missedCount, 1);
      expect(s.dueToday, isFalse);
      expect(s.nextSlot, '2026-10-14');
    });

    test('a written slot is not pending', () {
      final s = status(today: '2026-10-09', written: ['2026-10-07']);
      expect(s.pendingDates, isEmpty);
      expect(s.missedCount, 0);
    });

    test('daily: missed days plus one due today, earliest first', () {
      final s = status(
        start: '2026-10-05',
        end: '2026-10-30',
        every: 1,
        today: '2026-10-08',
        written: ['2026-10-06'],
      );
      expect(s.pendingDates, ['2026-10-05', '2026-10-07', '2026-10-08']);
      expect(s.missedCount, 2);
      expect(s.dueToday, isTrue);
      expect(s.nextSlot, '2026-10-09');
    });

    test('no next slot once the last slot has passed', () {
      final s = status(today: '2026-10-29', end: '2026-10-21');
      expect(s.nextSlot, isNull);
      expect(s.pendingDates, ['2026-10-07', '2026-10-14', '2026-10-21']);
    });

    test('extending the end date creates new pending slots', () {
      final before = status(today: '2026-10-30', end: '2026-10-14');
      final after = status(today: '2026-10-30', end: '2026-10-28');
      expect(after.pendingDates.length, before.pendingDates.length + 2);
    });
  });
  group('statistic text', () {
    String stat({
      int written = 0,
      int missed = 0,
      bool running = true,
      String? next,
    }) => experimentCheckInStatistic(
      written: written,
      missed: missed,
      running: running,
      nextSlot: next,
    );

    test('nothing written and nothing owed', () {
      expect(stat(), '0 written');
    });

    test('written with missed slots hides the next date', () {
      expect(
        stat(written: 2, missed: 3, next: '2026-10-14'),
        '2 written · 3 missed',
      );
    });

    test('written with none missed shows the next date', () {
      expect(stat(written: 4, next: '2026-10-14'), '4 written · next Oct 14');
    });

    test('a concluded experiment with missed slots keeps counting them', () {
      expect(
        stat(written: 1, missed: 2, running: false),
        '1 written · 2 missed',
      );
    });

    test('a concluded experiment never shows a next date', () {
      expect(stat(written: 5, running: false, next: '2026-10-14'), '5 written');
    });

    test('running with no future slot shows only the written count', () {
      expect(stat(written: 3), '3 written');
    });
  });
}
