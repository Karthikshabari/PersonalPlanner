import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/theme/app_colors.dart';
import 'package:personal_planner/core/widgets/task_block_widget.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/task_quick_create.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/current_time_indicator.dart';

import '../helpers/test_container.dart';

void main() {
  Future<void> pumpDesktop(WidgetTester tester, ProviderContainer container) =>
      pumpApp(tester, container, surface: const Size(1400, 1000));

  testWidgets('app launches with dark theme and 24-hour grid', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpDesktop(tester, container);
    expect(find.byType(MaterialApp), findsOneWidget);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, AppColors.backgroundDark);
    for (var hour = 0; hour < 24; hour++) {
      expect(
        find.text('${hour.toString().padLeft(2, '0')}:00'),
        findsWidgets,
        reason: 'Hour label $hour:00 missing',
      );
    }
    await teardownApp(tester, container);
  });

  testWidgets('editor shows a neutral prompt when no task is selected', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpDesktop(tester, container);
    expect(find.text('Select a task to edit'), findsOneWidget);
    expect(
      find.text('The selected task is no longer available.'),
      findsNothing,
    );
    await teardownApp(tester, container);
  });

  testWidgets('current time indicator is visible on today', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpDesktop(tester, container);
    expect(find.byType(CurrentTimeIndicator), findsOneWidget);
    await teardownApp(tester, container);
  });

  testWidgets('double-tap empty slot creates task via quick create', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpDesktop(tester, container);
    await doubleTap(tester, find.byKey(const ValueKey('timeline-gestures')));
    await settle(tester);
    expect(find.text('Task title…'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(TaskQuickCreate),
        matching: find.byType(TextField),
      ),
      'Deep Work',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(
      find.descendant(
        of: find.byType(TaskBlockWidget),
        matching: find.text('Deep Work'),
      ),
      findsOneWidget,
    );
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);

    final tasks = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .watchTasksForDay(DateTime.now())
          .first,
    );
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Deep Work');
    expect(tasks.single.status.dbValue, 'planned');
    expect(tasks.single.isInbox, false);
    expect(tasks.single.scheduledDuration, const Duration(hours: 1));
    await teardownApp(tester, container);
  });

  testWidgets('task block renders category color left border', (tester) async {
    final container = await buildTestContainer(tester);
    final categories = await runDb(
      tester,
      () =>
          container.read(categoryRepositoryProvider).watchAllCategories().first,
    );
    final work = categories.firstWhere((c) => c.name == 'Work');
    final now = DateTime.now();
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Categorized',
              startTime: DateTime(now.year, now.month, now.day, 9),
              endTime: DateTime(now.year, now.month, now.day, 10),
              categoryId: work.id,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );
    await pumpDesktop(tester, container);

    final blockFinder = find.byType(TaskBlockWidget);
    expect(blockFinder, findsOneWidget);
    final containers = tester.widgetList<Container>(
      find.descendant(
        of: blockFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    final decorated = containers
        .map((c) => c.decoration! as BoxDecoration)
        .firstWhere((d) => d.border is Border);
    final border = decorated.border! as Border;
    expect(border.left.width, 4);
    expect(border.left.color, AppColors.parseHex('#4285F4'));
    await teardownApp(tester, container);
  });

  testWidgets('tapping a task opens editor panel and saves edits', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final now = DateTime.now();
    final hour = now.hour >= 22 ? 20 : now.hour;
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Editable task',
              startTime: DateTime(now.year, now.month, now.day, hour),
              endTime: DateTime(now.year, now.month, now.day, hour + 1),
              estimatedDurationMin: 60,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );
    await pumpDesktop(tester, container);

    await tester.tap(
      find.descendant(
        of: find.byType(TaskBlockWidget),
        matching: find.text('Editable task'),
      ),
    );
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), inserted.id);
    expect(find.text('Edit Task'), findsOneWidget);

    final titleField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Title',
    );
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, 'Renamed via editor');

    final notesField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Notes',
    );
    await tester.enterText(notesField, 'Some notes');

    // The editor content scrolls (subtasks/tags sections); bring Save into
    // view before tapping.
    final saveButton = find.byKey(const ValueKey('save-task-button'));
    await tester.ensureVisible(saveButton);
    await settle(tester);
    await tester.tap(saveButton);
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
    );
    expect(saved!.title, 'Renamed via editor');
    expect(saved.notes, 'Some notes');
    expect(
      find.descendant(
        of: find.byType(TaskBlockWidget),
        matching: find.text('Renamed via editor'),
      ),
      findsOneWidget,
    );
    await teardownApp(tester, container);
  });

  testWidgets('status cycles Planned -> In Progress -> Completed', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final now = DateTime.now();
    final hour = now.hour >= 22 ? 20 : now.hour;
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Cycle me',
              startTime: DateTime(now.year, now.month, now.day, hour),
              endTime: DateTime(now.year, now.month, now.day, hour + 1),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );
    await pumpDesktop(tester, container);

    expect(find.text('Planned'), findsOneWidget);
    await tester.tap(find.text('Planned'));
    await settle(tester);
    expect(find.text('In Progress'), findsOneWidget);

    await tester.tap(find.text('In Progress'));
    await settle(tester);
    expect(find.text('Completed'), findsOneWidget);

    final tasks = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .watchTasksForDay(DateTime(now.year, now.month, now.day))
          .first,
    );
    expect(tasks.single.status, TaskStatus.completed);
    await teardownApp(tester, container);
  });

  testWidgets('date navigation prev/next/today updates header', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpDesktop(tester, container);
    final todayLabel = DateFormat('MMM d, yyyy')
        .format(DateTime.now())
        .replaceAll(',', '');
    Finder label(String raw) => find.byWidgetPredicate(
      (w) => w is Text && w.data != null && w.data!.replaceAll(',', '') == raw,
    );
    expect(label(todayLabel), findsOneWidget);

    await tester.tap(find.byTooltip('Next day'));
    await settle(tester);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(
      label(DateFormat('MMM d, yyyy').format(tomorrow).replaceAll(',', '')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Previous day'));
    await settle(tester);
    await tester.tap(find.byTooltip('Previous day'));
    await settle(tester);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            w.data!
                .replaceAll(',', '')
                .contains(DateFormat('MMM d').format(yesterday)),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Today'));
    await settle(tester);
    expect(label(todayLabel), findsOneWidget);
    await teardownApp(tester, container);
  });

  testWidgets('timeline auto-scrolls near current time on launch', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpDesktop(tester, container);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final offset = scrollable.position.pixels;
    final nowMinutes = DateTime.now().hour * 60 + DateTime.now().minute;
    const pixelsPerMinute = 64 / 60;
    final maxExtent = scrollable.position.maxScrollExtent;
    final expected = ((nowMinutes - 90) * pixelsPerMinute - 64 * 1.5).clamp(
      0.0,
      maxExtent,
    );
    expect(offset, closeTo(expected, 2.0));
    await teardownApp(tester, container);
  });
}
