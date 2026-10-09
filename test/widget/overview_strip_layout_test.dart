import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/widgets/app_surface.dart';
import 'package:personal_planner/features/day_context/providers/day_context_providers.dart';
import 'package:personal_planner/features/review/domain/review_overview.dart';
import 'package:personal_planner/features/review/domain/weekly_review_history.dart';
import 'package:personal_planner/features/review/presentation/widgets/overview_day_strip.dart';
import 'package:personal_planner/features/review/presentation/widgets/overview_strip.dart';
import 'package:personal_planner/features/review/presentation/widgets/overview_week_strip.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_layout.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_theme.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

/// Overview strips: layout at every width and text scale, lazy building of a
/// long history, arrows, keyboard, rebuild counts and haptics.
///
/// Widget tests render with the Ahem font (every glyph about one em wide, much
/// wider than real text), so the rules are asserted, not exact column counts.
/// A widget test that always clears the debug globals it may set: the
/// framework checks them before tear-down callbacks run.
void stripTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugOnRebuildDirtyWidget = null;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    }
  });
}

void main() {
  final today = startOfDay(DateTime.now());
  final thisWeek = startOfWeek(DateTime.now());

  Finder dayTile(DateTime d) =>
      find.byKey(ValueKey('overview-day-${isoDateString(d)}'));
  Finder weekTile(DateTime d) =>
      find.byKey(ValueKey('overview-week-${isoDateString(d)}'));
  final dayList = find.byKey(const ValueKey('overview-strip'));
  final weekList = find.byKey(const ValueKey('overview-week-strip'));

  // ---- data -------------------------------------------------------------

  /// A mix: no tasks, a 0 % day, a reviewed day, a Leave day, a long custom
  /// context label on a reviewed day.
  List<ReviewOverviewDay> daysOf(int count) => [
    for (var i = 0; i < count; i++)
      () {
        final date = addDays(today, -i);
        final now = DateTime.now();
        DailyReview? review(int mood) => DailyReview(
          id: 'r$i',
          date: date,
          mood: mood,
          createdAt: now,
          updatedAt: now,
        );
        DayContext context(DayContextKind kind, [String? label]) => DayContext(
          id: 'c$i',
          date: isoDateString(date),
          kind: kind,
          customLabel: label,
          createdAt: now,
          updatedAt: now,
        );
        return switch (i % 5) {
          0 => ReviewOverviewDay(date: date, totalTasks: 0, completedTasks: 0),
          1 => ReviewOverviewDay(date: date, totalTasks: 3, completedTasks: 0),
          2 => ReviewOverviewDay(
            date: date,
            totalTasks: 3,
            completedTasks: 1,
            review: review(i % 4 + 1),
          ),
          3 => ReviewOverviewDay(
            date: date,
            totalTasks: 2,
            completedTasks: 2,
            dayContext: context(DayContextKind.leave),
          ),
          _ => ReviewOverviewDay(
            date: date,
            totalTasks: 4,
            completedTasks: 3,
            review: review(4),
            dayContext: context(
              DayContextKind.custom,
              'Working from the airport lounge',
            ),
          ),
        };
      }(),
  ];

  List<WeeklyHistoryWeek> weeksOf(int count) => [
    for (var i = 0; i < count; i++)
      WeeklyHistoryWeek(
        weekStart: addDays(thisWeek, -7 * i),
        totalTasks: i % 3 == 0 ? 0 : 4,
        completedTasks: i % 3 == 0 ? 0 : i % 4,
        review: i % 2 == 0
            ? null
            : WeeklyReview(
                id: 'w$i',
                weekStartDate: addDays(thisWeek, -7 * i),
                mood: i % 4 + 1,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
      ),
  ];

  // ---- harness (no database) ---------------------------------------------

  /// Pumps one strip alone, in the card the screen puts it in, with the data
  /// provided by overrides. [platform] defaults to Linux (arrows at any width).
  Future<void> pumpStrip(
    WidgetTester tester, {
    required Widget Function(bool wide) strip,
    List<ReviewOverviewDay>? days,
    List<WeeklyHistoryWeek>? weeks,
    double width = 1100,
    double scale = 1.0,
    TargetPlatform platform = TargetPlatform.linux,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (scale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (days != null)
            reviewOverviewWindowProvider.overrideWith(
              (ref, count) => Stream.value(days),
            ),
          if (weeks != null)
            reviewOverviewWeekWindowProvider.overrideWith(
              (ref, count) async => weeks,
            ),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(ReviewLayout.pagePadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ReviewLayout.maxContentWidth,
                  ),
                  child: AppSurface(child: strip(ReviewLayout.isWide(width))),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Widget dayStrip(bool wide) => OverviewDayStrip(wide: wide);
  Widget weekStrip(bool wide) => const OverviewWeekStrip();

  double pixels(WidgetTester tester, Finder list) => tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      )
      .position
      .pixels;

  bool fullyInside(WidgetTester tester, Finder tile, Finder list) {
    final t = tester.getRect(tile);
    final l = tester.getRect(list);
    return t.left >= l.left - 0.5 && t.right <= l.right + 0.5;
  }

  double fadeOpacity(WidgetTester tester, String key) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  bool arrowEnabled(WidgetTester tester, String key) =>
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  /// Presses an arrow and lets its 220 ms scroll finish (the first frame
  /// only starts the animation).
  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('long histories build lazily', () {
    stripTest('400 days: only the visible tiles and a small cache exist', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(400));
      expect(tester.takeException(), isNull);
      final built = find.byType(OverviewTileFrame).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(25));
      expect(dayTile(addDays(today, -300)), findsNothing);

      // Far away from the start the count stays small.
      await tester.drag(dayList, const Offset(-3000, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OverviewTileFrame).evaluate().length, lessThan(25));
    });

    stripTest('60 weeks: only the visible tiles and a small cache exist', (
      tester,
    ) async {
      await pumpStrip(tester, strip: weekStrip, weeks: weeksOf(60));
      expect(tester.takeException(), isNull);
      final built = find.byType(OverviewTileFrame).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(25));
      expect(weekTile(addDays(thisWeek, -7 * 50)), findsNothing);
    });

    stripTest('a brand-new install: one tile, no fades, both arrows off', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(1));
      expect(tester.takeException(), isNull);
      expect(find.byType(OverviewTileFrame), findsOneWidget);
      expect(fullyInside(tester, dayTile(today), dayList), isTrue);
      expect(fadeOpacity(tester, 'overview-fade-older'), 0);
      expect(fadeOpacity(tester, 'overview-fade-newer'), 0);
      expect(arrowEnabled(tester, 'overview-older'), isFalse);
      expect(arrowEnabled(tester, 'overview-newer'), isFalse);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('overview-detail'))).data,
        contains('No tasks'),
      );
    });

    stripTest('equal size for every tile of a mode, whatever it shows', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(30));
      final sizes = {
        for (final e in find.byType(OverviewTileFrame).evaluate())
          tester.getSize(find.byWidget(e.widget)),
      };
      expect(sizes, hasLength(1));
    });
  });

  group('widths and text scales', () {
    for (final width in [320.0, 360.0, 700.0, 1100.0, 1600.0, 2000.0]) {
      for (final scale in [1.0, 1.3]) {
        stripTest('days at ${width.toInt()} dp, text scale $scale', (
          tester,
        ) async {
          await pumpStrip(
            tester,
            strip: dayStrip,
            days: daysOf(60),
            width: width,
            scale: scale,
            platform: width < 600
                ? TargetPlatform.android
                : TargetPlatform.linux,
          );
          expect(tester.takeException(), isNull);

          // Today is selected and whole, and the tiles share one size.
          expect(fullyInside(tester, dayTile(today), dayList), isTrue);
          final frames = find.byType(OverviewTileFrame).evaluate().toList();
          expect({
            for (final e in frames) tester.getSize(find.byWidget(e.widget)),
          }, hasLength(1));

          // No fixed label is cut ("Not reviewed", the tier names, "No tasks").
          for (final label in ['Not reviewed', 'No tasks']) {
            for (final element in find.text(label).evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
            }
          }

          // Summary row: side by side when wide, stacked with a full-width
          // 48 dp button when narrow.
          final detail = tester.getRect(
            find.byKey(const ValueKey('overview-detail')),
          );
          final button = tester.getRect(
            find.byKey(const ValueKey('overview-open-day')),
          );
          if (ReviewLayout.isWide(width)) {
            expect(button.left, greaterThanOrEqualTo(detail.right));
            expect(button.center.dy, closeTo(detail.center.dy, 30));
          } else {
            expect(button.top, greaterThanOrEqualTo(detail.bottom));
            expect(button.height, 48);
            expect(
              button.width,
              closeTo(
                // card padding and its 1 dp border on each side
                tester.getSize(find.byType(AppSurface)).width - 34,
                0.5,
              ),
            );
          }

          // Legend: one row when it fits, rows of two (2 x 2) when it does not.
          final rows = {
            for (final label in ['Good', 'Great', 'Excellent', 'Legendary'])
              tester
                  .getRect(
                    find.descendant(
                      of: find.byKey(const ValueKey('overview-legend')),
                      matching: find.text(label),
                    ),
                  )
                  .center
                  .dy
                  .round(),
          };
          expect(rows.length, anyOf(1, 2));
          if (width <= 360) expect(rows.length, 2);
          if (width >= 1100 && scale == 1.0) expect(rows.length, 1);

          // The page still scrolls vertically and never sideways.
          await tester.drag(dayList, const Offset(-200, 0));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        });

        stripTest('weeks at ${width.toInt()} dp, text scale $scale', (
          tester,
        ) async {
          await pumpStrip(
            tester,
            strip: weekStrip,
            weeks: weeksOf(30),
            width: width,
            scale: scale,
            platform: width < 600
                ? TargetPlatform.android
                : TargetPlatform.linux,
          );
          expect(tester.takeException(), isNull);
          expect(fullyInside(tester, weekTile(thisWeek), weekList), isTrue);
          final frames = find.byType(OverviewTileFrame).evaluate().toList();
          expect({
            for (final e in frames) tester.getSize(find.byWidget(e.widget)),
          }, hasLength(1));
          for (final element in find.text('Not reviewed').evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            expect(paragraph.didExceedMaxLines, isFalse);
          }
          // Weeks have no summary row or open action.
          expect(find.byKey(const ValueKey('overview-open-day')), findsNothing);
          expect(find.byKey(const ValueKey('overview-legend')), findsOneWidget);
        });
      }
    }

    stripTest('the light theme lays out the same', (tester) async {
      await pumpStrip(
        tester,
        strip: dayStrip,
        days: daysOf(30),
        brightness: Brightness.light,
      );
      expect(tester.takeException(), isNull);
      expect(fullyInside(tester, dayTile(today), dayList), isTrue);
    });
  });

  group('arrows', () {
    stripTest('hidden below 600 dp on touch platforms, kept on desktop', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        strip: dayStrip,
        days: daysOf(30),
        width: 590,
        platform: TargetPlatform.android,
      );
      expect(find.byKey(const ValueKey('overview-older')), findsNothing);
      expect(find.byKey(const ValueKey('overview-newer')), findsNothing);

      await pumpStrip(
        tester,
        strip: dayStrip,
        days: daysOf(30),
        width: 590,
        platform: TargetPlatform.linux,
      );
      expect(find.byKey(const ValueKey('overview-older')), findsOneWidget);

      await pumpStrip(
        tester,
        strip: dayStrip,
        days: daysOf(30),
        width: 800,
        platform: TargetPlatform.android,
      );
      expect(find.byKey(const ValueKey('overview-older')), findsOneWidget);
    });

    stripTest('each press scrolls whole tiles (visible - 1) in 220 ms', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(120));
      final extent = tester.getSize(dayTile(today)).width + 8;
      final visible = (tester.getSize(dayList).width / extent).floor();
      final step = (visible - 1).clamp(1, 1000);
      expect(pixels(tester, dayList), 0);

      await tester.tap(find.byKey(const ValueKey('overview-older')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = pixels(tester, dayList);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(step * extent));
      await tester.pump(const Duration(milliseconds: 150));
      expect(pixels(tester, dayList), closeTo(step * extent, 0.5));

      await tester.tap(find.byKey(const ValueKey('overview-newer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(pixels(tester, dayList), 0);
    });

    stripTest('disabled at both ends, enabled in between; both ends scroll', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(60));
      expect(arrowEnabled(tester, 'overview-newer'), isFalse);
      expect(arrowEnabled(tester, 'overview-older'), isTrue);
      expect(fadeOpacity(tester, 'overview-fade-older'), 1);
      expect(fadeOpacity(tester, 'overview-fade-newer'), 0);

      // Pressing the disabled arrow does nothing.
      await tester.tap(
        find.byKey(const ValueKey('overview-newer')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(pixels(tester, dayList), 0);

      await press(tester, 'overview-older');
      expect(arrowEnabled(tester, 'overview-newer'), isTrue);
      expect(fadeOpacity(tester, 'overview-fade-newer'), 1);

      for (var i = 0; i < 60 && arrowEnabled(tester, 'overview-older'); i++) {
        await press(tester, 'overview-older');
      }
      expect(arrowEnabled(tester, 'overview-older'), isFalse);
      expect(fadeOpacity(tester, 'overview-fade-older'), 0);
      expect(fadeOpacity(tester, 'overview-fade-newer'), 1);
      expect(tester.takeException(), isNull);

      for (var i = 0; i < 60 && arrowEnabled(tester, 'overview-newer'); i++) {
        await press(tester, 'overview-newer');
      }
      expect(arrowEnabled(tester, 'overview-newer'), isFalse);
      expect(pixels(tester, dayList), 0);
      expect(fullyInside(tester, dayTile(today), dayList), isTrue);
    });

    stripTest('48 dp tap area and a label for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpStrip(tester, strip: dayStrip, days: daysOf(60));
      expect(
        tester.getSize(find.byKey(const ValueKey('overview-older'))),
        const Size(48, 48),
      );
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byKey(const ValueKey('overview-older')),
            matching: find.byType(IconButton),
          ),
        ),
        isSemantics(
          tooltip: 'Earlier days',
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });

    stripTest('reduced motion: the press jumps', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpStrip(tester, strip: dayStrip, days: daysOf(120));
      await tester.tap(find.byKey(const ValueKey('overview-older')));
      await tester.pump();
      expect(pixels(tester, dayList), greaterThan(0));
    });
  });

  group('selection and keyboard', () {
    stripTest('tab order follows the reading order; Enter and Space select', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(60));
      double? focusedTileX() {
        final context = FocusManager.instance.primaryFocus?.context;
        final frame = context
            ?.findAncestorStateOfType<State<OverviewTileFrame>>();
        if (frame == null) return null;
        return (frame.context.findRenderObject()! as RenderBox)
            .localToGlobal(Offset.zero)
            .dx;
      }

      Future<void> tab() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }

      // Tab until the first tile has focus (arrows that are off are skipped).
      for (var i = 0; i < 12 && focusedTileX() == null; i++) {
        await tab();
      }
      final order = <double>[focusedTileX()!];

      // The focused tile shows the 2 px focus ring.
      final ring = find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.foregroundDecoration is BoxDecoration &&
            ((w.foregroundDecoration! as BoxDecoration).border as Border?)
                    ?.top
                    .width ==
                2,
        skipOffstage: false, // a cached tile beside the viewport may be it
      );
      expect(ring, findsOneWidget);

      // The next tiles follow left to right.
      for (var i = 0; i < 3; i++) {
        await tab();
        order.add(focusedTileX()!);
      }
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]));
      }

      // Enter selects the focused tile, which moves the summary line.
      String? detail() => tester
          .widget<Text>(find.byKey(const ValueKey('overview-detail')))
          .data;
      final before = detail();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 200));
      final afterEnter = detail();
      expect(afterEnter, isNot(before));

      await tab();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 200));
      expect(detail(), isNot(afterEnter));
    });

    stripTest('semantics: button, selected state and the announced label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpStrip(tester, strip: dayStrip, days: daysOf(30));
      final day = daysOf(30)[2]; // a reviewed day
      final tile = dayTile(day.date);
      final label = tester.getSemantics(tile).label;
      expect(label, contains('Excellent'));
      expect(label, contains('33% done'));
      expect(
        tester.getSemantics(dayTile(today)),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(tester.getSemantics(dayTile(today)).label, contains('today'));
      expect(
        tester.getSemantics(tile),
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getSemantics(tile),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(dayTile(today)),
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );
      handle.dispose();
    });

    stripTest('hover is tonal and the cursor is a pointer', (tester) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(30));
      final tokens = AppThemeTokens.dark();
      final inset = Color.alphaBlend(
        tokens.textPrimary.withValues(alpha: 0.06),
        tokens.surface,
      );
      final hover = Color.alphaBlend(
        tokens.textPrimary.withValues(alpha: 0.12),
        tokens.surface,
      );
      Color fillOf(Finder tile) =>
          ((tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: tile,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!)
                  as BoxDecoration)
              .color!;
      final target = dayTile(addDays(today, -1));
      expect(fillOf(target), inset);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fillOf(target), hover);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fillOf(target), inset);
    });

    stripTest('selecting a tile rebuilds only the two tiles and the summary', (
      tester,
    ) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(60));
      final counts = <String, int>{};
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final name = element.widget.runtimeType.toString();
        counts[name] = (counts[name] ?? 0) + 1;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      await tester.tap(dayTile(addDays(today, -2)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(counts['OverviewTileFrame'], 2, reason: '$counts');
      expect(counts['ValueListenableBuilder<DateTime>'], 1, reason: '$counts');
      for (final name in [
        'OverviewDayStrip',
        'OverviewStrip',
        'OverviewDayTileBody',
        'OverviewDaySummary',
        'OverviewLegend',
      ]) {
        expect(counts[name] ?? 0, 0, reason: '$name in $counts');
      }

      // Hover on one tile rebuilds that tile alone. (After a touch tap the
      // focus highlight mode is "touch", where hover shows nothing; a real
      // mouse switches it back.)
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      counts.clear();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(dayTile(addDays(today, -1))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(counts['OverviewTileFrame'], greaterThanOrEqualTo(1));
      expect(counts['OverviewTileFrame'], lessThanOrEqualTo(2));
      expect(counts['OverviewDayStrip'] ?? 0, 0);
      expect(counts['OverviewDaySummary'] ?? 0, 0);
    });

    stripTest('scrolling does not rebuild the tiles', (tester) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(120));
      final counts = <String, int>{};
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final name = element.widget.runtimeType.toString();
        counts[name] = (counts[name] ?? 0) + 1;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      // Move only a little, so no new tile is built; scrolling flips the edge
      // state, which must not touch the tiles.
      await tester.tap(find.byKey(const ValueKey('overview-older')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(counts['OverviewDayTileBody'] ?? 0, lessThan(25));
      expect(counts['OverviewDayStrip'] ?? 0, 0);
    });

    stripTest('selecting a week moves only the highlight', (tester) async {
      await pumpStrip(tester, strip: weekStrip, weeks: weeksOf(30));
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(weekTile(thisWeek)),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      final other = weekTile(addDays(thisWeek, -7));
      await tester.tap(other);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getSemantics(other),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(weekTile(thisWeek)),
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );
      handle.dispose();
    });

    stripTest('idle: no frame is scheduled', (tester) async {
      await pumpStrip(tester, strip: dayStrip, days: daysOf(60));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('tier tag colour', () {
    for (final (name, colors, tokens) in [
      ('dark', ReviewColors.dark, AppThemeTokens.dark()),
      ('light', ReviewColors.light, AppThemeTokens.light()),
    ]) {
      test('every tier name reads at 4.5:1 in the $name theme', () {
        for (var level = 1; level <= 4; level++) {
          final color = overviewReadable(
            colors.mood(level),
            tokens.surface,
            tokens.textPrimary,
          );
          expect(
            overviewContrast(color, tokens.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'tier $level',
          );
        }
      });
    }
  });

  group('haptics', () {
    Future<List<String>> tapAndCollect(
      WidgetTester tester,
      TargetPlatform platform,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpStrip(
        tester,
        strip: dayStrip,
        days: daysOf(30),
        platform: platform,
      );
      await tester.tap(dayTile(addDays(today, -1)));
      await tester.pump(const Duration(milliseconds: 200));
      // Tapping the tile that is already selected does nothing more.
      await tester.tap(dayTile(addDays(today, -1)));
      await tester.pump(const Duration(milliseconds: 200));
      return calls;
    }

    stripTest('Android: one selection click per new selection', (tester) async {
      expect(await tapAndCollect(tester, TargetPlatform.android), [
        'HapticFeedbackType.selectionClick',
      ]);
    });

    stripTest('desktop: none', (tester) async {
      expect(await tapAndCollect(tester, TargetPlatform.linux), isEmpty);
    });
  });

  // ---- the screen, with a real database -------------------------------

  group('the screen', () {
    Future<ProviderContainer> pumpScreen(
      WidgetTester tester, {
      required double width,
      double scale = 1.0,
      String path = '/review/overview',
    }) async {
      if (scale != 1.0) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final container = await buildTestContainer(tester);
      await runDb(tester, () async {
        final start = DateTime(today.year, today.month, today.day, 9);
        await container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'A task with a rather long title for the day',
                startTime: start,
                endTime: start.add(const Duration(hours: 1)),
                createdAt: start,
                updatedAt: start,
              ),
            );
        await container
            .read(dayContextRepositoryProvider)
            .save(
              isoDateString(today),
              DayContextKind.custom,
              'Working from the airport lounge',
            );
        await container
            .read(dayContextRepositoryProvider)
            .save(
              isoDateString(addDays(today, -1)),
              DayContextKind.leave,
              null,
            );
      });
      appRouter.go(path);
      await pumpApp(tester, container, surface: Size(width, 1000));
      await settle(tester);
      return container;
    }

    for (final width in [320.0, 360.0, 700.0, 1100.0, 1600.0, 2000.0]) {
      for (final scale in [1.0, 1.3]) {
        stripTest(
          'no exception at ${width.toInt()} dp, text scale $scale, both modes',
          (tester) async {
            final container = await pumpScreen(
              tester,
              width: width,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            expect(dayList, findsOneWidget);
            expect(fullyInside(tester, dayTile(today), dayList), isTrue);

            // Inner toggle: "Days" / "Weeks" (not the header's Daily / Weekly).
            final toggle = find.byKey(const ValueKey('overview-subtabs'));
            expect(
              find.descendant(of: toggle, matching: find.text('Days')),
              findsOneWidget,
            );
            expect(
              find.descendant(of: toggle, matching: find.text('Daily')),
              findsNothing,
            );
            final card = tester.getRect(find.byType(AppSurface));
            expect(card.left, greaterThanOrEqualTo(16));
            expect(card.right, lessThanOrEqualTo(width - 16 + 0.5));
            if (width <= 700) {
              // Narrow: the toggle takes the whole card width.
              expect(tester.getSize(toggle).width, closeTo(card.width - 34, 1));
            }

            await tester.tap(
              find.descendant(of: toggle, matching: find.text('Weeks')),
            );
            await settle(tester);
            expect(tester.takeException(), isNull);
            expect(weekList, findsOneWidget);
            expect(dayList, findsNothing);
            expect(fullyInside(tester, weekTile(thisWeek), weekList), isTrue);

            await tester.tap(
              find.descendant(of: toggle, matching: find.text('Days')),
            );
            await settle(tester);
            expect(tester.takeException(), isNull);
            expect(fullyInside(tester, dayTile(today), dayList), isTrue);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await finish(tester, container);
          },
        );
      }
    }

    stripTest('the mode switch cross-fades in at most 150 ms', (tester) async {
      final container = await pumpScreen(tester, width: 1100);
      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, const Duration(milliseconds: 150));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await finish(tester, container);
    });

    stripTest('weeks open with the current week selected', (tester) async {
      final container = await pumpScreen(
        tester,
        width: 1100,
        path: '/review/overview?tab=weekly',
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(weekTile(thisWeek)),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(find.byKey(const ValueKey('overview-legend')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-open-day')), findsNothing);
      handle.dispose();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await finish(tester, container);
    });
  });
}
