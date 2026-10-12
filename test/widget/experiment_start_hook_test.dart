// The start form passes `onCreated` to createExperiment, which runs it in the
// same transaction: a failing hook creates nothing; the Insights button (no
// hook) is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/experiment_start_form.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  Future<void> submit(WidgetTester tester) async {
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
  }

  testWidgets('a hook runs with the created experiment and the form closes', (
    tester,
  ) async {
    final container = await open(tester);
    Experiment? seen;
    showExperimentStartForm(
      tester.element(find.byType(Scaffold).first),
      initialName: 'Garage',
      onCreated: (created) async => seen = created,
    );
    await settle(tester);
    expect(find.text('New experiment'), findsOneWidget);
    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('experiment-name')),
    );
    expect(name.controller!.text, 'Garage');

    await submit(tester);
    expect(seen?.tagName, 'Garage');
    expect(find.text('New experiment'), findsNothing);
    final rows = await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .select(container.read(appDatabaseProvider).experiments)
          .get(),
    );
    expect(rows.single.id, seen!.id);
    await finish(tester, container);
  });

  testWidgets('a failing hook creates nothing and the form stays open', (
    tester,
  ) async {
    final container = await open(tester);
    showExperimentStartForm(
      tester.element(find.byType(Scaffold).first),
      initialName: 'Garage',
      onCreated: (_) async => throw StateError('the idea changed'),
    );
    await settle(tester);
    await submit(tester);

    expect(find.text('New experiment'), findsOneWidget);
    expect(
      find.text('The experiment was not started. Try again.'),
      findsOneWidget,
    );
    final db = container.read(appDatabaseProvider);
    expect(await runDb(tester, () => db.select(db.experiments).get()), isEmpty);
    expect(await runDb(tester, () => db.select(db.tags).get()), isEmpty);
    await finish(tester, container);
  });

  testWidgets('without a hook it behaves as before', (tester) async {
    final container = await open(tester);
    showExperimentStartForm(
      tester.element(find.byType(Scaffold).first),
      initialName: 'Plain',
    );
    await settle(tester);
    await submit(tester);
    final db = container.read(appDatabaseProvider);
    expect(
      await runDb(tester, () => db.select(db.experiments).get()),
      hasLength(1),
    );
    await finish(tester, container);
  });
}
