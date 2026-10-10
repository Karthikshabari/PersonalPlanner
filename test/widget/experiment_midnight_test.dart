import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';

import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart';

void main() {
  testWidgets('Experiments follow the planner clock past midnight', (
    tester,
  ) async {
    setupSqliteForTests();
    // The same approach as analytics_calendar_clock_test.dart: the existing
    // Insights clock fires at planner midnight and re-reads the factory.
    var now = PlannerTimeZone.calendarDate(
      2026,
      10,
      6,
      hour: 23,
      minute: 59,
      second: 59,
    );
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () => now,
    );
    // A weekly experiment: its only slot is Oct 6 (start + 7 - 1) and the
    // window ends on Oct 7, so midnight moves it from "due today" to "missed"
    // and brings the end panel.
    final e = await runDb(
      tester,
      () =>
          ExperimentRepository(container.read(appDatabaseProvider))
              .createExperiment(
                name: 'Learn C',
                startDate: '2026-09-30',
                endDate: '2026-10-07',
                weekdayTargetMin: 60,
                weekendTargetMin: 90,
                checkInEveryDays: 7,
              ),
    );
    // Oct 7 has 30 planned tagged minutes, which only the new day's line shows.
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Tagged block',
              startTime: PlannerTimeZone.calendarDate(2026, 10, 7, hour: 14),
              endTime: PlannerTimeZone.calendarDate(
                2026,
                10,
                7,
                hour: 14,
                minute: 30,
              ),
              status: TaskStatus.planned,
              tagId: e.tagId,
              createdAt: now,
              updatedAt: now,
            ),
          ),
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1200, 1000));

    List<String> todayLine() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey('experiment-today-${e.id}')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .take(4)
        .toList();

    expect(isoDateString(container.read(insightsNowProvider)), '2026-10-06');
    expect(find.text('1 due today'), findsOneWidget);
    expect(find.text('1 missed'), findsNothing);
    expect(todayLine(), ['Today', '0m done', '0m still planned', 'target 1h']);
    expect(find.byKey(ValueKey('end-panel-${e.id}')), findsNothing);

    now = PlannerTimeZone.calendarDate(2026, 10, 7, second: 1);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    expect(isoDateString(container.read(insightsNowProvider)), '2026-10-07');
    // The slot of Oct 6 is now behind us: a missed chip replaces the due one.
    expect(find.text('1 due today'), findsNothing);
    expect(find.text('1 missed'), findsOneWidget);
    // The today line moved to the new day (it shows that day's planned block).
    expect(todayLine(), ['Today', '0m done', '30m still planned', 'target 1h']);
    // Oct 7 is the end date: the end panel is there.
    expect(find.byKey(ValueKey('end-panel-${e.id}')), findsOneWidget);
    expect(find.text('The end date has arrived'), findsOneWidget);

    await teardownApp(tester, container);
  });
}
