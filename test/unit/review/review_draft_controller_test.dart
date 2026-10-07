import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/review_draft.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/providers/review_draft_controller.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../../helpers/sqlite_setup.dart';

class _FailingReviewRepository extends ReviewRepository {
  _FailingReviewRepository(super.db);

  @override
  Future<DailyReview> saveReviewDraft({
    required DateTime date,
    required int mood,
    required String note,
    required Map<String, String> taskReasons,
  }) => throw StateError('x');
}

TaskOutcomeRow _row(String id, TaskOutcome outcome) => TaskOutcomeRow(
  taskId: id,
  title: id,
  startTime: null,
  plannedMinutes: 0,
  trackedMinutes: 0,
  outcome: outcome,
);

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ProviderContainer container;
  final day = startOfDay(DateTime(2026, 10, 6));
  final otherDay = addDays(day, 1);

  ProviderContainer build({List overrides = const []}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...overrides.cast(),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> hydrated(DateTime d) async {
    final p = reviewDraftProvider(d);
    container.listen(p, (_, _) {});
    for (var i = 0; i < 50 && !container.read(p).hydrated; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = build();
  });

  tearDown(() => db.close());

  test('defaults to Good with no saved review', () async {
    await hydrated(day);
    final draft = container.read(reviewDraftProvider(day));
    expect(draft.mood, 1);
    expect(draft.note, '');
    expect(draft.dirty, isFalse);
  });

  test('edits mark dirty and save clears it', () async {
    await hydrated(day);
    final p = reviewDraftProvider(day);
    final c = container.read(p.notifier);
    c.setMood(3);
    c.setNote('n');
    c.setReason('t2', 'Blocked');
    expect(container.read(p).dirty, isTrue);

    final ok = await c.save(
      rows: [
        _row('t1', TaskOutcome.completed),
        _row('t2', TaskOutcome.notStarted),
      ],
    );

    expect(ok, isTrue);
    final saved = await ReviewRepository(db).getReviewForDate(day);
    expect(saved?.mood, 3);
    expect(saved?.reflection, 'n');
    expect(saved?.taskReasons, {'t2': 'Blocked'});
    expect(container.read(p).dirty, isFalse);
    expect(container.read(p).saveStatus, ReviewSaveStatus.saved);
  });

  test('completed rows never store a reason', () async {
    await hydrated(day);
    final c = container.read(reviewDraftProvider(day).notifier);
    c.setReason('t1', 'Should not persist');
    await c.save(rows: [_row('t1', TaskOutcome.completed)]);
    final saved = await ReviewRepository(db).getReviewForDate(day);
    expect(saved?.taskReasons, isEmpty);
  });

  test('an edit after saving returns to idle', () async {
    await hydrated(day);
    final p = reviewDraftProvider(day);
    final c = container.read(p.notifier);
    await c.save(rows: const []);
    expect(container.read(p).saveStatus, ReviewSaveStatus.saved);
    c.setMood(2);
    expect(container.read(p).saveStatus, ReviewSaveStatus.idle);
    expect(container.read(p).dirty, isTrue);
  });

  test('drafts are keyed by date', () async {
    await hydrated(day);
    await hydrated(otherDay);
    container.read(reviewDraftProvider(day).notifier).setNote('A');
    expect(container.read(reviewDraftProvider(otherDay)).note, '');
  });

  test('failure keeps the draft dirty', () async {
    container = build(
      overrides: [
        reviewRepositoryProvider.overrideWithValue(
          _FailingReviewRepository(db),
        ),
      ],
    );
    await hydrated(day);
    final p = reviewDraftProvider(day);
    final c = container.read(p.notifier);
    c.setMood(2);
    final ok = await c.save(rows: const []);
    expect(ok, isFalse);
    expect(container.read(p).saveStatus, ReviewSaveStatus.failed);
    expect(container.read(p).dirty, isTrue);
  });

  group('unsaved drafts', () {
    // Opens the draft, edits it and lets go, like a screen that is left.
    Future<void> editAndLeave(DateTime d, String note) async {
      final sub = container.listen(reviewDraftProvider(d), (_, _) {});
      for (
        var i = 0;
        i < 50 && !container.read(reviewDraftProvider(d)).hydrated;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      container.read(reviewDraftProvider(d).notifier).setNote(note);
      sub.close();
      await Future<void>.delayed(Duration.zero);
    }

    test(
      'a dirty draft survives with no listeners; a clean one does not',
      () async {
        await editAndLeave(day, 'kept');
        expect(container.read(reviewDraftProvider(day)).note, 'kept');
        expect(container.read(reviewDraftProvider(day)).dirty, isTrue);
        expect(container.exists(reviewDraftProvider(otherDay)), isFalse);
      },
    );

    test('a draft for one date never shows on another', () async {
      await editAndLeave(day, 'A only');
      final other = container.read(reviewDraftProvider(otherDay));
      expect(other.note, '');
      expect(other.dirty, isFalse);
    });

    test('an untouched day is not a draft', () async {
      await hydrated(day);
      final draft = container.read(reviewDraftProvider(day));
      expect(draft.mood, 1);
      expect(draft.dirty, isFalse);
    });

    test('reverting to the saved values drops the draft', () async {
      await ReviewRepository(db).saveReviewDraft(
        date: day,
        mood: 2,
        note: 'saved',
        taskReasons: const {'t2': 'Blocked'},
      );
      await hydrated(day);
      final p = reviewDraftProvider(day);
      final c = container.read(p.notifier);
      c.setNote('changed');
      c.setReason('t2', 'Other');
      c.setMood(4);
      expect(container.read(p).dirty, isTrue);
      c.setNote('saved');
      c.setReason('t2', 'Blocked');
      c.setMood(2);
      expect(container.read(p).dirty, isFalse);
      expect(container.read(reviewDraftKeeperProvider).holds(day), isFalse);
    });

    test('successful save discards the draft and keeps saved values', () async {
      await editAndLeave(day, '  note  ');
      final c = container.read(reviewDraftProvider(day).notifier);
      expect(await c.save(rows: const []), isTrue);
      final draft = container.read(reviewDraftProvider(day));
      expect(draft.dirty, isFalse);
      expect(draft.note, 'note');
      expect(container.read(reviewDraftKeeperProvider).holds(day), isFalse);
    });

    test('a failed save keeps the draft held', () async {
      container = build(
        overrides: [
          reviewRepositoryProvider.overrideWithValue(
            _FailingReviewRepository(db),
          ),
        ],
      );
      await editAndLeave(day, 'keep me');
      final c = container.read(reviewDraftProvider(day).notifier);
      expect(await c.save(rows: const []), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(reviewDraftProvider(day)).note, 'keep me');
      expect(container.read(reviewDraftKeeperProvider).holds(day), isTrue);
    });

    test('at most 30 drafts are kept, oldest first', () async {
      final dates = [for (var i = 0; i < 31; i++) addDays(day, i)];
      for (final d in dates) {
        await editAndLeave(d, 'draft ${d.day}');
      }
      expect(container.exists(reviewDraftProvider(dates.first)), isFalse);
      for (final d in dates.skip(1)) {
        expect(container.exists(reviewDraftProvider(d)), isTrue);
        expect(container.read(reviewDraftProvider(d)).note, 'draft ${d.day}');
      }
    });
  });
}
