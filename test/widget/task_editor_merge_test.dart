import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  final date = DateTime(2027, 3, 15, 9);

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
    expect(container.read(selectedTaskIdProvider), task.id);
  }

  Finder titleField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == 'Title',
  );

  Future<void> save(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('save-task-button'));
    final editorScrollable = find
        .ancestor(of: button, matching: find.byType(Scrollable))
        .last;
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
    await settle(tester);
    await tester.tap(button);
    await settle(tester);
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
}
