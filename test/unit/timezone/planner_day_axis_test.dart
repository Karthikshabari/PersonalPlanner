import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/planner_day_axis.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

void main() {
  setUp(() => PlannerTimeZone.initialize(identifier: 'America/New_York'));

  test('spring-forward axis omits the missing wall-clock hour', () {
    final axis = PlannerDayAxis(PlannerTimeZone.calendarDate(2026, 3, 8));
    expect(axis.durationMinutes, 23 * 60);

    final start = PlannerTimeZone.calendarDate(2026, 3, 8, hour: 1, minute: 30);
    final end = PlannerTimeZone.calendarDate(2026, 3, 8, hour: 3, minute: 30);
    expect(axis.elapsedMinutes(end) - axis.elapsedMinutes(start), 60);
    expect(PlannerTimeZone.toPlannerLocal(axis.instantAt(120 * 1.0)).hour, 3);
  });

  test('fall-back axis gives repeated hour distinct positions', () {
    final axis = PlannerDayAxis(PlannerTimeZone.calendarDate(2026, 11, 1));
    expect(axis.durationMinutes, 25 * 60);
    final markers = axis.hourMarkers;
    expect(markers.length, 26);
    expect(markers[1].label, contains('01:00'));
    expect(markers[2].label, contains('01:00'));
    expect(markers[1].label, isNot(markers[2].label));
    expect(markers[1].elapsedMinutes, isNot(markers[2].elapsedMinutes));
  });

  test('elapsed axis preserves seconds within a scheduled minute', () {
    final date = PlannerTimeZone.calendarDate(2026, 7, 23);
    final axis = PlannerDayAxis(date);
    final start = PlannerTimeZone.calendarDate(
      2026,
      7,
      23,
      hour: 9,
      second: 30,
    );
    expect(axis.elapsedMinutes(start), closeTo(9 * 60 + 0.5, 0.0001));
    expect(
      axis.instantAt(axis.elapsedMinutes(start)).difference(start),
      Duration.zero,
    );
  });
}
