// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recurring_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RecurringRule _$RecurringRuleFromJson(Map<String, dynamic> json) =>
    _RecurringRule(
      id: json['id'] as String,
      rrule: json['rrule'] as String,
      taskTitle: json['taskTitle'] as String,
      taskDescription: json['taskDescription'] as String?,
      durationMin: (json['durationMin'] as num).toInt(),
      categoryId: json['categoryId'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      startTimeOfDay: json['startTimeOfDay'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      isActive: json['isActive'] as bool? ?? true,
      exceptions:
          (json['exceptions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );

Map<String, dynamic> _$RecurringRuleToJson(_RecurringRule instance) =>
    <String, dynamic>{
      'id': instance.id,
      'rrule': instance.rrule,
      'taskTitle': instance.taskTitle,
      'taskDescription': instance.taskDescription,
      'durationMin': instance.durationMin,
      'categoryId': instance.categoryId,
      'priority': instance.priority,
      'tags': instance.tags,
      'startTimeOfDay': instance.startTimeOfDay,
      'startDate': instance.startDate.toIso8601String(),
      'endDate': instance.endDate?.toIso8601String(),
      'isActive': instance.isActive,
      'exceptions': instance.exceptions,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };
