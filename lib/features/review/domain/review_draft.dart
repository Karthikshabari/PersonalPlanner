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
    this.savedMood = reviewDefaultMood,
    this.savedNote = '',
    this.savedReasons = const <String, String>{},
    this.dirty = false,
    this.editVersion = 0,
    this.saveStatus = ReviewSaveStatus.idle,
    this.completedTaskIds = const <String>{},
  });

  final DateTime date;
  final bool hydrated;

  /// Bumped whenever stored values replace the draft, so text fields know to
  /// reload their controllers.
  final int hydrationVersion;
  final int mood;
  final String note;
  final Map<String, String> reasons;

  /// What is stored for the date (defaults when no review exists). A draft is
  /// "dirty" only while it differs from these.
  final int savedMood;
  final String savedNote;
  final Map<String, String> savedReasons;
  final bool dirty;
  final int editVersion;
  final ReviewSaveStatus saveStatus;

  /// Tasks that are Completed right now. Their reason field is hidden and
  /// Save drops their reasons, so they never count as unsaved edits.
  final Set<String> completedTaskIds;

  ReviewDraft copyWith({
    bool? hydrated,
    int? hydrationVersion,
    int? mood,
    String? note,
    Map<String, String>? reasons,
    int? savedMood,
    String? savedNote,
    Map<String, String>? savedReasons,
    bool? dirty,
    int? editVersion,
    ReviewSaveStatus? saveStatus,
    Set<String>? completedTaskIds,
  }) => ReviewDraft(
    date: date,
    hydrated: hydrated ?? this.hydrated,
    hydrationVersion: hydrationVersion ?? this.hydrationVersion,
    mood: mood ?? this.mood,
    note: note ?? this.note,
    reasons: reasons ?? this.reasons,
    savedMood: savedMood ?? this.savedMood,
    savedNote: savedNote ?? this.savedNote,
    savedReasons: savedReasons ?? this.savedReasons,
    dirty: dirty ?? this.dirty,
    editVersion: editVersion ?? this.editVersion,
    saveStatus: saveStatus ?? this.saveStatus,
    completedTaskIds: completedTaskIds ?? this.completedTaskIds,
  );

  /// True when mood, note or any non-blank reason of a task that can take one
  /// differs from what is saved. Notes and reasons compare trimmed, as the
  /// repository stores them; reasons of Completed tasks are ignored on both
  /// sides because the form hides them and Save drops them.
  bool get differsFromSaved =>
      mood != savedMood ||
      note.trim() != savedNote ||
      !mapEquals(
        _withoutCompleted(_normalizedReasons(reasons)),
        _withoutCompleted(savedReasons),
      );

  Map<String, String> _withoutCompleted(Map<String, String> source) =>
      completedTaskIds.isEmpty
      ? source
      : {
          for (final entry in source.entries)
            if (!completedTaskIds.contains(entry.key)) entry.key: entry.value,
        };

  static Map<String, String> _normalizedReasons(Map<String, String> source) => {
    for (final entry in source.entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
  };

  /// Re-points the saved baseline (remote change) keeping the edits.
  ReviewDraft rebase(DailyReview? review) {
    final base = copyWith(
      savedMood: review?.mood ?? reviewDefaultMood,
      savedNote: review?.reflection ?? '',
      savedReasons: review?.taskReasons ?? const <String, String>{},
    );
    return base.copyWith(dirty: base.differsFromSaved);
  }

  /// Records a successful write of [mood], [note] and [reasons]. With
  /// [adoptSaved] the visible values become the stored ones (trimmed); the
  /// text fields reload only if that changed anything.
  ReviewDraft afterSave({
    required int mood,
    required String note,
    required Map<String, String> reasons,
    required bool adoptSaved,
  }) {
    final saved = copyWith(
      savedMood: mood,
      savedNote: note.trim(),
      savedReasons: Map.unmodifiable(reasons),
    );
    if (!adoptSaved) return saved.copyWith(dirty: saved.differsFromSaved);
    final changed =
        this.note != saved.savedNote ||
        !mapEquals(this.reasons, saved.savedReasons);
    return saved.copyWith(
      mood: mood,
      note: saved.savedNote,
      reasons: saved.savedReasons,
      dirty: false,
      hydrationVersion: changed ? hydrationVersion + 1 : hydrationVersion,
    );
  }

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
      savedMood: nextMood,
      savedNote: nextNote,
      savedReasons: nextReasons,
      dirty: false,
      hydrationVersion: changed ? hydrationVersion + 1 : hydrationVersion,
    );
  }
}
