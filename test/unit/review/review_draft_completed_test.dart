import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/review_draft.dart';
import 'package:personal_planner/features/review/providers/review_draft_controller.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../../helpers/sqlite_setup.dart';

/// B4: a reason that belongs to a Completed task is invisible and dropped by
/// Save, so it must not count as an unsaved edit.
void main() {
  final day = startOfDay(DateTime(2026, 10, 6));

  group('ReviewDraft.differsFromSaved', () {
    ReviewDraft draft({
      Map<String, String> reasons = const {},
      Map<String, String> savedReasons = const {},
      Set<String> completed = const {},
    }) => ReviewDraft(
      date: day,
      hydrated: true,
      reasons: reasons,
      savedReasons: savedReasons,
      completedTaskIds: completed,
    );

    test('a reason of a not-done task counts', () {
      expect(draft(reasons: {'a': 'Blocked'}).differsFromSaved, isTrue);
    });

    test('a reason of a Completed task is ignored', () {
      final d = draft(reasons: {'a': 'Blocked'}, completed: {'a'});
      expect(d.differsFromSaved, isFalse);
    });

    test('only the Completed task is ignored', () {
      final d = draft(
        reasons: {'a': 'Blocked', 'b': 'Tired'},
        completed: {'a'},
      );
      expect(d.differsFromSaved, isTrue);
    });

    test(
      'a stored reason of a now Completed task is ignored on both sides',
      () {
        final d = draft(
          reasons: const {},
          savedReasons: {'a': 'Blocked'},
          completed: {'a'},
        );
        expect(d.differsFromSaved, isFalse);
      },
    );

    test('mood and note still count when a Completed reason is present', () {
      final withMood = draft(
        reasons: {'a': 'x'},
        completed: {'a'},
      ).copyWith(mood: 3);
      expect(withMood.differsFromSaved, isTrue);
      final withNote = draft(
        reasons: {'a': 'x'},
        completed: {'a'},
      ).copyWith(note: 'n');
      expect(withNote.differsFromSaved, isTrue);
    });

    test('blank reasons never count, as before', () {
      expect(draft(reasons: {'a': '   '}).differsFromSaved, isFalse);
    });
  });

  group('ReviewDraftController', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      setupSqliteForTests();
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await db.close();
    });

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
    }

    test('completing the task drops its reason from the dirty state', () async {
      final repo = container.read(taskRepositoryProvider);
      final start = DateTime(day.year, day.month, day.day, 9);
      final task = await repo.insertTask(
        Task(
          id: '',
          title: 'Write report',
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          createdAt: start,
          updatedAt: start,
        ),
      );
      final draftProvider = reviewDraftProvider(day);
      container.listen(draftProvider, (_, _) {});
      container.listen(taskOutcomesProvider(day), (_, _) {});
      await until(
        () =>
            container.read(draftProvider).hydrated &&
            container.read(taskOutcomesProvider(day)).hasValue,
      );

      container.read(draftProvider.notifier).setReason(task.id, 'Blocked');
      expect(container.read(draftProvider).dirty, isTrue);
      expect(container.read(reviewDraftKeeperProvider).holds(day), isTrue);

      final latest = (await repo.getTaskById(task.id))!;
      await repo.updateTask(latest.copyWith(status: TaskStatus.completed));
      await until(() => !container.read(draftProvider).dirty);

      final draft = container.read(draftProvider);
      expect(draft.completedTaskIds, {task.id});
      expect(draft.differsFromSaved, isFalse);
      expect(draft.reasons, {task.id: 'Blocked'}); // kept, just not counted
      expect(container.read(reviewDraftKeeperProvider).holds(day), isFalse);
    });

    test('reopening the task makes its reason count again', () async {
      final repo = container.read(taskRepositoryProvider);
      final start = DateTime(day.year, day.month, day.day, 9);
      final task = await repo.insertTask(
        Task(
          id: '',
          title: 'Write report',
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          status: TaskStatus.completed,
          createdAt: start,
          updatedAt: start,
        ),
      );
      final draftProvider = reviewDraftProvider(day);
      container.listen(draftProvider, (_, _) {});
      container.listen(taskOutcomesProvider(day), (_, _) {});
      await until(
        () =>
            container.read(draftProvider).hydrated &&
            container.read(draftProvider).completedTaskIds.contains(task.id),
      );

      container.read(draftProvider.notifier).setReason(task.id, 'Blocked');
      expect(container.read(draftProvider).dirty, isFalse);

      final latest = (await repo.getTaskById(task.id))!;
      await repo.updateTask(latest.copyWith(status: TaskStatus.planned));
      await until(() => container.read(draftProvider).dirty);

      expect(container.read(reviewDraftKeeperProvider).holds(day), isTrue);
    });
  });
}
