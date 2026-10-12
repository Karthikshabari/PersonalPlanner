// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_closure.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_InboxClosure _$InboxClosureFromJson(Map<String, dynamic> json) =>
    _InboxClosure(
      kind: $enumDecode(_$InboxCloseKindEnumMap, json['kind']),
      at: DateTime.parse(json['at'] as String),
      reason: json['reason'] as String?,
      experimentId: json['experiment_id'] as String?,
      reopenedAt: json['reopened_at'] == null
          ? null
          : DateTime.parse(json['reopened_at'] as String),
    );

Map<String, dynamic> _$InboxClosureToJson(_InboxClosure instance) =>
    <String, dynamic>{
      'kind': _$InboxCloseKindEnumMap[instance.kind]!,
      'at': instance.at.toIso8601String(),
      'reason': instance.reason,
      'experiment_id': instance.experimentId,
      'reopened_at': instance.reopenedAt?.toIso8601String(),
    };

const _$InboxCloseKindEnumMap = {
  InboxCloseKind.closed: 'closed',
  InboxCloseKind.letGo: 'let_go',
  InboxCloseKind.experiment: 'experiment',
};
