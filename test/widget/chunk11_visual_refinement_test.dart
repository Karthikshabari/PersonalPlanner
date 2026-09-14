import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/widgets/app_surface.dart';
import 'package:personal_planner/core/widgets/task_block_widget.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('semantic tokens stay available in dark and light themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AppSurface(
              child: AppSectionHeader(
                title: 'Design system probe',
                subtitle: 'Semantic state labels remain readable',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(AppSurface));
      final tokens = AppThemeTokens.of(context);
      expect(tokens.canvas, isNot(equals(Colors.transparent)));
      expect(tokens.textPrimary, isNot(equals(tokens.textMuted)));
      expect(tokens.controlHeight, greaterThanOrEqualTo(44));
      expect(find.text('Design system probe'), findsOneWidget);
      expect(
        find.text('Semantic state labels remain readable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Day View remains usable at narrow, minimum desktop, and wide sizes',
    (tester) async {
      final container = await buildTestContainer(tester);
      for (final entry in <({Size size, TargetPlatform platform})>[
        (size: const Size(360, 800), platform: TargetPlatform.android),
        (size: const Size(390, 844), platform: TargetPlatform.android),
        (size: const Size(800, 600), platform: TargetPlatform.linux),
        (size: const Size(1400, 1000), platform: TargetPlatform.linux),
      ]) {
        debugDefaultTargetPlatformOverride = entry.platform;
        appRouter.go('/day');
        await pumpApp(tester, container, surface: entry.size);

        expect(find.byKey(const ValueKey('day-week-switcher')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('day-settings-action')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sync-status-action')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('timeline-gestures')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await finish(tester, container);
    },
  );

  testWidgets('dense Day View fixture preserves task-state cues', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    final day = DateTime(2027, 3, 15);
    container.read(selectedDateProvider.notifier).state = day;
    final categories = await runDb(
      tester,
      () => container.read(categoryRepositoryProvider).getAllCategories(),
    );
    final work = categories.firstWhere((category) => category.name == 'Work');
    await runDb(
      tester,
      () => RecurringRepository(container.read(appDatabaseProvider)).createRule(
        RecurringRule(
          id: 'fixture-rule',
          rrule: 'FREQ=DAILY',
          taskTitle: 'Recurring fixture task',
          durationMin: 45,
          categoryId: work.id,
          startTimeOfDay: '06:00',
          startDate: day,
          isActive: false,
          createdAt: day,
          updatedAt: day,
        ),
      ),
    );
    final tasks = <Task>[];
    for (var index = 0; index < 24; index++) {
      final start = index == 2
          ? day.add(const Duration(hours: 23))
          : day.add(Duration(hours: 6, minutes: index * 30));
      final duration = index == 2 ? 30 : 45;
      tasks.add(
        Task(
          id: '',
          title: index == 0
              ? 'A very long planning title that must remain readable in a dense schedule'
              : 'Dense block ${index + 1}',
          startTime: start,
          endTime: start.add(Duration(minutes: duration)),
          estimatedDurationMin: duration,
          categoryId: work.id,
          status: switch (index % 4) {
            0 => TaskStatus.planned,
            1 => TaskStatus.inProgress,
            2 => TaskStatus.completed,
            _ => TaskStatus.skipped,
          },
          recurringRuleId: index == 2 ? 'fixture-rule' : null,
          createdAt: day,
          updatedAt: day,
        ),
      );
    }
    final inserted = <Task>[];
    for (final task in tasks) {
      inserted.add(
        await runDb(
          tester,
          () => container.read(taskRepositoryProvider).insertTask(task),
        ),
      );
    }
    // Use the existing timer service so the fixture exercises the same active
    // timer presentation as a real task, while preserving timer semantics.
    await runDb(
      tester,
      () =>
          TimerService(container.read(appDatabaseProvider))
              .start(inserted[0].id),
    );

    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    expect(find.byType(TaskBlockWidget), findsNWidgets(24));
    expect(
      find.descendant(
        of: find.byType(TaskBlockWidget),
        matching: find.text(
          'A very long planning title that must remain readable in a dense schedule',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('timer-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('block-timer-chip')), findsNothing);
    expect(
      (await runDb(
        tester,
        () =>
            container.read(taskRepositoryProvider).getTaskById(inserted[2].id),
      ))!.recurringRuleId,
      'fixture-rule',
    );
    expect(tester.takeException(), isNull);

    await finish(tester, container);
  });
}
