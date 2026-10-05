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

    /// Legacy (UAT F-010): no UI; kept so stored values round-trip.
    @Default(0) int priority,

    /// Legacy (UAT F-010) tag ids: no UI; kept so stored values round-trip.
    @Default([]) List<String> tags,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _TaskTemplate;

  factory TaskTemplate.fromJson(Map<String, dynamic> json) =>
      _$TaskTemplateFromJson(json);
}
