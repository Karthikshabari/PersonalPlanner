import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/screens/week_view_screen.dart';

void main() {
  test('an ordinary week shows the year once, at the end', () {
    expect(
      weekRangeLabel(PlannerTimeZone.calendarDate(2026, 10, 26)),
      'Oct 26 – Nov 1, 2026',
    );
  });

  test('a week across a year boundary shows both years', () {
    expect(
      weekRangeLabel(PlannerTimeZone.calendarDate(2026, 12, 28)),
      'Dec 28, 2026 – Jan 3, 2027',
    );
  });
}
