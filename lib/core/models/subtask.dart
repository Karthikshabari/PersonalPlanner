import 'package:freezed_annotation/freezed_annotation.dart';

part 'subtask.freezed.dart';
part 'subtask.g.dart';

@freezed
abstract class Subtask with _$Subtask {
  const factory Subtask({
    required String id,
    required String taskId,
    required String title,
    @Default(false) bool isCompleted,
    @Default(0) int sortOrder,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Subtask;

  factory Subtask.fromJson(Map<String, dynamic> json) =>
      _$SubtaskFromJson(json);
}
