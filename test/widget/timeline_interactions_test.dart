import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/widgets/task_block_widget.dart';
import 'package:personal_planner/features/timeline/presentation/providers/day_tasks_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/grid_settings_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart'
    as date_provider;
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/ghost_preview.dart';

import '../helpers/test_container.dart';

/// A fixed date that is never "today", so the timeline anchors at 07:00 and
/// block positions are deterministic.
final DateTime viewDay = DateTime(2027, 3, 15);

Task taskSpec(String title, int startMinutes, int endMinutes) => Task(
      id: '',
      title: title,
      startTime: viewDay.add(Duration(minutes: startMinutes)),
      endTime: viewDay.add(Duration(minutes: endMinutes)),
      estimatedDurationMin: endMinutes - startMinutes,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<Task> insertTask(
  WidgetTester tester,
  ProviderContainer container,
  Task task,
) async {
  final created = await runDb(
    tester,
    () => container.read(taskRepositoryProvider).insertTask(task),
  );
  // Let the Drift watch stream deliver the new row to the timeline.
  await settle(tester);
  return created;
}

Finder blockOf(Task t) => find.byKey(ValueKey('task-block-${t.id}'));

/// Reads the day list through the live Drift watch stream using bounded
/// pump-polling. Stays entirely inside the FakeAsync zone (no tester.runAsync
/// after gestures) and always terminates.
Future<List<Task>> streamedDayTasks(
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

Future<Task?> streamedTaskById(
  WidgetTester tester,
  ProviderContainer container,
  String id,
) async {
  final tasks = await streamedDayTasks(tester, container);
  for (final t in tasks) {
    if (t.id == id) return t;
  }
  return null;
}

Future<void> mouseDrag(
  WidgetTester tester,
  Finder finder,
  Offset delta,
) async {
  final center = tester.getCenter(finder);
  final gesture =
      await tester.startGesture(center, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 50));
  const steps = 6.0;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(delta / steps);
    await tester.pump(const Duration(milliseconds: 20));
  }
  await gesture.up();
  await tester.pump();
}

