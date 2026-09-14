import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  setUp(() {
    // Each test gets a fresh ProviderContainer; reset the global router so a
    // Day route element from the preceding test cannot be reused with a
    // closed container subscription.
    appRouter.go('/day');
  });

  final date = DateTime(2027, 3, 15, 9);

  void requestEditor(ProviderContainer container, String taskId) {
    container.read(selectedTaskIdProvider.notifier).state = taskId;
    container.read(taskEditorOpenProvider.notifier).state = true;
  }

  Future<Task> insertTask(WidgetTester tester, ProviderContainer container) {
    return runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Merge target',
              startTime: date,
              endTime: date.add(const Duration(hours: 1)),
              estimatedDurationMin: 60,
              createdAt: date,
              updatedAt: date,
            ),
          ),
    );
  }

  Future<void> openEditor(
    WidgetTester tester,
    ProviderContainer container,
    Task task,
  ) async {
    await tester.tap(find.byKey(ValueKey('task-block-${task.id}')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('selected-task-edit-${task.id}')));
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), task.id);
  }

  Finder titleField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == 'Title',
  );

  Future<void> save(
    WidgetTester tester, {
    bool replacePlanChange = true,
  }) async {
    final button = find.byKey(const ValueKey('save-task-button'));
    // The editor's task, tags and recurrence providers resolve independently
    // after the selected-task state changes. Under a loaded test process the
    // panel can take more than the generic settle window to mount its actions;
    // wait for the externally visible Save control instead of treating that
    // normal loading interval as a missing widget.
    for (
      var attempt = 0;
      attempt < 30 && button.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(button, findsOneWidget);
    final scrollables = find.ancestor(
      of: button,
      matching: find.byType(Scrollable),
    );
    if (scrollables.evaluate().isNotEmpty) {
      final editorScrollable = scrollables.last;
      for (var attempt = 0; attempt < 12; attempt++) {
        await settle(tester);
        final rect = tester.getRect(button);
        final viewport = tester.getRect(editorScrollable);
        if (rect.top >= viewport.top + 24 &&
            rect.bottom <= viewport.bottom - 24) {
          break;
        }
        final dy = rect.center.dy > viewport.center.dy ? -100.0 : 100.0;
        await tester.drag(editorScrollable, Offset(0, dy));
      }
    }
    await settle(tester);
    await tester.tap(button);
    await settle(tester);
    // Existing editor tests predate R14. A title edit now requires a
    // deliberate choice; these unrelated merge/baseline cases retain their
    // former semantic intent by choosing the non-history replacement path.
    final replace = find.byKey(const ValueKey('plan-change-replace'));
    if (replacePlanChange && replace.evaluate().isNotEmpty) {
      await tester.tap(replace);
      await settle(tester);
    }
  }

  testWidgets('save merges unrelated external changes', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await openEditor(tester, container, task);

    await tester.enterText(titleField(), 'Local title');
    final current = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(current!.copyWith(description: 'External description')),
    );
    await save(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved!.title, 'Local title');
    expect(saved.description, 'External description');
    await finish(tester, container);
  });

  testWidgets('same-field conflict offers reload and keeps latest values', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    await tester.enterText(titleField(), 'Local title');
    final current = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(current!.copyWith(title: 'Remote title')),
    );
    await save(tester);

    expect(find.text('Task changed elsewhere'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reload-task')));
    await settle(tester);
    expect(
      tester.widget<TextField>(titleField()).controller!.text,
      'Remote title',
    );
    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved!.title, 'Remote title');
    await finish(tester, container);
  });

  testWidgets('clean editor adopts an external persisted update', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    final current = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(current!.copyWith(description: 'Remote description')),
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (tester
              .widget<TextField>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is TextField &&
                      widget.decoration?.labelText == 'Description',
                ),
              )
              .controller
              ?.text ==
          'Remote description') {
        break;
      }
    }

    final description = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Description',
    );
    expect(
      tester.widget<TextField>(description).controller!.text,
      'Remote description',
    );
    await tester.enterText(titleField(), 'Local after remote');
    await save(tester);
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);
    expect(find.text('Discard unsaved changes?'), findsNothing);
    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved!.title, 'Local after remote');
    expect(saved.description, 'Remote description');
    await finish(tester, container);
  });

  testWidgets('editor round-trips persisted times in the planner timezone', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    PlannerTimeZone.initialize(identifier: 'America/New_York');
    final plannerStart = PlannerTimeZone.calendarDate(
      2027,
      3,
      15,
      hour: 9,
      minute: 30,
    );
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Planner timezone task',
              startTime: plannerStart,
              endTime: plannerStart.add(const Duration(minutes: 90)),
              estimatedDurationMin: 90,
              createdAt: plannerStart,
              updatedAt: plannerStart,
            ),
          ),
    );
    container.read(selectedDateProvider.notifier).state =
        PlannerTimeZone.startOfDay(plannerStart);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await openEditor(tester, container, task);
    await save(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(
      saved!.startTime!.toUtc().millisecondsSinceEpoch,
      plannerStart.toUtc().millisecondsSinceEpoch,
    );
    expect(
      saved.endTime!.toUtc().millisecondsSinceEpoch,
      plannerStart
          .add(const Duration(minutes: 90))
          .toUtc()
          .millisecondsSinceEpoch,
    );
    await finish(tester, container);
    PlannerTimeZone.initialize(identifier: 'UTC');
  });

  testWidgets('title-only save preserves a multi-day schedule exactly', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final start = DateTime(2027, 3, 15, 9, 17, 42);
    final end = DateTime(2027, 3, 17, 10, 18, 43);
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Long task',
              startTime: start,
              endTime: end,
              estimatedDurationMin: 2941,
              createdAt: start,
              updatedAt: start,
            ),
          ),
    );
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    // Select directly so the regression does not depend on whether a very
    // long block is clipped out of the day timeline's hit-test region.
    requestEditor(container, task.id);
    await settle(tester);
    await tester.enterText(titleField(), 'Renamed long task');
    await save(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved!.title, 'Renamed long task');
    expect(
      saved.startTime!.toUtc().millisecondsSinceEpoch,
      start.toUtc().millisecondsSinceEpoch,
    );
    expect(
      saved.endTime!.toUtc().millisecondsSinceEpoch,
      end.toUtc().millisecondsSinceEpoch,
    );
    await finish(tester, container);
  });

  testWidgets('closing a dirty editor requires an explicit discard choice', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    await tester.enterText(titleField(), 'Discarded title');
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), task.id);
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);

    expect(container.read(selectedTaskIdProvider), isNull);
    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved!.title, 'Merge target');

    // Reopen the same task: the discarded controller draft must not survive
    // the desktop panel's unmount-free close path.
    requestEditor(container, task.id);
    await settle(tester);
    expect(
      tester.widget<TextField>(titleField()).controller!.text,
      'Merge target',
    );
    await finish(tester, container);
  });

  testWidgets('successful Save establishes a clean close baseline', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    await tester.enterText(titleField(), 'Saved title');
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Description',
      ),
      'Saved description',
    );
    await save(tester);
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);

    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(container.read(selectedTaskIdProvider), isNull);
    await finish(tester, container);
  });

  testWidgets('editing after Save makes the editor dirty again', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    await tester.enterText(titleField(), 'First saved title');
    await save(tester);
    // Re-select after the persistence stream settles. This keeps the
    // regression focused on the persisted baseline even when a test database
    // briefly emits its loading state between two writes.
    requestEditor(container, task.id);
    await settle(tester);
    await tester.enterText(titleField(), 'Second unsaved title');
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);

    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(
      tester.widget<TextField>(titleField()).controller!.text,
      'Second unsaved title',
    );
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets('failed Save leaves the editor dirty', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    await tester.enterText(titleField(), '');
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    await settle(tester);
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);

    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    await tester.enterText(titleField(), 'Restored title');
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets('clearing an edited Actual total requires an explicit zero', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Actual validation',
              actualDurationMin: 5,
              createdAt: date,
              updatedAt: date,
            ),
          ),
    );
    container.read(selectedDateProvider.notifier).state = date;
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);
    final actualField = find.byKey(const ValueKey('actual-duration-field'));
    await tester.enterText(actualField, '');
    await save(tester);

    expect(find.text('Enter total minutes, or 0'), findsWidgets);
    final reloaded = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(reloaded?.actualDurationMin, 5);
    await finish(tester, container);
  });

  testWidgets('an unchanged editor closes without prompting', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    requestEditor(container, task.id);
    await settle(tester);

    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(container.read(selectedTaskIdProvider), isNull);
    await finish(tester, container);
  });

  testWidgets('editor actions remain visible while the form scrolls', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 800));
    requestEditor(container, task.id);
    await settle(tester);

    final templateButton = find.byKey(
      const ValueKey('save-as-template-button'),
    );
    final formScrollables = find.ancestor(
      of: templateButton,
      matching: find.byType(Scrollable),
    );
    expect(formScrollables, findsOneWidget);
    final formScrollable = formScrollables.last;
    await tester.scrollUntilVisible(
      templateButton,
      500,
      scrollable: formScrollable,
    );
    await settle(tester);

    expect(find.byTooltip('Close editor'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-task-button')), findsOneWidget);
    expect(templateButton, findsOneWidget);
    expect(
      tester.getRect(templateButton).bottom,
      lessThanOrEqualTo(tester.getRect(formScrollable).bottom),
    );
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('missing-task state keeps a usable close action', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 800));
    requestEditor(container, 'missing-task');
    await settle(tester);

    expect(
      find.text('The selected task is no longer available.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Close editor'), findsOneWidget);
    await tester.tap(find.byTooltip('Close editor'));
    await settle(tester);

    expect(container.read(selectedTaskIdProvider), isNull);
    expect(find.text('Discard unsaved changes?'), findsNothing);
    await finish(tester, container);
  });
}
