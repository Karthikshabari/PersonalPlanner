import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/subtask.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/task_editor/providers/subtask_providers.dart';
import 'package:personal_planner/features/task_editor/providers/tag_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import '../helpers/test_container.dart';

final DateTime viewDay = DateTime(2027, 3, 15);

Future<Task> insertTask(WidgetTester tester, ProviderContainer container,
    String title, {int startHour = 8}) async {
  final created = await runDb(
    tester,
    () => container.read(taskRepositoryProvider).insertTask(Task(
          id: '',
          title: title,
          startTime: viewDay.add(Duration(hours: startHour)),
          endTime: viewDay.add(Duration(hours: startHour + 1)),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )),
  );
  await settle(tester);
  return created;
}

Finder blockOf(Task t) => find.byKey(ValueKey('task-block-${t.id}'));

Future<List<Subtask>> subtasksOf(
    WidgetTester tester, ProviderContainer container, String taskId) {
  return runDb(
    tester,
    () =>
        container.read(subtaskRepositoryProvider).getSubtasksForTask(taskId),
  );
}

/// Scrolls the editor panel so [target] sits fully inside its viewport.
/// Chunk 4 added the recurrence picker above the subtasks/tags sections,
/// which pushed them close to (or below) the panel's bottom edge, so tests
/// must bring them into view before tapping/dragging.
Future<void> bringIntoView(WidgetTester tester, Finder target) async {
  final editorScrollable =
      find.ancestor(of: target, matching: find.byType(Scrollable)).last;
  for (var attempt = 0; attempt < 12; attempt++) {
    await settle(tester);
    final rect = tester.getRect(target);
    final viewport = tester.getRect(editorScrollable);
    const margin = 32.0;
    if (rect.top >= viewport.top + margin &&
        rect.bottom <= viewport.bottom - margin) {
      return;
    }
    final dy = rect.center.dy > viewport.center.dy ? -100.0 : 100.0;
    await tester.drag(editorScrollable, Offset(0, dy));
  }
}

void main() {
  Future<ProviderContainer> pumpDesktop(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    container.read(selectedDateProvider.notifier).state = viewDay;
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  testWidgets('add subtasks in editor and see completion count on the block',
      (tester) async {
    final container = await pumpDesktop(tester);
    final task = await insertTask(tester, container, 'Parent');

    await tester.tap(blockOf(task));
    await settle(tester);

    // Two subtasks via the inline field.
    await tester.enterText(find.byKey(const ValueKey('subtask-input')), 'First');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('subtask-input')), 'Second');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    // Block shows "0/2".
    expect(find.byKey(const ValueKey('subtask-count')), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);

    // Toggle the first checkbox → "1/2" with strikethrough.
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);
    expect(find.text('1/2'), findsOneWidget);
    expect((await subtasksOf(tester, container, task.id)).first.isCompleted,
        isTrue);
    await finish(tester, container);
  });

  testWidgets('delete a subtask via its X button', (tester) async {
    final container = await pumpDesktop(tester);
    final task = await insertTask(tester, container, 'WithKids');
    final repo = container.read(subtaskRepositoryProvider);
    await runDb(
      tester,
      () => repo.insertSubtask(Subtask(
            id: '',
            taskId: task.id,
            title: 'Doomed child',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )),
    );
    await settle(tester);
    await tester.tap(blockOf(task));
    await settle(tester);

    final xButton = find.descendant(
        of: find.byType(ListTile), matching: find.byIcon(Icons.close));
    await bringIntoView(tester, xButton);
    await tester.tap(xButton);
    await settle(tester);

    expect(await subtasksOf(tester, container, task.id), isEmpty);
    expect(find.byKey(const ValueKey('subtask-count')), findsNothing);
    await finish(tester, container);
  });

  testWidgets('dragging a subtask handle reorders it', (tester) async {
    final container = await pumpDesktop(tester);
    final task = await insertTask(tester, container, 'Reordering');
    final repo = container.read(subtaskRepositoryProvider);
    for (final title in ['A', 'B']) {
      await runDb(
        tester,
        () => repo.insertSubtask(Subtask(
              id: '',
              taskId: task.id,
              title: title,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )),
      );
    }
    await settle(tester);
    await tester.tap(blockOf(task));
    await settle(tester);

    // Drag B's handle above A.
    final handle = find.byIcon(Icons.drag_handle).last;
    await bringIntoView(tester, handle);
    final center = tester.getCenter(handle);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await settle(tester);

    final order =
        (await subtasksOf(tester, container, task.id)).map((s) => s.title);
    expect(order, ['B', 'A']);
    await finish(tester, container);
  });

  testWidgets('tag picker creates tags inline and multi-selects',
      (tester) async {
    final container = await pumpDesktop(tester);
    final taskA = await insertTask(tester, container, 'Tagged A');

    await tester.tap(blockOf(taskA));
    await settle(tester);

    // Create two tags by typing + Enter.
    for (final name in ['urgent-ish', 'later']) {
      await tester.enterText(find.byKey(const ValueKey('tag-input')), name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
    }

    expect(find.byKey(const ValueKey('tag-chip-urgent-ish')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-chip-later')), findsOneWidget);
    // Both are staged in the editor draft.
    expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((c) => c.selected)
            .length,
        2);

    // Detach one via its chip.
    await tester.tap(find.byKey(const ValueKey('tag-chip-later')));
    await settle(tester);
    expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((c) => c.selected)
            .length,
        1);
    final save = find.byKey(const ValueKey('save-task-button'));
    await bringIntoView(tester, save);
    await tester.tap(save);
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets('second task can select the same tag (multi-select)',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a = await insertTask(tester, container, 'Tagged A');
    final b = await insertTask(tester, container, 'Tagged B', startHour: 10);

    await tester.tap(blockOf(a));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('tag-input')), 'shared');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Wait for the real-async DB write to land and the stream to refresh.
    for (var i = 0; i < 50; i++) {
      if (find.byKey(const ValueKey('tag-chip-shared')).evaluate().isNotEmpty &&
          tester
                  .widgetList<FilterChip>(
                      find.byKey(const ValueKey('tag-chip-shared')))
                  .first
                  .selected) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);

    // Tag selection is part of the explicit editor Save contract.
    final save = find.byKey(const ValueKey('save-task-button'));
    await bringIntoView(tester, save);
    await tester.tap(save);
    await settle(tester);

    // Attach the same tag to task B through the repository (the picker's
    // data source); multi-select means two tasks can share one tag.
    final shared = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('shared'),
    );
    await runDb(
      tester,
      () => container.read(tagRepositoryProvider).addTagToTask(b.id, shared.id),
    );

    // B's editor shows the chip as selected.
    await tester.tap(blockOf(b));
    await settle(tester);
    for (var i = 0; i < 50; i++) {
      final chips = tester.widgetList<FilterChip>(
          find.byKey(const ValueKey('tag-chip-shared')));
      if (chips.isNotEmpty && chips.first.selected) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
        tester
            .widgetList<FilterChip>(
                find.byKey(const ValueKey('tag-chip-shared')))
            .first
            .selected,
        isTrue);

    final tagsForA = await runDb(
        tester, () => container.read(tagRepositoryProvider).getTagsForTask(a.id));
    final tagsForB = await runDb(
        tester, () => container.read(tagRepositoryProvider).getTagsForTask(b.id));
    expect(tagsForA.single.name, 'shared');
    expect(tagsForB.single.name, 'shared');
    await finish(tester, container);
  });
}