Future<void> pressCtrlZ(WidgetTester tester, {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

/// Resets the foundation override before the binding verifies invariants
/// (addTearDown callbacks run after that check in flutter_test) and pumps the
/// customary end-of-test frame.
Future<void> finish(WidgetTester tester, ProviderContainer container) async {
  debugDefaultTargetPlatformOverride = null;
  await tester.pump(const Duration(milliseconds: 100));
}

/// Boots the app at [platform] for the fixed [viewDay], runs [body] with the
/// container, and restores the platform override inside the test body.
Future<void> runDesktop(
  WidgetTester tester,
  Future<void> Function(ProviderContainer container) body, {
  TargetPlatform platform = TargetPlatform.linux,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final container = await buildTestContainer(tester);
  // Set the viewed date BEFORE pumping so the timeline's initial scroll
  // anchor targets 07:00 of [viewDay] and morning blocks are on screen.
  container.read(date_provider.selectedDateProvider.notifier).state = viewDay;
  await pumpApp(tester, container, surface: const Size(1400, 1000));
  try {
    await body(container);
  } finally {
    await finish(tester, container);
  }
}

void main() {
  Future<ProviderContainer> pumpDesktop(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    // Set the viewed date BEFORE pumping so the timeline's initial scroll
    // anchor targets 07:00 of [viewDay] and morning blocks are on screen.
    container.read(date_provider.selectedDateProvider.notifier).state =
        viewDay;
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }


  testWidgets('desktop drag moves a block and snaps to the grid',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Draggable', 480, 540));

    // Drag up by exactly one hour.
    await mouseDrag(tester, blockOf(a), const Offset(0, -64));
    await settle(tester);

    final fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.startTime!.hour, 7);
    expect(fetched.startTime!.minute, 0);
    expect(fetched.endTime!.hour, 8);
    expect(fetched.endTime!.minute, 0);
    await finish(tester, container);
  });

  testWidgets('ghost preview shows during drag and original is dimmed',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Ghosty', 480, 540));

    final center = tester.getCenter(blockOf(a));
    final gesture =
        await tester.startGesture(center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GhostPreview), findsOneWidget);
    // The original stays mounted under an Opacity dimmer (key must NOT change
    // mid-drag or the gesture recognizer would be disposed).
    final dimmers = tester.widgetList<Opacity>(
      find.descendant(of: blockOf(a), matching: find.byType(Opacity)),
    );
    expect(dimmers.any((o) => o.opacity == 0.35), isTrue);

    await gesture.up();
    await settle(tester);
    expect(find.byType(GhostPreview), findsNothing);
    await finish(tester, container);
  });

  testWidgets('resize by bottom handle extends duration', (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Stretchy', 480, 540));

    final handle = find.descendant(
      of: blockOf(a),
      matching: find.byKey(const ValueKey('resize-handle')),
    );
    expect(handle, findsOneWidget);
    await mouseDrag(tester, handle, const Offset(0, 64));
    await settle(tester);

    final fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.scheduledDuration, const Duration(hours: 2));
    expect(fetched.startTime, a.startTime); // start unchanged
    await finish(tester, container);
  });

  testWidgets('resize cannot shrink below one grid slot', (tester) async {
    final container = await pumpDesktop(tester);
    final a = await insertTask(
        tester, container, taskSpec('One hour only', 480, 540));

    final handle = find.descendant(
      of: blockOf(a),
      matching: find.byKey(const ValueKey('resize-handle')),
    );
    await mouseDrag(tester, handle, const Offset(0, -300));
    await settle(tester);

    final fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.scheduledDuration, const Duration(hours: 1));
    await finish(tester, container);
  });

  testWidgets('conflict dialog appears on overlapping drop; cancel discards',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Alpha', 480, 540));
    await insertTask(tester, container, taskSpec('Beta', 540, 600));

    await mouseDrag(tester, blockOf(a), const Offset(0, 64)); // → 9:00–10:00
    await settle(tester);
    expect(find.text('Resolve conflict'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conflict-cancel')));
    await settle(tester);

    final fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.startTime, a.startTime); // cancel discarded the move
    await finish(tester, container);
  });

  testWidgets('"Shift All Following" moves all subsequent blocks',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Alpha', 480, 540));
    final b =
        await insertTask(tester, container, taskSpec('Beta', 540, 600));
    final c =
        await insertTask(tester, container, taskSpec('Gamma', 660, 720));

    await mouseDrag(tester, blockOf(a), const Offset(0, 64)); // → 9:00–10:00
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('conflict-shift-all')));
    await settle(tester);

    final fa = await streamedTaskById(tester, container, a.id);
    final fb = await streamedTaskById(tester, container, b.id);
    final fc = await streamedTaskById(tester, container, c.id);
    expect(fa!.startTime, viewDay.add(const Duration(hours: 9)));
    // Overlap = dropped.end (10:00) − firstConflict.start (9:00) = 60 min;
    // every following block shifts one hour, including C across its gap.
    expect(fb!.startTime, viewDay.add(const Duration(hours: 10)));
    expect(fc!.startTime, viewDay.add(const Duration(hours: 12)));
    await finish(tester, container);
  });

  testWidgets('"Shift Only Overlapping" leaves non-overlapping blocks alone',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Alpha', 480, 540));
    final b =
        await insertTask(tester, container, taskSpec('Beta', 540, 600));
    final c =
        await insertTask(tester, container, taskSpec('Gamma', 660, 720));

    await mouseDrag(tester, blockOf(a), const Offset(0, 64)); // → 9:00–10:00
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('conflict-shift-overlapping')));
    await settle(tester);

    final fa = await streamedTaskById(tester, container, a.id);
    final fb = await streamedTaskById(tester, container, b.id);
    final fc = await streamedTaskById(tester, container, c.id);
    expect(fa!.startTime, viewDay.add(const Duration(hours: 9)));
    // Only B overlapped the drop; shifted forward by its own overlap.
    expect(fb!.startTime, viewDay.add(const Duration(hours: 10)));
    // B no longer reaches C's slot, so C stays untouched (no gap shift).
    expect(fc!.startTime, c.startTime);
    await finish(tester, container);
  });

  testWidgets('"Keep Overlap" keeps both blocks and renders indicator',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Alpha', 480, 540));
    await insertTask(tester, container, taskSpec('Beta', 540, 600));

    await mouseDrag(tester, blockOf(a), const Offset(0, 64)); // → 9:00–10:00
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('conflict-keep-overlap')));
    await settle(tester);

    final fa = await streamedTaskById(tester, container, a.id);
    expect(fa!.startTime, viewDay.add(const Duration(hours: 9)));

    // Both overlapping blocks render the runtime overlap indicator.
    final flagged = tester
        .widgetList<TaskBlockWidget>(find.byType(TaskBlockWidget))
        .where((w) => w.hasOverlap)
        .length;
    expect(flagged, 2);
    await finish(tester, container);
  });

  testWidgets('Ctrl+Z undoes a move; Ctrl+Shift+Z redoes it', (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Undoable', 480, 540));

    await mouseDrag(tester, blockOf(a), const Offset(0, -64)); // → 7:00
    await settle(tester);

    await pressCtrlZ(tester);
    await settle(tester);
    var fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.startTime, a.startTime);
    expect(find.textContaining('Undo:'), findsOneWidget);

    await pressCtrlZ(tester, shift: true);
    await settle(tester);
    fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.startTime!.hour, 7);
    expect(find.textContaining('Redo:'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('D key duplicates the selected task into the next free slot',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Original', 480, 540));
    await insertTask(tester, container, taskSpec('Occupying', 540, 600));

    await tester.tap(find.text('Original'));
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), a.id);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await settle(tester);

    final dayTasks = await streamedDayTasks(tester, container);
    expect(dayTasks, hasLength(3));
    final copy = dayTasks
        .singleWhere((t) => t.title == 'Original' && t.id != a.id);
    // 9:00–10:00 occupied → copy lands at 10:00.
    expect(copy.startTime, viewDay.add(const Duration(hours: 10)));
    expect(copy.scheduledDuration, a.scheduledDuration);
    expect(find.textContaining('Duplicated'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Delete key asks for confirmation and soft-deletes',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('Doomed', 480, 540));

    await tester.tap(find.text('Doomed'));
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await settle(tester);

    expect(find.text('Delete task?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    final dayTasks = await streamedDayTasks(tester, container);
    expect(dayTasks, isEmpty);
    // The day stream filters deleted rows, so read the raw record directly
    // (getTaskById intentionally includes soft-deleted rows).
    final raw =
        await runDb(tester, () => container.read(taskRepositoryProvider).getTaskById(a.id));
    expect(raw!.deletedAt, isNotNull);

    // Ctrl+Z restores the deleted task.
    await pressCtrlZ(tester);
    await settle(tester);
    final restored = await streamedDayTasks(tester, container);
    expect(restored, hasLength(1));
    await finish(tester, container);
  });

  testWidgets('right-click opens context menu with Change Status submenu',
      (tester) async {
    final container = await pumpDesktop(tester);
    final a =
        await insertTask(tester, container, taskSpec('MenuTarget', 480, 540));

    await tester.tap(blockOf(a), buttons: kSecondaryMouseButton);
    await settle(tester);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Change Status ›'), findsOneWidget);

    await tester.tap(find.text('Change Status ›'));
    await settle(tester);
    await tester.tap(find.text('Completed').last);
    await settle(tester);

    final fetched = await streamedTaskById(tester, container, a.id);
    expect(fetched!.status, TaskStatus.completed);
    await finish(tester, container);
  });

  testWidgets('long-press without movement opens context menu (touch)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = await buildTestContainer(tester);
    container.read(date_provider.selectedDateProvider.notifier).state =
        viewDay;
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await insertTask(tester, container, taskSpec('TouchMenu', 480, 540));

    await tester.longPress(find.text('TouchMenu'));
    await settle(tester);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Change Status ›'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('grid interval change persists and updates timeline snapping',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    appRouter.go('/settings');
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('grid-interval-dropdown')));
    await settle(tester);
    await tester.tap(find.text('15 min').last);
    await settle(tester);

    expect(container.read(gridIntervalProvider).value, 15);

    // Back on the day view the new interval drives quick-create sizing.
    appRouter.go('/day');
    await settle(tester);
    container.read(date_provider.selectedDateProvider.notifier).state =
        viewDay;
    await settle(tester);

    await doubleTap(tester, find.byKey(const ValueKey('timeline-gestures')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Quarter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    final tasks = await streamedDayTasks(tester, container);
    expect(tasks.single.title, 'Quarter');
    expect(tasks.single.scheduledDuration, const Duration(minutes: 15));
    await finish(tester, container);
  });
}
