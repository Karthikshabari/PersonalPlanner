import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';

import '../helpers/test_container.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  testWidgets('Insights advances at planner midnight without resetting week', (
    tester,
  ) async {
    setupSqliteForTests();
    var now = PlannerTimeZone.calendarDate(
      2026,
      9,
      20,
      hour: 23,
      minute: 59,
      second: 59,
    );
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () => now,
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1200, 900));

    final currentWeek = startOfWeek(now);
    final selected = container.read(selectedInsightsWeekProvider.notifier);
    selected.state = currentWeek;
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('insights-next-week')))
          .onPressed,
      isNull,
    );

    now = PlannerTimeZone.calendarDate(2026, 9, 21, second: 1);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(isoDateString(container.read(insightsNowProvider)), '2026-09-21');
    expect(
      container.read(selectedInsightsWeekProvider),
      currentWeek,
      reason: 'midnight must not reset the selected week',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('insights-next-week')))
          .onPressed,
      isNotNull,
    );

    final historical = addDays(currentWeek, -14);
    selected.state = historical;
    now = PlannerTimeZone.calendarDate(2026, 9, 22, second: 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await settle(tester);

    expect(isoDateString(container.read(insightsNowProvider)), '2026-09-22');
    expect(
      container.read(selectedInsightsWeekProvider),
      historical,
      reason: 'resume must preserve deliberate historical navigation',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('insights-next-week')))
          .onPressed,
      isNotNull,
    );

    await teardownApp(tester, container);
  });

  testWidgets('Insights clock uses DST-safe planner midnight arithmetic', (
    tester,
  ) async {
    setupSqliteForTests();
    PlannerTimeZone.initialize(identifier: 'America/New_York');
    addTearDown(() => PlannerTimeZone.initialize(identifier: 'Asia/Kolkata'));

    var now = PlannerTimeZone.calendarDate(
      2026,
      3,
      7,
      hour: 23,
      minute: 59,
      second: 59,
    );
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () => now,
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1200, 900));

    // Mar 8, 2026 starts in standard time and ends in daylight time, so the
    // following planner day is 23 elapsed hours away, not a fixed 24 hours.
    now = PlannerTimeZone.calendarDate(2026, 3, 8, second: 1);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(isoDateString(container.read(insightsNowProvider)), '2026-03-08');

    now = PlannerTimeZone.calendarDate(2026, 3, 9, second: 1);
    await tester.pump(const Duration(hours: 23, seconds: 1));
    await settle(tester);
    expect(isoDateString(container.read(insightsNowProvider)), '2026-03-09');

    await teardownApp(tester, container);
  });

  testWidgets('Insights clock cleanup cancels its rollover timer', (
    tester,
  ) async {
    setupSqliteForTests();
    var nowCalls = 0;
    final now = PlannerTimeZone.calendarDate(2026, 9, 21, hour: 12);
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () {
        nowCalls++;
        return now;
      },
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1200, 900));
    final callsBeforeDispose = nowCalls;

    await teardownApp(tester, container);
    await tester.pump(const Duration(days: 2));
    expect(nowCalls, callsBeforeDispose);
  });
}
