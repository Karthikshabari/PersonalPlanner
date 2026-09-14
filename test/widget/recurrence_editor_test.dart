import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/recurring/providers/recurring_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  Task taskOnViewedDay(String title) {
    // Place the block at the current hour so the auto-scrolled timeline
    // keeps it on screen.
    final now = DateTime.now();
    final hour = now.hour >= 22 ? 20 : now.hour;
    return Task(
      id: '',
      title: title,
      startTime: DateTime(now.year, now.month, now.day, hour),
      endTime: DateTime(now.year, now.month, now.day, hour + 1),
      estimatedDurationMin: 60,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  RecurringRule dailyRuleFor(Task task) {
    final start = task.startTime!;
    return RecurringRule(
      id: '',
      rrule: 'FREQ=DAILY',
      taskTitle: task.title,
      durationMin: 60,
      startTimeOfDay:
          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
      startDate: DateTime(start.year, start.month, start.day),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> openEditor(
    WidgetTester tester,
    ProviderContainer container,
    Task inserted,
  ) async {
    await tester.tap(find.byKey(ValueKey('task-block-${inserted.id}')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('selected-task-edit-${inserted.id}')));
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), inserted.id);
    expect(find.text('Edit Task'), findsOneWidget);
  }

  /// Scrolls the editor panel so [target] sits comfortably inside its
  /// viewport (the timeline is a separate Scrollable; the panel's viewport
  /// shares edges with the header/inbox strips, so plain ensureVisible can
  /// leave widgets obscured).
  Future<void> bringIntoView(WidgetTester tester, Finder target) async {
    final editorScrollable = find
        .ancestor(of: target, matching: find.byType(Scrollable))
        .last;
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
    fail('target never became visible: $target');
  }

  Future<void> chooseDropdownItem(
    WidgetTester tester,
    Key fieldKey,
    String label,
  ) async {
    await bringIntoView(tester, find.byKey(fieldKey));
    await tester.tap(find.byKey(fieldKey));
    await settle(tester);
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  Future<void> saveTask(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('save-task-button'));
    await tester.tap(button);
    await settle(tester);
  }

  testWidgets('picking Daily creates a rule and links the instance', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(taskOnViewedDay('Recur me')),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);

    // No rule yet: saving without touching Repeat must not create one.
    await saveTask(tester);
    var rules = await runDb(
      tester,
      () => container.read(recurringRepositoryProvider).getActiveRules(),
    );
    expect(rules, isEmpty);

    // Pick "Daily".
    await chooseDropdownItem(
      tester,
      const ValueKey('recurrence-picker'),
      'Daily',
    );
    await saveTask(tester);

    rules = await runDb(
      tester,
      () => container.read(recurringRepositoryProvider).getActiveRules(),
    );
    expect(rules, hasLength(1));
    expect(rules.single.rrule, 'FREQ=DAILY');
    expect(rules.single.taskTitle, 'Recur me');
    expect(rules.single.durationMin, 60);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
    );
    expect(saved!.recurringRuleId, rules.single.id);

    // The block shows the recurring indicator.
    expect(find.byKey(const ValueKey('recurring-indicator')), findsOneWidget);
    await teardownApp(tester, container);
  });

  testWidgets('saving an existing recurring instance asks for scope', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final rulesRepo = container.read(recurringRepositoryProvider);
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(taskOnViewedDay('Series')),
    );
    await runDb(tester, () => rulesRepo.createRule(dailyRuleFor(inserted)));
    final rule = (await runDb(tester, () => rulesRepo.getActiveRules())).single;
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(inserted.copyWith(recurringRuleId: rule.id)),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);

    final titleField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Title',
    );
    await tester.enterText(titleField, 'Renamed series');

    await saveTask(tester);

    // Scope dialog appeared.
    expect(find.text('This occurrence only'), findsOneWidget);
    expect(find.text('This and all future'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scope-all-future')));
    await settle(tester);
    // R14 asks after scope resolution. Replacement retains this pre-R14
    // scope test's intent without creating title-history evidence.
    await tester.tap(find.byKey(const ValueKey('plan-change-replace')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
    );
    expect(saved!.title, 'Renamed series');
    final updatedRule = await runDb(
      tester,
      () => rulesRepo.getRuleById(rule.id),
    );
    // Template fields follow the edit ("this and all future").
    expect(updatedRule!.taskTitle, 'Renamed series');
    await teardownApp(tester, container);
  });

  testWidgets('"this occurrence only" leaves the rule untouched', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final rulesRepo = container.read(recurringRepositoryProvider);
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(taskOnViewedDay('Keep rule')),
    );
    await runDb(tester, () => rulesRepo.createRule(dailyRuleFor(inserted)));
    final rule = (await runDb(tester, () => rulesRepo.getActiveRules())).single;
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(inserted.copyWith(recurringRuleId: rule.id)),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);
    final titleField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Title',
    );
    await tester.enterText(titleField, 'Only this one');
    await saveTask(tester);

    await tester.tap(find.byKey(const ValueKey('scope-this-occurrence')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-change-replace')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
    );
    expect(saved!.title, 'Only this one');
    final untouched = await runDb(tester, () => rulesRepo.getRuleById(rule.id));
    expect(untouched!.taskTitle, 'Keep rule');
    await teardownApp(tester, container);
  });

  testWidgets(
    'cancelled recurrence edit writes nothing and keeps end semantics',
    (tester) async {
      final container = await buildTestContainer(tester);
      final rulesRepo = container.read(recurringRepositoryProvider);
      final inserted = await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(taskOnViewedDay('Cancel recurrence')),
      );
      final createdRule = dailyRuleFor(inserted)
          .copyWith(rrule: 'FREQ=DAILY;COUNT=4');
      await runDb(tester, () => rulesRepo.createRule(createdRule));
      final rule = (await runDb(
        tester,
        () => rulesRepo.getActiveRules(),
      )).single;
      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .updateTask(inserted.copyWith(recurringRuleId: rule.id)),
      );
      await pumpApp(tester, container, surface: const Size(1400, 1000));

      await openEditor(tester, container, inserted);
      await saveTask(tester);
      await tester.tap(find.text('Cancel').last);
      await settle(tester);

      final unchangedTask = await runDb(
        tester,
        () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
      );
      final unchangedRule = await runDb(
        tester,
        () => rulesRepo.getRuleById(rule.id),
      );
      expect(unchangedTask!.title, 'Cancel recurrence');
      expect(unchangedRule!.rrule, 'FREQ=DAILY;COUNT=4');
      await finish(tester, container);
    },
  );

  testWidgets('unchanged all-future recurrence edit preserves COUNT', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final rulesRepo = container.read(recurringRepositoryProvider);
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(taskOnViewedDay('Keep count')),
    );
    await runDb(
      tester,
      () => rulesRepo.createRule(
        dailyRuleFor(inserted).copyWith(rrule: 'FREQ=DAILY;COUNT=4'),
      ),
    );
    final rule = (await runDb(tester, () => rulesRepo.getActiveRules())).single;
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(inserted.copyWith(recurringRuleId: rule.id)),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);
    await saveTask(tester);
    await tester.tap(find.byKey(const ValueKey('scope-all-future')));
    await settle(tester);

    final unchangedRule = await runDb(
      tester,
      () => rulesRepo.getRuleById(rule.id),
    );
    expect(unchangedRule!.rrule, 'FREQ=DAILY;COUNT=4');
    await finish(tester, container);
  });

  testWidgets('Never + "this occurrence only" detaches just the task', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final rulesRepo = container.read(recurringRepositoryProvider);
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(taskOnViewedDay('Detach me')),
    );
    await runDb(tester, () => rulesRepo.createRule(dailyRuleFor(inserted)));
    final rule = (await runDb(tester, () => rulesRepo.getActiveRules())).single;
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .updateTask(inserted.copyWith(recurringRuleId: rule.id)),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);
    await chooseDropdownItem(
      tester,
      const ValueKey('recurrence-picker'),
      'Never',
    );
    await saveTask(tester);

    expect(find.text('This occurrence only'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-this-occurrence')));
    await settle(tester);

    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
    );
    expect(saved!.recurringRuleId, isNull);
    // Series itself stays alive.
    final kept = await runDb(tester, () => rulesRepo.getRuleById(rule.id));
    expect(kept!.isActive, isTrue);
    expect(find.byKey(const ValueKey('recurring-indicator')), findsNothing);
    await teardownApp(tester, container);
  });

  testWidgets('delete offers single vs all-future scope', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    final rulesRepo = container.read(recurringRepositoryProvider);
    final tasksRepo = container.read(taskRepositoryProvider);
    final inserted = await runDb(
      tester,
      () => tasksRepo.insertTask(taskOnViewedDay('Delete me')),
    );
    await runDb(tester, () => rulesRepo.createRule(dailyRuleFor(inserted)));
    final rule = (await runDb(tester, () => rulesRepo.getActiveRules())).single;
    await runDb(
      tester,
      () => tasksRepo.updateTask(inserted.copyWith(recurringRuleId: rule.id)),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester);

    // Confirm delete…
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    // …then pick "All future occurrences".
    expect(find.text('This occurrence only'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-all-future')));
    await settle(tester);

    final deleted = await runDb(
      tester,
      () => tasksRepo.getTaskById(inserted.id),
    );
    expect(deleted!.deletedAt, isNotNull);
    final ended = await runDb(tester, () => rulesRepo.getRuleById(rule.id));
    expect(ended!.isActive, isFalse);
    final expectedEnd = DateTime(
      inserted.startTime!.year,
      inserted.startTime!.month,
      inserted.startTime!.day,
    ).subtract(const Duration(days: 1));
    expect(ended.endDate, expectedEnd);
    expect(find.text('Recurring series ended'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('delete "this occurrence only" soft-deletes and adds exception', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    final rulesRepo = container.read(recurringRepositoryProvider);
    final tasksRepo = container.read(taskRepositoryProvider);
    final inserted = await runDb(
      tester,
      () => tasksRepo.insertTask(taskOnViewedDay('Skip once')),
    );
    await runDb(tester, () => rulesRepo.createRule(dailyRuleFor(inserted)));
    final rule = (await runDb(tester, () => rulesRepo.getActiveRules())).single;
    await runDb(
      tester,
      () => tasksRepo.updateTask(inserted.copyWith(recurringRuleId: rule.id)),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await openEditor(tester, container, inserted);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('scope-this-occurrence')));
    await settle(tester);

    final deleted = await runDb(
      tester,
      () => tasksRepo.getTaskById(inserted.id),
    );
    expect(deleted!.deletedAt, isNotNull);
    final kept = await runDb(tester, () => rulesRepo.getRuleById(rule.id));
    // The series stays alive; this date can never re-materialize.
    expect(kept!.isActive, isTrue);
    expect(kept.endDate, isNull);
    final start = inserted.startTime!;
    expect(
      kept.exceptions,
      contains(
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
      ),
    );
    expect(find.text('Occurrence deleted'), findsOneWidget);
    await finish(tester, container);
  });
}
