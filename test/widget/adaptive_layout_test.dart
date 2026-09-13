import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/layout/adaptive_layout.dart';
import 'package:personal_planner/core/widgets/adaptive_shell.dart';

import '../helpers/test_container.dart';

void main() {
  group('WeekViewportLayout', () {
    test('uses content capacity at phone, intermediate and desktop widths', () {
      expect(WeekViewportLayout.capacityFor(320), 1);
      expect(WeekViewportLayout.capacityFor(599), 1);
      expect(WeekViewportLayout.capacityFor(600), 3);
      expect(WeekViewportLayout.capacityFor(768), 3);
      expect(WeekViewportLayout.capacityFor(1199), 3);
      expect(WeekViewportLayout.capacityFor(1200), 7);
      expect(WeekViewportLayout.capacityFor(1440), 7);
    });

    test('text scaling raises the minimum column width before paging', () {
      expect(WeekViewportLayout.capacityFor(1200, textScale: 1.5), 3);
      expect(WeekViewportLayout.capacityFor(1800, textScale: 1.5), 7);
      expect(
        WeekViewportLayout.forWidth(1200, textScale: 1.5).minimumDayWidth,
        240,
      );
    });

    test('pages preserve consecutive order and final short page', () {
      final layout = WeekViewportLayout.forWidth(600);
      expect(layout.pagesOf([0, 1, 2, 3, 4, 5, 6]), [
        [0, 1, 2],
        [3, 4, 5],
        [6],
      ]);
    });
  });

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
