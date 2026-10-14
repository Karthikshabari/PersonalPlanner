import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/layout/adaptive_layout.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/widgets/adaptive_shell.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

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

  testWidgets('large width shows an extended rail with seven labelled items', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AdaptiveShell), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.labelType, NavigationRailLabelType.none);
    expect(rail.destinations, hasLength(4));
    for (final label in [
      'Day',
      'Inbox',
      'Review',
      'Insights',
      'Search',
      'Categories',
      'Settings',
    ]) {
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'rail label $label',
      );
    }
    // Settings is reachable from exactly one place, and the old "PLAN"
    // caption is gone.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('PLAN'), findsNothing);
    expect(find.byKey(const ValueKey('day-settings-action')), findsNothing);
    // The rail carries Search, so the app bar does not.
    expect(find.byKey(const ValueKey('mobile-search-action')), findsNothing);
    await teardownApp(tester, container);
  });

  testWidgets('medium and expanded widths show an icons-only rail', (
    tester,
  ) async {
    for (final size in const [
      Size(600, 900),
      Size(700, 900),
      Size(839, 900),
      Size(1000, 800),
      Size(1199, 800),
    ]) {
      final container = await buildTestContainer(tester);
      appRouter.go('/day');
      await pumpApp(tester, container, surface: size);
      expect(find.byType(NavigationBar), findsNothing, reason: '$size');
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse, reason: '$size');
      // Hidden labels still get tooltips; Settings exists once.
      for (final label in [
        'Day',
        'Inbox',
        'Review',
        'Insights',
        'Search',
        'Categories',
        'Settings',
      ]) {
        expect(find.byTooltip(label), findsOneWidget, reason: '$label $size');
      }
      expect(find.text('PLAN'), findsNothing);
      expect(find.byKey(const ValueKey('mobile-search-action')), findsNothing);
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await teardownApp(tester, container);
    }
  });

  testWidgets('a short window collapses the rail to primary plus More', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(800, 360));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(4));
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byTooltip('Categories'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    expect(find.widgetWithText(MenuItemButton, 'Search'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Categories'), findsOneWidget);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Settings'));
    await settle(tester);
    expect(appRouter.state.uri.path, '/settings');
    await teardownApp(tester, container);
  });

  testWidgets('desktop Home shortcut uses the existing Day destination', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(
      rail.destinations
          .map((destination) => (destination.label as Text).data)
          .toList(),
      ['Day', 'Inbox', 'Review', 'Insights'],
    );
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/app_logo.png',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Home'), findsOneWidget);

    final selected = addDays(DateTime.now(), 3);
    container.read(selectedDateProvider.notifier).state = selected;
    appRouter.go('/week');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-navigation-shortcut')));
    await settle(tester);
    expect(find.byKey(const ValueKey('timeline-gestures')), findsOneWidget);
    expect(isSameDay(container.read(selectedDateProvider), selected), isTrue);

    appRouter.go('/week');
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Day'),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('timeline-gestures')), findsOneWidget);
    expect(isSameDay(container.read(selectedDateProvider), selected), isTrue);
    await teardownApp(tester, container);
  });

  testWidgets('width 599 shows the bottom bar, 600 shows a rail', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(599, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await pumpApp(tester, container, surface: const Size(600, 900));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    await teardownApp(tester, container);
  });

  testWidgets(
    'compact phones keep five stable destinations and global Search',
    (tester) async {
      for (final width in <double>[320, 360, 393, 412]) {
        final container = await buildTestContainer(tester);
        appRouter.go('/day');
        await pumpApp(tester, container, surface: Size(width, 844));

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.destinations, hasLength(5));
        expect(
          bar.destinations
              .map(
                (destination) => (destination as NavigationDestination).label,
              )
              .toList(),
          ['Day', 'Inbox', 'Review', 'Insights', 'More'],
        );
        // The labels are real text in the bar.
        for (final label in ['Day', 'Inbox', 'Review', 'Insights', 'More']) {
          expect(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(label),
            ),
            findsOneWidget,
            reason: '$label at ${width}px',
          );
        }
        expect(find.byKey(const ValueKey('day-settings-action')), findsNothing);
        expect(find.byTooltip('Search'), findsOneWidget);
        expect(find.byKey(const ValueKey('day-week-switcher')), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width}px',
        );

        await teardownApp(tester, container);
      }
    },
  );

  testWidgets(
    'Week stays inside Planner and keeps Day selected in mobile nav',
    (tester) async {
      final container = await buildTestContainer(tester);
      appRouter.go('/day');
      await pumpApp(tester, container, surface: const Size(393, 844));

      await tester.tap(find.text('Week'));
      await settle(tester);
      expect(find.byKey(const ValueKey('week-pages')), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
      expect(bar.destinations, hasLength(5));

      await tester.tap(find.text('Day').last);
      await settle(tester);
      expect(find.byKey(const ValueKey('timeline-gestures')), findsOneWidget);
      await teardownApp(tester, container);
    },
  );

  testWidgets('compact More opens Categories and Settings, Back returns', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(393, 844));
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.text('More'));
    await settle(tester);
    expect(find.byKey(const ValueKey('more-sheet-categories')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-sheet-settings')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('more-sheet-settings'))).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(const ValueKey('more-sheet-settings')));
    await settle(tester);
    expect(appRouter.state.uri.path, '/settings');
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Categories'), findsWidgets);
    await tester.tap(find.text('Categories').first);
    await settle(tester);
    // Categories is a secondary Settings route; the compact shell keeps the
    // primary destinations out of secondary screens rather than falsely
    // selecting Day.
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
    expect(appRouter.state.uri.path, '/day');
    expect(find.byType(NavigationBar), findsOneWidget);
    await teardownApp(tester, container);
  });

  testWidgets('compact More also reaches Categories directly', (tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(360, 800));
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('more-sheet-categories')));
    await settle(tester);
    expect(appRouter.state.uri.path, '/categories');
    expect(find.byType(NavigationBar), findsNothing);
    await teardownApp(tester, container);
  });
}
