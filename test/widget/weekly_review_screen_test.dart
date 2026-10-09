import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

void main() {
  DateTime thisWeek() => startOfWeek(DateTime.now());

  // Disposing a reactive-stats provider mid-test starts an async onCancel in
  // the FakeAsync zone; give it real time so database.close() in finish()
  // does not hang.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  Future<ProviderContainer> pumpWeekly(
    WidgetTester tester, {
    Size surface = const Size(1400, 1000),
    Future<void> Function(ProviderContainer container)? seed,
  }) async {
    final container = await buildTestContainer(tester);
    if (seed != null) await runDb(tester, () => seed(container));
    appRouter.go('/review/weekly');
    await pumpApp(tester, container, surface: surface);
    await settle(tester);
    return container;
  }

  Future<void> addTask(
    ProviderContainer container,
    String title,
    int dayOffset, {
    TaskStatus status = TaskStatus.planned,
  }) async {
    final start = addDays(thisWeek(), dayOffset).add(const Duration(hours: 9));
    await container
        .read(taskRepositoryProvider)
        .insertTask(
          Task(
            id: '',
            title: title,
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            status: status,
            createdAt: start,
            updatedAt: start,
          ),
        );
  }

  Future<void> seedWeek(ProviderContainer container) async {
    await addTask(container, 'Write report', 0, status: TaskStatus.completed);
    await addTask(container, 'Gym session', 0, status: TaskStatus.skipped);
    await addTask(container, 'Read docs', 1);
  }

  double top(WidgetTester tester, String key) =>
      tester.getTopLeft(find.byKey(ValueKey(key))).dy;

  testWidgets('wide: header, sub-tabs, glance and two columns', (tester) async {
    final container = await pumpWeekly(tester, seed: seedWeek);

    expect(find.text('Weekly Review'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('Not reviewed'), findsWidgets);
    expect(find.text('Review'), findsWidgets);
    expect(find.text('Next week (optional)'), findsOneWidget);
    expect(find.text('Week at a glance'), findsOneWidget);
    expect(find.text('33% completed'), findsOneWidget);
    expect(find.text('1 of 3 tasks · 1 skipped'), findsOneWidget);
    expect(find.text('What got in the way'), findsOneWidget);
    expect(find.text('Task outcomes'), findsOneWidget);
    expect(find.text('How was the week?'), findsOneWidget);
    expect(find.text('How did the week feel?'), findsOneWidget);
    expect(find.text('Your week'), findsOneWidget);
    expect(find.text('Save your review to reveal your week.'), findsOneWidget);
    expect(find.text('What changed this week'), findsNothing);
    expect(find.textContaining('planned'), findsNothing);

    final reasonsLeft = tester.getTopLeft(find.text('What got in the way')).dx;
    final moodLeft = tester.getTopLeft(find.text('How was the week?')).dx;
    expect(moodLeft, greaterThan(reasonsLeft));
    expect(
      tester.getTopLeft(find.text('Task outcomes')).dy,
      greaterThan(tester.getTopLeft(find.text('What got in the way')).dy),
    );
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('narrow: one column in the spec order', (tester) async {
    final container = await pumpWeekly(
      tester,
      surface: const Size(390, 844),
      seed: seedWeek,
    );

    final order = [
      top(tester, 'weekly-glance-headline'),
      tester.getTopLeft(find.text('What got in the way')).dy,
      top(tester, 'weekly-outcomes-count'),
      top(tester, 'weekly-mood-1'),
      top(tester, 'weekly-reveal'),
      top(tester, 'weekly-feeling'),
    ];
    expect(order, orderedEquals([...order]..sort()));
    expect(tester.getTopLeft(find.text('How was the week?')).dx, lessThan(40));
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('last week note and mood open this week', (tester) async {
    final container = await pumpWeekly(
      tester,
      seed: (container) async {
        await seedWeek(container);
        await container
            .read(reviewRepositoryProvider)
            .saveWeeklyReviewDraft(
              weekStart: addDays(thisWeek(), -7),
              mood: 2,
              feeling: 'Busy',
              note: 'Start with the hardest task before 11.',
            );
      },
    );

    expect(find.text('From last week'), findsOneWidget);
    expect(
      find.text('"Start with the hardest task before 11."'),
      findsOneWidget,
    );
    expect(find.text('Last week: Great'), findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('a renamed, rescheduled task is one outcome row', (tester) async {
    final container = await pumpWeekly(
      tester,
      seed: (container) async {
        final start = thisWeek().add(const Duration(hours: 9));
        final event = PlanTitleChange(
          id: '00000000-0000-7000-8000-0000000005b1',
          previousTitle: 'Refactor tests',
          newTitle: 'Refactor sync tests',
          changedAt: DateTime.now().toUtc(),
        );
        final repo = container.read(taskRepositoryProvider);
        await repo.insertTask(
          Task(
            id: '00000000-0000-7000-8000-0000000005a2',
            title: 'Refactor sync tests',
            startTime: addDays(start, 1),
            endTime: addDays(start, 1).add(const Duration(hours: 1)),
            createdAt: start,
            updatedAt: start,
          ),
        );
        await repo.insertTask(
          Task(
            id: '00000000-0000-7000-8000-0000000005a1',
            title: 'Refactor sync tests',
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            status: TaskStatus.rescheduled,
            rescheduledToId: '00000000-0000-7000-8000-0000000005a2',
            planTitleHistory: [event],
            displayPlanChangeId: event.id,
            createdAt: start,
            updatedAt: start,
          ),
        );
      },
    );

    expect(find.text('Skipped or rescheduled · 1'), findsOneWidget);
    expect(find.text('Refactor tests'), findsOneWidget);
    expect(find.text('Rescheduled'), findsOneWidget);
    expect(find.textContaining('Added during the week'), findsNothing);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('Next week tab: starters, blocker line and preview', (
    tester,
  ) async {
    final container = await pumpWeekly(tester, seed: seedWeek);

    await tester.tap(find.text('Next week (optional)'));
    await settle(tester);
    expect(find.text('A note for next week'), findsOneWidget);
    expect(
      find.text("Optional. It appears at the top of next week's review."),
      findsOneWidget,
    );
    expect(find.text('No blockers recorded this week.'), findsOneWidget);
    expect(
      find.text("Nothing set. Next week's review will start without a note."),
      findsOneWidget,
    );

    await tester.tap(find.text('Protect time for…'));
    await settle(tester);
    final note = find.byKey(const ValueKey('weekly-note'));
    expect(
      tester.widget<TextField>(note).controller!.text,
      'Protect time for ',
    );

    await tester.tap(find.text('Say no to…'));
    await settle(tester);
    expect(
      tester.widget<TextField>(note).controller!.text,
      'Protect time for ',
    );

    await tester.enterText(note, 'Protect time for deep work');
    await settle(tester);
    expect(find.text('"Protect time for deep work"'), findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('Save writes mood, feeling and note', (tester) async {
    final container = await pumpWeekly(tester, seed: seedWeek);

    await tester.tap(find.byKey(const ValueKey('weekly-mood-3')));
    await settle(tester);
    await tester.ensureVisible(find.text('Focused'));
    await settle(tester);
    await tester.tap(find.text('Focused'));
    await settle(tester);
    await tester.ensureVisible(find.text('Next week (optional)'));
    await settle(tester);
    await tester.tap(find.text('Next week (optional)'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('weekly-note')),
      'Keep doing reviews',
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('weekly-save')));
    await settle(tester);

    final WeeklyReview? saved = await runDb(
      tester,
      () => container
          .read(reviewRepositoryProvider)
          .getWeeklyReviewForWeek(thisWeek()),
    );
    expect(saved!.mood, 3);
    expect(saved.feeling, 'Focused');
    expect(saved.reflection, 'Keep doing reviews');
    expect(find.text('Review saved'), findsOneWidget);
    expect(find.text('Reviewed · Excellent'), findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('an old review without a mood reads Reviewed, Good preselected', (
    tester,
  ) async {
    final container = await pumpWeekly(
      tester,
      seed: (container) async {
        await container.read(appDatabaseProvider).customStatement(
          'INSERT INTO weekly_reviews(id, week_start_date, reflection, '
          "created_at, updated_at) VALUES ('old-weekly', ?, 'Old note', "
          "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
          [isoDateString(thisWeek())],
        );
      },
    );
    final handle = tester.ensureSemantics();

    expect(find.text('Reviewed'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('weekly-mood-1'))),
      isSemantics(label: 'Good', hasCheckedState: true, isChecked: true),
    );
    handle.dispose();
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('a future week hides the status chip', (tester) async {
    final container = await pumpWeekly(tester);
    container.read(selectedWeekStartProvider.notifier).state = addDays(
      thisWeek(),
      14,
    );
    await settle(tester);
    await drainDisposedStreams(tester);

    expect(find.text('This week has not happened yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-status-chip')), findsNothing);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });
}
