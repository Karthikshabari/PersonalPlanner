import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/widgets/task_block_widget.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

/// QA phase 5: the overlap marker ignores Cancelled blocks (Day and Week) and
/// Needs attention > Edit opens the desktop editor on the item's day.
void main() {
  setUp(() => appRouter.go('/day'));

  final day = DateTime(2027, 3, 15);

  Task block(String title, int startMinutes, int endMinutes) => Task(
    id: '',
    title: title,
    startTime: day.add(Duration(minutes: startMinutes)),
    endTime: day.add(Duration(minutes: endMinutes)),
    createdAt: day,
    updatedAt: day,
  );

  Future<(ProviderContainer, Task, Task)> pumpOverlap(
    WidgetTester tester,
    String route,
  ) async {
    final container = await buildTestContainer(tester);
    final repo = container.read(taskRepositoryProvider);
    final first = await runDb(
      tester,
      () => repo.insertTask(block('Alpha', 9 * 60, 10 * 60)),
    );
    final second = await runDb(
      tester,
      () => repo.insertTask(block('Beta', 9 * 60 + 30, 10 * 60 + 30)),
    );
    container.read(selectedDateProvider.notifier).state = day;
    appRouter.go(route);
    await pumpApp(tester, container, surface: const Size(1600, 1000));
    return (container, first, second);
  }

  Finder markers() => find.byWidgetPredicate(
    (widget) => widget is TaskBlockWidget && widget.hasOverlap,
  );

  for (final route in ['/day', '/week']) {
    testWidgets('$route: a Cancelled block clears the overlap marker', (
      tester,
    ) async {
      final (container, _, second) = await pumpOverlap(tester, route);
      expect(find.byType(TaskBlockWidget), findsNWidgets(2));
      expect(markers(), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('overlapping task')), findsWidgets);

      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .updateTask(second.copyWith(status: TaskStatus.cancelled)),
      );
      await settle(tester);

      expect(markers(), findsNothing);
      expect(find.bySemanticsLabel(RegExp('overlapping task')), findsNothing);
      await finish(tester, container);
    });
  }

  testWidgets('Needs attention Edit on desktop opens the editor', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final overdue = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Overdue elsewhere',
              startTime: DateTime(
                yesterday.year,
                yesterday.month,
                yesterday.day,
                8,
              ),
              endTime: DateTime(
                yesterday.year,
                yesterday.month,
                yesterday.day,
                9,
              ),
              createdAt: day,
              updatedAt: day,
            ),
          ),
    );
    container.read(selectedDateProvider.notifier).state = day;
    await pumpApp(tester, container, surface: const Size(1600, 1000));
    expect(container.read(taskEditorOpenProvider), isFalse);

    await tester.tap(find.byKey(ValueKey('inbox-menu-${overdue.id}')));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);

    expect(container.read(selectedTaskIdProvider), overdue.id);
    expect(container.read(taskEditorOpenProvider), isTrue);
    expect(
      container.read(selectedDateProvider),
      startOfDay(overdue.startTime!),
    );
    expect(find.byKey(const ValueKey('save-task-button')), findsOneWidget);
    await finish(tester, container);
  });
}
