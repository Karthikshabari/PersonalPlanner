import 'package:flutter/foundation.dart';

import '../../../core/models/daily_review.dart';
import 'review_mood.dart';

enum ReviewSaveStatus { idle, saving, saved, failed }

/// Unsaved edits of the Daily review form for one date.
@immutable
class ReviewDraft {
  const ReviewDraft({
    required this.date,
    this.hydrated = false,
    this.hydrationVersion = 0,
    this.mood = reviewDefaultMood,
    this.note = '',
    this.reasons = const <String, String>{},
    this.dirty = false,
    this.editVersion = 0,
    this.saveStatus = ReviewSaveStatus.idle,
  });

  final DateTime date;
  final bool hydrated;

  /// Bumped whenever stored values replace the draft, so text fields know to
  /// reload their controllers.
  final int hydrationVersion;
  final int mood;
  final String note;
  final Map<String, String> reasons;
  final bool dirty;
  final int editVersion;
  final ReviewSaveStatus saveStatus;

  ReviewDraft copyWith({
    bool? hydrated,
    int? hydrationVersion,
    int? mood,
    String? note,
    Map<String, String>? reasons,
    bool? dirty,
    int? editVersion,
    ReviewSaveStatus? saveStatus,
  }) => ReviewDraft(
    date: date,
    hydrated: hydrated ?? this.hydrated,
    hydrationVersion: hydrationVersion ?? this.hydrationVersion,
    mood: mood ?? this.mood,
    note: note ?? this.note,
    reasons: reasons ?? this.reasons,
    dirty: dirty ?? this.dirty,
    editVersion: editVersion ?? this.editVersion,
    saveStatus: saveStatus ?? this.saveStatus,
  );

  /// Replaces the values with the saved review (defaults when none: mood Good).
  ReviewDraft hydrateFrom(DailyReview? review) {
    final nextMood = review?.mood ?? reviewDefaultMood;
    final nextNote = review?.reflection ?? '';
    final nextReasons = review?.taskReasons ?? const <String, String>{};
    final changed =
        !hydrated ||
        nextMood != mood ||
        nextNote != note ||
        !mapEquals(nextReasons, reasons);
    return copyWith(
      hydrated: true,
      mood: nextMood,
      note: nextNote,
      reasons: nextReasons,
      dirty: false,
      hydrationVersion: changed ? hydrationVersion + 1 : hydrationVersion,
    );
  }
}
