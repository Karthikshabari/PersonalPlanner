import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../../core/models/daily_review.dart';
import '../domain/review_draft.dart';
import '../domain/task_outcome.dart';
import 'review_providers.dart';

/// Most unsaved drafts kept in memory at once; the oldest edit is dropped first.
const maxKeptReviewDrafts = 30;

/// Holds the keep-alive links of dirty drafts, least recently edited first.
class ReviewDraftKeeper {
  final _links = <DateTime, KeepAliveLink>{};

  bool holds(DateTime date) => _links.containsKey(date);

  void hold(DateTime date, KeepAliveLink link) {
    _links.remove(date);
    _links[date] = link;
    while (_links.length > maxKeptReviewDrafts) {
      final oldest = _links.keys.first;
      _links.remove(oldest)!.close();
    }
  }

  void touch(DateTime date) {
    final link = _links.remove(date);
    if (link != null) _links[date] = link;
  }

  void release(DateTime date) => _links.remove(date)?.close();

  /// The draft provider was disposed; its link is already gone.
  void forget(DateTime date) => _links.remove(date);
}

final reviewDraftKeeperProvider = Provider<ReviewDraftKeeper>(
  (ref) => ReviewDraftKeeper(),
);

/// Draft for one date. Callers must pass `startOfDay(date)`. Unsaved edits
/// keep the draft alive across tab switches (D17).
final reviewDraftProvider = NotifierProvider.autoDispose
    .family<ReviewDraftController, ReviewDraft, DateTime>(
      ReviewDraftController.new,
    );

class ReviewDraftController extends Notifier<ReviewDraft> {
  ReviewDraftController(this.date);

  final DateTime date;
  late final ReviewDraftKeeper _keeper;

  @override
  ReviewDraft build() {
    _keeper = ref.read(reviewDraftKeeperProvider);
    ref.onDispose(() => _keeper.forget(date));
    ref.listen<AsyncValue<DailyReview?>>(dailyReviewProvider(date), (_, next) {
      if (!next.hasValue) return;
      if (state.saveStatus == ReviewSaveStatus.saving) return;
      if (!state.dirty) {
        state = state.hydrateFrom(next.value);
        return;
      }
      state = state.rebase(next.value);
      if (!state.dirty) _keeper.release(date);
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
    final edited = next.copyWith(dirty: next.differsFromSaved);
    if (!edited.dirty) {
      _keeper.release(date);
    } else if (_keeper.holds(date)) {
      _keeper.touch(date);
    } else {
      _keeper.hold(date, ref.keepAlive());
    }
    state = edited.copyWith(
      dirty: edited.dirty,
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
    state = state
        .afterSave(
          mood: snapshot.mood,
          note: snapshot.note,
          reasons: reasons,
          adoptSaved: untouched,
        )
        .copyWith(
          saveStatus: untouched
              ? ReviewSaveStatus.saved
              : ReviewSaveStatus.idle,
        );
    if (!state.dirty) _keeper.release(date);
    return true;
  }
}
