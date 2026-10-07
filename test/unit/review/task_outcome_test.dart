import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/utils/duration_utils.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';

TaskOutcomeRow _row(String id, String title, DateTime? start) => TaskOutcomeRow(
  taskId: id,
  title: title,
  startTime: start,
  plannedMinutes: 0,
  trackedMinutes: 0,
  outcome: TaskOutcome.notStarted,
);

void main() {
  test('resolveTaskOutcome follows the precedence table', () {
    final cases = <(TaskStatus, int, TaskOutcome)>[
      (TaskStatus.completed, 0, TaskOutcome.completed),
      (TaskStatus.completed, 30, TaskOutcome.completed),
      (TaskStatus.completed, -5, TaskOutcome.completed),
      (TaskStatus.inProgress, 15, TaskOutcome.partlyDone),
      (TaskStatus.planned, 45, TaskOutcome.partlyDone),
      (TaskStatus.skipped, 20, TaskOutcome.partlyDone),
      (TaskStatus.cancelled, 5, TaskOutcome.partlyDone),
      (TaskStatus.rescheduled, 10, TaskOutcome.partlyDone),
      (TaskStatus.skipped, 0, TaskOutcome.skipped),
      (TaskStatus.cancelled, 0, TaskOutcome.skipped),
      (TaskStatus.rescheduled, 0, TaskOutcome.rescheduled),
      (TaskStatus.planned, 0, TaskOutcome.notStarted),
      (TaskStatus.inProgress, 0, TaskOutcome.notStarted),
      (TaskStatus.planned, clampTrackedMinutes(-5), TaskOutcome.notStarted),
    ];
    for (final (status, tracked, expected) in cases) {
      expect(
        resolveTaskOutcome(status, trackedMinutes: tracked),
        expected,
        reason: '$status / $tracked',
      );
    }
  });

  test('labels are exact', () {
    expect(TaskOutcome.completed.label, 'Completed');
    expect(TaskOutcome.partlyDone.label, 'Partly done');
    expect(TaskOutcome.notStarted.label, 'Not started');
    expect(TaskOutcome.skipped.label, 'Skipped');
    expect(TaskOutcome.rescheduled.label, 'Rescheduled');
  });

  test('completionPercent', () {
    expect(completionPercent(1, 5), 20);
    expect(completionPercent(2, 3), 67);
    expect(completionPercent(0, 4), 0);
    expect(completionPercent(1, 8), 13);
    expect(completionPercent(0, 0), isNull);
  });

  test('duration labels', () {
    expect(const Duration(minutes: 45).shortLabel, '45m');
    expect(const Duration(minutes: 60).shortLabel, '1h');
    expect(const Duration(minutes: 90).shortLabel, '1h 30m');
  });

  test('compareTaskOutcomeRows orders by start, then case-insensitive title', () {
    final t = DateTime(2026, 10, 6, 9);
    final rows = [
      _row('4', 'zeta', null),
      _row('3', 'beta', t),
      _row('2', 'Alpha', t),
      _row('1', 'late', t.add(const Duration(hours: 1))),
    ]..sort(compareTaskOutcomeRows);
    expect(rows.map((r) => r.taskId), ['2', '3', '1', '4']);
  });
}
