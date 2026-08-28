import 'package:freezed_annotation/freezed_annotation.dart';

part 'weekly_review.freezed.dart';
part 'weekly_review.g.dart';

/// End-of-week reflection for the Mon–Sun week starting at [weekStartDate]
/// (planner.md Chunk 5 #3); persisted as `yyyy-MM-dd` text of that Monday.
@freezed
abstract class WeeklyReview with _$WeeklyReview {
  const factory WeeklyReview({
    required String id,
    required DateTime weekStartDate,
    String? reflection,
    int? overallRating,
    @Default([]) List<String> goalsMet,
    @Default([]) List<String> goalsMissed,
    @Default([]) List<String> nextWeekFocus,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _WeeklyReview;

  factory WeeklyReview.fromJson(Map<String, dynamic> json) =>
      _$WeeklyReviewFromJson(json);
}
