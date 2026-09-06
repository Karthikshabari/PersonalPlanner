import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> pumpReview(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    // Rail destination added in Chunk 5.
    await tester.tap(find.text('Review').last);
    await settle(tester);
    return container;
  }

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> seedTwoTasks(
    WidgetTester tester,
    ProviderContainer container,
    DateTime date,
  ) async {
    final categories = await runDb(
      tester,
      () =>
          container.read(appDatabaseProvider).categoryDao.getActiveCategories(),
    );
    final work = categories.firstWhere((c) => c.name == 'Work');
    final tasks = container.read(taskRepositoryProvider);
    await runDb(
      tester,
      () => tasks.insertTask(
        Task(
          id: '',
          title: 'Morning run',
          startTime: DateTime(date.year, date.month, date.day, 9),
          endTime: DateTime(date.year, date.month, date.day, 10),
          status: TaskStatus.completed,
          categoryId: work.id,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    await runDb(
      tester,
      () => tasks.insertTask(
        Task(
          id: '',
          title: 'Deep work',
          startTime: DateTime(date.year, date.month, date.day, 11),
          endTime: DateTime(date.year, date.month, date.day, 12, 30),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> showReviewForToday(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    appRouter.go('/day');
    await settle(tester);
    await tester.tap(find.text('Review').last);
    await settle(tester);
  }

  testWidgets('daily review shows auto stats and the read-only mini timeline', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    await seedTwoTasks(tester, container, today());
    await showReviewForToday(tester, container);

    expect(find.text('Daily Review'), findsOneWidget);
    expect(find.text('Auto-computed stats'), findsOneWidget);
    // Completion rate: 1 completed / (2 − 0 cancelled).
    expect(find.text('50%'), findsOneWidget);
    // Planned total: 1h + 1h30m.
    expect(find.text('2h 30m'), findsOneWidget);
    // Mini timeline renders both blocks with their statuses.
    expect(find.byKey(const ValueKey('review-mini-timeline')), findsOneWidget);
    expect(find.text('Morning run'), findsOneWidget);
    expect(find.text('Deep work'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    await finish(tester, container);
  });

  testWidgets(
    'fill and save the daily review persists it and refreshes stats',
    (tester) async {
      final container = await pumpReview(tester);

      await tester.enterText(
        find.byKey(const ValueKey('review-reflection')),
        'Solid focus day',
      );
      await tester.tap(find.byKey(const ValueKey('rating-Energy level-4')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('review-wins')),
          matching: find.byType(TextField),
        ),
        'Shipped chunk 5',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('review-wins')),
          matching: find.byIcon(Icons.add),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('review-save')));
      await settle(tester);
      expect(find.text('Daily review saved'), findsOneWidget);

      final repo = container.read(reviewRepositoryProvider);
      final saved = await runDb(tester, () => repo.getReviewForDate(today()));
      expect(saved!.reflection, 'Solid focus day');
      expect(saved.energyLevel, 4);
      expect(saved.wins, ['Shipped chunk 5']);

      final cached = await runDb(
        tester,
        () => container
            .read(appDatabaseProvider)
            .statsDao
            .getStatsForDate(isoDateString(today())),
      );
      expect(cached!.energyLevel, 4);

      // Re-mounting hydrates the form from the saved row.
      await pumpApp(tester, container, surface: const Size(1400, 1000));
      await settle(tester);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('review-reflection')),
      );
      expect(field.controller!.text, 'Solid focus day');
      await finish(tester, container);
    },
  );

  testWidgets('date selector navigates days and returns to Today', (
    tester,
  ) async {
    final container = await pumpReview(tester);

    await tester.tap(find.byKey(const ValueKey('review-next-day')));
    await settle(tester);
    var shown = container.read(selectedReviewDateProvider);
    expect(isSameDay(shown, today().add(const Duration(days: 1))), isTrue);

    await tester.tap(find.text('Today'));
    await settle(tester);
    shown = container.read(selectedReviewDateProvider);
    expect(isSameDay(shown, today()), isTrue);
    await finish(tester, container);
  });

  testWidgets('weekly review shows aggregates and saves the review', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    await seedTwoTasks(tester, container, today());
    await showReviewForToday(tester, container);

    await tester.tap(find.byKey(const ValueKey('open-weekly-review')));
    await settle(tester);

    expect(find.text('Weekly Review'), findsOneWidget);
    // Aggregate stats card renders computed values for the current week.
    expect(find.text('Completion rate'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('weekly-reflection')),
      'Good week overall',
    );
    await tester.tap(find.byKey(const ValueKey('rating-Overall rating-5')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-goals-met')),
        matching: find.byType(TextField),
      ),
      'Plan every morning',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-goals-met')),
        matching: find.byIcon(Icons.add),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('weekly-save')));
    await settle(tester);
    expect(find.text('Weekly review saved'), findsOneWidget);

    final repo = container.read(reviewRepositoryProvider);
    final saved = await runDb(
      tester,
      () => repo.getWeeklyReviewForWeek(startOfWeek(DateTime.now())),
    );
    expect(saved!.overallRating, 5);
    expect(saved.goalsMet, ['Plan every morning']);
    await finish(tester, container);
  });

  testWidgets('review view switches retain the selected planning period', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    await tester.tap(find.byKey(const ValueKey('open-weekly-review')));
    await settle(tester);
    final selectedWeek = addDays(startOfWeek(today()), -7);
    container.read(selectedWeekStartProvider.notifier).state = selectedWeek;
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('open-daily-review')));
    await settle(tester);

    expect(container.read(selectedReviewDateProvider), selectedWeek);
    expect(find.text('Daily Review'), findsOneWidget);
    await finish(tester, container);
  });
}
