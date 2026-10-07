import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../../core/models/daily_review.dart';
import '../domain/review_draft.dart';
import '../domain/task_outcome.dart';
import 'review_providers.dart';

/// Draft for one date. Callers must pass `startOfDay(date)`. Unsaved edits
/// keep the draft alive across tab switches (D17).
final reviewDraftProvider = NotifierProvider.autoDispose
    .family<ReviewDraftController, ReviewDraft, DateTime>(
      ReviewDraftController.new,
    );

class ReviewDraftController extends Notifier<ReviewDraft> {
  ReviewDraftController(this.date);

  final DateTime date;
  KeepAliveLink? _keepAlive;

  @override
  ReviewDraft build() {
    ref.onDispose(() => _keepAlive = null);
    ref.listen<AsyncValue<DailyReview?>>(dailyReviewProvider(date), (_, next) {
      if (!next.hasValue) return;
      if (state.dirty || state.saveStatus == ReviewSaveStatus.saving) return;
      state = state.hydrateFrom(next.value);
    });
    final current = ref.read(dailyReviewProvider(date));
    final initial = ReviewDraft(date: date);
    return current.hasValue ? initial.hydrateFrom(current.value) : initial;
  }

  void setMood(int mood) {
    if (mood < 1 || mood > 4 || mood == state.mood) return;
    _edit(state.copyWith(mood: mood));
  }

  void setNote(String note) {
    if (note == state.note) return;
    _edit(state.copyWith(note: note));
  }

  void setReason(String taskId, String text) {
    final next = Map<String, String>.of(state.reasons);
    if (text.trim().isEmpty) {
      next.remove(taskId);
    } else {
      next[taskId] = text;
    }
    if (mapEquals(next, state.reasons)) return;
    _edit(state.copyWith(reasons: Map.unmodifiable(next)));
  }

  void _edit(ReviewDraft next) {
    _keepAlive ??= ref.keepAlive();
    state = next.copyWith(
      dirty: true,
      editVersion: state.editVersion + 1,
      saveStatus: state.saveStatus == ReviewSaveStatus.saving
          ? ReviewSaveStatus.saving
          : ReviewSaveStatus.idle,
    );
  }

  /// One write of mood, note and the reasons of every non-completed row.
  /// Returns true on success.
  Future<bool> save({required List<TaskOutcomeRow> rows}) async {
    if (!state.hydrated || state.saveStatus == ReviewSaveStatus.saving) {
      return false;
    }
    final snapshot = state;
    state = state.copyWith(saveStatus: ReviewSaveStatus.saving);
    final reasons = <String, String>{
      for (final row in rows)
        if (row.outcome != TaskOutcome.completed &&
            (snapshot.reasons[row.taskId]?.trim().isNotEmpty ?? false))
          row.taskId: snapshot.reasons[row.taskId]!.trim(),
    };
    try {
      await ref
          .read(reviewRepositoryProvider)
          .saveReviewDraft(
            date: date,
            mood: snapshot.mood,
            note: snapshot.note,
            taskReasons: reasons,
          );
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(saveStatus: ReviewSaveStatus.failed);
      }
      return false;
    }
    try {
      await ref.read(dailyStatsServiceProvider).computeAndCache(date);
    } catch (_) {
      // Derived cache only; the review itself is saved (D26).
    }
    if (!ref.mounted) return true;
    final untouched = state.editVersion == snapshot.editVersion;
    state = state.copyWith(
      dirty: untouched ? false : state.dirty,
      saveStatus: untouched ? ReviewSaveStatus.saved : ReviewSaveStatus.idle,
    );
    if (untouched) {
      _keepAlive?.close();
      _keepAlive = null;
    }
    return true;
  }
}
