import 'package:freezed_annotation/freezed_annotation.dart';
import 'enums/priority.dart';
import 'enums/task_status.dart';

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
    String? categoryId,
    @Default(Priority.none) Priority priority,
    @Default(TaskStatus.planned) TaskStatus status,
    String? notes,
    String? recurringRuleId,
    String? rescheduledFromId,
    String? rescheduledToId,
    @Default(false) bool isInbox,
    String? missedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}

extension TaskX on Task {
  Duration? get scheduledDuration =>
      startTime != null && endTime != null ? endTime!.difference(startTime!) : null;
}
