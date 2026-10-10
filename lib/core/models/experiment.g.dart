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

_ExperimentTargetChange _$ExperimentTargetChangeFromJson(
  Map<String, dynamic> json,
) => _ExperimentTargetChange(
  effectiveWeekStart: json['effective_week_start'] as String,
  weekdayTargetMin: (json['weekday_target_min'] as num).toInt(),
  weekendTargetMin: (json['weekend_target_min'] as num).toInt(),
  madeOn: json['made_on'] as String,
);

Map<String, dynamic> _$ExperimentTargetChangeToJson(
  _ExperimentTargetChange instance,
) => <String, dynamic>{
  'effective_week_start': instance.effectiveWeekStart,
  'weekday_target_min': instance.weekdayTargetMin,
  'weekend_target_min': instance.weekendTargetMin,
  'made_on': instance.madeOn,
};
