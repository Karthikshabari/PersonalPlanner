import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/theme/theme_mode_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart';

import '../helpers/test_container.dart';

const _months = {
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
};

InsightsSnapshot _snapshot(DateTime generatedFor) => InsightsSnapshot(
  generatedFor: generatedFor,
  consistencyStart: addDays(generatedFor, -364),
  consistencyDays: const [],
  streaks: const StreakSummary(current: 0, best: 0),
  weekStart: startOfWeek(generatedFor),
  weekEndExclusive: addDays(startOfWeek(generatedFor), 7),
  plannedMinutes: 0,
  actualMinutes: 0,
  completedPlannedMinutes: 0,
  categories: const [],
  notable: const [],
);

Future<void> _pumpGrid(
  WidgetTester tester, {
  required double width,
  required DateTime generatedFor,
  bool compact = false,
}) async {
  tester.view.physicalSize = Size(math.max(width, 800), 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppThemeTokens.light()]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ConsistencyGrid(
              snapshot: _snapshot(generatedFor),
              compact: compact,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<ProviderContainer> _pumpInsights(
  WidgetTester tester,
  Size size,
  ThemeMode mode,
) async {
  final container = await buildTestContainer(tester);
  await runDb(
    tester,
    () => container.read(themeModeProvider.notifier).setMode(mode),
  );
  appRouter.go('/analytics');
  await pumpApp(tester, container, surface: size);
  return container;
}

Finder _cells() => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.key is ValueKey &&
      ((w.key! as ValueKey).value as String).startsWith('consistency-cell-'),
);

List<Rect> _monthLabelRects(WidgetTester tester) => [
  for (final element in find.byType(Text).evaluate())
    if (_months.contains((element.widget as Text).data))
      tester.getRect(find.byWidget(element.widget)),
];

void main() {
  const widths = [320.0, 393.0, 600.0, 800.0, 839.0, 900.0, 1280.0, 1920.0];

  group('Insights Consistency grid never overflows', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in widths) {
        testWidgets('${mode.name} at ${width.toInt()} px', (tester) async {
          final container = await _pumpInsights(
            tester,
            Size(width, 1280),
            mode,
          );

          expect(tester.takeException(), isNull);
          final today = ValueKey(
            'consistency-day-${isoDateString(startOfDay(DateTime.now()))}',
          );
          // The most recent week is always on screen.
          expect(find.byKey(today), findsOneWidget);
          final card = tester.getRect(
            find.byKey(const ValueKey('consistency-section')),
          );
          if (width >= 700) {
            // Not scrolled: every cell sits inside the card.
            for (final rect
                in tester
                    .widgetList(_cells())
                    .map((w) => tester.getRect(find.byWidget(w)))) {
              expect(rect.right, lessThanOrEqualTo(card.right + 0.001));
            }
          }
          await teardownApp(tester, container);
        });
      }
    }
  });

  group('Consistency grid sizing', () {
    final day = PlannerTimeZone.calendarDate(2026, 10, 25);

    testWidgets('keeps the 16 px cell and all weeks when it fits', (
      tester,
    ) async {
      for (final width in [1280.0, 1920.0]) {
        await _pumpGrid(tester, width: width, generatedFor: day);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_cells().first), const Size(16, 16));
        expect(_cells(), findsNWidgets(53 * 7));
      }
    });

    testWidgets('compact keeps the 9 px floor and all weeks (scrolls)', (
      tester,
    ) async {
      for (final width in [320.0, 393.0]) {
        await _pumpGrid(tester, width: width, generatedFor: day, compact: true);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_cells().first), const Size(9, 9));
        expect(_cells(), findsNWidgets(53 * 7));
      }
    });

    testWidgets('shrinks to 8 px, then drops the oldest weeks', (tester) async {
      // 623 px grid area (the 800 px window): 8 px cells fit all 53 weeks.
      await _pumpGrid(tester, width: 623, generatedFor: day);
      expect(tester.takeException(), isNull);
      expect(_cells(), findsNWidgets(53 * 7));
      expect(tester.getSize(_cells().first).width, lessThan(9));

      // 520 px: too narrow for 53 weeks at 8 px; the oldest are dropped.
      await _pumpGrid(tester, width: 520, generatedFor: day);
      expect(tester.takeException(), isNull);
      expect(_cells().evaluate().length, lessThan(53 * 7));
      expect(
        find.byKey(ValueKey('consistency-day-${isoDateString(day)}')),
        findsOneWidget,
      );
      final right = tester.getRect(_cells().last).right;
      expect(right, lessThanOrEqualTo(520.001));
    });

    testWidgets('no width from 700 to 1920 overflows or hides today', (
      tester,
    ) async {
      for (var width = 700.0; width <= 1920; width += 7) {
        await _pumpGrid(tester, width: width, generatedFor: day);
        expect(tester.takeException(), isNull, reason: 'width $width');
        expect(
          find.byKey(ValueKey('consistency-day-${isoDateString(day)}')),
          findsOneWidget,
        );
      }
    });
  });

  group('Consistency month labels', () {
    testWidgets('never overlap, at any width or start day', (tester) async {
      final start = PlannerTimeZone.calendarDate(2026, 10, 1);
      for (final width in [700.0, 800.0, 1280.0, 1920.0]) {
        for (var offset = 0; offset < 62; offset++) {
          await _pumpGrid(
            tester,
            width: width,
            generatedFor: addDays(start, offset),
          );
          final rects = _monthLabelRects(tester)
            ..sort((a, b) => a.left.compareTo(b.left));
          for (var i = 1; i < rects.length; i++) {
            expect(
              rects[i].left,
              greaterThanOrEqualTo(rects[i - 1].right),
              reason: 'width $width, day offset $offset',
            );
          }
        }
      }
    });

    testWidgets('a one-week first month ("Oct") is dropped, not run into Nov', (
      tester,
    ) async {
      await _pumpGrid(
        tester,
        width: 1280,
        generatedFor: PlannerTimeZone.calendarDate(2026, 10, 25),
      );
      expect(find.text('Nov'), findsOneWidget);
    });
  });
}
