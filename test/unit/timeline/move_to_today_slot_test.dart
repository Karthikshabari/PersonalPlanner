import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/attention/move_to_today_slot.dart';

void main() {
  PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');

  DateTime ist(
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => PlannerTimeZone.calendarDate(
    2026,
    month,
    day,
    hour: hour,
    minute: minute,
    second: second,
  );

  Task task(String id, DateTime? start, int minutes) => Task(
    id: id,
    title: id,
    startTime: start,
    endTime: start?.add(Duration(minutes: minutes)),
    createdAt: ist(10, 1),
    updatedAt: ist(10, 1),
  );

  /// A block on today's plan (Oct 14), from hh:mm for [minutes].
  Task block(int hour, int minute, int minutes) =>
      task('block-$hour$minute', ist(10, 14, hour, minute), minutes);

  // A task from yesterday, 14:00 for 60 minutes.
  final yesterday = task('y', ist(10, 13, 14), 60);

  group('moveToTodaySlot', () {
    test('keeps the clock time when it is still well ahead', () {
      final slot = moveToTodaySlot(yesterday, ist(10, 14, 10, 20), 30, []);
      expect(slot, (start: ist(10, 14, 14), end: ist(10, 14, 15)));
    });

    test('15 minutes ahead is enough, 14 is not', () {
      final now = ist(10, 14, 10, 20);
      final atBoundary = task('b', ist(10, 13, 10, 35), 30);
      expect(
        moveToTodaySlot(atBoundary, now, 30, [])?.start,
        ist(10, 14, 10, 35),
      );
      final tooSoon = task('s', ist(10, 13, 10, 34), 30);
      // Next grid slot at or after 10:20 on a 30-minute grid.
      expect(moveToTodaySlot(tooSoon, now, 30, [])?.start, ist(10, 14, 10, 30));
    });

    test(
      'seconds count: 10:20:30 rounds up to 10:21 before the 15 minutes',
      () {
        final now = ist(10, 14, 10, 20, 30);
        expect(
          moveToTodaySlot(
            task('a', ist(10, 13, 10, 36), 30),
            now,
            30,
            [],
          )?.start,
          ist(10, 14, 10, 36),
        );
        expect(
          moveToTodaySlot(
            task('b', ist(10, 13, 10, 35), 30),
            now,
            30,
            [],
          )?.start,
          ist(10, 14, 10, 30),
        );
      },
    );

    test('a past clock time goes to the next free grid slot after now', () {
      final morning = task('m', ist(10, 13, 8), 60);
      final slot = moveToTodaySlot(morning, ist(10, 14, 10, 20), 30, []);
      expect(slot, (start: ist(10, 14, 10, 30), end: ist(10, 14, 11, 30)));
      // On the grid already: that slot is allowed.
      final onGrid = moveToTodaySlot(morning, ist(10, 14, 10, 30), 30, []);
      expect(onGrid?.start, ist(10, 14, 10, 30));
      // A 60-minute grid rounds up to the hour.
      expect(
        moveToTodaySlot(morning, ist(10, 14, 10, 20), 60, [])?.start,
        ist(10, 14, 11),
      );
    });

    test('skips blocks and gaps that are too small', () {
      final morning = task('m', ist(10, 13, 8), 60);
      final slot = moveToTodaySlot(morning, ist(10, 14, 10, 20), 30, [
        block(10, 30, 30), // 10:30-11:00
        block(11, 30, 60), // 11:30-12:30; the 11:00-11:30 gap is too small
      ]);
      expect(slot?.start, ist(10, 14, 12, 30));
      expect(slot?.end, ist(10, 14, 13, 30));
    });

    test('the same clock time is not checked for overlaps (the dialog is)', () {
      final slot = moveToTodaySlot(yesterday, ist(10, 14, 10, 20), 30, [
        block(14, 0, 60),
      ]);
      expect(slot?.start, ist(10, 14, 14));
    });

    test(
      'a task that would run past midnight is not kept at its clock time',
      () {
        final late = task('l', ist(10, 13, 23), 120);
        final slot = moveToTodaySlot(late, ist(10, 14, 10, 20), 30, []);
        expect(slot?.start, ist(10, 14, 10, 30));
      },
    );

    test('end of day: fits until midnight, then nothing', () {
      final hour = task('h', ist(10, 13, 8), 60);
      final half = task('f', ist(10, 13, 8), 30);
      // 23:10 -> from 23:30: 30 minutes fit, 60 do not.
      expect(moveToTodaySlot(hour, ist(10, 14, 23, 10), 30, []), isNull);
      final fits = moveToTodaySlot(half, ist(10, 14, 23, 10), 30, []);
      expect(fits?.start, ist(10, 14, 23, 30));
      expect(fits?.end, ist(10, 15));
      // 23:59 -> the next grid slot is midnight, nothing fits today.
      expect(moveToTodaySlot(half, ist(10, 14, 23, 59), 30, []), isNull);
    });

    test('just after midnight uses the planner day, not the UTC day', () {
      // 00:05 on Oct 14 in the planner zone is 18:35 UTC on Oct 13.
      final now = ist(10, 14, 0, 5);
      expect(now.toUtc().day, 13);
      final slot = moveToTodaySlot(yesterday, now, 30, []);
      expect(slot?.start, ist(10, 14, 14));
      final early = moveToTodaySlot(
        task('e', ist(10, 13, 0, 10), 30),
        now,
        30,
        [],
      );
      expect(early?.start, ist(10, 14, 0, 30));
    });

    test('just before midnight only the last slot is left', () {
      // At 23:50 nothing fits today and nothing is placed on the next day;
      // 23:40 with a 15-minute task still fits in the last slot.
      expect(
        moveToTodaySlot(
          task('x', ist(10, 13, 8), 30),
          ist(10, 14, 23, 50),
          15,
          [],
        ),
        isNull,
      );
      expect(
        moveToTodaySlot(
          task('x', ist(10, 13, 8), 15),
          ist(10, 14, 23, 40),
          15,
          [],
        )?.start,
        ist(10, 14, 23, 45),
      );
    });

    test('a task without an interval is given 60 minutes', () {
      final slot = moveToTodaySlot(
        task('n', null, 0),
        ist(10, 14, 10, 20),
        30,
        [],
      );
      expect(slot, (start: ist(10, 14, 10, 30), end: ist(10, 14, 11, 30)));
    });

    test('a task longer than a day never fits', () {
      expect(
        moveToTodaySlot(
          task('d', ist(10, 12, 8), 25 * 60),
          ist(10, 14, 8),
          30,
          [],
        ),
        isNull,
      );
    });
  });

  group('placeAllToday', () {
    final now = ist(10, 14, 10, 20);

    test('places oldest first, one after another, keeping durations', () {
      final placed = placeAllToday(
        [
          task('t1', ist(10, 10, 9), 60),
          task('t2', ist(10, 11, 9), 30),
          task('t3', ist(10, 12, 9), 45),
        ],
        now,
        30,
        [block(11, 0, 60)],
      );
      expect([for (final p in placed) p.task.id], ['t1', 't2', 't3']);
      // t1 (60) cannot start 10:30 (11:00 is taken) so it goes after the block.
      expect(placed[0].slot, (start: ist(10, 14, 12), end: ist(10, 14, 13)));
      expect(placed[1].slot, (
        start: ist(10, 14, 13),
        end: ist(10, 14, 13, 30),
      ));
      // 45 minutes: the next start is the grid slot after 13:30.
      expect(placed[2].slot, (
        start: ist(10, 14, 13, 30),
        end: ist(10, 14, 14, 15),
      ));
    });

    test('later tasks use the gap before a block when it fits', () {
      final placed = placeAllToday(
        [task('a', ist(10, 10, 9), 30), task('b', ist(10, 11, 9), 30)],
        now,
        30,
        [block(11, 0, 60)],
      );
      expect(placed[0].slot.start, ist(10, 14, 10, 30));
      // 11:00 is taken: b goes after the block.
      expect(placed[1].slot.start, ist(10, 14, 12));
    });

    test('stops at the first task that does not fit and says how many did', () {
      final tasks = [
        for (var i = 0; i < 4; i++) task('t$i', ist(10, 10 + i, 9), 60),
      ];
      // 21:10 on a 60-minute grid: 22:00-23:00, 23:00-24:00, then no room.
      final placed = placeAllToday(tasks, ist(10, 14, 21, 10), 60, []);
      expect(placed.length, 2);
      expect(placed.last.slot.end, ist(10, 15));
    });

    test(
      'a long task that does not fit stops the batch before a short one',
      () {
        final placed = placeAllToday(
          [
            task('long', ist(10, 10, 9), 180),
            task('short', ist(10, 11, 9), 30),
          ],
          ist(10, 14, 21, 10),
          60,
          [],
        );
        expect(placed, isEmpty);
      },
    );

    test('an empty list places nothing', () {
      expect(placeAllToday(const [], now, 30, const []), isEmpty);
    });
  });
}
