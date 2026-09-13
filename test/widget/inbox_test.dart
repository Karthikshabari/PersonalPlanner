import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
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
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  testWidgets('quick-add creates an inbox item shown in the sidebar', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);

    await tester.enterText(
      find.byKey(const ValueKey('inbox-quick-add')),
      'New idea',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('New idea'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-sidebar')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('quick-add preserves multiline whitespace with Ctrl+Enter', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
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
    expect(find.text('Due today'), findsOneWidget);
    expect(item.startTime, isNull);
    expect(item.endTime, isNull);
    expect(find.byKey(const ValueKey('overdue-badge')), findsNothing);
    await finish(tester, container);
  });

  testWidgets('dragging an inbox item onto the timeline schedules it', (
    tester,
  ) async {
    final container = await pumpDesktop(tester);
    final item = await runDb(
      tester,
      () => container.read(inboxRepositoryProvider).addToInbox('Drag me'),
    );
    await settle(tester);

    Finder tileOf(Task t) => find.byKey(ValueKey('inbox-item-${t.id}'));
    expect(tileOf(item), findsOneWidget);

    final startPt = tester.getCenter(tileOf(item));
    final target = tester
        .getCenter(find.byKey(const ValueKey('timeline-gestures')))
        .translate(-100, -60);
    final stepDelta = (target - startPt) / 8;

    final gesture = await tester.startGesture(
      startPt,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 120));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(stepDelta);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await settle(tester);

    expect(find.text('Schedule Inbox capture'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('quick-create-input')),
      'Prepare proposal',
    );
    await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
    await settle(tester);

    final tasks = await dayTasks(tester, container);
    expect(tasks, hasLength(1));
    final scheduled = tasks.single;
    expect(scheduled.title, 'Prepare proposal');
    expect(scheduled.isInbox, isFalse);
    expect(scheduled.planTitleHistory, isEmpty);
    expect(scheduled.displayPlanChangeId, isNull);
    expect(scheduled.startTime!.day, viewDay.day);
    // One grid slot (default 60 min), snapped to the grid boundary.
    expect(scheduled.scheduledDuration, const Duration(hours: 1));
    expect(scheduled.startTime!.minute % 60, 0);
    await finish(tester, container);
  });

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

    Finder tileOf(Task t) => find.byKey(ValueKey('inbox-item-${t.id}'));

    final startPt = tester.getCenter(tileOf(original));
    final target = tester
        .getCenter(find.byKey(const ValueKey('timeline-gestures')))
        .translate(-100, -60);
    final stepDelta = (target - startPt) / 8;

    final gesture = await tester.startGesture(startPt);
    await tester.pump(const Duration(milliseconds: 120));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(stepDelta);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await settle(tester);

    expect(find.text('Reschedule overdue task'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
    await settle(tester);

    final reloadedOriginal = await taskById(tester, container, original.id);
    expect(reloadedOriginal!.status, TaskStatus.rescheduled);
    expect(reloadedOriginal.rescheduledToId, isNotNull);

    final copy = await taskById(
      tester,
      container,
      reloadedOriginal.rescheduledToId!,
    );
    expect(copy, isNotNull);
    expect(copy!.rescheduledFromId, original.id);
    expect(copy.status, TaskStatus.planned);
    expect(copy.startTime!.day, viewDay.day);
    expect(copy.scheduledDuration, const Duration(hours: 1));

    // The copy appears on today's (viewed) timeline.
    final viewedTasks = await dayTasks(tester, container);
    expect(viewedTasks.map((t) => t.id), contains(copy.id));

    // The original remains visible on its ORIGINAL date as "Rescheduled".
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
}
