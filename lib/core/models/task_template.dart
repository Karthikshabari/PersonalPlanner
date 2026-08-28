import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_template.freezed.dart';
part 'task_template.g.dart';

@freezed
abstract class TaskTemplate with _$TaskTemplate {
  const factory TaskTemplate({
    required String id,
    required String name,
    String? description,
    required int durationMin,
    String? categoryId,
    @Default(0) int priority,
    @Default([]) List<String> tags,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _TaskTemplate;

  factory TaskTemplate.fromJson(Map<String, dynamic> json) =>
      _$TaskTemplateFromJson(json);
}
