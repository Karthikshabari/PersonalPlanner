// Manual diagnostic: pinpoints which stage of the drag test wedges
// flutter_tester. Run stages INDIVIDUALLY:
//
//   flutter test --concurrency=1 test/widget/diag_stages_test.dart --plain-name "s0"
//   flutter test --concurrency=1 test/widget/diag_stages_test.dart --plain-name "s1"
//   flutter test --concurrency=1 test/widget/diag_stages_test.dart --plain-name "s2"
//   flutter test --concurrency=1 test/widget/diag_stages_test.dart --plain-name "s3"
//   flutter test --concurrency=1 test/widget/diag_stages_test.dart --plain-name "s4"
//
// s0 baseline        : pump app, insert task, read via poll      (expected PASS)
// s1 drag            : + mouse drag, settle                      (expected PASS)
// s2 drag + pollRead : + bounded pump-poll of the watch stream   (?)
// s3 drag + runAsync : + tester.runAsync(getTaskById)            (?)
// s4 drag + delete   : + Delete key flow with confirm dialog     (?)
//
// If the process hangs, note WHICH stage and how RAM behaves
// (`watch -n 2 'ps -o rss,comm -C flutter_tester'`), then Ctrl-C / pkill.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/day_tasks_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart'
    as date_provider;

import '../helpers/test_container.dart';

final DateTime viewDay = DateTime(2027, 3, 15);

Future<Task> seed(WidgetTester tester, ProviderContainer container) async {
  final created = await runDb(
    tester,
    () => container.read(taskRepositoryProvider).insertTask(Task(
          id: '',
          title: 'Diag',
          startTime: viewDay.add(const Duration(hours: 8)),
          endTime: viewDay.add(const Duration(hours: 9)),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )),
  );
  await settle(tester);
  return created;
}

Future<void> boot(WidgetTester tester, ProviderContainer container) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  container.read(date_provider.selectedDateProvider.notifier).state = viewDay;
  await pumpApp(tester, container, surface: const Size(1400, 1000));
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

Future<List<Task>> pollRead(
  WidgetTester tester,
  ProviderContainer container,
) async {
  List<Task>? data;
  for (var i = 0; i < 100; i++) {
    data = container.read(dayTasksProvider).value;
    if (data != null && data.isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 20));
  }
  // ignore: avoid_print
  print('STAGE pollRead saw ${data?.length ?? -1} tasks');
  await settle(tester);
  return data ?? const <Task>[];
}

Future<void> done(WidgetTester tester, ProviderContainer container) async {
  debugDefaultTargetPlatformOverride = null;
  await teardownApp(tester, container);
}

void main() {
  testWidgets('s0 baseline: insert + poll read', (tester) async {
    final c = await buildTestContainer(tester);
    await boot(tester, c);
    final a = await seed(tester, c);
    // ignore: avoid_print
    print('STAGE s0 inserted ${a.id}');
    final tasks = await pollRead(tester, c);
    // ignore: avoid_print
    print('STAGE s0 read ${tasks.length}');
    expect(tasks, hasLength(1));
    await done(tester, c);
    // ignore: avoid_print
    print('STAGE s0 COMPLETE');
  });

  testWidgets('s1 drag only', (tester) async {
    final c = await buildTestContainer(tester);
    await boot(tester, c);
    final a = await seed(tester, c);
    // ignore: avoid_print
    print('STAGE s1 inserted');
    await mouseDrag(tester, find.byKey(ValueKey('task-block-${a.id}')),
        const Offset(0, -64));
    await settle(tester);
    // ignore: avoid_print
    print('STAGE s1 dragged');
    await done(tester, c);
    // ignore: avoid_print
    print('STAGE s1 COMPLETE');
  });

  testWidgets('s2 drag + poll read', (tester) async {
    final c = await buildTestContainer(tester);
    await boot(tester, c);
    final a = await seed(tester, c);
    await mouseDrag(tester, find.byKey(ValueKey('task-block-${a.id}')),
        const Offset(0, -64));
    await settle(tester);
    // ignore: avoid_print
    print('STAGE s2 dragged');
    final tasks = await pollRead(tester, c);
    // ignore: avoid_print
    print('STAGE s2 read ${tasks.length}, first start=${tasks.first.startTime}');
    expect(tasks.first.startTime!.hour, 7);
    await done(tester, c);
    // ignore: avoid_print
    print('STAGE s2 COMPLETE');
  });

  testWidgets('s3 drag + runAsync read', (tester) async {
    final c = await buildTestContainer(tester);
    await boot(tester, c);
    final a = await seed(tester, c);
    await mouseDrag(tester, find.byKey(ValueKey('task-block-${a.id}')),
        const Offset(0, -64));
    await settle(tester);
    // ignore: avoid_print
    print('STAGE s3 dragged');
    final fetched = await runDb(
      tester,
      () => c.read(taskRepositoryProvider).getTaskById(a.id),
    );
    // ignore: avoid_print
    print('STAGE s3 read hour=${fetched!.startTime!.hour}');
    expect(fetched.startTime!.hour, 7);
    await done(tester, c);
    // ignore: avoid_print
    print('STAGE s3 COMPLETE');
  });
}
