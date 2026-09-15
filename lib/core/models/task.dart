import 'package:freezed_annotation/freezed_annotation.dart';

import 'plan_title_change.dart';
import 'enums/priority.dart';
import 'enums/task_status.dart';
import '../utils/task_time_metrics.dart';

part 'task.freezed.dart';
part 'task.g.dart';

@freezed
abstract class Task with _$Task {
  const factory Task({
    required String id,
    required String title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    int? estimatedDurationMin,
    int? actualDurationMin,
    @Default(0) int manualDurationAdjustmentMin,

    /// Distinguishes an explicit manual zero from no manually recorded work.
    @Default(false) bool manualActualSet,
    String? categoryId,
    @Default(Priority.none) Priority priority,
    @Default(TaskStatus.planned) TaskStatus status,
    String? notes,
    String? recurringRuleId,
    String? recurrenceRemovalReason,
    String? rescheduledFromId,
    String? rescheduledToId,
    @Default(false) bool isInbox,
    @Default(0) int inboxContentVersion,
    String? dueDate,
    String? missedAt,
    @Default(<PlanTitleChange>[]) List<PlanTitleChange> planTitleHistory,
    String? displayPlanChangeId,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}

extension TaskX on Task {
  Duration? get scheduledDuration =>
      TaskTimeMetrics.scheduledDuration(startTime, endTime);

  int? get plannedDurationMinutes =>
      TaskTimeMetrics.plannedMinutes(startTime, endTime);

  /// The one deliberately selected plan-change event for compact timeline
  /// decoration. Invalid/stale pointers are rejected at every persistence
  /// boundary, but this remains defensive for in-memory legacy fixtures.
  PlanTitleChange? get displayPlanChange {
    final id = displayPlanChangeId;
    if (id == null) return null;
    for (final event in planTitleHistory) {
      if (event.id == id &&
          event.revertedAt == null &&
          event.newTitle.trim() == title.trim()) {
        return event;
      }
    }
    return null;
  }
}
