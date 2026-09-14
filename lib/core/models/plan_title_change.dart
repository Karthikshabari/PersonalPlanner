// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_title_change.freezed.dart';
part 'plan_title_change.g.dart';

/// An intentional change to the name of an already-persisted plan.
///
/// The event body is immutable once written.  Only [revertedAt] changes when
/// recurrence Undo/Redo reverses and reapplies the command that introduced
/// it. Database and sync representations use snake_case to remain portable.
@freezed
abstract class PlanTitleChange with _$PlanTitleChange {
  const factory PlanTitleChange({
    required String id,
    @JsonKey(name: 'previous_title') required String previousTitle,
    @JsonKey(name: 'new_title') required String newTitle,
    @JsonKey(name: 'changed_at') required DateTime changedAt,
    @JsonKey(name: 'reverted_at') DateTime? revertedAt,
  }) = _PlanTitleChange;

  factory PlanTitleChange.fromJson(Map<String, dynamic> json) =>
      _$PlanTitleChangeFromJson(json);
}
