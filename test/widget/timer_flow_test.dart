import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/data/timer_repository.dart';
import 'package:personal_planner/features/timer/providers/timer_providers.dart';

import '../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  late Task alpha;
  late Task beta;

  Future<void> setUpScaffolding(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    final tasks = container.read(taskRepositoryProvider);
    final now = DateTime.now();
    // Around the current hour so both blocks sit inside the auto-scrolled
    // viewport (anchor = now − 90 min).
    var hour = now.hour;
    if (hour >= 22) hour = 20;
    Future<Task> insertAt(int startHour, String title) => tasks.insertTask(
      Task(
        id: '',
        title: title,
        startTime: DateTime(now.year, now.month, now.day, startHour),
        endTime: DateTime(now.year, now.month, now.day, startHour + 1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    alpha = await runDb(tester, () => insertAt(hour, 'Alpha'));
    beta = await runDb(tester, () => insertAt(hour + 1, 'Beta'));
    // Let the day-tasks stream deliver the seeded rows before interacting.
    await settle(tester);
  }

  Future<void> selectTask(WidgetTester tester, Task task) async {
    await tester.tap(
      find.byKey(ValueKey('task-block-${task.id}')),
      warnIfMissed: false,
    );
    await settle(tester);
  }

  TaskRepository tasksRepoOf(ProviderContainer c) =>
      c.read(taskRepositoryProvider);

  TimerRepository timerRepoOf(ProviderContainer c) =>
      c.read(timerRepositoryProvider);

  testWidgets('start shows ticking chip + overlay and auto-sets In Progress', (
    tester,
  ) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);

    expect(find.byKey(const ValueKey('timer-overlay')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);

    // Overlay appears on desktop; block shows the ticking chip.
    expect(find.byKey(const ValueKey('timer-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('block-timer-chip')), findsOneWidget);
    expect(find.text('00:00:00'), findsWidgets);

    // Timer ticks once per second — block chip, editor and overlay in sync.
    // The elapsed stream is mounted asynchronously after the start write. In
    // a long sequential suite it can miss the first fake-clock tick, so wait
    // for the observable two-second state with a bounded timeout instead of
    // assuming the provider mounted at t=0.
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      if (find.text('00:00:02').evaluate().isNotEmpty) break;
    }
    expect(find.text('00:00:02'), findsWidgets);
    expect(find.byKey(const ValueKey('overlay-timer-elapsed')), findsOneWidget);

    // Auto-status: planned → in progress (Chunk 6 #11).
    final reloaded = await runDb(
      tester,
      () => tasksRepoOf(container).getTaskById(alpha.id),
    );
    expect(reloaded!.status, TaskStatus.inProgress);

    // Tear down the running timer the way a user would so no periodic
    // stream outlives the test's widget tree.
    await tester.tap(find.byKey(const ValueKey('overlay-pause-button')));
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets('pause then resume creates two separate sessions', (
    tester,
  ) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('overlay-pause-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('timer-overlay')), findsNothing);

    // Resume via the editor button (idle again → "Start timer").
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('timer-overlay')), findsOneWidget);

    final sessions = await runDb(
      tester,
      () => timerRepoOf(container).getSessionsForTask(alpha.id),
    );
    expect(sessions, hasLength(2));
    expect(sessions.where((s) => s.endedAt == null), hasLength(1));

    // Tear down the running timer so no periodic stream outlives the tree.
    await tester.tap(find.byKey(const ValueKey('overlay-pause-button')));
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets('starting B auto-pauses A', (tester) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);

    // Switch selection to Beta and start there.
    await selectTask(tester, beta);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);

    final aSessions = await runDb(
      tester,
      () => timerRepoOf(container).getSessionsForTask(alpha.id),
    );
    final bSessions = await runDb(
      tester,
      () => timerRepoOf(container).getSessionsForTask(beta.id),
    );
    expect(aSessions.single.endedAt, isNotNull);
    expect(bSessions.where((s) => s.endedAt == null), hasLength(1));

    // Exactly one overlay for the one running session.
    expect(find.byKey(const ValueKey('timer-overlay')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('overlay-pause-button')));
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets('stop prompts "Mark as Completed?" — Yes completes the task', (
    tester,
  ) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('overlay-stop-button')));
    await settle(tester);
    expect(find.text('Mark as Completed?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mark-completed-yes')));
    await settle(tester);

    expect(find.byKey(const ValueKey('timer-overlay')), findsNothing);
    final reloaded = await runDb(
      tester,
      () => tasksRepoOf(container).getTaskById(alpha.id),
    );
    expect(reloaded!.status, TaskStatus.completed);
    await finish(tester, container);
  });

  testWidgets('stop prompt "No" keeps the task In Progress', (tester) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('overlay-stop-button')));
    await settle(tester);
    await tester.tap(find.text('No'));
    await settle(tester);

    final reloaded = await runDb(
      tester,
      () => tasksRepoOf(container).getTaskById(alpha.id),
    );
    expect(reloaded!.status, TaskStatus.inProgress);
    await finish(tester, container);
  });

  testWidgets('deleting the timed task finalizes its session', (tester) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timer-start-button')),
    );
    await tester.tap(find.byKey(const ValueKey('timer-start-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('timer-overlay')), findsOneWidget);

    // Delete via keyboard (block still selected).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await settle(tester);
    expect(find.text('Delete task?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await settle(tester);

    // Overlay disappears and the session is finalized, not orphaned.
    expect(find.byKey(const ValueKey('timer-overlay')), findsNothing);
    final sessions = await runDb(
      tester,
      () => timerRepoOf(container).getSessionsForTask(alpha.id),
    );
    expect(sessions.single.endedAt, isNotNull);

    // Undo restores the task with its tracked time intact.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await settle(tester);
    final restored = await runDb(
      tester,
      () => tasksRepoOf(container).getTaskById(alpha.id),
    );
    expect(restored!.deletedAt, isNull);
    await finish(tester, container);
  });

  testWidgets('actual duration is manually editable in the editor', (
    tester,
  ) async {
    await setUpScaffolding(tester);
    await selectTask(tester, alpha);

    const field = Key('actual-duration-field');
    await tester.ensureVisible(find.byKey(field));
    await tester.enterText(find.byKey(field), '45');
    await tester.ensureVisible(find.byKey(const ValueKey('save-task-button')));
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    await settle(tester);

    final reloaded = await runDb(
      tester,
      () => tasksRepoOf(container).getTaskById(alpha.id),
    );
    expect(reloaded!.actualDurationMin, 45);
    await finish(tester, container);
  });
}
