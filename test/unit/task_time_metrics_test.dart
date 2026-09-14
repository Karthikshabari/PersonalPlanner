import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/task_time_metrics.dart';

void main() {
  test('projects positive intervals from exact elapsed microseconds', () {
    final start = DateTime.utc(2026, 1, 1, 16, 0, 0, 500);
    final end = DateTime.utc(2026, 1, 1, 17, 30, 0, 400);

    expect(
      TaskTimeMetrics.scheduledDuration(start, end),
      const Duration(minutes: 89, seconds: 59, milliseconds: 900),
    );
    expect(TaskTimeMetrics.plannedMinutes(start, end), 89);
    expect(
      TaskTimeMetrics.plannedMinutes(
        DateTime.utc(2026, 1, 1, 16),
        DateTime.utc(2026, 1, 1, 16, 0, 1),
      ),
      1,
    );
  });

  test('supports multi-day and cross-midnight intervals without a 24h cap', () {
    expect(
      TaskTimeMetrics.plannedMinutes(
        DateTime.utc(2026, 1, 1, 23, 30),
        DateTime.utc(2026, 1, 2, 0, 30),
      ),
      60,
    );
    expect(
      TaskTimeMetrics.plannedMinutes(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3, 1),
      ),
      2940,
    );
  });

  test('returns null for incomplete or invalid schedules', () {
    expect(TaskTimeMetrics.plannedMinutes(null, DateTime.utc(2026)), isNull);
    expect(
      TaskTimeMetrics.plannedMinutes(
        DateTime.utc(2026, 1, 1, 10),
        DateTime.utc(2026, 1, 1, 9),
      ),
      isNull,
    );
  });

  test('coverage starts at the original task start', () {
    final segment = TaskTimeMetrics.coverageForSegment(
      taskStart: DateTime.utc(2026, 1, 1, 23, 30),
      taskEnd: DateTime.utc(2026, 1, 2, 0, 30),
      actualMinutes: 45,
      segmentStart: DateTime.utc(2026, 1, 2),
      segmentEnd: DateTime.utc(2026, 1, 2, 0, 30),
    );
    expect(segment.strong, const Duration(minutes: 15));
    expect(segment.light, const Duration(minutes: 15));
  });

  test('coverage projections match zero, complete and overtime work', () {
    final start = DateTime.utc(2026, 1, 1, 16);
    final end = DateTime.utc(2026, 1, 1, 17);
    ({Duration strong, Duration light}) coverage(int minutes) =>
        TaskTimeMetrics.coverageForSegment(
          taskStart: start,
          taskEnd: end,
          actualMinutes: minutes,
          segmentStart: start,
          segmentEnd: end,
        );

    expect(coverage(0), (
      strong: Duration.zero,
      light: const Duration(hours: 1),
    ));
    expect(coverage(45), (
      strong: const Duration(minutes: 45),
      light: const Duration(minutes: 15),
    ));
    expect(coverage(60), (
      strong: const Duration(hours: 1),
      light: Duration.zero,
    ));
    expect(coverage(75), (
      strong: const Duration(hours: 1),
      light: Duration.zero,
    ));
  });
}
