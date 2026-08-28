// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_review.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WeeklyReview _$WeeklyReviewFromJson(Map<String, dynamic> json) =>
    _WeeklyReview(
      id: json['id'] as String,
      weekStartDate: DateTime.parse(json['weekStartDate'] as String),
      reflection: json['reflection'] as String?,
      overallRating: (json['overallRating'] as num?)?.toInt(),
      goalsMet:
          (json['goalsMet'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      goalsMissed:
          (json['goalsMissed'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      nextWeekFocus:
          (json['nextWeekFocus'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );

Map<String, dynamic> _$WeeklyReviewToJson(_WeeklyReview instance) =>
    <String, dynamic>{
      'id': instance.id,
      'weekStartDate': instance.weekStartDate.toIso8601String(),
      'reflection': instance.reflection,
      'overallRating': instance.overallRating,
      'goalsMet': instance.goalsMet,
      'goalsMissed': instance.goalsMissed,
      'nextWeekFocus': instance.nextWeekFocus,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };
