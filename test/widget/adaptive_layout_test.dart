import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/widgets/adaptive_shell.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('desktop width shows navigation rail, no bottom bar',
      (tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(
      tester,
      container,
      surface: const Size(1400, 1000),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AdaptiveShell), findsOneWidget);
    expect(find.text('Day'), findsWidgets);
    await teardownApp(tester, container);
  });

  testWidgets('mobile width shows bottom navigation bar', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(
      tester,
      container,
      surface: const Size(600, 900),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await teardownApp(tester, container);
  });

  testWidgets('bottom navigation navigates to settings and categories',
      (tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(
      tester,
      container,
      surface: const Size(600, 900),
    );
    await tester.tap(find.text('Settings').last);
    await settle(tester);
    expect(find.text('Categories'), findsWidgets);
    await tester.tap(find.text('Categories').first);
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('Learning'), findsOneWidget);
    await teardownApp(tester, container);
  });
}
