// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'experiment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ExperimentExtension _$ExperimentExtensionFromJson(Map<String, dynamic> json) =>
    _ExperimentExtension(
      reason: json['reason'] as String,
      previousEndDate: json['previous_end_date'] as String,
      newEndDate: json['new_end_date'] as String,
      madeOn: json['made_on'] as String,
    );

Map<String, dynamic> _$ExperimentExtensionToJson(
  _ExperimentExtension instance,
) => <String, dynamic>{
  'reason': instance.reason,
  'previous_end_date': instance.previousEndDate,
  'new_end_date': instance.newEndDate,
  'made_on': instance.madeOn,
};
