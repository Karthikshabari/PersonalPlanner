import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/weekly_review.dart';
import '../domain/review_draft.dart';
import '../domain/weekly_review_draft.dart';
import '../domain/weekly_review_text.dart';
import 'review_draft_controller.dart';
import 'review_providers.dart';

/// Keep-alive links of dirty weekly drafts, keyed by week start. A separate
/// keeper from Daily's, so a Monday date and a week start never collide;
/// same limit of 30 (oldest edit dropped first).
final weeklyReviewDraftKeeperProvider = Provider<ReviewDraftKeeper>(
  (ref) => ReviewDraftKeeper(),
);

/// Week starts whose "Your week" reveal already played in this app session
/// (WD14). It lives as long as the provider container (the signed-in
/// account); a new session starts empty.
final weeklyRevealPlayedProvider = Provider<Set<DateTime>>(
  (ref) => <DateTime>{},
);

/// Draft for one week. Callers must pass `startOfWeek(date)`. Unsaved edits
/// keep the draft alive across tab and route switches, exactly like Daily.
final weeklyReviewDraftProvider = NotifierProvider.autoDispose
    .family<WeeklyReviewDraftController, WeeklyReviewDraft, DateTime>(
      WeeklyReviewDraftController.new,
    );

class WeeklyReviewDraftController extends Notifier<WeeklyReviewDraft> {
  WeeklyReviewDraftController(this.weekStart);

  final DateTime weekStart;
  late final ReviewDraftKeeper _keeper;

  @override
  WeeklyReviewDraft build() {
    _keeper = ref.read(weeklyReviewDraftKeeperProvider);
    ref.onDispose(() => _keeper.forget(weekStart));
    ref.listen<AsyncValue<WeeklyReview?>>(weeklyReviewProvider(weekStart), (
      _,
      next,
    ) {
      if (!next.hasValue) return;
      if (state.saveStatus == ReviewSaveStatus.saving) return;
      if (!state.dirty) {
        state = state.hydrateFrom(next.value);
        return;
      }
      state = state.rebase(next.value);
      if (!state.dirty) _keeper.release(weekStart);
    });
    final current = ref.read(weeklyReviewProvider(weekStart));
    final initial = WeeklyReviewDraft(weekStart: weekStart);
    return current.hasValue ? initial.hydrateFrom(current.value) : initial;
  }

  void setMood(int mood) {
    if (mood < 1 || mood > 4 || mood == state.mood) return;
    _edit(state.copyWith(mood: mood));
  }

  void setFeeling(String feeling) {
    if (feeling == state.feeling) return;
    _edit(state.copyWith(feeling: feeling));
  }

  void setNote(String note) {
    if (note == state.note) return;
    _edit(state.copyWith(note: note));
  }

  void _edit(WeeklyReviewDraft next) {
    final edited = next.copyWith(dirty: next.differsFromSaved);
    if (!edited.dirty) {
      _keeper.release(weekStart);
    } else if (_keeper.holds(weekStart)) {
      _keeper.touch(weekStart);
    } else {
      _keeper.hold(weekStart, ref.keepAlive());
    }
    state = edited.copyWith(
      dirty: edited.dirty,
      editVersion: state.editVersion + 1,
      saveStatus: state.saveStatus == ReviewSaveStatus.saving
          ? ReviewSaveStatus.saving
          : ReviewSaveStatus.idle,
    );
  }

  /// One write of mood, feeling and note. Returns true on success.
  Future<bool> save() async {
    if (!state.hydrated || state.saveStatus == ReviewSaveStatus.saving) {
      return false;
    }
    final snapshot = state;
    state = state.copyWith(saveStatus: ReviewSaveStatus.saving);
    final feeling = normalizeWeeklyFeeling(snapshot.feeling) ?? '';
    final note = snapshot.note.trim();
    try {
      await ref
          .read(reviewRepositoryProvider)
          .saveWeeklyReviewDraft(
            weekStart: weekStart,
            mood: snapshot.mood,
            feeling: feeling,
            note: note,
          );
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(saveStatus: ReviewSaveStatus.failed);
      }
      return false;
    }
    if (!ref.mounted) return true;
    final untouched = state.editVersion == snapshot.editVersion;
    state = state
        .afterSave(
          mood: snapshot.mood,
          feeling: feeling,
          note: note,
          adoptSaved: untouched,
        )
        .copyWith(
          saveStatus: untouched
              ? ReviewSaveStatus.saved
              : ReviewSaveStatus.idle,
        );
    if (!state.dirty) _keeper.release(weekStart);
    return true;
  }
}
