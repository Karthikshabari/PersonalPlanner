import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import 'test_container.dart';

/// A fixed past day: no now-line, and the timeline anchors at 07:00.
final DateTime responsiveDay = DateTime(2026, 3, 10);

/// The clock the Inbox and Day's attention list see.
final DateTime responsiveNow = DateTime(2026, 3, 10, 10, 30);

/// Pumps Day at [size] with three blocks on [responsiveDay], [overdue] planned
/// tasks that ended before [responsiveNow] and one Inbox capture due that
/// day. With [blocks] false the day has no timeline blocks: with the Ahem test
/// font TaskBlockWidget's status/duration row overflows at 360 wide and text
/// scale 1.5 (a block-text issue, not the Day layout; real fonts fit, see the
/// goldens), so that case checks the layout without blocks.
Future<ProviderContainer> pumpResponsiveDay(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  int overdue = 13,
  bool blocks = true,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = await buildTestContainer(
    tester,
    inboxNowFactory: () => responsiveNow,
    minuteClockFactory: () => Stream<DateTime>.value(responsiveNow),
  );
  final repo = container.read(taskRepositoryProvider);
  Task block(String title, DateTime day, int startMin, int endMin) => Task(
    id: '',
    title: title,
    startTime: day.add(Duration(minutes: startMin)),
    endTime: day.add(Duration(minutes: endMin)),
    createdAt: responsiveDay,
    updatedAt: responsiveDay,
  );
  for (final task in [
    if (blocks) ...[
      block('Write project report', responsiveDay, 9 * 60, 10 * 60 + 30),
      block('Review pull requests', responsiveDay, 11 * 60, 11 * 60 + 30),
      block('Plan the week', responsiveDay, 14 * 60, 15 * 60),
    ],
    for (var i = 0; i < overdue; i++)
      block(
        'Overdue ${i + 1}',
        responsiveDay.subtract(Duration(days: 1 + i)),
        9 * 60,
        10 * 60,
      ),
  ]) {
    await runDb(tester, () => repo.insertTask(task));
  }
  await runDb(
    tester,
    () => container
        .read(inboxRepositoryProvider)
        .addToInbox('Send the signed lease back', dueDate: '2026-03-10'),
  );
  container.read(selectedDateProvider.notifier).state = responsiveDay;
  appRouter.go('/day');
  await pumpApp(tester, container, surface: size);
  container.read(selectedDateProvider.notifier).state = responsiveDay;
  await settle(tester);
  return container;
}
