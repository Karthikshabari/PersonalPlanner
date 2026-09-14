import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  final date = DateTime(2027, 4, 3, 9);

  Finder titleField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == 'Title',
  );

  Finder descriptionField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.labelText == 'Description',
  );

  Future<Task> createAndOpen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Read bok',
              description: 'Original description',
              startTime: date,
              endTime: date.add(const Duration(hours: 1)),
              createdAt: date,
              updatedAt: date,
            ),
          ),
    );
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 4, 3);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    container.read(selectedTaskIdProvider.notifier).state = task.id;
    container.read(taskEditorOpenProvider.notifier).state = true;
    for (
      var attempt = 0;
      attempt < 30 && titleField().evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(titleField(), findsOneWidget);
    return task;
  }

  Future<void> submitToDecision(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    for (
      var attempt = 0;
      attempt < 20 &&
          find.byKey(const ValueKey('plan-change-preserve')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Replace changes the title without adding an event', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(titleField(), 'Read book');
    await submitToDecision(tester);
    expect(find.byKey(const ValueKey('plan-change-replace')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-change-replace')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved?.title, 'Read book');
    expect(saved?.planTitleHistory, isEmpty);
    expect(saved?.displayPlanChangeId, isNull);
    await finish(tester, container);
  });

  testWidgets('Preserve retains repeated events and selects the latest one', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(titleField(), 'Office work');
    await submitToDecision(tester);
    await tester.tap(find.byKey(const ValueKey('plan-change-preserve')));
    await settle(tester);
    await tester.enterText(titleField(), 'Client call');
    await submitToDecision(tester);
    await tester.tap(find.byKey(const ValueKey('plan-change-preserve')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved?.planTitleHistory, hasLength(2));
    expect(saved?.planTitleHistory.first.previousTitle, 'Read bok');
    expect(saved?.planTitleHistory.last.previousTitle, 'Office work');
    expect(saved?.displayPlanChange?.previousTitle, 'Office work');
    expect(saved?.displayPlanChange?.newTitle, 'Client call');
    await tester.tap(find.byKey(const ValueKey('plan-changes-section')));
    await settle(tester);
    expect(find.text('Read bok → Office work'), findsOneWidget);
    expect(find.text('Office work → Client call'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Replace clears decoration while retaining earlier events', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(titleField(), 'Office work');
    await submitToDecision(tester);
    await tester.tap(find.byKey(const ValueKey('plan-change-preserve')));
    await settle(tester);
    await tester.enterText(titleField(), 'Client calls');
    await submitToDecision(tester);
    await tester.tap(find.byKey(const ValueKey('plan-change-replace')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved?.title, 'Client calls');
    expect(saved?.displayPlanChangeId, isNull);
    expect(saved?.planTitleHistory, hasLength(1));
    expect(saved?.planTitleHistory.single.previousTitle, 'Read bok');
    await finish(tester, container);
  });

  testWidgets('Cancel writes neither title nor history', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(titleField(), 'Office work');
    await submitToDecision(tester);
    await tester.tap(find.byKey(const ValueKey('plan-change-cancel')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved?.title, 'Read bok');
    expect(saved?.planTitleHistory, isEmpty);
    expect(
      tester.widget<TextField>(titleField()).controller?.text,
      'Office work',
    );
    await finish(tester, container);
  });

  testWidgets('description-only Save never asks for a title decision', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(descriptionField(), 'Changed description');
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    await settle(tester);

    expect(find.byKey(const ValueKey('plan-change-preserve')), findsNothing);
    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved?.description, 'Changed description');
    expect(saved?.planTitleHistory, isEmpty);
    await finish(tester, container);
  });

  testWidgets('trim-only title edits do not ask for a plan decision', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(titleField(), '  Read bok  ');
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    await settle(tester);

    expect(find.byKey(const ValueKey('plan-change-preserve')), findsNothing);
    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(saved?.title, 'Read bok');
    expect(saved?.planTitleHistory, isEmpty);
    await finish(tester, container);
  });

  testWidgets('a changed title while the dialog is open retries from remote', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await createAndOpen(tester, container);

    await tester.enterText(titleField(), 'Office work');
    await submitToDecision(tester);
    final persisted = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(persisted!.copyWith(title: 'Remote plan')),
    );
    await tester.tap(find.byKey(const ValueKey('plan-change-preserve')));
    await settle(tester);

    final staleResult = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(staleResult?.title, 'Remote plan');
    expect(staleResult?.planTitleHistory, isEmpty);

    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    for (
      var attempt = 0;
      attempt < 20 &&
          find.byKey(const ValueKey('keep-my-task')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('keep-my-task')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('keep-my-task')));
    for (
      var attempt = 0;
      attempt < 20 &&
          find.byKey(const ValueKey('plan-change-preserve')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('plan-change-preserve')));
    await settle(tester);

    final retried = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(retried?.title, 'Office work');
    expect(retried?.planTitleHistory, hasLength(1));
    expect(retried?.planTitleHistory.single.previousTitle, 'Remote plan');
    await finish(tester, container);
  });
}
