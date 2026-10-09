import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/theme/theme_mode_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/providers/day_context_providers.dart';

import '../helpers/test_container.dart';

/// B1 (newest-end arrow), B2 (edge fades) and B3 (adaptive card height) of the
/// Overview day strip.
void main() {
  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  final strip = find.byKey(const ValueKey('overview-strip'));
  final older = find.byKey(const ValueKey('overview-older'));
  final newer = find.byKey(const ValueKey('overview-newer'));
  final fadeOlder = find.byKey(const ValueKey('overview-fade-older'));
  final fadeNewer = find.byKey(const ValueKey('overview-fade-newer'));

  Finder card(DateTime d) =>
      find.byKey(ValueKey('overview-day-${isoDateString(d)}'));

  Future<ProviderContainer> pumpOverview(
    WidgetTester tester, {
    Size surface = const Size(1400, 1000),
    double textScale = 1.0,
    bool seed = false,
  }) async {
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final container = await buildTestContainer(tester);
    if (seed) {
      final day = today();
      final start = DateTime(day.year, day.month, day.day, 9);
      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'Write report',
                startTime: start,
                endTime: start.add(const Duration(hours: 1)),
                createdAt: start,
                updatedAt: start,
              ),
            ),
      );
      await runDb(
        tester,
        () => container
            .read(dayContextRepositoryProvider)
            .save(isoDateString(day), DayContextKind.travel, null),
      );
    }
    appRouter.go('/review/overview');
    await pumpApp(tester, container, surface: surface);
    return container;
  }

  VoidCallback? arrowAction(WidgetTester tester, Finder arrow) => tester
      .widget<IconButton>(
        find.descendant(of: arrow, matching: find.byType(IconButton)),
      )
      .onPressed;

  double fadeOpacity(WidgetTester tester, Finder fade) => tester
      .widget<AnimatedOpacity>(
        find.descendant(of: fade, matching: find.byType(AnimatedOpacity)),
      )
      .opacity;

  Future<void> scrollOlder(WidgetTester tester) async {
    await tester.drag(strip, const Offset(400, 0));
    await settle(tester);
  }

  group('B1 arrows', () {
    testWidgets('the newer arrow is disabled at the newest end', (
      tester,
    ) async {
      final container = await pumpOverview(tester);

      expect(arrowAction(tester, newer), isNull);
      expect(arrowAction(tester, older), isNotNull);
      await finish(tester, container);
    });

    testWidgets('it enables after scrolling to older days and disables again '
        'back at today', (tester) async {
      final container = await pumpOverview(tester);

      await tester.tap(older);
      await settle(tester);
      expect(arrowAction(tester, newer), isNotNull);

      for (var i = 0; i < 6 && arrowAction(tester, newer) != null; i++) {
        await tester.tap(newer);
        await settle(tester);
      }
      expect(arrowAction(tester, newer), isNull);
      expect(card(today()), findsOneWidget);
      await finish(tester, container);
    });

    testWidgets('layout does not change when the arrow toggles; semantics '
        'report the disabled state', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await pumpOverview(tester);
      final sizeDisabled = tester.getSize(newer);
      final stripWidth = tester.getSize(strip).width;
      final arrowButton = find.descendant(
        of: newer,
        matching: find.byType(IconButton),
      );
      expect(
        tester.getSemantics(arrowButton),
        isSemantics(
          tooltip: 'Later days',
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      await scrollOlder(tester);

      expect(tester.getSize(newer), sizeDisabled);
      expect(tester.getSize(strip).width, stripWidth);
      expect(
        tester.getSemantics(arrowButton),
        isSemantics(
          tooltip: 'Later days',
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
      await finish(tester, container);
    });
  });

  group('B2 edge fades', () {
    testWidgets('only the older edge fades at the newest end', (tester) async {
      final container = await pumpOverview(tester);

      expect(fadeOpacity(tester, fadeOlder), 1);
      expect(fadeOpacity(tester, fadeNewer), 0);
      await finish(tester, container);
    });

    testWidgets('both edges fade mid-strip, then only the older one again', (
      tester,
    ) async {
      final container = await pumpOverview(tester);

      await scrollOlder(tester);
      expect(fadeOpacity(tester, fadeOlder), 1);
      expect(fadeOpacity(tester, fadeNewer), 1);

      await tester.drag(strip, const Offset(-3000, 0));
      await settle(tester);
      expect(fadeOpacity(tester, fadeNewer), 0);
      expect(fadeOpacity(tester, fadeOlder), 1);
      await finish(tester, container);
    });

    testWidgets('also on a phone width without arrows', (tester) async {
      final container = await pumpOverview(
        tester,
        surface: const Size(390, 844),
      );
      expect(older, findsNothing);

      expect(fadeOpacity(tester, fadeNewer), 0);
      await scrollOlder(tester);
      expect(fadeOpacity(tester, fadeNewer), 1);
      await finish(tester, container);
    });

    testWidgets('fades ignore pointers so cards under them stay tappable', (
      tester,
    ) async {
      final container = await pumpOverview(tester);
      for (final fade in [fadeOlder, fadeNewer]) {
        expect(
          find.descendant(of: fade, matching: find.byType(IgnorePointer)),
          findsWidgets,
        );
      }
      await finish(tester, container);
    });

    for (final (name, mode, tokens) in [
      ('dark', ThemeMode.dark, AppThemeTokens.dark()),
      ('light', ThemeMode.light, AppThemeTokens.light()),
    ]) {
      testWidgets('the fade follows the $name theme surface', (tester) async {
        final container = await pumpOverview(tester);
        await runDb(
          tester,
          () => container.read(themeModeProvider.notifier).setMode(mode),
        );
        await settle(tester);

        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: fadeOlder,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final colors = (decoration.gradient! as LinearGradient).colors;
        expect(colors.first, tokens.surface);
        expect(colors.last, tokens.surface.withValues(alpha: 0));
        await finish(tester, container);
      });
    }

    testWidgets('animations off: the fade changes at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final container = await pumpOverview(tester);

      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(of: fadeNewer, matching: find.byType(AnimatedOpacity)),
      );
      expect(fade.duration, Duration.zero);
      await finish(tester, container);
    });
  });

  group('B3 card height', () {
    double cardHeight(WidgetTester tester) =>
        tester.getSize(card(today())).height;

    for (final scale in [1.0, 1.3, 1.6]) {
      for (final surface in [const Size(360, 800), const Size(1400, 1000)]) {
        testWidgets(
          'tallest card fits its content exactly at text scale $scale, '
          '${surface.width.toInt()} dp',
          (tester) async {
            final container = await pumpOverview(
              tester,
              surface: surface,
              textScale: scale,
              seed: true,
            );
            expect(tester.takeException(), isNull);

            // Today's card has a task, no review and a context: the fullest
            // content. Its Column plus the padding and border is the tile, so
            // there is neither overflow nor dead space.
            final content = tester.getSize(
              find
                  .descendant(of: card(today()), matching: find.byType(Column))
                  .first,
            );
            // 10 dp of padding and the 1 dp border on each side.
            expect(cardHeight(tester), closeTo(content.height + 22, 1));

            // Every card in the strip shares that height.
            expect(
              tester.getSize(card(addDays(today(), -1))).height,
              cardHeight(tester),
            );

            await scrollOlder(tester);
            expect(tester.takeException(), isNull);
            await finish(tester, container);
          },
        );
      }
    }

    testWidgets('cards grow with the text scale and are compact at 1.0', (
      tester,
    ) async {
      final heights = <double>[];
      for (final scale in [1.0, 1.3, 1.6]) {
        final container = await pumpOverview(
          tester,
          textScale: scale,
          seed: true,
        );
        heights.add(cardHeight(tester));
        await finish(tester, container);
      }
      expect(heights[1], greaterThan(heights[0]));
      expect(heights[2], greaterThan(heights[1]));
      // Part A's stopgap was 266 - 16 = 250 dp of card at normal scale; the
      // measured height is about 207 dp even with the wide test font.
      expect(heights[0], lessThan(220));
    });

    testWidgets('a window with no tasks or context has shorter cards', (
      tester,
    ) async {
      final container = await pumpOverview(tester);
      final plain = cardHeight(tester);
      await finish(tester, container);

      final container2 = await pumpOverview(tester, seed: true);
      expect(plain, lessThan(cardHeight(tester)));
      await finish(tester, container2);
    });
  });
}
