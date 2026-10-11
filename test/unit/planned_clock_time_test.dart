import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/planned_clock_time.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

void main() {
  PlannerTimeZone.initialize(identifier: 'UTC');
  final tue = PlannerTimeZone.calendarDate(2026, 9, 15);
  final wed = PlannerTimeZone.calendarDate(2026, 9, 16);
  final thu = PlannerTimeZone.calendarDate(2026, 9, 17);

  PlannedSpan span(DateTime day, int startMin, int endMin) => (
    start: day.add(Duration(minutes: startMin)),
    end: day.add(Duration(minutes: endMin)),
  );

  // Tue 23:30 to Wed 00:30.
  final midnight = span(tue, 23 * 60 + 30, 24 * 60 + 30);

  group('interval union and clipping', () {
    test('a block crossing midnight is split 30 / 30 by day', () {
      expect(PlannedClockTime.unionMinutes([midnight], tue, wed), 30);
      expect(PlannedClockTime.unionMinutes([midnight], wed, thu), 30);
      expect(PlannedClockTime.spillInMinutes([midnight], wed), 30);
      expect(PlannedClockTime.spillInMinutes([midnight], tue), 0);
    });

    test('two overlapping blocks count the shared 30 minutes once', () {
      final blocks = [
        span(wed, 9 * 60, 10 * 60),
        span(wed, 9 * 60 + 30, 10 * 60 + 30),
      ];
      expect(PlannedClockTime.unionMinutes(blocks, wed, thu), 90);
      expect(PlannedClockTime.clippedSumMinutes(blocks, wed, thu), 120);
      expect(PlannedClockTime.overlapMinutes(blocks, wed, thu), 30);
    });

    test('the seeded Wednesday is 180 clock minutes with 30m overlap', () {
      final blocks = [
        midnight,
        span(wed, 9 * 60, 10 * 60),
        span(wed, 9 * 60 + 30, 10 * 60 + 30),
        span(wed, 14 * 60, 15 * 60),
      ];
      expect(PlannedClockTime.unionMinutes(blocks, wed, thu), 180);
      expect(PlannedClockTime.overlapMinutes(blocks, wed, thu), 30);
      expect(PlannedClockTime.spillInMinutes(blocks, wed), 30);
      // Completed: P1, P3 and the M1 spill-over.
      final completed = [
        midnight,
        span(wed, 9 * 60, 10 * 60),
        span(wed, 14 * 60, 15 * 60),
      ];
      expect(PlannedClockTime.unionMinutes(completed, wed, thu), 150);
    });

    test('a block inside another, touching blocks and empty input', () {
      expect(
        PlannedClockTime.unionMinutes(
          [span(wed, 60, 240), span(wed, 120, 180)],
          wed,
          thu,
        ),
        180,
      );
      expect(
        PlannedClockTime.unionMinutes(
          [span(wed, 60, 120), span(wed, 120, 180)],
          wed,
          thu,
        ),
        120,
      );
      expect(PlannedClockTime.unionMinutes(const [], wed, thu), 0);
    });

    test('a range of several days equals the sum of the day unions', () {
      final blocks = [midnight, span(tue, 9 * 60, 10 * 60)];
      expect(PlannedClockTime.unionMinutes(blocks, tue, thu), 120);
    });
  });

  group('counting a block on its start day', () {
    test('a midnight block counts on the day it starts only', () {
      expect(PlannedClockTime.startsOnDay(midnight.start, tue), isTrue);
      expect(PlannedClockTime.startsOnDay(midnight.start, wed), isFalse);
    });

    test('a block starting exactly at midnight belongs to that day', () {
      expect(PlannedClockTime.startsOnDay(wed, wed), isTrue);
      expect(PlannedClockTime.startsOnDay(wed, tue), isFalse);
      expect(PlannedClockTime.startsOnDay(null, wed), isFalse);
    });
  });
}
