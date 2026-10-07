import 'dart:math' as math;

import '../../../core/models/enums/task_status.dart';
import 'review_plan_change.dart';

enum TaskOutcome { completed, partlyDone, skipped, rescheduled, notStarted }

extension TaskOutcomeLabel on TaskOutcome {
  String get label => switch (this) {
    TaskOutcome.completed => 'Completed',
    TaskOutcome.partlyDone => 'Partly done',
    TaskOutcome.notStarted => 'Not started',
    TaskOutcome.skipped => 'Skipped',
    TaskOutcome.rescheduled => 'Rescheduled',
  };
}

/// Outcome of one task for its review day. First match wins:
/// 1 completed, 2 tracked > 0, 3 skipped/cancelled, 4 rescheduled,
/// 5 everything else.
TaskOutcome resolveTaskOutcome(TaskStatus status, {required int trackedMinutes}) {
  if (status == TaskStatus.completed) return TaskOutcome.completed;
  if (trackedMinutes > 0) return TaskOutcome.partlyDone;
  if (status == TaskStatus.skipped || status == TaskStatus.cancelled) {
    return TaskOutcome.skipped;
  }
  if (status == TaskStatus.rescheduled) return TaskOutcome.rescheduled;
  return TaskOutcome.notStarted;
}

/// round(completed / total × 100), or null when the day had no tasks.
int? completionPercent(int completed, int total) =>
    total <= 0 ? null : (completed * 100 / total).round();

class TaskOutcomeRow {
  final String taskId;
  final String title;
  final DateTime? startTime;
  final int plannedMinutes;
  final int trackedMinutes;
  final TaskOutcome outcome;
  final ReviewPlanChange? planChange;

  const TaskOutcomeRow({
    required this.taskId,
    required this.title,
    required this.startTime,
    required this.plannedMinutes,
    required this.trackedMinutes,
    required this.outcome,
    this.planChange,
  });
}

/// Scheduled start ascending, then title (case-insensitive), then ID.
int compareTaskOutcomeRows(TaskOutcomeRow a, TaskOutcomeRow b) {
  final aStart = a.startTime;
  final bStart = b.startTime;
  if (aStart != null && bStart != null) {
    final byStart = aStart.compareTo(bStart);
    if (byStart != 0) return byStart;
  } else if (aStart != bStart) {
    return aStart == null ? 1 : -1;
  }
  final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (byTitle != 0) return byTitle;
  final byRaw = a.title.compareTo(b.title);
  return byRaw != 0 ? byRaw : a.taskId.compareTo(b.taskId);
}

int clampTrackedMinutes(int? minutes) => math.max(0, minutes ?? 0);
