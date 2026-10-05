import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/recurring/providers/recurring_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

/// UAT F-001 / F-007: the open editor must keep describing the persisted
/// task — after a delete, and after the viewed day changes.
void main() {
  setUp(() => appRouter.go('/day'));

  final viewDay = DateTime(2027, 3, 15);
  final start = DateTime(2027, 3, 15, 9);

  Future<Task> insertTask(
    WidgetTester tester,
    ProviderContainer container,
    String title,
  ) {
    return runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: title,
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              estimatedDurationMin: 60,
              createdAt: start,
              updatedAt: start,
            ),
          ),
    );
  }

  Future<void> openEditor(
    WidgetTester tester,
    ProviderContainer container,
    Task task,
  ) async {
    container.read(selectedTaskIdProvider.notifier).state = task.id;
    container.read(taskEditorOpenProvider.notifier).state = true;
    await settle(tester);
    expect(find.text('Edit Task'), findsOneWidget);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    await settle(tester);
  }

  /// Attaches a daily rule to [task] the way the editor's Repeat picker does.
  Future<Task> makeRecurring(
    WidgetTester tester,
    ProviderContainer container,
    Task task,
  ) async {
    final rules = container.read(recurringRepositoryProvider);
    final rule = await runDb(
      tester,
      () => rules.createRule(
        RecurringRule(
          id: '',
          rrule: 'FREQ=DAILY',
          taskTitle: task.title,
          durationMin: 60,
          startTimeOfDay: '09:00',
          startDate: viewDay,
          createdAt: start,
          updatedAt: start,
        ),
      ),
    );
    final linked = task.copyWith(recurringRuleId: rule.id);
    await runDb(
      tester,
      () => container.read(taskRepositoryProvider).updateTask(linked),
    );
    return linked;
  }

  Future<int> outboxCount(WidgetTester tester, ProviderContainer container) =>
      runDb(
        tester,
        () => container
            .read(appDatabaseProvider)
            .customSelect('SELECT COUNT(*) AS c FROM sync_log')
            .getSingle()
            .then((row) => row.read<int>('c')),
      );

  Future<int> revisionOf(
    WidgetTester tester,
    ProviderContainer container,
    String id,
  ) => runDb(
    tester,
    () => container
        .read(taskRepositoryProvider)
        .getTaskWithRevision(id)
        .then((snapshot) => snapshot!.$2),
  );

  testWidgets('deleting the task open in the editor closes the editor', (
    tester,
  ) async {
    // Desktop: the block opens its context menu on right-click.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    final task = await insertTask(tester, container, 'Delete while open');
    container.read(selectedDateProvider.notifier).state = viewDay;
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await openEditor(tester, container, task);

    // Save an edit first: the stale snapshot the bug fell back to predates it.
    await tester.enterText(field('Description'), 'Saved description');
    await tapSave(tester);
    expect(fieldText(tester, 'Description'), 'Saved description');

    // Real delete path: block context menu -> Delete -> confirm.
    await tester.tap(
      find.byKey(ValueKey('task-block-${task.id}')),
      buttons: kSecondaryMouseButton,
    );
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(find.text('Delete task?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    final raw = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    expect(raw!.deletedAt, isNotNull);
    expect(container.read(selectedTaskIdProvider), isNull);
    expect(find.text('Edit Task'), findsNothing);
    expect(find.textContaining('Something went wrong'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
    await finish(tester, container);
  });

  testWidgets(
    'saved occurrence title survives viewing another day (this occurrence)',
    (tester) async {
      final container = await buildTestContainer(tester);
      final task = await makeRecurring(
        tester,
        container,
        await insertTask(tester, container, 'Series title'),
      );
      container.read(selectedDateProvider.notifier).state = viewDay;
      await pumpApp(tester, container, surface: const Size(1400, 1000));
      await openEditor(tester, container, task);

      await tester.enterText(field('Title'), 'Edited occurrence');
      await tapSave(tester);
      await tester.tap(find.byKey(const ValueKey('scope-this-occurrence')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('plan-change-replace')));
      await settle(tester);
      expect(fieldText(tester, 'Title'), 'Edited occurrence');

      // The editor stays bound to this task while another day is viewed.
      container.read(selectedDateProvider.notifier).state = viewDay.add(
        const Duration(days: 1),
      );
      await settle(tester);
      expect(container.read(selectedTaskIdProvider), task.id);
      expect(fieldText(tester, 'Title'), 'Edited occurrence');

      // Nothing is dirty, so leaving does not ask to discard.
      await tester.tap(find.byTooltip('Close editor'));
      await settle(tester);
      expect(find.text('Discard unsaved changes?'), findsNothing);
      final saved = await runDb(
        tester,
        () => container.read(taskRepositoryProvider).getTaskById(task.id),
      );
      expect(saved!.title, 'Edited occurrence');
      await finish(tester, container);
    },
  );

  testWidgets('a clean Save on a recurring task prompts for and writes nothing', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await makeRecurring(
      tester,
      container,
      await insertTask(tester, container, 'Clean series'),
    );
    container.read(selectedDateProvider.notifier).state = viewDay;
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await openEditor(tester, container, task);
    final revision = await revisionOf(tester, container, task.id);
    final outbox = await outboxCount(tester, container);

    await tapSave(tester);

    expect(find.text('This occurrence only'), findsNothing);
    expect(find.text('No changes to save'), findsOneWidget);
    expect(await revisionOf(tester, container, task.id), revision);
    expect(await outboxCount(tester, container), outbox);
    await finish(tester, container);
  });
}
