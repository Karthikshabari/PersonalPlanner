// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskTemplate _$TaskTemplateFromJson(Map<String, dynamic> json) =>
    _TaskTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      durationMin: (json['durationMin'] as num).toInt(),
      categoryId: json['categoryId'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );

Map<String, dynamic> _$TaskTemplateToJson(_TaskTemplate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'durationMin': instance.durationMin,
      'categoryId': instance.categoryId,
      'priority': instance.priority,
      'tags': instance.tags,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };
