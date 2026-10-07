import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/providers/day_context_providers.dart';
import 'package:personal_planner/features/review/providers/review_draft_controller.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

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

  testWidgets(
    'daily review shows factual summary without a duplicate timeline',
    (tester) async {
      final container = await pumpReview(tester);
      await seedTwoTasks(tester, container, today());
      await showReviewForToday(tester, container);

      expect(find.text('Daily Review'), findsOneWidget);
      expect(find.text('Today / Day at a glance'), findsOneWidget);
      // Factual completion summary: 1 completed out of 2 planned items.
      expect(find.text('1 / 2 completed'), findsOneWidget);
      // Planned total: 1h + 1h30m.
      expect(find.textContaining('2h 30m planned'), findsOneWidget);
      expect(find.textContaining('tracked'), findsNothing);
      expect(find.byKey(const ValueKey('review-mini-timeline')), findsNothing);
      expect(find.text('Energy level'), findsNothing);
      expect(find.text('Planning accuracy'), findsNothing);
      expect(find.text('What changed'), findsNothing);
      expect(find.text('Added during the day'), findsNothing);
      expect(find.text('Task outcomes'), findsOneWidget);
      expect(find.text('Tomorrow'), findsNothing);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Not started'), findsOneWidget);
      expect(find.text('1 without a reason'), findsOneWidget);
      await finish(tester, container);
    },
  );

  Future<List<Task>> tasksOn(
    WidgetTester tester,
    ProviderContainer container,
    DateTime date,
  ) async {
    final rows = await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .taskDao
          .getTasksBetween(date, date.add(const Duration(days: 1))),
    );
    return rows.map(TaskRepository.fromRow).toList();
  }

  testWidgets('shows the plan-change block with the struck old title', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    final date = today();
    final repo = container.read(taskRepositoryProvider);
    await runDb(
      tester,
      () => repo.insertTask(
        Task(
          id: '',
          title: 'sample 6',
          startTime: DateTime(date.year, date.month, date.day, 14),
          endTime: DateTime(date.year, date.month, date.day, 15),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    final current = (await tasksOn(tester, container, date)).single;
    final event = PlanTitleChange(
      id: '00000000-0000-7000-8000-0000000003f1',
      previousTitle: 'sample 6',
      newTitle: 'sample 06',
      changedAt: DateTime.now().toUtc(),
    );
    await runDb(
      tester,
      () => repo.updateTask(
        current.copyWith(
          title: 'sample 06',
          planTitleHistory: [event],
          displayPlanChangeId: event.id,
        ),
      ),
    );
    await showReviewForToday(tester, container);

    expect(
      find.byKey(ValueKey('review-plan-change-${current.id}')),
      findsOneWidget,
    );
    expect(find.text('sample 6'), findsOneWidget);
    expect(find.textContaining('PLAN CHANGED'), findsOneWidget);
    expect(find.text('sample 06'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('empty day keeps mood, note and save', (tester) async {
    final container = await pumpReview(tester);

    expect(find.text('No tasks were planned for this day.'), findsOneWidget);
    expect(find.text('How was the day?'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-save')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('mood defaults to Good and selecting another saves it', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    final handle = tester.ensureSemantics();

    expect(
      tester.getSemantics(find.byKey(const ValueKey('review-mood-1'))),
      isSemantics(label: 'Good', hasCheckedState: true, isChecked: true),
    );
    await tester.tap(find.byKey(const ValueKey('review-mood-3')));
    await settle(tester);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('review-mood-3'))),
      isSemantics(
        label: 'Excellent',
        hasCheckedState: true,
        isChecked: true,
      ),
    );
    expect(container.read(reviewDraftProvider(today())).dirty, isTrue);

    await tester.tap(find.byKey(const ValueKey('review-save')));
    await settle(tester);

    expect(find.text('Reviewed · Excellent'), findsOneWidget);
    handle.dispose();
    await finish(tester, container);
  });

  testWidgets('chip shows Not reviewed until saved', (tester) async {
    final container = await pumpReview(tester);

    expect(find.text('Not reviewed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await settle(tester);
    expect(find.text('Reviewed · Good'), findsOneWidget);
    expect(find.text('Not reviewed'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('review-next-day')));
    await settle(tester);
    expect(find.byKey(const ValueKey('review-status-chip')), findsNothing);
    await finish(tester, container);
  });

  testWidgets('preset chip fills the reason and save-as-preset adds a preset', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    await seedTwoTasks(tester, container, today());
    await showReviewForToday(tester, container);
    final notStarted = (await tasksOn(
      tester,
      container,
      today(),
    )).firstWhere((t) => t.title == 'Deep work');
    final field = find.byKey(ValueKey('review-reason-${notStarted.id}'));

    await tester.tap(find.widgetWithText(ActionChip, 'Blocked'));
    await settle(tester);
    expect(tester.widget<TextField>(field).controller!.text, 'Blocked');

    await tester.enterText(field, 'Meeting ran long');
    await settle(tester);
    await tester.tap(
      find.byKey(ValueKey('review-save-as-preset-${notStarted.id}')),
    );
    await settle(tester);

    expect(find.text('Preset added'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Meeting ran long'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('two columns at 1400 dp, one column at 390 dp', (tester) async {
    final container = await pumpReview(tester);
    expect(
      tester.getTopLeft(find.text('How was the day?')).dx >
          tester.getTopLeft(find.text('Task outcomes')).dx,
      isTrue,
    );

    await pumpApp(tester, container, surface: const Size(390, 844));
    await settle(tester);
    expect(
      tester.getTopLeft(find.text('How was the day?')).dy >
          tester.getTopLeft(find.text('Task outcomes')).dy,
      isTrue,
    );
    await finish(tester, container);
  });

  testWidgets('completed rows have no reason field', (tester) async {
    final container = await pumpReview(tester);
    await seedTwoTasks(tester, container, today());
    await showReviewForToday(tester, container);
    final tasks = await tasksOn(tester, container, today());
    final completed = tasks.firstWhere((t) => t.title == 'Morning run');
    final open = tasks.firstWhere((t) => t.title == 'Deep work');

    expect(find.byKey(ValueKey('review-reason-${completed.id}')), findsNothing);
    expect(find.byKey(ValueKey('review-reason-${open.id}')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('daily review shows the saved day context badge only when set', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/review');
    await pumpApp(tester, container, surface: const Size(390, 844));
    await settle(tester);
    final date = today();
    final badge = find.byKey(
      ValueKey('review-day-context-${isoDateString(date)}'),
    );

    expect(badge, findsNothing);

    await runDb(
      tester,
      () => container
          .read(dayContextRepositoryProvider)
          .save(isoDateString(date), DayContextKind.office, null),
    );
    await settle(tester);

    expect(badge, findsOneWidget);
    expect(find.text('Office'), findsOneWidget);

    await runDb(
      tester,
      () => container
          .read(dayContextRepositoryProvider)
          .save(isoDateString(date), DayContextKind.travel, null),
    );
    await settle(tester);

    expect(badge, findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('Office'), findsNothing);
    await finish(tester, container);
  });

  testWidgets(
    'fill and save the daily review persists it and refreshes stats',
    (tester) async {
      final container = await pumpReview(tester);

      await tester.enterText(
        find.byKey(const ValueKey('review-note')),
        'Solid focus day',
      );
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('review-save')));
      await settle(tester);
      expect(find.text('Review saved'), findsOneWidget);

      final repo = container.read(reviewRepositoryProvider);
      final saved = await runDb(tester, () => repo.getReviewForDate(today()));
      expect(saved!.reflection, 'Solid focus day');
      expect(saved.energyLevel, isNull);

      final cached = await runDb(
        tester,
        () => container
            .read(appDatabaseProvider)
            .statsDao
            .getStatsForDate(isoDateString(today())),
      );
      expect(cached!.energyLevel, isNull);

      // Re-mounting hydrates the form from the saved row.
      await pumpApp(tester, container, surface: const Size(1400, 1000));
      await settle(tester);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('review-note')),
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

  testWidgets('editing the simplified note preserves legacy review fields', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final repo = container.read(reviewRepositoryProvider);
    await runDb(
      tester,
      () => repo.saveDailyReview(
        DailyReview(
          id: '',
          date: today(),
          reflection: 'Old note',
          energyLevel: 4,
          wins: ['Legacy win'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await tester.tap(find.text('Review').last);
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('review-note')),
      'Updated note',
    );
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await settle(tester);

    final saved = await runDb(tester, () => repo.getReviewForDate(today()));
    expect(saved!.reflection, 'Updated note');
    expect(saved.energyLevel, 4);
    expect(saved.wins, ['Legacy win']);
    await finish(tester, container);
  });

  testWidgets('weekly review shows aggregates and saves the review', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    await seedTwoTasks(tester, container, today());
    await showReviewForToday(tester, container);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('review-mode-switcher')),
        matching: find.text('Weekly'),
      ),
    );
    await settle(tester);

    expect(find.text('Weekly Review'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('1 / 2 completed'), findsOneWidget);
    expect(find.text('What changed this week'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('weekly-note')),
      'Good week overall',
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
    expect(saved!.reflection, 'Good week overall');
    await finish(tester, container);
  });

  testWidgets('review view switches retain the selected planning period', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('review-mode-switcher')),
        matching: find.text('Weekly'),
      ),
    );
    await settle(tester);
    final selectedWeek = addDays(startOfWeek(today()), -7);
    container.read(selectedWeekStartProvider.notifier).state = selectedWeek;
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('week-next')));
    await settle(tester);
    expect(container.read(selectedWeekStartProvider), startOfWeek(today()));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('review-mode-switcher')),
        matching: find.text('Daily'),
      ),
    );
    await settle(tester);

    expect(container.read(selectedReviewDateProvider), startOfWeek(today()));
    expect(find.text('Daily Review'), findsOneWidget);
    await finish(tester, container);
  });
}
