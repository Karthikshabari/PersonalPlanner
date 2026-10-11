import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

DateTime d(int day) => PlannerTimeZone.calendarDate(2026, 10, day);
String iso(DateTime d) => isoDateString(d);

void main() {
  tearDown(() => plannerWeekStartDay = WeekStartDay.monday);

  // 2026-10-11 is a Sunday.
  final sunday = d(11);
  final wednesday = d(14);

  test('Monday start is the default and matches the old behaviour', () {
    expect(iso(startOfWeek(sunday)), iso(d(5)));
    expect(iso(startOfWeek(wednesday)), iso(d(12)));
    expect(iso(weeklyReviewKey(sunday)), iso(d(5)));
    expect(dayOfPlannerWeek(sunday), 7);
  });

  test('Sunday start moves the week boundary', () {
    plannerWeekStartDay = WeekStartDay.sunday;
    expect(iso(startOfWeek(sunday)), iso(d(11)));
    expect(iso(startOfWeek(d(10))), iso(d(4)));
    expect(iso(startOfWeek(wednesday)), iso(d(11)));
    expect(dayOfPlannerWeek(sunday), 1);
    expect(dayOfPlannerWeek(d(10)), 7);
    expect(iso(startOfIsoWeek(sunday)), iso(d(5)));
  });

  test('a saved review keeps one Monday key for either start day', () {
    // Week Mon 12 Oct .. Sun 18 Oct is stored under Monday 12 Oct.
    final key = d(12);
    expect(iso(weeklyReviewKey(wednesday)), iso(key));
    plannerWeekStartDay = WeekStartDay.sunday;
    // Sun 11 .. Sat 17 contains that Monday and maps to the same key.
    for (var day = 11; day <= 17; day++) {
      expect(iso(weeklyReviewKey(d(day))), iso(key));
    }
    expect(iso(weeklyReviewKey(key)), iso(key));
    expect(
      iso(weeklyReviewKey(weeklyReviewKey(sunday))),
      iso(weeklyReviewKey(sunday)),
    );
  });
}
