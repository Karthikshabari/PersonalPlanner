import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/presentation/day_context_editor.dart';
import 'package:personal_planner/features/day_context/providers/day_context_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets(
    'Day context editor validates, persists, and never mutates tasks',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = await buildTestContainer(tester);
      final date = DateTime(2026, 9, 18);
      final dateText = isoDateString(date);
      container.read(selectedDateProvider.notifier).state = date;
      final taskRepository = container.read(taskRepositoryProvider);
      await runDb(
        tester,
        () => taskRepository.insertTask(
          Task(
            id: '',
            title: 'Friday plan',
            startTime: DateTime(2026, 9, 18, 9),
            endTime: DateTime(2026, 9, 18, 10),
            estimatedDurationMin: 60,
            status: TaskStatus.planned,
            createdAt: DateTime(2026, 9, 18, 8),
            updatedAt: DateTime(2026, 9, 18, 8),
          ),
        ),
      );

      appRouter.go('/day');
      await pumpApp(tester, container, surface: const Size(390, 844));
      final db = container.read(appDatabaseProvider);
      final tasksBefore = await runDb(tester, () => db.select(db.tasks).get());
      final taskOperationsBefore = (await runDb(
        tester,
        () => db.select(db.syncLog).get(),
      )).where((row) => row.entityTableName == 'tasks').length;

      final action = find.byKey(ValueKey('day-context-action-$dateText'));
      expect(action, findsOneWidget);
      expect(find.text('Add day context'), findsOneWidget);
      await tester.tap(action);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('day-context-kind')));
      await settle(tester);
      expect(find.text('Custom'), findsOneWidget);
      await tester.tap(find.text('Custom'));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('day-context-custom-label')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('day-context-save')));
      await settle(tester);
      expect(find.text('Enter a label.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('day-context-custom-label')),
        '  Family visit  ',
      );
      await tester.tap(find.byKey(const ValueKey('day-context-save')));
      await settle(tester);

      DayContext? context = await runDb(
        tester,
        () => container
            .read(dayContextRepositoryProvider)
            .watchForDate(dateText)
            .first,
      );
      expect(context?.displayLabel, 'Family visit');
      expect(context?.date, dateText);
      final contextId = context!.id;
      expect(find.text('Family visit'), findsOneWidget);

      final tasksAfterSave = await runDb(
        tester,
        () => db.select(db.tasks).get(),
      );
      expect(tasksAfterSave, tasksBefore);
      final taskOperationsAfter = (await runDb(
        tester,
        () => db.select(db.syncLog).get(),
      )).where((row) => row.entityTableName == 'tasks').length;
      expect(taskOperationsAfter, taskOperationsBefore);

      await tester.tap(action);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-context-remove')));
      await settle(tester);
      context = await runDb<DayContext?>(
        tester,
        () => container
            .read(dayContextRepositoryProvider)
            .watchForDate(dateText)
            .first,
      );
      expect(context, isNull);
      final tombstone = await runDb(
        tester,
        () => (db.select(
          db.dayContexts,
        )..where((row) => row.id.equals(contextId))).getSingle(),
      );
      expect(tombstone.deletedAt, isNotNull);

      await tester.tap(find.byKey(ValueKey('day-context-action-$dateText')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-context-kind')));
      await settle(tester);
      await tester.tap(find.text('Travel').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-context-save')));
      await settle(tester);
      context = await runDb<DayContext?>(
        tester,
        () => container
            .read(dayContextRepositoryProvider)
            .watchForDate(dateText)
            .first,
      );
      expect(context?.id, contextId);
      expect(context?.displayLabel, 'Travel');
      expect(
        await runDb(
          tester,
          () => (db.select(
            db.dayContexts,
          )..where((row) => row.date.equals(dateText))).get(),
        ),
        hasLength(1),
      );
      expect(await runDb(tester, () => db.select(db.tasks).get()), tasksBefore);
      await finish(tester, container);
    },
  );

  testWidgets('Week headers expose the selected date context action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    final selected = startOfWeek(DateTime(2026, 9, 18));
    final contextDate = addDays(selected, 4);
    container.read(selectedDateProvider.notifier).state = selected;
    await runDb(
      tester,
      () => container
          .read(dayContextRepositoryProvider)
          .save(isoDateString(contextDate), DayContextKind.travel, null),
    );

    appRouter.go('/week');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    expect(
      find.byKey(ValueKey('day-context-action-${isoDateString(contextDate)}')),
      findsOneWidget,
    );
    expect(find.text('Travel'), findsOneWidget);
    expect(find.byType(DayContextAction), findsNWidgets(7));
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });
}
