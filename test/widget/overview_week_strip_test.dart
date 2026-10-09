import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

void main() {
  DateTime thisWeek() => startOfWeek(DateTime.now());
  Finder card(DateTime weekStart) =>
      find.byKey(ValueKey('overview-week-${isoDateString(weekStart)}'));
  final strip = find.byKey(const ValueKey('overview-week-strip'));

  // Disposing a reactive-stats provider mid-test starts an async onCancel in
  // the FakeAsync zone; give it real time so database.close() in finish()
  // does not hang.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  Future<ProviderContainer> pumpAt(
    WidgetTester tester,
    String path, {
    Size surface = const Size(1400, 1000),
    double textScale = 1.0,
  }) async {
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final container = await buildTestContainer(tester);
    final lastWeek = addDays(thisWeek(), -7);
    await runDb(tester, () async {
      final tasks = container.read(taskRepositoryProvider);
      for (var i = 0; i < 4; i++) {
        final start = addDays(lastWeek, i).add(const Duration(hours: 9));
        await tasks.insertTask(
          Task(
            id: '',
            title: 'Task $i',
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            status: i < 3 ? TaskStatus.completed : TaskStatus.planned,
            createdAt: start,
            updatedAt: start,
          ),
        );
      }
      await container
          .read(reviewRepositoryProvider)
          .saveWeeklyReviewDraft(
            weekStart: lastWeek,
            mood: 3,
            feeling: '',
            note: '',
          );
    });
    appRouter.go(path);
    await pumpApp(tester, container, surface: surface);
    await settle(tester);
    return container;
  }

  testWidgets('?tab=weekly opens week cards, newest at the right', (
    tester,
  ) async {
    final container = await pumpAt(tester, '/review/overview?tab=weekly');
    final handle = tester.ensureSemantics();

    expect(strip, findsOneWidget);
    expect(
      find.text('Weekly overview comes in the weekly round.'),
      findsNothing,
    );
    final lastWeek = addDays(thisWeek(), -7);
    expect(
      tester.getTopLeft(card(thisWeek())).dx,
      greaterThan(tester.getTopLeft(card(lastWeek)).dx),
    );
    expect(tester.getSize(card(lastWeek)).width, 112);
    expect(
      tester.getSemantics(card(lastWeek)).label,
      endsWith(': 75% completed, Excellent'),
    );
    expect(
      tester.getSemantics(card(thisWeek())).label,
      endsWith(': No tasks, Not reviewed'),
    );
    expect(
      find.descendant(of: card(lastWeek), matching: find.byType(InkWell)),
      findsNothing,
    );
    handle.dispose();
    await finish(tester, container);
  });

  testWidgets('arrows hidden below 520 dp', (tester) async {
    final container = await pumpAt(
      tester,
      '/review/overview?tab=weekly',
      surface: const Size(390, 844),
    );
    expect(find.byKey(const ValueKey('overview-week-older')), findsNothing);
    expect(find.byKey(const ValueKey('overview-week-newer')), findsNothing);

    await pumpApp(tester, container, surface: const Size(1400, 1000));
    expect(find.byKey(const ValueKey('overview-week-older')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-week-newer')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('scrolling to the older end loads 12 more weeks', (tester) async {
    final container = await pumpAt(tester, '/review/overview?tab=weekly');
    final target = card(addDays(thisWeek(), -7 * 16));
    expect(target, findsNothing);

    await tester.dragUntilVisible(target, strip, const Offset(300, 0));
    await settle(tester);

    expect(target, findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('See in Overview from Weekly opens the updated week card', (
    tester,
  ) async {
    final container = await pumpAt(tester, '/review/weekly');
    await tester.tap(find.byKey(const ValueKey('weekly-mood-4')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('weekly-save')));
    await settle(tester);
    await tester.tap(find.text('See in Overview'));
    await settle(tester);
    await drainDisposedStreams(tester);
    final handle = tester.ensureSemantics();

    expect(strip, findsOneWidget);
    expect(
      tester.getSemantics(card(thisWeek())).label,
      endsWith(': No tasks, Legendary'),
    );
    handle.dispose();
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('week cards fit 360 dp at text scale 1.3', (tester) async {
    final container = await pumpAt(
      tester,
      '/review/overview?tab=weekly',
      surface: const Size(360, 800),
      textScale: 1.3,
    );
    expect(strip, findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });
}
