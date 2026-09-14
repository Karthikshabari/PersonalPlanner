import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

void main() {
  setUp(() => PlannerTimeZone.initialize(identifier: 'America/New_York'));

  test('calendar-day arithmetic preserves local midnight across DST start', () {
    final before = parseIsoDate('2026-03-08');
    final after = addDays(before, 1);

    expect(isoDateString(before), '2026-03-08');
    expect(isoDateString(after), '2026-03-09');
    expect(startOfDay(after).hour, 0);
    expect(after.difference(before).inHours, 23);
  });

  test('calendar-day arithmetic preserves local midnight across DST end', () {
    final before = parseIsoDate('2026-11-01');
    final after = addDays(before, 1);

    expect(isoDateString(after), '2026-11-02');
    expect(startOfDay(after).hour, 0);
    expect(after.difference(before).inHours, 25);
  });
}
