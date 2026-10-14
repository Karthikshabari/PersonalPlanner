import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/attention/overdue_age.dart';

void main() {
  // IST (+05:30): planner midnight is 18:30 UTC the day before.
  PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');

  DateTime ist(int month, int day, [int hour = 0, int minute = 0]) =>
      PlannerTimeZone.calendarDate(
        2026,
        month,
        day,
        hour: hour,
        minute: minute,
      );

  // Wednesday, October 14, 15:00 planner time.
  final now = ist(10, 14, 15);

  String age(DateTime instant) => formatOverdueAge(instant, now);

  group('formatOverdueAge', () {
    test('under a minute is "Just now"; a clock behind is too', () {
      expect(age(now), 'Just now');
      expect(age(now.subtract(const Duration(seconds: 59))), 'Just now');
      expect(age(now.add(const Duration(minutes: 5))), 'Just now');
    });

    test('under an hour counts minutes, whatever the day', () {
      expect(age(now.subtract(const Duration(minutes: 1))), '1 min ago');
      expect(
        age(now.subtract(const Duration(minutes: 59, seconds: 59))),
        '59 min ago',
      );
      // 23:50 yesterday to 00:10 today is still 20 minutes.
      expect(
        formatOverdueAge(ist(10, 13, 23, 50), ist(10, 14, 0, 10)),
        '20 min ago',
      );
    });

    test('an hour or more on the same planner day counts hours', () {
      expect(age(ist(10, 14, 14)), '1 hour ago');
      expect(age(ist(10, 14, 13, 59)), '1 hour ago');
      expect(age(ist(10, 14, 1)), '14 hours ago');
      expect(age(ist(10, 14, 0)), '15 hours ago');
    });

    test('the planner day decides, not UTC', () {
      // 00:30 planner time on Oct 14 is 19:00 UTC on Oct 13.
      final instant = DateTime.utc(2026, 10, 13, 19);
      expect(age(instant), '14 hours ago');
      // 23:30 planner time on Oct 13 is 18:00 UTC on Oct 13.
      expect(age(DateTime.utc(2026, 10, 13, 18)), 'Yesterday');
    });

    test('the previous planner day is "Yesterday", even under 24 hours', () {
      expect(age(ist(10, 13, 20)), 'Yesterday');
      expect(age(ist(10, 13, 23, 59)), 'Yesterday');
      expect(age(ist(10, 13)), 'Yesterday');
      // The day before yesterday, even though it is under 48 hours ago.
      expect(age(ist(10, 12, 23, 59)), '2 days ago');
    });

    test('2 to 13 days count days', () {
      expect(age(ist(10, 12, 15)), '2 days ago');
      expect(age(ist(10, 1, 9)), '13 days ago');
    });

    test('14 days up to 8 weeks count whole weeks', () {
      expect(age(ist(9, 30, 9)), '2 weeks ago');
      expect(age(ist(9, 17, 9)), '3 weeks ago'); // 27 days
      expect(age(ist(8, 20, 9)), '7 weeks ago'); // 55 days
    });

    test('8 weeks and older show the date', () {
      expect(age(ist(8, 19, 9)), 'Aug 19'); // 56 days
      expect(age(ist(1, 2, 9)), 'Jan 2');
    });
  });

  group('formatOverdueExact', () {
    Task task({String? missedAt, DateTime? start}) => Task(
      id: 't',
      title: 'Task',
      startTime: start,
      missedAt: missedAt,
      createdAt: now,
      updatedAt: now,
    );

    test('prefers missedAt (a UTC minute) shown in the planner zone', () {
      // 06:30 UTC is 12:00 IST.
      final text = formatOverdueExact(
        task(missedAt: '2026-10-13T06:30', start: ist(10, 12, 9)),
      );
      expect(text, 'Tue, Oct 13 · 12:00');
    });

    test('falls back to the start when missedAt is absent or malformed', () {
      expect(
        formatOverdueExact(task(start: ist(10, 12, 9, 5))),
        'Mon, Oct 12 · 09:05',
      );
      expect(
        formatOverdueExact(task(missedAt: 'garbage', start: ist(10, 12, 9, 5))),
        'Mon, Oct 12 · 09:05',
      );
    });

    test('is empty when the task has no time', () {
      expect(formatOverdueExact(task()), '');
    });
  });
}
