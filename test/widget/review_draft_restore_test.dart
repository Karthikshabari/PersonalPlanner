import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/providers/review_draft_controller.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart';

class _FailingReviewRepository extends ReviewRepository {
  _FailingReviewRepository(super.db);

  @override
  Future<DailyReview> saveReviewDraft({
    required DateTime date,
    required int mood,
    required String note,
    required Map<String, String> taskReasons,
  }) async => throw StateError('disk full');
}

void main() {
  // Dates depend on the planner time zone, which the test setup configures;
  // they are therefore computed per test, after the container is built.
  late DateTime day;
  late DateTime otherDay;

  void initDays() {
    final today = startOfDay(DateTime.now());
    // Older than the Overview's first 30-day window, so its day cards (with
    // their own test-font layout) are not built while these tests visit it.
    day = addDays(today, -45);
    otherDay = addDays(today, -46);
  }

  Future<ProviderContainer> newContainer(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    initDays();
    return container;
  }

  final noteField = find.byKey(const ValueKey('review-note'));
  final saveButton = find.byKey(const ValueKey('review-save'));
  final hint = find.byKey(const ValueKey('review-unsaved-hint'));

  Future<Task> addTask(
    WidgetTester tester,
    ProviderContainer container,
    DateTime d,
    String title,
  ) {
    final start = DateTime(d.year, d.month, d.day, 9);
    return runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: title,
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              createdAt: start,
              updatedAt: start,
            ),
          ),
    );
  }

  Future<void> pumpDay(
    WidgetTester tester,
    ProviderContainer container,
    DateTime d,
  ) async {
    container.read(selectedReviewDateProvider.notifier).state = d;
    appRouter.go('/review');
    await pumpApp(tester, container, surface: const Size(1400, 1400));
    // The form stays disabled until the saved review has been read.
    for (var i = 0; i < 20; i++) {
      if (container.read(reviewDraftProvider(d)).hydrated) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
    }
    expect(container.read(reviewDraftProvider(d)).hydrated, isTrue);
  }

  Finder reasonField(Task t) => find.byKey(ValueKey('review-reason-${t.id}'));

  String textOf(WidgetTester tester, Finder f) =>
      tester.widget<TextField>(f).controller!.text;

  // Leaving the Daily tab disposes reactive-stats providers; give their async
  // onCancel real time so database.close() in finish() does not hang.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  Future<void> leaveAndReturn(WidgetTester tester, String route) async {
    appRouter.go(route);
    await settle(tester);
    await drainDisposedStreams(tester);
    appRouter.go('/review');
    await settle(tester);
  }

  Future<void> edit(WidgetTester tester, Task task) async {
    await tester.enterText(noteField, 'Long day');
    await tester.enterText(reasonField(task), 'Meeting ran over');
    await tester.ensureVisible(find.byKey(const ValueKey('review-mood-3')));
    await tester.tap(find.byKey(const ValueKey('review-mood-3')));
    await settle(tester);
  }

  for (final route in ['/review/overview', '/review/weekly']) {
    testWidgets('edits survive a visit to $route', (tester) async {
      final container = await newContainer(tester);
      final task = await addTask(tester, container, day, 'Write report');
      await pumpDay(tester, container, day);
      await edit(tester, task);
      expect(hint, findsOneWidget);

      await leaveAndReturn(tester, route);

      expect(textOf(tester, noteField), 'Long day');
      expect(textOf(tester, reasonField(task)), 'Meeting ran over');
      expect(container.read(reviewDraftProvider(day)).mood, 3);
      expect(hint, findsOneWidget);
      expect(find.text('Save review'), findsOneWidget);
      // Nothing was written: still "Not reviewed".
      expect(
        await runDb(
          tester,
          () => container.read(reviewRepositoryProvider).getReviewForDate(day),
        ),
        isNull,
      );
      await drainDisposedStreams(tester);
      await finish(tester, container);
    });
  }

  testWidgets('a draft for date A does not appear on date B', (tester) async {
    final container = await newContainer(tester);
    final task = await addTask(tester, container, day, 'Write report');
    await pumpDay(tester, container, day);
    await edit(tester, task);

    await tester.tap(find.byKey(const ValueKey('review-prev-day')));
    await settle(tester);
    expect(textOf(tester, noteField), '');
    expect(hint, findsNothing);
    expect(container.read(reviewDraftProvider(otherDay)).mood, 1);

    await tester.tap(find.byKey(const ValueKey('review-next-day')));
    await settle(tester);
    expect(textOf(tester, noteField), 'Long day');
    expect(textOf(tester, reasonField(task)), 'Meeting ran over');
    expect(hint, findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('an untouched day shows no hint and keeps nothing', (
    tester,
  ) async {
    final container = await newContainer(tester);
    await pumpDay(tester, container, day);
    expect(hint, findsNothing);
    expect(container.read(reviewDraftProvider(day)).dirty, isFalse);

    await leaveAndReturn(tester, '/review/overview');
    expect(hint, findsNothing);
    expect(textOf(tester, noteField), '');
    expect(container.read(reviewDraftProvider(day)).mood, 1);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('a successful save discards the draft and the hint', (
    tester,
  ) async {
    final container = await newContainer(tester);
    final task = await addTask(tester, container, day, 'Write report');
    await pumpDay(tester, container, day);
    await edit(tester, task);
    await leaveAndReturn(tester, '/review/overview');
    expect(hint, findsOneWidget);

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await settle(tester);

    expect(hint, findsNothing);
    expect(find.text('Saved'), findsOneWidget);
    expect(textOf(tester, noteField), 'Long day');
    expect(textOf(tester, reasonField(task)), 'Meeting ran over');
    final saved = await runDb(
      tester,
      () => container.read(reviewRepositoryProvider).getReviewForDate(day),
    );
    expect(saved?.reflection, 'Long day');
    expect(saved?.mood, 3);
    expect(container.read(reviewDraftKeeperProvider).holds(day), isFalse);

    await leaveAndReturn(tester, '/review/weekly');
    expect(hint, findsNothing);
    expect(textOf(tester, noteField), 'Long day');
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('a failed save keeps the draft', (tester) async {
    setupSqliteForTests();
    initDays();
    late ProviderContainer container;
    await tester.runAsync(() async {
      final database = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          reviewRepositoryProvider.overrideWithValue(
            _FailingReviewRepository(database),
          ),
        ],
      );
      await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
    });
    await pumpDay(tester, container, day);
    await tester.enterText(noteField, 'Keep me');
    await settle(tester);

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    expect(find.text('Couldn\'t save the review. Try again.'), findsOneWidget);
    expect(hint, findsOneWidget);

    await leaveAndReturn(tester, '/review/overview');
    expect(textOf(tester, noteField), 'Keep me');
    expect(hint, findsOneWidget);
    expect(find.text('Save review'), findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('reverting to the saved values drops the draft and the hint', (
    tester,
  ) async {
    final container = await newContainer(tester);
    await runDb(
      tester,
      () => container
          .read(reviewRepositoryProvider)
          .saveReviewDraft(
            date: day,
            mood: 2,
            note: 'Saved note',
            taskReasons: const {},
          ),
    );
    await pumpDay(tester, container, day);
    expect(hint, findsNothing);

    await tester.enterText(noteField, 'Something else');
    await settle(tester);
    expect(hint, findsOneWidget);
    expect(find.text('Save review'), findsOneWidget);

    await tester.enterText(noteField, 'Saved note');
    await settle(tester);
    expect(hint, findsNothing);
    expect(container.read(reviewDraftKeeperProvider).holds(day), isFalse);
    await finish(tester, container);
  });
}
