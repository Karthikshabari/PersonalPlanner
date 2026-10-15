import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/experiment_actions_menu.dart';

import '../helpers/test_container.dart';

void main() {
  // Wednesday Oct 7 2026, midday planner time.
  final now = PlannerTimeZone.calendarDate(2026, 10, 7, hour: 12);

  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () => now,
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  ExperimentRepository repoOf(ProviderContainer c) =>
      ExperimentRepository(c.read(appDatabaseProvider));

  Future<Experiment> running(
    WidgetTester tester,
    ProviderContainer container, {
    String name = 'Learn C',
    int checkIns = 0,
  }) => runDb(tester, () async {
    final repo = repoOf(container);
    final e = await repo.createExperiment(
      name: name,
      startDate: '2026-10-05',
      endDate: '2026-10-11',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 1,
    );
    for (var i = 0; i < checkIns; i++) {
      await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-0${5 + i}',
        note: 'ok',
        today: '2026-10-07',
      );
    }
    return e;
  });

  Future<Experiment> past(
    WidgetTester tester,
    ProviderContainer container,
    String name,
    ExperimentOutcome outcome,
  ) => runDb(tester, () async {
    final repo = repoOf(container);
    final e = await repo.createExperiment(
      name: name,
      startDate: '2026-08-01',
      endDate: '2026-08-07',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 7,
    );
    return repo.concludeExperiment(
      e.id,
      outcome: outcome,
      today: '2026-10-07',
      expectedRevision: e.revision,
    );
  });

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    expect(finder, findsOneWidget, reason: key);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    expect(finder, findsOneWidget, reason: text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  /// ⋮ menu of [e] -> Delete experiment, which opens the confirmation.
  Future<void> chooseDelete(WidgetTester tester, Experiment e) async {
    await tapKey(tester, 'experiment-menu-${e.id}');
    await tapText(tester, 'Delete experiment');
    expect(find.text('Delete experiment?'), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    await settle(tester);
  }

  testWidgets('running row: menu, confirmation with check-ins, Cancel keeps '
      'the row, Delete shows the Undo line, Undo restores it', (tester) async {
    final container = await open(tester);
    final e = await running(tester, container, checkIns: 2);
    await settle(tester);

    expect(find.byTooltip('More actions'), findsOneWidget);
    await chooseDelete(tester, e);
    expect(
      find.text(
        '"Learn C" will be removed from Insights on all your devices. '
        'Its 2 check-ins go with it. '
        'Your blocks keep the tag "Learn C" and their time.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);
    expect(find.byKey(ValueKey('experiment-row-${e.id}')), findsOneWidget);
    expect(find.textContaining('Deleted Learn C'), findsNothing);

    await chooseDelete(tester, e);
    await confirm(tester);
    expect(find.byKey(ValueKey('experiment-row-${e.id}')), findsNothing);
    expect(find.text('Deleted Learn C.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.byKey(const ValueKey('experiments-empty')), findsOneWidget);

    await tapKey(tester, 'experiment-undo-delete-${e.id}');
    await settle(tester);
    expect(find.text('Deleted Learn C.'), findsNothing);
    expect(find.byKey(ValueKey('experiment-row-${e.id}')), findsOneWidget);
    expect(find.text('Running (1)'), findsOneWidget);
    expect(await runDb(tester, () => repoOf(container).countCheckIns(e.id)), 2);

    await teardownApp(tester, container);
  });

  testWidgets('concluded row: the confirmation leaves out the check-in '
      'sentence when there are none', (tester) async {
    final container = await open(tester);
    final e = await past(
      tester,
      container,
      'Stopped one',
      ExperimentOutcome.drop,
    );
    await settle(tester);
    await tapText(tester, 'Concluded (1)');

    await chooseDelete(tester, e);
    expect(
      find.text(
        '"Stopped one" will be removed from Insights on all your devices. '
        'Your blocks keep the tag "Stopped one" and their time.',
      ),
      findsOneWidget,
    );
    await confirm(tester);
    expect(find.text('Deleted Stopped one.'), findsOneWidget);
    expect(find.byKey(const ValueKey('experiments-empty')), findsOneWidget);

    await teardownApp(tester, container);
  });

  testWidgets('kept row: the menu deletes it from the Kept segment and Undo '
      'brings it back', (tester) async {
    final container = await open(tester);
    final e = await past(tester, container, 'Kept one', ExperimentOutcome.keep);
    await settle(tester);
    await tapText(tester, 'Kept (1)');
    expect(find.byKey(ValueKey('kept-row-${e.id}')), findsOneWidget);

    await chooseDelete(tester, e);
    await confirm(tester);
    expect(find.byKey(ValueKey('kept-row-${e.id}')), findsNothing);
    expect(find.text('Deleted Kept one.'), findsOneWidget);
    expect(find.byKey(const ValueKey('experiments-empty')), findsOneWidget);

    await tapKey(tester, 'experiment-undo-delete-${e.id}');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-row-${e.id}')), findsOneWidget);
    expect(find.text('Deleted Kept one.'), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('the line follows the last delete, and the empty card keeps it', (
    tester,
  ) async {
    final container = await open(tester);
    final a = await running(tester, container, name: 'First');
    final b = await running(tester, container, name: 'Second');
    await settle(tester);

    await chooseDelete(tester, a);
    await confirm(tester);
    expect(find.text('Deleted First.'), findsOneWidget);
    await chooseDelete(tester, b);
    await confirm(tester);
    expect(find.text('Deleted First.'), findsNothing);
    expect(find.text('Deleted Second.'), findsOneWidget);
    expect(find.byKey(const ValueKey('experiments-empty')), findsOneWidget);

    await teardownApp(tester, container);
  });

  testWidgets('Undo after the experiment changed shows the error and removes '
      'the line', (tester) async {
    final container = await open(tester);
    final e = await running(tester, container);
    await settle(tester);
    await chooseDelete(tester, e);
    await confirm(tester);
    expect(find.text('Deleted Learn C.'), findsOneWidget);

    // Another device restored it and deleted it again: the revision moved on.
    await runDb(tester, () async {
      final repo = repoOf(container);
      final row = await container
          .read(appDatabaseProvider)
          .experimentDao
          .getExperimentById(e.id);
      await repo.restoreExperiment(e.id, expectedRevision: row!.revision);
      await repo.deleteExperiment(e.id, expectedRevision: row.revision + 1);
    });
    await tapKey(tester, 'experiment-undo-delete-${e.id}');
    await settle(tester);
    expect(find.text(experimentUndoDeleteFailed), findsOneWidget);
    expect(find.text('Deleted Learn C.'), findsNothing);
    expect(find.byKey(ValueKey('experiment-row-${e.id}')), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('the start form refuses the name of a deleted experiment with '
      'the deleted-name message', (tester) async {
    final container = await open(tester);
    final e = await running(tester, container);
    await settle(tester);
    await chooseDelete(tester, e);
    await confirm(tester);

    await tapKey(tester, 'experiments-start');
    await tester.enterText(
      find.byKey(const ValueKey('experiment-name')),
      'learn c',
    );
    await settle(tester);
    expect(
      find.text(
        'An experiment called "Learn C" was deleted. Pick a different name.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('already uses the tag'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('experiment-start-submit')),
          )
          .onPressed,
      isNull,
    );

    await teardownApp(tester, container);
  });
}
