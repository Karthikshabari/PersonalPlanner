// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_title_change.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PlanTitleChange _$PlanTitleChangeFromJson(Map<String, dynamic> json) =>
    _PlanTitleChange(
      id: json['id'] as String,
      previousTitle: json['previous_title'] as String,
      newTitle: json['new_title'] as String,
      changedAt: DateTime.parse(json['changed_at'] as String),
      revertedAt: json['reverted_at'] == null
          ? null
          : DateTime.parse(json['reverted_at'] as String),
    );

Map<String, dynamic> _$PlanTitleChangeToJson(_PlanTitleChange instance) =>
    <String, dynamic>{
      'id': instance.id,
      'previous_title': instance.previousTitle,
      'new_title': instance.newTitle,
      'changed_at': instance.changedAt.toIso8601String(),
      'reverted_at': instance.revertedAt?.toIso8601String(),
    };
