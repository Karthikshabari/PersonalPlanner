import 'package:freezed_annotation/freezed_annotation.dart';

part 'daily_review.freezed.dart';
part 'daily_review.g.dart';

/// End-of-day reflection (planner.md Chunk 5 #2). [date] is the local
/// calendar day (midnight); persisted as `yyyy-MM-dd` text.
@freezed
abstract class DailyReview with _$DailyReview {
  const factory DailyReview({
    required String id,
    required DateTime date,
    String? reflection,
    int? energyLevel,
    int? productivityRating,
    int? planningAccuracyRating,
    @Default([]) List<String> wins,
    @Default([]) List<String> improvements,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _DailyReview;

  factory DailyReview.fromJson(Map<String, dynamic> json) =>
      _$DailyReviewFromJson(json);
}
