import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/test_container.dart';

/// The semantics node of the button whose accessible name is [label]. A
/// tooltip alone is not a name: screen readers and the UAT tool read `label`.
SemanticsNode _button(WidgetTester tester, String label) {
  final nodes = find.semantics.byLabel(label).evaluate();
  expect(nodes, isNotEmpty, reason: 'no semantics node labelled "$label"');
  return nodes.firstWhere(
    (n) => n.getSemanticsData().flagsCollection.isButton,
    orElse: () => fail('"$label" is not a button'),
  );
}

void main() {
  late SemanticsHandle handle;

  Future<ProviderContainer> open(WidgetTester tester, String path) async {
    handle = tester.ensureSemantics();
    final container = await buildTestContainer(tester);
    appRouter.go(path);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  Future<void> close(WidgetTester tester, ProviderContainer container) async {
    await teardownApp(tester, container);
    handle.dispose();
  }

  testWidgets('Categories row icon buttons have labels', (tester) async {
    final h = await open(tester, '/categories');
    for (final label in [
      'Focus category, off',
      'Edit category',
      'Delete category',
    ]) {
      _button(tester, label);
    }
    await close(tester, h);
  });

  testWidgets('Day previous and next arrows have labels', (tester) async {
    final h = await open(tester, '/day');
    _button(tester, 'Previous day');
    _button(tester, 'Next day');
    await close(tester, h);
  });

  testWidgets('Review previous and next arrows have labels', (tester) async {
    final h = await open(tester, '/review');
    _button(tester, 'Previous day');
    _button(tester, 'Next day');
    await close(tester, h);
  });

  testWidgets('rail destinations are in the semantics tree', (tester) async {
    final h = await open(tester, '/day');
    for (final label in ['Day', 'Inbox', 'Review', 'Insights']) {
      final nodes = find.semantics.byLabel(RegExp('^$label\n')).evaluate();
      expect(nodes, isNotEmpty, reason: 'rail destination $label');
    }
    final day = find.semantics.byLabel(RegExp('^Day\n')).evaluate().single;
    expect(day.getSemanticsData().flagsCollection.isSelected.name, 'isTrue');
    for (final label in ['Search', 'Categories', 'Settings']) {
      _button(tester, label);
    }
    await close(tester, h);
  });

  testWidgets('Inbox segments show no counts while loading', (tester) async {
    handle = tester.ensureSemantics();
    final container = await buildTestContainer(tester);
    appRouter.go('/inbox');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PersonalPlannerApp(),
      ),
    );
    await tester.pump();
    expect(find.semantics.byLabel('Open, loading'), findsOneWidget);
    expect(find.semantics.byLabel(RegExp(r'^Open, \d')), findsNothing);
    await settle(tester);
    expect(find.semantics.byLabel(RegExp(r'^Open, \d')), findsOneWidget);
    await teardownApp(tester, container);
    handle.dispose();
  });
}
