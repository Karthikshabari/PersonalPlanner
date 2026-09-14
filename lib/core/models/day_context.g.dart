// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_context.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DayContext _$DayContextFromJson(Map<String, dynamic> json) => _DayContext(
  id: json['id'] as String,
  date: json['date'] as String,
  kind: $enumDecode(_$DayContextKindEnumMap, json['kind']),
  customLabel: json['customLabel'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
  revision: (json['revision'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _$DayContextToJson(_DayContext instance) =>
    <String, dynamic>{
      'id': instance.id,
      'date': instance.date,
      'kind': _$DayContextKindEnumMap[instance.kind]!,
      'customLabel': instance.customLabel,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
      'revision': instance.revision,
    };

const _$DayContextKindEnumMap = {
  DayContextKind.office: 'office',
  DayContextKind.holiday: 'holiday',
  DayContextKind.leave: 'leave',
  DayContextKind.travel: 'travel',
  DayContextKind.custom: 'custom',
};
