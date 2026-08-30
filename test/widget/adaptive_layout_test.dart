import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/widgets/adaptive_shell.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('desktop width shows navigation rail, no bottom bar', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AdaptiveShell), findsOneWidget);
    expect(find.text('Day'), findsWidgets);
    await teardownApp(tester, container);
  });

  testWidgets('mobile width shows bottom navigation bar', (tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(600, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await teardownApp(tester, container);
  });

  testWidgets(
    'mobile navigation keeps primary destinations and settings reachable',
    (tester) async {
      final container = await buildTestContainer(tester);
      await pumpApp(tester, container, surface: const Size(600, 900));
      expect(find.text('Settings'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('day-settings-action')));
      await settle(tester);
      expect(find.text('Categories'), findsWidgets);
      await tester.tap(find.text('Categories').first);
      await settle(tester);
      // Categories is a secondary Settings route; the mobile shell keeps the
      // five primary destinations out of secondary screens rather than
      // falsely selecting Day.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('Learning'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(find.text('Categories'), findsWidgets);
      await tester.pageBack();
      await settle(tester);
      expect(find.byKey(const ValueKey('day-settings-action')), findsOneWidget);
      await teardownApp(tester, container);
    },
  );
}
