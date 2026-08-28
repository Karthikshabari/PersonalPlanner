// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_review.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DailyReview _$DailyReviewFromJson(Map<String, dynamic> json) => _DailyReview(
  id: json['id'] as String,
  date: DateTime.parse(json['date'] as String),
  reflection: json['reflection'] as String?,
  energyLevel: (json['energyLevel'] as num?)?.toInt(),
  productivityRating: (json['productivityRating'] as num?)?.toInt(),
  planningAccuracyRating: (json['planningAccuracyRating'] as num?)?.toInt(),
  wins:
      (json['wins'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  improvements:
      (json['improvements'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
);

Map<String, dynamic> _$DailyReviewToJson(_DailyReview instance) =>
    <String, dynamic>{
      'id': instance.id,
      'date': instance.date.toIso8601String(),
      'reflection': instance.reflection,
      'energyLevel': instance.energyLevel,
      'productivityRating': instance.productivityRating,
      'planningAccuracyRating': instance.planningAccuracyRating,
      'wins': instance.wins,
      'improvements': instance.improvements,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };
