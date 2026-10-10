import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';

import '../helpers/test_container.dart';

/// How often the Kept list and each Kept row are rebuilt. A bar tap rebuilds
/// that row only; a write to an untagged task rebuilds nothing.
void main() {
  late Map<String, int> rows;
  late int list;

  void startCounting() {
    rows = {};
    list = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final name = element.widget.runtimeType.toString();
      if (name == 'KeptExperimentList') list++;
      if (name == 'KeptExperimentRow') {
        final key = element.widget.key! as ValueKey<String>;
        final id = key.value.replaceFirst('kept-row-', '');
        rows[id] = (rows[id] ?? 0) + 1;
      }
    };
  }

  Future<(ProviderContainer, Experiment, Experiment)> pumpKept(
    WidgetTester tester,
  ) async {
    final now = PlannerTimeZone.calendarDate(2026, 10, 10, hour: 12);
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () => now,
    );
    Future<Experiment> keep(String name) => runDb(tester, () async {
      final repo = ExperimentRepository(container.read(appDatabaseProvider));
      final created = await repo.createExperiment(
        name: name,
        startDate: '2026-09-04',
        endDate: '2026-10-03',
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        checkInEveryDays: 7,
      );
      return repo.concludeExperiment(
        created.id,
        outcome: ExperimentOutcome.keep,
        today: '2026-10-09',
        expectedRevision: created.revision,
      );
    });
    final first = await keep('Morning pages');
    final second = await keep('Evening walk');
    for (final e in [first, second]) {
      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'Tagged block',
                startTime: PlannerTimeZone.calendarDate(2026, 10, 7, hour: 9),
                endTime: PlannerTimeZone.calendarDate(2026, 10, 7, hour: 10),
                status: TaskStatus.completed,
                actualDurationMin: 60,
                tagId: e.tagId,
                createdAt: now,
                updatedAt: now,
              ),
            ),
      );
    }
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1400, 1400));
    final segment = find.text('Kept (2)');
    await tester.ensureVisible(segment);
    await tester.pump();
    await tester.tap(segment);
    await settle(tester);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    return (container, first, second);
  }

  testWidgets('tapping a bar rebuilds that row only', (tester) async {
    final (container, first, second) = await pumpKept(tester);
    final bar = find.byKey(ValueKey('kept-bar-${first.id}-2026-09-07'));
    await tester.ensureVisible(bar);
    await settle(tester);
    startCounting();
    await tester.tap(bar);
    await settle(tester);

    expect(rows[first.id], greaterThan(0), reason: 'the tapped row: $rows');
    expect(rows[second.id] ?? 0, 0, reason: 'the other row: $rows');
    expect(list, 0, reason: 'the list');
    debugOnRebuildDirtyWidget = null;
    await teardownApp(tester, container);
  });

  testWidgets('opening the explain panel rebuilds that row only', (
    tester,
  ) async {
    final (container, first, second) = await pumpKept(tester);
    final toggle = find.byKey(ValueKey('kept-explain-toggle-${first.id}'));
    await tester.ensureVisible(toggle);
    await settle(tester);
    startCounting();
    await tester.tap(toggle);
    await settle(tester);

    expect(rows[first.id], greaterThan(0));
    expect(rows[second.id] ?? 0, 0);
    expect(list, 0);
    debugOnRebuildDirtyWidget = null;
    await teardownApp(tester, container);
  });

  testWidgets('inserting an untagged task rebuilds nothing', (tester) async {
    final (container, first, second) = await pumpKept(tester);
    await settle(tester);
    startCounting();
    final now = PlannerTimeZone.calendarDate(2026, 10, 8, hour: 12);
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Untagged block',
              startTime: PlannerTimeZone.calendarDate(2026, 10, 8, hour: 9),
              endTime: PlannerTimeZone.calendarDate(2026, 10, 8, hour: 10),
              status: TaskStatus.completed,
              actualDurationMin: 60,
              createdAt: now,
              updatedAt: now,
            ),
          ),
    );
    await settle(tester);
    await settle(tester);

    expect(list, 0, reason: 'the list');
    expect(rows[first.id] ?? 0, 0, reason: 'row 1: $rows');
    expect(rows[second.id] ?? 0, 0, reason: 'row 2: $rows');
    debugOnRebuildDirtyWidget = null;
    await teardownApp(tester, container);
  });
}
