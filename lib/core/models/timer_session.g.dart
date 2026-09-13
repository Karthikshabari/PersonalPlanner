// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timer_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TimerWorkInterval _$TimerWorkIntervalFromJson(Map<String, dynamic> json) =>
    _TimerWorkInterval(
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: DateTime.parse(json['end_at'] as String),
      durationSec: (json['duration_sec'] as num).toInt(),
    );

Map<String, dynamic> _$TimerWorkIntervalToJson(_TimerWorkInterval instance) =>
    <String, dynamic>{
      'start_at': instance.startAt.toIso8601String(),
      'end_at': instance.endAt.toIso8601String(),
      'duration_sec': instance.durationSec,
    };

_TimerSession _$TimerSessionFromJson(Map<String, dynamic> json) =>
    _TimerSession(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      state:
          $enumDecodeNullable(_$TimerSessionStateEnumMap, json['state']) ??
          TimerSessionState.finished,
      runningSince: json['runningSince'] == null
          ? null
          : DateTime.parse(json['runningSince'] as String),
      workIntervals:
          (json['workIntervals'] as List<dynamic>?)
              ?.map(
                (e) => TimerWorkInterval.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <TimerWorkInterval>[],
      ownerDeviceId: json['ownerDeviceId'] as String?,
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
      'state': _$TimerSessionStateEnumMap[instance.state]!,
      'runningSince': instance.runningSince?.toIso8601String(),
      'workIntervals': instance.workIntervals,
      'ownerDeviceId': instance.ownerDeviceId,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };

const _$TimerSessionStateEnumMap = {
  TimerSessionState.running: 'running',
  TimerSessionState.paused: 'paused',
  TimerSessionState.finished: 'finished',
};
