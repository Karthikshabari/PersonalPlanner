import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/layout/breakpoints.dart';
import 'package:personal_planner/core/layout/size_class_scope.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/presentation/screens/day_view_screen.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/timeline_widget.dart';

import '../helpers/day_responsive_fixture.dart';
import '../helpers/test_container.dart';

void main() {
  testWidgets('live resizing swaps the navigation but never remounts Day', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(360, 800));

    final dayState = tester.state(find.byType(DayViewScreen));
    final timeline = find.byKey(const ValueKey('timeline-gestures'));
    expect(timeline, findsOneWidget);

    void expectNav({
      required WindowSizeClass sizeClass,
      required bool bar,
      required bool rail,
      required bool extended,
    }) {
      final context = tester.element(find.byType(DayViewScreen));
      expect(DaySizeClass.of(context), sizeClass);
      expect(find.byType(NavigationBar), bar ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationRail), rail ? findsOneWidget : findsNothing);
      if (rail) {
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          extended,
        );
      }
      // Same State object: Day was moved, not rebuilt from scratch.
      expect(tester.state(find.byType(DayViewScreen)), same(dayState));
      expect(timeline, findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    expectNav(
      sizeClass: WindowSizeClass.compact,
      bar: true,
      rail: false,
      extended: false,
    );

    for (final step in <(Size, WindowSizeClass, bool)>[
      (const Size(700, 900), WindowSizeClass.medium, false),
      (const Size(1000, 800), WindowSizeClass.expanded, false),
      (const Size(1400, 1000), WindowSizeClass.large, true),
      // And back down again, through every class.
      (const Size(1000, 800), WindowSizeClass.expanded, false),
      (const Size(700, 900), WindowSizeClass.medium, false),
      (const Size(360, 800), WindowSizeClass.compact, false),
    ]) {
      tester.view.physicalSize = step.$1;
      await tester.pump();
      // Let the rail's extend animation finish.
      await tester.pump(const Duration(milliseconds: 400));
      final compact = step.$2 == WindowSizeClass.compact;
      expectNav(
        sizeClass: step.$2,
        bar: compact,
        rail: !compact,
        extended: step.$3,
      );
    }
    await teardownApp(tester, container);
  });

  testWidgets(
    'resizing through every size class keeps the timeline State and scroll',
    (tester) async {
      final container = await pumpResponsiveDay(
        tester,
        size: const Size(1920, 1080),
      );
      final timelineState = tester.state(find.byType(TimelineWidget));
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('timeline-gestures')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

      // Scroll away from the opening position so a remount would show.
      position().jumpTo(position().pixels + 180);
      await tester.pump();
      final offset = position().pixels;
      expect(offset, greaterThan(0));

      for (final size in const [
        Size(1000, 1100),
        Size(800, 1100),
        Size(360, 1100),
        Size(800, 1100),
        Size(1000, 1100),
        Size(1920, 1080),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.state(find.byType(TimelineWidget)),
          same(timelineState),
          reason: 'TimelineWidget remounted at $size',
        );
        expect(position().pixels, offset, reason: 'scroll moved at $size');
        expect(tester.takeException(), isNull);
      }
      await finish(tester, container);
    },
  );
}
