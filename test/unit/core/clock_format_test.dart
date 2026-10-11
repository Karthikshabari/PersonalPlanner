import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/clock_format.dart';

void main() {
  test('formatClock24 is zero-padded 24-hour HH:mm', () {
    expect(formatClock24(DateTime(2026, 10, 11, 0, 5)), '00:05');
    expect(formatClock24(DateTime(2026, 10, 11, 9, 0)), '09:00');
    expect(formatClock24(DateTime(2026, 10, 11, 13, 30)), '13:30');
    expect(formatClock24(DateTime(2026, 10, 11, 23, 59)), '23:59');
  });
}
