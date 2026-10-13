import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/models/inbox_item.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/inbox/presentation/widgets/overdue_badge.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/inbox/presentation/widgets/inbox_badge.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/day_tasks_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart'
    as date_provider;

import '../helpers/inbox_screen_harness.dart';
import '../helpers/test_container.dart';

final DateTime viewDay = DateTime(2027, 3, 15);

Future<Task> insertTask(
  WidgetTester tester,
  ProviderContainer container,
  Task task,
) async {
  final created = await runDb(
    tester,
    () => container.read(taskRepositoryProvider).insertTask(task),
  );
  await settle(tester);
  return created;
}

Future<List<Task>> dayTasks(
  WidgetTester tester,
  ProviderContainer container,
) async {
  List<Task>? data;
  for (var i = 0; i < 150; i++) {
    data = container.read(dayTasksProvider).value;
    if (data != null && data.isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 20));
  }
  await settle(tester);
  return data ?? const <Task>[];
}

Future<Task?> taskById(
  WidgetTester tester,
  ProviderContainer container,
  String id,
) async {
  final tasks = await runDb(
    tester,
    () => container.read(taskRepositoryProvider).getTaskById(id),
  );
  return tasks;
}

void main() {
  Future<ProviderContainer> pumpDesktop(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    container.read(date_provider.selectedDateProvider.notifier).state = viewDay;
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  testWidgets('quick-add creates an inbox item in the dedicated Inbox screen', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    appRouter.go('/inbox');
    await settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('inbox-quick-add')),
      'New idea',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('New idea'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-sidebar')), findsNothing);
    await finish(tester, container);
  });

  testWidgets('quick-add preserves multiline whitespace with Ctrl+Enter', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    appRouter.go('/inbox');
    await settle(tester);
    const raw = '  First paragraph\n\n\tIndented second paragraph  ';

    await tester.enterText(find.byKey(const ValueKey('inbox-quick-add')), raw);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await settle(tester);

    final item = (await runDb(
      tester,
      () => container.read(inboxRepositoryProvider).watchInboxItems().first,
    )).single;
    expect(item.task.description, raw);
    expect(item.task.title, 'Inbox capture');
    expect(item.displayPreview, 'First paragraph');
    await finish(tester, container);
  });

  testWidgets('overdue scheduled task surfaces with amber badge', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await insertTask(
      tester,
      container,
      Task(
        id: '',
        title: 'Overdue thing',
        startTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 8),
        endTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 9),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    expect(find.byKey(const ValueKey('overdue-badge')), findsOneWidget);
    expect(find.text('Overdue thing'), findsOneWidget);
    // Badge shows the original date (medium date without year part).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('overdue-badge')),
        matching: find.text(DateFormat('MMM d').format(yesterday)),
      ),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets('overdue badge renders missed UTC minute in planner timezone', (
    tester,
  ) async {
    PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');
    final task = Task(
      id: 'badge-task',
      title: 'Badge task',
      missedAt: '2026-09-14T18:30',
      createdAt: DateTime.utc(2026, 9, 14),
      updatedAt: DateTime.utc(2026, 9, 14),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OverdueBadge(item: InboxItem.overdue(task))),
      ),
    );

    expect(find.text('Missed Sep 15 00:00'), findsOneWidget);
  });

  testWidgets('Inbox due date is shown separately from missed schedule', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    final now = DateTime.now();
    final due =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final item = await runDb(
      tester,
      () => container
          .read(inboxRepositoryProvider)
          .addToInbox('Due capture', dueDate: due),
    );
    await settle(tester);

    expect(find.byKey(const ValueKey('due-date-badge')), findsOneWidget);
    expect(find.text('Due today'), findsWidgets);
    expect(item.startTime, isNull);
    expect(item.endTime, isNull);
    expect(find.byKey(const ValueKey('overdue-badge')), findsNothing);
    await finish(tester, container);
  });

  testWidgets(
    'Day omits Inbox tiles while scheduling preserves the task flow',
    (tester) async {
      final container = await pumpDesktop(tester);
      final item = await runDb(
        tester,
        () => container.read(inboxRepositoryProvider).addToInbox('Drag me'),
      );
      await settle(tester);
      expect(container.read(date_provider.selectedDateProvider), viewDay);

      Finder tileOf(Task t) => find.byKey(ValueKey('inbox-item-${t.id}'));
      expect(tileOf(item), findsNothing);

      final scheduled = await runDb(
        tester,
        () => container
            .read(inboxRepositoryProvider)
            .createSession(
              item.id,
              DateTime(2027, 3, 15, 10),
              DateTime(2027, 3, 15, 11),
              now: DateTime.now(),
              title: 'Prepare proposal',
            ),
      );
      await settle(tester);

      final tasks = await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .watchTasksForDay(viewDay)
            .first,
      );
      expect(tasks, hasLength(1));
      final shown = tasks.single;
      expect(shown.id, scheduled.id);
      expect(shown.title, 'Prepare proposal');
      expect(shown.isInbox, isFalse);
      expect(shown.planTitleHistory, isEmpty);
      expect(shown.displayPlanChangeId, isNull);
      expect(shown.startTime!.day, viewDay.day);
      // One grid slot (default 60 min), snapped to the grid boundary.
      expect(scheduled.scheduledDuration, const Duration(hours: 1));
      expect(scheduled.startTime!.minute % 60, 0);
      await finish(tester, container);
    },
  );

  testWidgets('dropping an overdue item reschedules with a linked copy', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    final yesterday = DateTime.now().subtract(const Duration(days: 2));
    final original = await insertTask(
      tester,
      container,
      Task(
        id: '',
        title: 'Stale work',
        startTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 8),
        endTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 9),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await settle(tester);

    final copy = await runDb(
      tester,
      () => container
          .read(inboxRepositoryProvider)
          .rescheduleOverdue(
            original.id,
            DateTime(2027, 3, 15, 10),
            DateTime(2027, 3, 15, 11),
          ),
    );
    await settle(tester);

    final reloadedOriginal = await taskById(tester, container, original.id);
    expect(reloadedOriginal!.status, TaskStatus.rescheduled);
    expect(reloadedOriginal.rescheduledToId, isNotNull);

    expect(copy.id, reloadedOriginal.rescheduledToId);
    expect(copy.rescheduledFromId, original.id);
    expect(copy.status, TaskStatus.planned);
    expect(copy.startTime!.day, viewDay.day);
    expect(copy.scheduledDuration, const Duration(hours: 1));

    // The copy appears on today's (viewed) timeline.
    container.invalidate(dayTasksProvider);
    container.invalidate(activeDayTasksProvider);
    await settle(tester);
    final viewedTasks = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .watchTasksForDay(viewDay)
          .first,
    );
    expect(viewedTasks.map((t) => t.id), contains(copy.id));

    // The historical predecessor remains persisted on its original date, but
    // it is no longer an active timeline block.
    container.read(date_provider.selectedDateProvider.notifier).state =
        DateTime(yesterday.year, yesterday.month, yesterday.day);
    await settle(tester);
    final originalDayTasks = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .watchTasksForDay(
            DateTime(yesterday.year, yesterday.month, yesterday.day),
          )
          .first,
    );
    final shown = originalDayTasks.singleWhere((t) => t.id == original.id);
    expect(shown.status, TaskStatus.rescheduled);
    expect(find.byKey(ValueKey('task-block-${original.id}')), findsNothing);

    await finish(tester, container);
  });

  testWidgets('mobile inbox tab lists items and quick-adds', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(600, 1000));

    // Go to the Inbox tab via bottom navigation.
    await tester.tap(find.text('Inbox').last);
    await settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('inbox-quick-add')),
      'Mobile idea',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('Mobile idea'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-quick-add')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Day attention does not remove ideas from the Inbox screen', (
    tester,
  ) async {
    final fixedNow = DateTime.utc(2026, 9, 16, 6, 30);
    final container = await buildTestContainer(
      tester,
      minuteClockFactory: () => Stream.value(fixedNow),
    );
    final inbox = container.read(inboxRepositoryProvider);
    await runDb(tester, () => inbox.addToInbox('No due date'));
    await runDb(
      tester,
      () => inbox.addToInbox('Due today', dueDate: '2026-09-16'),
    );
    await runDb(
      tester,
      () => inbox.addToInbox('Next week', dueDate: '2026-09-21'),
    );
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await settle(tester);

    expect(find.text('No due date'), findsNothing);
    expect(find.text('Due today'), findsWidgets);
    expect(find.text('Next week'), findsNothing);

    appRouter.go('/inbox');
    await settle(tester);
    expect(find.text('No due date'), findsOneWidget);
    expect(find.text('Due today'), findsWidgets);
    expect(find.text('Next week'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Inbox item menu deletes through the task soft-delete flow', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    appRouter.go('/inbox');
    await settle(tester);
    final first = await runDb(
      tester,
      () => container.read(inboxRepositoryProvider).addToInbox('Delete me'),
    );
    final second = await runDb(
      tester,
      () => container.read(inboxRepositoryProvider).addToInbox('Keep me'),
    );
    await settle(tester);

    final firstMenu = find.byKey(ValueKey('inbox-menu-${first.id}'));
    await tester.tap(firstMenu);
    await settle(tester);
    expect(find.text('Edit'), findsOneWidget);
    // Dates are given in the dates panel, not from this menu.
    expect(find.text('Schedule'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete task?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.byKey(ValueKey('inbox-item-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('inbox-item-${second.id}')), findsOneWidget);

    final deleted = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(first.id),
    );
    final retained = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(second.id),
    );
    expect(deleted?.deletedAt, isNotNull);
    expect(retained?.deletedAt, isNull);
    await finish(tester, container);
  });

  // UAT F-006: the delete confirmation names what the user sees and where.
  testWidgets('deleting an Inbox capture names it and says Inbox', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    appRouter.go('/inbox');
    await settle(tester);
    final capture = await runDb(
      tester,
      () => container
          .read(inboxRepositoryProvider)
          .addToInbox('Call the plumber\nabout the leak'),
    );
    await settle(tester);

    await tester.tap(find.byKey(ValueKey('inbox-menu-${capture.id}')));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(
      find.text(
        '"Call the plumber" will be removed from your Inbox.\n'
        'You can undo this with Ctrl+Z.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Inbox capture'), findsNothing);
    expect(find.textContaining('the timeline'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    final deleted = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(capture.id),
    );
    expect(deleted?.deletedAt, isNotNull);
    await finish(tester, container);
  });

  testWidgets('deleting a scheduled task still names its title and timeline', (
    tester,
  ) async {
    // Desktop: the block opens its context menu on right-click.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await pumpDesktop(tester);
    final start = DateTime(viewDay.year, viewDay.month, viewDay.day, 9);
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Planned block',
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              estimatedDurationMin: 60,
              createdAt: start,
              updatedAt: start,
            ),
          ),
    );
    await settle(tester);

    await tester.tap(
      find.byKey(ValueKey('task-block-${task.id}')),
      buttons: kSecondaryMouseButton,
    );
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);

    expect(
      find.text(
        '"Planned block" will be removed from the timeline.\n'
        'You can undo this with Ctrl+Z.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await finish(tester, container);
  });

  // -----------------------------------------------------------------------
  // The new Inbox screen (Phase 4). Fixed clock: Monday 2026-10-12 12:00 in
  // the planner zone, so "today" is the 12th.
  // -----------------------------------------------------------------------

  group('new Inbox screen', () {
    testWidgets('capture adds an idea under Ideas and has no due date', (
      tester,
    ) async {
      final (container, _) = await pumpInbox(tester);
      expect(find.text('Nothing open. Type an idea above.'), findsOneWidget);
      expect(find.text('Open (0)'), findsOneWidget);
      expect(find.text('Done (0)'), findsOneWidget);
      expect(find.text('Dropped (0)'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('inbox-quick-add')),
        'Buy SAP book',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(find.byKey(const ValueKey('inbox-section-Ideas')), findsOneWidget);
      expect(find.text('Buy SAP book'), findsOneWidget);
      expect(find.text('Open (1)'), findsOneWidget);
      // A capture has no date: dates come later as sessions.
      expect(find.byKey(const ValueKey('inbox-due-date')), findsNothing);
      expect(find.text('Add due date'), findsNothing);
      await finish(tester, container);
    });

    testWidgets('the edit dialog has no due date control', (tester) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async => idea = await h.idea('Edit me'),
      );
      await tester.tap(find.byKey(ValueKey('inbox-menu-${idea.id}')));
      await settle(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(find.text('Edit Inbox capture'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-due-date')), findsNothing);
      expect(find.text('Add due date'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await finish(tester, container);
    });

    testWidgets('counts, section order and the Done and Dropped chips', (
      tester,
    ) async {
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          await h.idea('Plain idea');
          final coming = await h.idea('Coming idea');
          await h.session(coming.id, start: h.at(2, 9));
          final left = await h.idea('Left idea');
          await h.session(left.id, start: h.at(-2, 9));
          final finished = await h.idea('Finished idea');
          await h.session(
            finished.id,
            start: h.at(-3, 9),
            status: TaskStatus.completed,
          );
          final closed = await h.idea('Closed idea');
          await h.inbox.closeItem(closed.id, 'Not needed', h.now);
        },
      );
      expect(find.text('Open (3)'), findsOneWidget);
      expect(find.text('Done (1)'), findsOneWidget);
      expect(find.text('Dropped (1)'), findsOneWidget);

      double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      expect(
        top('inbox-section-Left over'),
        lessThan(top('inbox-section-Ideas')),
      );
      expect(
        top('inbox-section-Ideas'),
        lessThan(top('inbox-section-Coming up')),
      );
      expect(find.text('Finished idea'), findsNothing);
      expect(find.text('Closed idea'), findsNothing);
      // The Left over row says when it was missed.
      expect(find.text('Missed Sat, Oct 10 · 09:00'), findsOneWidget);
      expect(find.text('Next Wed, Oct 14 · 09:00 · 1 session'), findsOneWidget);

      await pickSegment(tester, 'Done (1)');
      expect(find.text('Finished idea'), findsOneWidget);
      expect(find.text('Closed idea'), findsNothing);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Plain idea'), findsNothing);

      await pickSegment(tester, 'Dropped (1)');
      expect(find.text('Closed idea'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Finished idea'), findsNothing);
      expect(find.text('Plain idea'), findsNothing);
      await finish(tester, container);
    });

    testWidgets('only one row is expanded at a time', (tester) async {
      late Task first;
      late Task second;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          first = await h.idea('First idea');
          second = await h.idea('Second idea');
        },
      );
      await expandRow(tester, first.id);
      expect(trailOf(first.id), findsOneWidget);
      expect(trailOf(second.id), findsNothing);

      await expandRow(tester, second.id);
      expect(trailOf(first.id), findsNothing);
      expect(trailOf(second.id), findsOneWidget);

      await expandRow(tester, second.id);
      expect(trailOf(second.id), findsNothing);
      await finish(tester, container);
    });

    testWidgets('the trail shows badges, Review reasons and the break day', (
      tester,
    ) async {
      late Task idea;
      late Task withReason;
      late Task noReason;
      late Task onBreak;
      late Task upcoming;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Sort the garage');
          await h.session(
            idea.id,
            start: h.at(-3, 9),
            status: TaskStatus.completed,
          );
          withReason = await h.session(idea.id, start: h.at(-2, 9));
          noReason = await h.session(idea.id, start: h.at(-1, 9));
          onBreak = await h.session(idea.id, start: h.at(-4, 9));
          upcoming = await h.session(idea.id, start: h.at(2, 9));
          await h.saveReviewReason('2026-10-10', {withReason.id: 'Ran late'});
          await DayContextRepository(h.db)
              .save(isoDateString(h.at(-4, 0)), DayContextKind.holiday, null);
        },
      );
      await expandRow(tester, idea.id);

      String reasonText(Task session) => tester
          .widget<Text>(
            find.byKey(ValueKey('inbox-session-reason-${session.id}')),
          )
          .data!;
      expect(reasonText(withReason), 'Reason: Ran late');
      expect(
        reasonText(noReason),
        'No reason yet. Reasons are written in Review.',
      );
      expect(reasonText(onBreak), 'Break day. No reason needed.');
      expect(
        find.byKey(ValueKey('inbox-session-reason-${upcoming.id}')),
        findsNothing,
      );

      Finder badge(String label) => find.descendant(
        of: trailOf(idea.id),
        matching: find.widgetWithText(InboxBadge, label),
      );
      expect(badge('Missed'), findsNWidgets(3));
      expect(badge('Done'), findsOneWidget);
      expect(badge('Coming up'), findsOneWidget);
      // Every session that is still on Day can be opened there.
      expect(find.text('Open in Day'), findsNWidgets(5));
      // The Inbox only reads reasons: no field to type one.
      expect(
        find.descendant(of: trailOf(idea.id), matching: find.byType(TextField)),
        findsNothing,
      );
      await finish(tester, container);
    });

    testWidgets('Open in Day selects the session on Day', (tester) async {
      late Task idea;
      late Task session;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Plan the trip');
          session = await h.session(idea.id, start: h.at(2, 9));
        },
      );
      await expandRow(tester, idea.id);
      await tester.tap(find.byKey(ValueKey('inbox-open-day-${session.id}')));
      await settle(tester);

      expect(container.read(selectedTaskIdProvider), session.id);
      expect(container.read(taskEditorOpenProvider), isTrue);
      expect(
        isoDateString(container.read(date_provider.selectedDateProvider)),
        isoDateString(h.at(2, 9)),
      );
      expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/day');
      await finish(tester, container);
    });

    testWidgets(
      'Close it needs typed text, stores it trimmed, moves to Dropped',
      (tester) async {
        late Task idea;
        late Task missed;
        final (container, h) = await pumpInbox(
          tester,
          seed: (h) async {
            idea = await h.idea('Call the bank');
            missed = await h.session(idea.id, start: h.at(-1, 9));
          },
        );
        expect(find.text('Open (1)'), findsOneWidget);
        await expandRow(tester, idea.id);
        await tester.tap(find.byKey(const ValueKey('inbox-action-close')));
        await settle(tester);

        expect(find.text('Why are you closing it?'), findsOneWidget);
        expect(
          find.text(
            'Sessions not started yet are removed from Day. '
            'Missed ones stay in Review.',
          ),
          findsOneWidget,
        );
        // Typed text only: no presets, no suggestions.
        for (final chip in [ActionChip, ChoiceChip, FilterChip, InputChip]) {
          expect(find.byType(chip), findsNothing);
        }
        expect(submitEnabled(tester), isFalse);
        await tester.enterText(
          find.byKey(const ValueKey('inbox-reason-field')),
          '   ',
        );
        await tester.pump();
        expect(submitEnabled(tester), isFalse);
        await tester.enterText(
          find.byKey(const ValueKey('inbox-reason-field')),
          'x',
        );
        await tester.pump();
        expect(submitEnabled(tester), isTrue);

        await tester.enterText(
          find.byKey(const ValueKey('inbox-reason-field')),
          '  Not needed  ',
        );
        await tester.tap(find.byKey(const ValueKey('inbox-panel-submit')));
        await settle(tester);

        final stored = await runDb(tester, () => h.reload(idea.id));
        expect(stored.inboxHistory.single.kind, InboxCloseKind.closed);
        expect(stored.inboxHistory.single.reason, 'Not needed');
        final session = await runDb(tester, () => h.reload(missed.id));
        expect(session.status, TaskStatus.skipped);

        expect(find.text('Open (0)'), findsOneWidget);
        expect(find.text('Done (0)'), findsOneWidget);
        expect(find.text('Dropped (1)'), findsOneWidget);
        await pickSegment(tester, 'Dropped (1)');
        expect(
          find.descendant(of: rowOf(idea.id), matching: find.text('Closed')),
          findsOneWidget,
        );
        // The trail of the row that was open shows the reason, read only.
        expect(find.text('Closed Oct 12 · Not needed'), findsOneWidget);
        await finish(tester, container);
      },
    );

    testWidgets('Let go works on an idea without sessions, reason optional', (
      tester,
    ) async {
      late Task idea;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async => idea = await h.idea('Learn the oboe'),
      );
      await expandRow(tester, idea.id);
      // No session: Let go is the footer action, not Close it.
      expect(find.byKey(const ValueKey('inbox-action-close')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('inbox-action-let-go')));
      await settle(tester);

      expect(find.text('Reason (optional)'), findsOneWidget);
      expect(submitEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('inbox-panel-submit')));
      await settle(tester);

      final stored = await runDb(tester, () => h.reload(idea.id));
      expect(stored.inboxHistory.single.kind, InboxCloseKind.letGo);
      expect(stored.inboxHistory.single.reason, isNull);
      await pickSegment(tester, 'Dropped (1)');
      expect(
        find.descendant(of: rowOf(idea.id), matching: find.text('Let go')),
        findsOneWidget,
      );
      await finish(tester, container);
    });

    testWidgets('an idea with session history is closed, not let go', (
      tester,
    ) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Tidy the shed');
          await h.session(
            idea.id,
            start: h.at(-1, 9),
            status: TaskStatus.skipped,
          );
        },
      );
      await expandRow(tester, idea.id);
      expect(find.byKey(const ValueKey('inbox-action-close')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-action-let-go')), findsNothing);
      await finish(tester, container);
    });

    testWidgets('Bring back returns the idea to Ideas with its old events', (
      tester,
    ) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Learn the oboe');
          await h.inbox.letGo(idea.id, 'Not now', h.now);
        },
      );
      await pickSegment(tester, 'Dropped (1)');
      await expandRow(tester, idea.id);
      expect(find.text('Let go Oct 12 · Not now'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inbox-action-bring-back')));
      await settle(tester);

      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Dropped (0)'), findsOneWidget);
      await pickSegment(tester, 'Open (1)');
      expect(find.byKey(const ValueKey('inbox-section-Ideas')), findsOneWidget);
      expect(rowOf(idea.id), findsOneWidget);
      // The open row keeps its trail, with the close and the bring back.
      expect(find.text('Let go Oct 12 · Not now'), findsOneWidget);
      expect(find.text('Brought back Oct 12'), findsOneWidget);
      await finish(tester, container);
    });

    testWidgets(
      'the reason field stops at 200 UTF-16 units and shows a counter',
      (tester) async {
        late Task idea;
        final (container, _) = await pumpInbox(
          tester,
          seed: (h) async {
            idea = await h.idea('Long reasons');
            await h.session(idea.id, start: h.at(-1, 9));
          },
        );
        await expandRow(tester, idea.id);
        await tester.tap(find.byKey(const ValueKey('inbox-action-close')));
        await settle(tester);

        final field = find.byKey(const ValueKey('inbox-reason-field'));
        String text() => tester.widget<TextField>(field).controller!.text;
        await tester.enterText(field, 'a' * 250);
        await tester.pump();
        expect(text().length, 200);
        expect(find.text('200/200'), findsOneWidget);

        // An emoji is two units and is never split: 199 + 2 does not fit.
        await tester.enterText(field, '${'a' * 199}\u{1F600}');
        await tester.pump();
        expect(text().length, 199);

        await tester.enterText(field, 'a' * 10);
        await tester.pump();
        expect(find.textContaining('/200'), findsNothing);
        await tester.enterText(field, 'a' * 182);
        await tester.pump();
        expect(find.text('182/200'), findsOneWidget);
        await finish(tester, container);
      },
    );

    testWidgets('keyboard: Enter opens, Ctrl+Enter submits, Esc steps back', (
      tester,
    ) async {
      // Desktop: the planner's own Enter ("edit") and Space ("cycle status")
      // shortcuts are live and must not swallow the row's activation.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      late Task idea;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Keyboard idea');
          await h.session(idea.id, start: h.at(-1, 9));
        },
      );
      tester.widget<InkWell>(headerOf(idea.id)).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(trailOf(idea.id), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(trailOf(idea.id), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('inbox-action-close')));
      await settle(tester);
      // Esc closes the panel first, then the trail.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(const ValueKey('inbox-close-panel')), findsNothing);
      expect(trailOf(idea.id), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(trailOf(idea.id), findsNothing);

      await expandRow(tester, idea.id);
      await tester.tap(find.byKey(const ValueKey('inbox-action-close')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('inbox-reason-field')),
        'Done with it',
      );
      await ctrlEnter(tester);
      final stored = await runDb(tester, () => h.reload(idea.id));
      expect(stored.inboxHistory.single.reason, 'Done with it');
      await finish(tester, container);
    });

    testWidgets('the Review line counts sessions and opens Review', (
      tester,
    ) async {
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          final a = await h.idea('First errand');
          await h.session(a.id, start: h.at(-2, 9));
          final b = await h.idea('Second errand');
          await h.session(b.id, start: h.at(-1, 9));
        },
      );
      expect(
        find.text(
          '2 missed sessions from the Inbox have no reason yet. '
          'Reasons are written in Review.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('inbox-open-review')));
      await settle(tester);

      // The most recent date with a missing reason.
      expect(
        isoDateString(container.read(selectedReviewDateProvider)),
        '2026-10-11',
      );
      expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/review');
      await finish(tester, container);
    });

    testWidgets('the Review line says "1 missed session"', (tester) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Only errand');
          await h.session(idea.id, start: h.at(-1, 9));
        },
      );
      expect(
        find.text(
          '1 missed session from the Inbox has no reason yet. '
          'Reasons are written in Review.',
        ),
        findsOneWidget,
      );
      await finish(tester, container);
    });

    testWidgets('the Review line is hidden when every reason is saved', (
      tester,
    ) async {
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          final fine = await h.idea('Reasoned errand');
          final s = await h.session(fine.id, start: h.at(-1, 9));
          await h.saveReviewReason('2026-10-11', {s.id: 'Sick'});
        },
      );
      expect(find.byKey(const ValueKey('inbox-reason-line')), findsNothing);
      await finish(tester, container);
    });

    testWidgets('Delete is offered while the idea has no live session', (
      tester,
    ) async {
      late Task bare;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async => bare = await h.idea('Bare idea'),
      );
      await tester.tap(find.byKey(ValueKey('inbox-menu-${bare.id}')));
      await settle(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await finish(tester, container);
    });

    testWidgets('Delete is hidden once the idea has a session', (tester) async {
      late Task planned;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          planned = await h.idea('Planned idea');
          await h.session(planned.id, start: h.at(2, 9));
        },
      );
      await tester.tap(find.byKey(ValueKey('inbox-menu-${planned.id}')));
      await settle(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      await finish(tester, container);
    });

    testWidgets('a focus request opens the idea in its segment, then clears', (
      tester,
    ) async {
      late Task open;
      late Task closed;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          open = await h.idea('Open idea');
          closed = await h.idea('Closed idea');
          await h.inbox.letGo(closed.id, null, h.now);
        },
        before: (c) =>
            c.read(inboxFocusItemProvider.notifier).state = closed.id,
      );
      expect(container.read(inboxFocusItemProvider), isNull);
      expect(container.read(inboxExpandedItemProvider), closed.id);
      expect(rowOf(closed.id), findsOneWidget);
      expect(trailOf(closed.id), findsOneWidget);
      expect(rowOf(open.id), findsNothing);

      // A request for an idea in Open switches back.
      container.read(inboxFocusItemProvider.notifier).state = open.id;
      await settle(tester);
      expect(container.read(inboxFocusItemProvider), isNull);
      expect(trailOf(open.id), findsOneWidget);
      expect(rowOf(closed.id), findsNothing);
      await finish(tester, container);
    });

    testWidgets('Dropped shows 30 rows, then 30 more', (tester) async {
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          for (var i = 0; i < 35; i++) {
            final idea = await h.idea('Gone $i');
            await h.inbox.letGo(idea.id, null, h.now);
          }
        },
      );
      expect(find.text('Dropped (35)'), findsOneWidget);
      await pickSegment(tester, 'Dropped (35)');
      final more = find.byKey(const ValueKey('inbox-show-more'));
      await tester.scrollUntilVisible(
        more,
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('inbox-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(more);
      await settle(tester);
      await tester.tap(more);
      await settle(tester);
      expect(more, findsNothing);
      await finish(tester, container);
    });

    testWidgets('a row rebuilds only for its own idea', (tester) async {
      late Task first;
      late Task second;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async {
          first = await h.idea('First idea');
          second = await h.idea('Second idea');
        },
      );
      final rebuilds = <String, int>{};
      var screens = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final name = element.widget.runtimeType.toString();
        if (name == 'InboxScreen') screens++;
        if (name == 'InboxIdeaRow') {
          final id = (element.widget.key! as GlobalKey).toString();
          rebuilds[id] = (rebuilds[id] ?? 0) + 1;
        }
      };
      try {
        final (task, revision) = (await runDb(
          tester,
          () => container
              .read(taskRepositoryProvider)
              .getTaskWithRevision(second.id),
        ))!;
        await runDb(
          tester,
          () => container
              .read(taskRepositoryProvider)
              .updateTask(
                task.copyWith(description: 'Second idea, reworded'),
                expectedRevision: revision,
              ),
        );
        await settle(tester);
        expect(find.text('Second idea, reworded'), findsOneWidget);
        expect(screens, 0, reason: 'the screen watches ids and counts only');
        expect(rebuilds.length, 1, reason: 'only the edited idea rebuilds');
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(h, isNotNull);
      expect(first.id, isNot(second.id));
      await finish(tester, container);
    });
  });
}
