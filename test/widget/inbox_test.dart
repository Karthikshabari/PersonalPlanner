import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/inbox_item.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/inbox/presentation/widgets/overdue_badge.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/providers/day_tasks_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart'
    as date_provider;

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
      find.textContaining(RegExp(r'(Jul|Aug|Sep) \d')),
      findsAtLeastNWidgets(1),
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
            .scheduleItem(
              item.id,
              DateTime(2027, 3, 15, 10),
              DateTime(2027, 3, 15, 11),
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

  testWidgets('Day attention does not remove items from the full Inbox', (
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
    expect(find.text('Schedule'), findsOneWidget);
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
}
