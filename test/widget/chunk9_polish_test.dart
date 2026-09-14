import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/presentation/providers/grid_settings_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  const phone = Size(390, 844);
  final viewDay = DateTime(2027, 3, 15);

  Future<void> pumpRoute(
    WidgetTester tester,
    ProviderContainer container,
    String route, {
    Size surface = phone,
  }) async {
    appRouter.go(route);
    await pumpApp(tester, container, surface: surface);
  }

  testWidgets('narrow Day View keeps primary actions reachable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = await buildTestContainer(tester);
    for (final surface in [const Size(360, 800), phone]) {
      await pumpRoute(tester, container, '/day', surface: surface);

      expect(find.byKey(const ValueKey('day-settings-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-status-action')), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await finish(tester, container);
  });

  testWidgets('mobile task editor stays within the IME-visible viewport', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = await buildTestContainer(tester);
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    container.read(selectedDateProvider.notifier).state = viewDay;
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Keyboard-visible task',
              startTime: viewDay.add(const Duration(hours: 9)),
              endTime: viewDay.add(const Duration(hours: 10)),
              estimatedDurationMin: 60,
              createdAt: viewDay,
              updatedAt: viewDay,
            ),
          ),
    );

    await pumpRoute(tester, container, '/day');
    await tester.tap(find.byKey(ValueKey('task-block-${task.id}')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('selected-task-edit-${task.id}')));
    await settle(tester);

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final sheetRect = tester.getRect(sheet);
    expect(sheetRect.bottom, lessThanOrEqualTo(484.0));
    expect(find.byKey(const ValueKey('save-task-button')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await finish(tester, container);
  });

  testWidgets('mobile double tap opens exactly one task editor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = await buildTestContainer(tester);
    container.read(selectedDateProvider.notifier).state = viewDay;
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Double tap target',
              startTime: viewDay.add(const Duration(hours: 9)),
              endTime: viewDay.add(const Duration(hours: 10)),
              createdAt: viewDay,
              updatedAt: viewDay,
            ),
          ),
    );

    await pumpRoute(tester, container, '/day');
    await doubleTap(tester, find.byKey(ValueKey('task-block-${task.id}')));
    await settle(tester);

    expect(find.text('Edit Task'), findsOneWidget);
    expect(find.text('Create scheduled task'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('save-task-button')), findsOneWidget);
    expect(container.read(selectedTaskIdProvider), task.id);
    expect(container.read(taskEditorOpenProvider), isTrue);
    await finish(tester, container);
  });

  testWidgets(
    'empty day keeps the timeline open and exposes a compact add action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = await buildTestContainer(tester);
      container.read(selectedDateProvider.notifier).state = viewDay;
      await pumpRoute(tester, container, '/day');

      expect(find.text('No tasks planned for this day'), findsNothing);
      expect(find.text('Tap + to add your first block'), findsNothing);
      expect(find.byKey(const ValueKey('empty-day-add')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('empty-day-add')));
      await settle(tester);
      expect(find.text('Create scheduled task'), findsOneWidget);

      await finish(tester, container);
    },
  );

  testWidgets('help shortcut opens the registry-generated overlay', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    appRouter.go('/day');
    await settle(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);

    expect(find.byKey(const ValueKey('shortcut-help-dialog')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ctrl+↑'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Ctrl+↑'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save and close the task editor'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Save and close the task editor'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await finish(tester, container);
  });

  testWidgets('15-minute mobile resize commits an exact 75-minute block', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = await buildTestContainer(tester);
    container.read(selectedDateProvider.notifier).state = viewDay;
    await container.read(gridIntervalProvider.future);
    await container.read(gridIntervalProvider.notifier).setInterval(15);
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Three PM block',
              startTime: viewDay.add(const Duration(hours: 15)),
              endTime: viewDay.add(const Duration(hours: 16)),
              estimatedDurationMin: 60,
              createdAt: DateTime(2027, 1, 1),
              updatedAt: DateTime(2027, 1, 1),
            ),
          ),
    );
    await pumpRoute(tester, container, '/day');

    final block = find.byKey(ValueKey('task-block-${task.id}'));
    await tester.ensureVisible(block);
    container.read(selectedTaskIdProvider.notifier).state = task.id;
    await settle(tester);

    final handle = find.descendant(
      of: block,
      matching: find.byKey(const ValueKey('resize-handle')),
    );
    expect(handle, findsOneWidget);
    expect(tester.getSize(handle).height, 48);

    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 20));
    // The first movement crosses Flutter's touch slop; the following 16px is
    // the resize delta delivered after the resize recognizer wins the arena.
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 16));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved!.scheduledDuration, const Duration(minutes: 75));
    expect(saved.endTime, viewDay.add(const Duration(hours: 16, minutes: 15)));
    expect(tester.takeException(), isNull);

    await finish(tester, container);
  });

  testWidgets('short mobile blocks expose a 48px selection target', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = await buildTestContainer(tester);
    container.read(selectedDateProvider.notifier).state = viewDay;
    await container.read(gridIntervalProvider.future);
    await container.read(gridIntervalProvider.notifier).setInterval(15);
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Short touch target',
              startTime: viewDay.add(const Duration(hours: 15)),
              endTime: viewDay.add(const Duration(hours: 15, minutes: 15)),
              estimatedDurationMin: 15,
              createdAt: DateTime(2027, 1, 1),
              updatedAt: DateTime(2027, 1, 1),
            ),
          ),
    );
    await pumpRoute(tester, container, '/day');

    final block = find.byKey(ValueKey('task-block-${task.id}'));
    await tester.ensureVisible(block);
    expect(tester.getSize(block).height, greaterThanOrEqualTo(48));
    expect(find.text('Short touch target'), findsOneWidget);
    await finish(tester, container);
  });
}
