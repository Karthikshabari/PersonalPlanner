import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('Insights has exactly the two intended sections on desktop', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await tester.tap(find.text('Insights'));
    await settle(tester);

    expect(find.text('Insights'), findsWidgets);
    expect(find.byKey(const ValueKey('consistency-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('this-week-section')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('this-week-desktop-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('planned-actual-summary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('category-time-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('notable-summary')), findsNothing);
    expect(find.text('No tracked time for this week yet.'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey(
          'consistency-day-${isoDateString(startOfDay(DateTime.now()))}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Productivity trend'), findsNothing);
    expect(find.text('Completion rate'), findsNothing);
    expect(find.text('Plan follow-through'), findsNothing);

    final range = consistencyCalendarRange(startOfDay(DateTime.now()));
    final firstWeek = startOfWeek(range.start);
    final lastWeek = startOfWeek(addDays(range.endExclusive, -1));
    final weekCount = lastWeek.difference(firstWeek).inDays ~/ 7 + 1;
    final consistencyCells = tester.widgetList<InkWell>(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey &&
            ((widget.key! as ValueKey).value is String) &&
            ((widget.key! as ValueKey).value as String).startsWith(
              'consistency-day-',
            ),
      ),
    );
    expect(consistencyCells, hasLength(weekCount * 7));

    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('insights-next-week')),
    );
    expect(next.onPressed, isNull);

    await teardownApp(tester, container);
  });

  testWidgets('phone layout stacks summaries and enforces week boundary', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(390, 844));

    expect(
      find.byKey(const ValueKey('this-week-mobile-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('this-week-desktop-layout')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('consistency-grid-scroll')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('insights-next-week')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('insights-previous-week')));
    await settle(tester);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('insights-next-week')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);

    await teardownApp(tester, container);
  });

  testWidgets('real plan and actual data render with read-only day details', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final today = startOfDay(DateTime.now());
    final repository = container.read(taskRepositoryProvider);
    await runDb(
      tester,
      () => repository.insertTask(
        Task(
          id: '',
          title: 'Completed plan',
          startTime: today.add(const Duration(hours: 9)),
          endTime: today.add(const Duration(hours: 10)),
          actualDurationMin: 45,
          manualDurationAdjustmentMin: 45,
          manualActualSet: true,
          status: TaskStatus.completed,
          createdAt: today,
          updatedAt: today,
        ),
      ),
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1200, 900));

    expect(find.text('100% follow-through'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    final dayCell = find.byKey(
      ValueKey('consistency-day-${isoDateString(today)}'),
    );
    expect(dayCell, findsOneWidget);
    expect(
      find.byKey(
        ValueKey('consistency-day-${isoDateString(addDays(today, -1))}'),
      ),
      findsOneWidget,
    );
    await tester.tap(dayCell);
    await tester.pumpAndSettle();
    expect(find.text('Planned'), findsWidgets);
    expect(find.text('Actual'), findsWidgets);
    expect(find.text('45m'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await teardownApp(tester, container);
  });

  testWidgets('consistency heatmap paints full-year cells with usable sizes', (
    tester,
  ) async {
    PlannerTimeZone.initialize(identifier: 'UTC');
    final generatedFor = PlannerTimeZone.calendarDate(2026, 9, 14);
    final range = consistencyCalendarRange(generatedFor);
    final snapshot = InsightsSnapshot(
      generatedFor: generatedFor,
      consistencyStart: range.start,
      consistencyDays: [
        ConsistencyDay(
          date: PlannerTimeZone.calendarDate(2026, 9, 13),
          plannedMinutes: 300,
          completedPlannedMinutes: 240,
          actualMinutes: 30,
          isFuture: false,
        ),
        ConsistencyDay(
          date: generatedFor,
          plannedMinutes: 210,
          completedPlannedMinutes: 90,
          actualMinutes: 0,
          isFuture: false,
        ),
      ],
      streaks: const StreakSummary(current: 0, best: 1),
      weekStart: startOfWeek(generatedFor),
      weekEndExclusive: addDays(startOfWeek(generatedFor), 7),
      plannedMinutes: 510,
      actualMinutes: 30,
      completedPlannedMinutes: 330,
      categories: const [],
      notable: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppThemeTokens.light()]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: InsightsSectionCard(
              title: 'Consistency',
              child: ConsistencyGrid(snapshot: snapshot, compact: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rangeFirstWeek = startOfWeek(range.start);
    final rangeLastWeek = startOfWeek(addDays(range.endExclusive, -1));
    final weekCount = rangeLastWeek.difference(rangeFirstWeek).inDays ~/ 7 + 1;
    final cells = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.key is ValueKey &&
          ((widget.key! as ValueKey).value as String).startsWith(
            'consistency-cell-',
          ),
    );
    expect(cells, findsNWidgets(weekCount * 7));

    for (final date in ['2026-09-13', '2026-09-14', '2026-09-12']) {
      final cell = find.byKey(ValueKey('consistency-cell-$date'));
      expect(cell, findsOneWidget);
      final size = tester.getSize(cell);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    }

    final lightTokens = AppThemeTokens.light();
    final strongCell = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('consistency-cell-2026-09-13')),
    );
    expect((strongCell.decoration as BoxDecoration).color, lightTokens.success);
    final mediumCell = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('consistency-cell-2026-09-14')),
    );
    expect(
      (mediumCell.decoration as BoxDecoration).color,
      Color.alphaBlend(
        lightTokens.success.withValues(alpha: 0.42),
        lightTokens.surfaceRaised,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('consistency-day-2026-09-13')));
    await tester.pumpAndSettle();
    expect(find.text('5h'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('progress bars clamp and preserve visible fractions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          child: Column(
            children: [
              InsightsProgressBar(
                key: const ValueKey('planned-fraction'),
                fraction: 180 / 180,
                color: Colors.blue,
              ),
              InsightsProgressBar(
                key: const ValueKey('actual-fraction'),
                fraction: 30 / 180,
                color: Colors.green,
              ),
              InsightsProgressBar(
                key: const ValueKey('over-plan-fraction'),
                fraction: 60 / 30,
                color: Colors.orange,
              ),
              InsightsProgressBar(
                key: const ValueKey('zero-fraction'),
                fraction: 0 / 0,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<InsightsProgressBar>(
            find.byKey(const ValueKey('planned-fraction')),
          )
          .normalizedFraction,
      1.0,
    );
    expect(
      tester
          .widget<InsightsProgressBar>(
            find.byKey(const ValueKey('actual-fraction')),
          )
          .normalizedFraction,
      closeTo(1 / 6, 0.0001),
    );
    expect(
      tester
          .widget<InsightsProgressBar>(
            find.byKey(const ValueKey('over-plan-fraction')),
          )
          .normalizedFraction,
      1.0,
    );
    expect(
      tester
          .widget<InsightsProgressBar>(
            find.byKey(const ValueKey('zero-fraction')),
          )
          .normalizedFraction,
      0.0,
    );
  });

  testWidgets('a single category receives the full category bar', (
    tester,
  ) async {
    const category = CategoryTime(
      id: 'uncategorized',
      name: 'Uncategorized',
      colorHex: '#9AA0A6',
      actualMinutes: 30,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 240,
          child: CategoryTimeRow(category: category, maxMinutes: 30),
        ),
      ),
    );
    expect(
      tester
          .widget<InsightsProgressBar>(
            find.byKey(const ValueKey('category-bar-uncategorized')),
          )
          .normalizedFraction,
      1.0,
    );
  });

  testWidgets('category bars normalize smaller values to the largest', (
    tester,
  ) async {
    const category = CategoryTime(
      id: 'learning',
      name: 'Learning',
      colorHex: '#4285F4',
      actualMinutes: 30,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 240,
          child: CategoryTimeRow(category: category, maxMinutes: 120),
        ),
      ),
    );
    expect(
      tester
          .widget<InsightsProgressBar>(
            find.byKey(const ValueKey('category-bar-learning')),
          )
          .normalizedFraction,
      closeTo(0.25, 0.0001),
    );
  });

  testWidgets('search result still selects its task in the day view', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    final day = DateTime(2026, 8, 24);
    final taskRepository = container.read(taskRepositoryProvider);
    await runDb(
      tester,
      () => taskRepository.insertTask(
        Task(
          id: '',
          title: 'Find this insights task',
          startTime: day.add(const Duration(hours: 9)),
          endTime: day.add(const Duration(hours: 10)),
          createdAt: day,
          updatedAt: day,
        ),
      ),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await tester.tap(find.text('Search'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('search-input')),
      'insights task',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
    await tester.tap(find.text('Find this insights task'));
    await settle(tester);
    expect(find.text('Edit Task'), findsOneWidget);

    await teardownApp(tester, container);
  });
}
