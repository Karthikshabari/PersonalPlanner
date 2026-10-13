// "Start as an experiment" from the Inbox, both entry points, and "See in
// Insights". Backing out leaves the idea unchanged; creating moves it to Done
// with a chip that follows the real experiment. Fixed clock: Monday 2026-10-12
// 12:00 in the planner zone, for the Inbox and for Insights.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/providers/experiment_providers.dart';

import '../helpers/inbox_screen_harness.dart';
import '../helpers/test_container.dart';

DateTime _fixed() => PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12);

Future<void> submitForm(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('experiment-start-submit'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await settle(tester);
}

Future<void> cancelForm(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('experiment-start-cancel'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await settle(tester);
}

Future<void> startFromFooter(WidgetTester tester, Task idea) async {
  await expandRow(tester, idea.id);
  await tester.tap(find.byKey(const ValueKey('inbox-action-experiment')));
  await settle(tester);
}

Future<List<Experiment>> experimentsOf(
  WidgetTester tester,
  ProviderContainer container,
) => runDb(
  tester,
  () =>
      ExperimentRepository(container.read(appDatabaseProvider))
          .watchExperiments()
          .first,
);

String selectedSegment(WidgetTester tester) => tester
    .widget<SegmentedButton<dynamic>>(
      find.byKey(const ValueKey('experiments-filter')),
    )
    .selected
    .single
    .toString();

void main() {
  testWidgets('the form opens with the idea\'s first line, clipped to 100', (
    tester,
  ) async {
    late Task idea;
    final longLine = 'x' * 150;
    final (container, _) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async => idea = await h.idea('$longLine\nsecond line'),
    );
    await startFromFooter(tester, idea);
    expect(find.text('New experiment'), findsOneWidget);
    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('experiment-name')),
    );
    expect(name.controller!.text, 'x' * 100);
    await cancelForm(tester);
    await finish(tester, container);
  });

  testWidgets('backing out of the form leaves the idea unchanged', (
    tester,
  ) async {
    late Task idea;
    late Task session;
    final (container, h) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        session = await h.session(idea.id, start: h.at(2, 9));
      },
    );
    final before = await runDb(tester, () => h.revisionOf(idea.id));
    await startFromFooter(tester, idea);
    expect(find.text('New experiment'), findsOneWidget);
    await cancelForm(tester);

    expect(find.text('New experiment'), findsNothing);
    expect(find.text('Open (1)'), findsOneWidget);
    expect(find.text('Done (0)'), findsOneWidget);
    final stored = await runDb(tester, () => h.reload(idea.id));
    expect(stored.inboxHistory, isEmpty);
    expect(await runDb(tester, () => h.revisionOf(idea.id)), before);
    final kept = await runDb(tester, () => h.reload(session.id));
    expect(kept.deletedAt, isNull);
    expect(await experimentsOf(tester, container), isEmpty);
    await finish(tester, container);
  });

  testWidgets('creating it moves the idea to Done and drops open sessions', (
    tester,
  ) async {
    late Task idea;
    late Task future;
    late Task missed;
    final (container, h) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        missed = await h.session(idea.id, start: h.at(-1, 9));
        future = await h.session(idea.id, start: h.at(2, 9));
      },
    );
    await startFromFooter(tester, idea);
    await submitForm(tester);

    final experiments = await experimentsOf(tester, container);
    expect(experiments, hasLength(1));
    final stored = await runDb(tester, () => h.reload(idea.id));
    expect(stored.inboxHistory.single.kind, InboxCloseKind.experiment);
    expect(stored.inboxHistory.single.experimentId, experiments.single.id);
    final dropped = await runDb(tester, () => h.reload(future.id));
    expect(dropped.deletedAt, isNotNull);
    final skipped = await runDb(tester, () => h.reload(missed.id));
    expect(skipped.status, TaskStatus.skipped);

    expect(find.text('Open (0)'), findsOneWidget);
    expect(find.text('Done (1)'), findsOneWidget);
    expect(find.text('Dropped (0)'), findsOneWidget);
    await pickSegment(tester, 'Done (1)');
    expect(
      find.descendant(
        of: rowOf(idea.id),
        matching: find.text('Experiment · Day 1 of 30'),
      ),
      findsOneWidget,
    );
    expect(find.text('Became an experiment Oct 12'), findsOneWidget);
    // An experiment is followed in Insights, not reopened here.
    expect(find.byKey(const ValueKey('inbox-action-insights')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-action-bring-back')), findsNothing);
    await finish(tester, container);
  });

  testWidgets('the dates panel hint starts the same flow, and backing out '
      'keeps the idea', (tester) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await expandRow(tester, idea.id);
    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    for (var day = 13; day <= 20; day++) {
      await tester.tap(find.byKey(ValueKey('inbox-date-2026-10-$day')));
      await settle(tester);
    }
    await tester.tap(find.byKey(const ValueKey('inbox-hint-experiment')));
    await settle(tester);

    // The panel closed and the form opened with the idea's name.
    expect(find.byKey(const ValueKey('inbox-dates-panel')), findsNothing);
    expect(find.text('New experiment'), findsOneWidget);
    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('experiment-name')),
    );
    expect(name.controller!.text, 'Research SAP');

    await cancelForm(tester);
    final stored = await runDb(tester, () => h.reload(idea.id));
    expect(stored.inboxHistory, isEmpty);
    expect(await runDb(tester, () => h.sessionsOf(idea.id)), isEmpty);
    expect(find.text('Open (1)'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('a started experiment from the hint ends in Done', (
    tester,
  ) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await expandRow(tester, idea.id);
    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    for (var day = 13; day <= 20; day++) {
      await tester.tap(find.byKey(ValueKey('inbox-date-2026-10-$day')));
      await settle(tester);
    }
    await tester.tap(find.byKey(const ValueKey('inbox-hint-experiment')));
    await settle(tester);
    await submitForm(tester);

    final stored = await runDb(tester, () => h.reload(idea.id));
    expect(stored.inboxHistory.single.kind, InboxCloseKind.experiment);
    // Nothing was saved from the unsaved picks.
    expect(await runDb(tester, () => h.sessionsOf(idea.id)), isEmpty);
    expect(find.text('Done (1)'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('See in Insights opens the Running segment for a running one', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await startFromFooter(tester, idea);
    await submitForm(tester);
    final experiment = (await experimentsOf(tester, container)).single;

    await pickSegment(tester, 'Done (1)');
    await tester.tap(find.byKey(const ValueKey('inbox-action-insights')));
    await settle(tester);

    expect(
      appRouter.routerDelegate.currentConfiguration.uri.path,
      '/analytics',
    );
    expect(container.read(experimentFocusProvider), isNull);
    expect(selectedSegment(tester), contains('running'));
    expect(
      find.byKey(ValueKey('experiment-row-${experiment.id}')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  for (final (outcome, segment) in [
    (ExperimentOutcome.drop, 'concluded'),
    (ExperimentOutcome.keep, 'kept'),
  ]) {
    testWidgets('See in Insights opens the $segment segment', (tester) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        insightsClock: _fixed,
        seed: (h) async => idea = await h.idea('Research SAP'),
      );
      await startFromFooter(tester, idea);
      await submitForm(tester);
      final created = (await experimentsOf(tester, container)).single;
      await runDb(
        tester,
        () => ExperimentRepository(container.read(appDatabaseProvider))
            .concludeExperiment(
              created.id,
              outcome: outcome,
              // After the 30 days: the repository refuses to conclude earlier.
              today: '2026-11-20',
              expectedRevision: created.revision,
            ),
      );
      await settle(tester);

      await pickSegment(tester, 'Done (1)');
      expect(
        find.descendant(
          of: rowOf(idea.id),
          matching: find.textContaining(
            outcome == ExperimentOutcome.keep
                ? 'Experiment · Kept'
                : 'Experiment · Concluded',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('inbox-action-insights')));
      await settle(tester);
      expect(selectedSegment(tester), contains(segment));
      expect(container.read(experimentFocusProvider), isNull);
      await finish(tester, container);
    });
  }

  testWidgets('a missing experiment shows Removed and offers Bring back', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      insightsClock: _fixed,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        await h.inbox.markBecameExperiment(
          idea.id,
          'experiment:missing',
          h.now,
        );
      },
    );
    await pickSegment(tester, 'Done (1)');
    expect(find.text('Experiment · Removed'), findsOneWidget);
    await expandRow(tester, idea.id);
    expect(find.byKey(const ValueKey('inbox-action-insights')), findsNothing);
    expect(
      find.byKey(const ValueKey('inbox-action-bring-back')),
      findsOneWidget,
    );
    await finish(tester, container);
  });
}
