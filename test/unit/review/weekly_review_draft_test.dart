import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/review_draft.dart';
import 'package:personal_planner/features/review/domain/weekly_review_draft.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';
import 'package:personal_planner/features/review/providers/weekly_review_draft_controller.dart';

import '../../helpers/sqlite_setup.dart';

class _FailingReviewRepository extends ReviewRepository {
  _FailingReviewRepository(super.db);

  @override
  Future<WeeklyReview> saveWeeklyReviewDraft({
    required DateTime weekStart,
    required int mood,
    required String feeling,
    required String note,
  }) => throw StateError('x');
}

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ProviderContainer container;
  final week = startOfWeek(DateTime(2026, 9, 30));
  final otherWeek = addDays(week, 7);

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

  Future<void> hydrated(DateTime w) async {
    final p = weeklyReviewDraftProvider(w);
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

  group('WeeklyReviewDraft rules', () {
    test('hydrates Good and empty texts when nothing is saved', () {
      final draft = WeeklyReviewDraft(weekStart: week).hydrateFrom(null);
      expect(draft.hydrated, isTrue);
      expect(draft.mood, 1);
      expect(draft.feeling, '');
      expect(draft.note, '');
      expect(draft.differsFromSaved, isFalse);
    });

    test('an old review without a mood hydrates as Good (WD34)', () {
      final draft = WeeklyReviewDraft(weekStart: week).hydrateFrom(
        WeeklyReview(
          id: 'w',
          weekStartDate: week,
          reflection: 'Old note',
          createdAt: week,
          updatedAt: week,
        ),
      );
      expect(draft.mood, 1);
      expect(draft.note, 'Old note');
      expect(draft.feeling, '');
    });

    test('text compares trimmed; rebase keeps edits', () {
      final draft = WeeklyReviewDraft(weekStart: week)
          .hydrateFrom(null)
          .copyWith(feeling: '  ');
      expect(draft.differsFromSaved, isFalse);
      final edited = draft.copyWith(note: 'Start with ');
      expect(edited.differsFromSaved, isTrue);
      final rebased = edited.rebase(
        WeeklyReview(
          id: 'w',
          weekStartDate: week,
          reflection: 'Start with',
          createdAt: week,
          updatedAt: week,
        ),
      );
      expect(rebased.note, 'Start with ');
      expect(rebased.dirty, isFalse);
    });
  });

  group('WeeklyReviewDraftController', () {
    test('edits mark dirty, save writes mood, feeling and note', () async {
      await hydrated(week);
      final p = weeklyReviewDraftProvider(week);
      final c = container.read(p.notifier);
      c.setMood(3);
      c.setFeeling('  Calm, proud ');
      c.setNote(' Keep doing reviews ');
      expect(container.read(p).dirty, isTrue);
      expect(
        container.read(weeklyReviewDraftKeeperProvider).holds(week),
        isTrue,
      );

      expect(await c.save(), isTrue);

      final draft = container.read(p);
      expect(draft.dirty, isFalse);
      expect(draft.saveStatus, ReviewSaveStatus.saved);
      expect(draft.feeling, 'Calm, proud');
      expect(draft.note, 'Keep doing reviews');
      expect(
        container.read(weeklyReviewDraftKeeperProvider).holds(week),
        isFalse,
      );
      final saved = (await ReviewRepository(db).getWeeklyReviewForWeek(week))!;
      expect(saved.mood, 3);
      expect(saved.feeling, 'Calm, proud');
      expect(saved.reflection, 'Keep doing reviews');
    });

    test('reverting to the saved values drops the draft', () async {
      await hydrated(week);
      final p = weeklyReviewDraftProvider(week);
      final c = container.read(p.notifier);
      c.setMood(2);
      expect(container.read(p).dirty, isTrue);
      c.setMood(1);
      expect(container.read(p).dirty, isFalse);
      expect(
        container.read(weeklyReviewDraftKeeperProvider).holds(week),
        isFalse,
      );
    });

    test('drafts are per week', () async {
      await hydrated(week);
      await hydrated(otherWeek);
      container.read(weeklyReviewDraftProvider(week).notifier).setMood(4);
      expect(container.read(weeklyReviewDraftProvider(otherWeek)).mood, 1);
    });

    test('a failed save keeps the draft and reports failed', () async {
      container = build(
        overrides: [
          reviewRepositoryProvider.overrideWithValue(
            _FailingReviewRepository(db),
          ),
        ],
      );
      await hydrated(week);
      final p = weeklyReviewDraftProvider(week);
      container.read(p.notifier).setFeeling('Tired');

      expect(await container.read(p.notifier).save(), isFalse);

      expect(container.read(p).saveStatus, ReviewSaveStatus.failed);
      expect(container.read(p).feeling, 'Tired');
      expect(container.read(p).dirty, isTrue);
    });
  });
}
