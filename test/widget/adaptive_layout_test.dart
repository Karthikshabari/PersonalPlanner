import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/layout/adaptive_layout.dart';
import 'package:personal_planner/core/layout/breakpoints.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/widgets/adaptive_shell.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import '../helpers/test_container.dart';

void main() {
  group('WeekViewportLayout', () {
    test(
      'column count follows the body width with a 160 px minimum column',
      () {
        final expected = {
          320.0: 1,
          599.0: 1,
          600.0: 3,
          800.0: 4,
          // 1280 px window minus the extended rail.
          1075.0: 6,
          1175.0: 6,
          1176.0: 7,
          1280.0: 7,
          1440.0: 7,
          1920.0: 7,
        };
        expected.forEach((width, columns) {
          expect(
            WeekViewportLayout.capacityFor(width),
            columns,
            reason: '$width',
          );
          if (width >= 600) {
            expect(
              WeekViewportLayout.forWidth(width).columnWidthFor(width),
              greaterThanOrEqualTo(WeekViewportLayout.defaultMinimumDayWidth),
              reason: '$width',
            );
          }
        });
      },
    );

    test('text scaling raises the minimum column width before paging', () {
      expect(WeekViewportLayout.capacityFor(1200, textScale: 1.5), 4);
      expect(WeekViewportLayout.capacityFor(1800, textScale: 1.5), 7);
      expect(
        WeekViewportLayout.forWidth(1200, textScale: 1.5).minimumDayWidth,
        240,
      );
    });

    test(
      'the last page is clamped to the last N days, for 1 to 7 per page',
      () {
        const days = [0, 1, 2, 3, 4, 5, 6];
        for (var perPage = 1; perPage <= 7; perPage++) {
          final layout = WeekViewportLayout(
            daysPerPage: perPage,
            minimumDayWidth: 160,
            rulerWidth: 56,
          );
          final pages = layout.pagesOf(days);
          expect(pages, hasLength((7 / perPage).ceil()), reason: '$perPage');
          for (final (index, page) in pages.indexed) {
            expect(page, hasLength(perPage), reason: '$perPage page $index');
            expect(page.first, layout.firstDayOfPage(index, days.length));
            // Consecutive days.
            expect(page, [for (var i = 0; i < perPage; i++) page.first + i]);
          }
          expect(pages.last.last, 6, reason: '$perPage');
          // Every day is on a page, and the page its index falls in shows it.
          for (final day in days) {
            expect(pages[day ~/ perPage], contains(day), reason: '$perPage');
          }
        }
        // Three per page used to end with a lone Sunday.
        expect(
          WeekViewportLayout(
            daysPerPage: 3,
            minimumDayWidth: 160,
            rulerWidth: 56,
          ).pagesOf(days),
          [
            [0, 1, 2],
            [3, 4, 5],
            [4, 5, 6],
          ],
        );
      },
    );
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

  testWidgets('medium and expanded widths label every rail destination', (
    tester,
  ) async {
    for (final size in const [
      Size(600, 900),
      Size(700, 900),
      Size(800, 1280),
      Size(800, 600),
      Size(839, 900),
      Size(1000, 800),
      Size(1199, 800),
      Size(1199, 560),
    ]) {
      final container = await buildTestContainer(tester);
      appRouter.go('/day');
      await pumpApp(tester, container, surface: size);
      expect(find.byType(NavigationBar), findsNothing, reason: '$size');
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse, reason: '$size');
      expect(rail.labelType, NavigationRailLabelType.all, reason: '$size');
      // Every destination shows its text; Settings exists once.
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
          reason: '$label $size',
        );
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

  test('wide means the expanded size class, once', () {
    expect(isDesktopWidth(839), isFalse);
    expect(isDesktopWidth(840), isTrue);
    expect(isDesktopWidth(Breakpoints.expanded), isTrue);
  });

  testWidgets('Settings sub-pages replace the route from 840 and push below', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/settings');
    await pumpApp(tester, container, surface: const Size(839, 900));
    // The rail also shows "Categories"; the Settings page's row comes last.
    await tester.tap(find.text('Categories').last);
    await settle(tester);
    expect(appRouter.state.uri.path, '/categories');
    expect(appRouter.canPop(), isTrue);

    appRouter.go('/settings');
    await pumpApp(tester, container, surface: const Size(860, 900));
    await tester.tap(find.text('Categories').last);
    await settle(tester);
    expect(appRouter.state.uri.path, '/categories');
    expect(appRouter.canPop(), isFalse);
    await teardownApp(tester, container);
  });
}
