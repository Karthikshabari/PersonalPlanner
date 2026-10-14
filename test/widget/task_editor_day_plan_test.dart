import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

/// QA phase 5 editor cases: Actual cap, no "null" for an invalid range, and
/// the read-only "Originally planned" line.
void main() {
  setUp(() => appRouter.go('/day'));

  final date = DateTime(2027, 3, 15, 9);

  Future<Task> insert(
    WidgetTester tester,
    ProviderContainer container, {
    String title = 'Editor target',
    DateTime? start,
    int? actual,
  }) {
    final from = start ?? date;
    return runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: title,
              startTime: from,
              endTime: from.add(const Duration(hours: 1)),
              actualDurationMin: actual,
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
    container.read(selectedDateProvider.notifier).state = DateTime(
      task.startTime!.year,
      task.startTime!.month,
      task.startTime!.day,
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    container.read(selectedTaskIdProvider.notifier).state = task.id;
    container.read(taskEditorOpenProvider.notifier).state = true;
    await settle(tester);
  }

  Future<void> saveWithActual(WidgetTester tester, String text) async {
    final field = find.byKey(const ValueKey('actual-duration-field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    final button = find.byKey(const ValueKey('save-task-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
  }

  Future<int?> storedActual(
    WidgetTester tester,
    ProviderContainer container,
    String id,
  ) async => (await runDb(
    tester,
    () => container.read(taskRepositoryProvider).getTaskById(id),
  ))?.actualDurationMin;

  testWidgets('Actual duration over 1440 is rejected, 1440 is saved', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insert(tester, container, actual: 5);
    await openEditor(tester, container, task);

    await saveWithActual(tester, '1441');
    expect(
      find.text('Actual duration must be 1440 minutes or less'),
      findsWidgets,
    );
    expect(await storedActual(tester, container, task.id), 5);

    await saveWithActual(tester, 'abc');
    expect(find.text('Actual duration must be a whole number'), findsWidgets);
    await saveWithActual(tester, '-5');
    expect(find.text('Actual duration must not be negative'), findsWidgets);
    expect(await storedActual(tester, container, task.id), 5);

    await saveWithActual(tester, '1440');
    expect(await storedActual(tester, container, task.id), 1440);
    await finish(tester, container);
  });

  testWidgets('an invalid time range does not print "null"', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insert(tester, container);
    await openEditor(tester, container, task);
    expect(find.text('Planned duration: 60 minutes'), findsOneWidget);

    // Move the End date back one day: End is then before Start.
    final endDate = find.byKey(const ValueKey('schedule-end-date'));
    await tester.ensureVisible(endDate);
    await tester.tap(endDate);
    await settle(tester);
    await tester.tap(find.text('14'));
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(find.byKey(const ValueKey('schedule-fields-error')), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('Planned duration'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('a moved block shows where it started, a plain one nothing', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final repo = container.read(taskRepositoryProvider);
    final first = await insert(tester, container, title: 'First slot');
    final second = await insert(
      tester,
      container,
      title: 'Second slot',
      start: date.add(const Duration(days: 1)),
    );
    final third = await insert(
      tester,
      container,
      title: 'Third slot',
      start: date.add(const Duration(days: 2)),
    );
    for (final (from, to) in [(first, second), (second, third)]) {
      await runDb(
        tester,
        () => repo.updateTask(
          from.copyWith(status: TaskStatus.rescheduled, rescheduledToId: to.id),
          allowRescheduledTransition: true,
        ),
      );
    }
    final plain = await insert(
      tester,
      container,
      title: 'Never moved',
      start: date.add(const Duration(days: 5)),
    );

    await openEditor(tester, container, third);
    final line = find.byKey(const ValueKey('original-plan-line'));
    expect(line, findsOneWidget);
    expect(
      (tester.widget<Text>(line).data!),
      matches(
        RegExp(
          r'^Originally planned \w{3} Mar 1[45], \d\d:\d\d–\d\d:\d\d'
          r' - moved 2 times$',
        ),
      ),
    );

    container.read(selectedTaskIdProvider.notifier).state = null;
    await settle(tester);
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 20);
    container.read(selectedTaskIdProvider.notifier).state = plain.id;
    container.read(taskEditorOpenProvider.notifier).state = true;
    await settle(tester);
    expect(find.byKey(const ValueKey('original-plan-line')), findsNothing);
    await finish(tester, container);
  });
}
