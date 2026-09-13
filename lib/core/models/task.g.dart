// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Task _$TaskFromJson(Map<String, dynamic> json) => _Task(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  startTime: json['startTime'] == null
      ? null
      : DateTime.parse(json['startTime'] as String),
  endTime: json['endTime'] == null
      ? null
      : DateTime.parse(json['endTime'] as String),
  estimatedDurationMin: (json['estimatedDurationMin'] as num?)?.toInt(),
  actualDurationMin: (json['actualDurationMin'] as num?)?.toInt(),
  manualDurationAdjustmentMin:
      (json['manualDurationAdjustmentMin'] as num?)?.toInt() ?? 0,
  manualActualSet: json['manualActualSet'] as bool? ?? false,
  categoryId: json['categoryId'] as String?,
  priority:
      $enumDecodeNullable(_$PriorityEnumMap, json['priority']) ?? Priority.none,
  status:
      $enumDecodeNullable(_$TaskStatusEnumMap, json['status']) ??
      TaskStatus.planned,
  notes: json['notes'] as String?,
  recurringRuleId: json['recurringRuleId'] as String?,
  rescheduledFromId: json['rescheduledFromId'] as String?,
  rescheduledToId: json['rescheduledToId'] as String?,
  isInbox: json['isInbox'] as bool? ?? false,
  inboxContentVersion: (json['inboxContentVersion'] as num?)?.toInt() ?? 0,
  dueDate: json['dueDate'] as String?,
  missedAt: json['missedAt'] as String?,
  planTitleHistory:
      (json['planTitleHistory'] as List<dynamic>?)
          ?.map((e) => PlanTitleChange.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PlanTitleChange>[],
  displayPlanChangeId: json['displayPlanChangeId'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
);

Map<String, dynamic> _$TaskToJson(_Task instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'description': instance.description,
  'startTime': instance.startTime?.toIso8601String(),
  'endTime': instance.endTime?.toIso8601String(),
  'estimatedDurationMin': instance.estimatedDurationMin,
  'actualDurationMin': instance.actualDurationMin,
  'manualDurationAdjustmentMin': instance.manualDurationAdjustmentMin,
  'manualActualSet': instance.manualActualSet,
  'categoryId': instance.categoryId,
  'priority': _$PriorityEnumMap[instance.priority]!,
  'status': _$TaskStatusEnumMap[instance.status]!,
  'notes': instance.notes,
  'recurringRuleId': instance.recurringRuleId,
  'rescheduledFromId': instance.rescheduledFromId,
  'rescheduledToId': instance.rescheduledToId,
  'isInbox': instance.isInbox,
  'inboxContentVersion': instance.inboxContentVersion,
  'dueDate': instance.dueDate,
  'missedAt': instance.missedAt,
  'planTitleHistory': instance.planTitleHistory,
  'displayPlanChangeId': instance.displayPlanChangeId,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'deletedAt': instance.deletedAt?.toIso8601String(),
};

const _$PriorityEnumMap = {
  Priority.none: 'none',
  Priority.low: 'low',
  Priority.medium: 'medium',
  Priority.high: 'high',
  Priority.urgent: 'urgent',
};

const _$TaskStatusEnumMap = {
  TaskStatus.planned: 'planned',
  TaskStatus.inProgress: 'in_progress',
  TaskStatus.completed: 'completed',
  TaskStatus.skipped: 'skipped',
  TaskStatus.cancelled: 'cancelled',
  TaskStatus.rescheduled: 'rescheduled',
};
