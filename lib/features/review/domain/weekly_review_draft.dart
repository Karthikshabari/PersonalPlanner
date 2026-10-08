import 'package:flutter/foundation.dart';

import '../../../core/models/weekly_review.dart';
import 'review_draft.dart';
import 'review_mood.dart';

/// Unsaved edits of the Weekly review form for one week. Same rules as the
/// Daily [ReviewDraft]: hydrate from the saved row, stay dirty only while
/// something differs from it, re-point the baseline on a remote change.
@immutable
class WeeklyReviewDraft {
  const WeeklyReviewDraft({
    required this.weekStart,
    this.hydrated = false,
    this.hydrationVersion = 0,
    this.mood = reviewDefaultMood,
    this.feeling = '',
    this.note = '',
    this.savedMood = reviewDefaultMood,
    this.savedFeeling = '',
    this.savedNote = '',
    this.dirty = false,
    this.editVersion = 0,
    this.saveStatus = ReviewSaveStatus.idle,
  });

  final DateTime weekStart;
  final bool hydrated;

  /// Bumped whenever stored values replace the draft, so text fields know to
  /// reload their controllers.
  final int hydrationVersion;
  final int mood;
  final String feeling;

  /// The note for next week (`weekly_reviews.reflection`).
  final String note;

  /// What is stored for the week (defaults when no review exists: Good, '',
  /// ''). A NULL stored mood also counts as Good (WD34).
  final int savedMood;
  final String savedFeeling;
  final String savedNote;
  final bool dirty;
  final int editVersion;
  final ReviewSaveStatus saveStatus;

  WeeklyReviewDraft copyWith({
    bool? hydrated,
    int? hydrationVersion,
    int? mood,
    String? feeling,
    String? note,
    int? savedMood,
    String? savedFeeling,
    String? savedNote,
    bool? dirty,
    int? editVersion,
    ReviewSaveStatus? saveStatus,
  }) => WeeklyReviewDraft(
    weekStart: weekStart,
    hydrated: hydrated ?? this.hydrated,
    hydrationVersion: hydrationVersion ?? this.hydrationVersion,
    mood: mood ?? this.mood,
    feeling: feeling ?? this.feeling,
    note: note ?? this.note,
    savedMood: savedMood ?? this.savedMood,
    savedFeeling: savedFeeling ?? this.savedFeeling,
    savedNote: savedNote ?? this.savedNote,
    dirty: dirty ?? this.dirty,
    editVersion: editVersion ?? this.editVersion,
    saveStatus: saveStatus ?? this.saveStatus,
  );

  /// True when mood, feeling or note differs from what is saved. Text
  /// compares trimmed, as the repository stores it.
  bool get differsFromSaved =>
      mood != savedMood ||
      feeling.trim() != savedFeeling ||
      note.trim() != savedNote;

  /// Re-points the saved baseline (remote change) keeping the edits.
  WeeklyReviewDraft rebase(WeeklyReview? review) {
    final base = copyWith(
      savedMood: review?.mood ?? reviewDefaultMood,
      savedFeeling: review?.feeling ?? '',
      savedNote: review?.reflection ?? '',
    );
    return base.copyWith(dirty: base.differsFromSaved);
  }

  /// Records a successful write. With [adoptSaved] the visible values become
  /// the stored ones (trimmed); text fields reload only if that changed them.
  WeeklyReviewDraft afterSave({
    required int mood,
    required String feeling,
    required String note,
    required bool adoptSaved,
  }) {
    final saved = copyWith(
      savedMood: mood,
      savedFeeling: feeling.trim(),
      savedNote: note.trim(),
    );
    if (!adoptSaved) return saved.copyWith(dirty: saved.differsFromSaved);
    final changed =
        this.feeling != saved.savedFeeling || this.note != saved.savedNote;
    return saved.copyWith(
      mood: mood,
      feeling: saved.savedFeeling,
      note: saved.savedNote,
      dirty: false,
      hydrationVersion: changed ? hydrationVersion + 1 : hydrationVersion,
    );
  }

  /// Replaces the values with the saved review (defaults when none: Good).
  WeeklyReviewDraft hydrateFrom(WeeklyReview? review) {
    final nextMood = review?.mood ?? reviewDefaultMood;
    final nextFeeling = review?.feeling ?? '';
    final nextNote = review?.reflection ?? '';
    final changed =
        !hydrated ||
        nextMood != mood ||
        nextFeeling != feeling ||
        nextNote != note;
    return copyWith(
      hydrated: true,
      mood: nextMood,
      feeling: nextFeeling,
      note: nextNote,
      savedMood: nextMood,
      savedFeeling: nextFeeling,
      savedNote: nextNote,
      dirty: false,
      hydrationVersion: changed ? hydrationVersion + 1 : hydrationVersion,
    );
  }
}
