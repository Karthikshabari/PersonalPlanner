// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timer_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TimerSession _$TimerSessionFromJson(Map<String, dynamic> json) =>
    _TimerSession(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );

Map<String, dynamic> _$TimerSessionToJson(_TimerSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'taskId': instance.taskId,
      'startedAt': instance.startedAt.toIso8601String(),
      'endedAt': instance.endedAt?.toIso8601String(),
      'durationSec': instance.durationSec,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };
