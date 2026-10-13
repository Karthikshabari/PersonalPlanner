import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

import 'inbox_fixtures.dart';
import 'test_container.dart';

/// The Inbox screen on a fixed planner clock: Monday 2026-10-12 12:00 unless
/// [clock] says otherwise. [seed] writes through an [InboxHarness] before the
/// screen is built; [before] runs on the container just before it is built.
Future<(ProviderContainer, InboxHarness)> pumpInbox(
  WidgetTester tester, {
  Future<void> Function(InboxHarness h)? seed,
  Size surface = const Size(1400, 1800),
  void Function(ProviderContainer container)? before,
  DateTime Function()? clock,
  DateTime Function()? insightsClock,
}) async {
  final fixed = PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12);
  final container = await buildTestContainer(
    tester,
    inboxNowFactory: clock ?? () => fixed,
    insightsNowFactory: insightsClock,
  );
  final h = InboxHarness(container.read(appDatabaseProvider));
  if (seed != null) await runDb(tester, () => seed(h));
  before?.call(container);
  appRouter.go('/inbox');
  await pumpApp(tester, container, surface: surface);
  return (container, h);
}

Finder headerOf(String id) => find.byKey(ValueKey('inbox-row-header-$id'));
Finder trailOf(String id) => find.byKey(ValueKey('inbox-trail-$id'));
Finder rowOf(String id) => find.byKey(ValueKey('inbox-item-$id'));
Finder dateChip(String isoDate) => find.byKey(ValueKey('inbox-date-$isoDate'));

Future<void> expandRow(WidgetTester tester, String id) async {
  await tester.tap(headerOf(id));
  await settle(tester);
}

Future<void> pickSegment(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await settle(tester);
}

Future<void> ctrlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await settle(tester);
}

/// Whether the open panel's Save / Close it / Let go button is enabled.
bool submitEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('inbox-panel-submit')))
        .onPressed !=
    null;
