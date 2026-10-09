import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/daily_stats.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/review/domain/review_draft.dart';
import 'package:personal_planner/features/review/domain/review_insights.dart';
import 'package:personal_planner/features/review/presentation/widgets/daily_glance_card.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_mood_card.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_save_bar.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

Widget _host(Widget child, {ThemeData? theme, double? height}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 400, height: height, child: child),
    ),
  ),
);

DailyStats _stats({
  int completed = 0,
  int total = 0,
  int skipped = 0,
  int cancelled = 0,
  int planned = 0,
  int actual = 0,
}) => DailyStats(
  date: DateTime(2026, 10, 9),
  computedAt: DateTime(2026, 10, 9),
  totalTasks: total,
  completedTasks: completed,
  skippedTasks: skipped,
  cancelledTasks: cancelled,
  plannedDurationMin: planned,
  actualDurationMin: actual,
);

ReviewInsights _insights(int moved) => ReviewInsights(
  changes: [
    for (var i = 0; i < moved; i++)
      ReviewChange(
        taskTitle: 'Task $i',
        detail: '10:00 -> 11:00',
        kind: ReviewChangeKind.moved,
      ),
  ],
);

void main() {
  group('DailyGlanceCard', () {
    Future<void> pumpGlance(
      WidgetTester tester,
      DailyStats stats, {
      bool future = false,
      bool isToday = false,
      int moved = 0,
    }) => tester.pumpWidget(
      _host(
        DailyGlanceCard(
          stats: stats,
          insights: _insights(moved),
          future: future,
          isToday: isToday,
        ),
      ),
    );

    testWidgets('a day without tasks says so and shows no bar', (tester) async {
      await pumpGlance(tester, _stats());
      expect(find.text('No tasks planned'), findsOneWidget);
      expect(find.textContaining('0 / 0'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('No planned time'), findsOneWidget);
    });

    testWidgets('value, slim bar and one caption line with · separators', (
      tester,
    ) async {
      await pumpGlance(
        tester,
        _stats(completed: 1, total: 3, skipped: 1, cancelled: 1, planned: 180),
        moved: 2,
      );
      expect(find.text('1 / 3 completed'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(1 / 3, 1e-9));
      expect(bar.minHeight, 4);
      final facts = tester.widget<Text>(
        find.byKey(const ValueKey('review-glance-facts')),
      );
      expect(facts.data, '3h planned · 2 moved · 1 skipped · 1 cancelled');
      expect(facts.style!.fontSize, 12, reason: 'caption style');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Today pill shows only for today', (tester) async {
      await pumpGlance(tester, _stats(total: 1), isToday: true);
      expect(find.byKey(const ValueKey('review-glance-today')), findsOneWidget);
      await pumpGlance(tester, _stats(total: 1));
      expect(find.byKey(const ValueKey('review-glance-today')), findsNothing);
    });

    testWidgets('a future day shows the count, no bar and no skipped/moved', (
      tester,
    ) async {
      await pumpGlance(
        tester,
        _stats(total: 4, planned: 90, skipped: 1),
        future: true,
        moved: 1,
      );
      expect(find.text('4 planned'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('skipped'), findsNothing);
      expect(find.textContaining('moved'), findsNothing);
    });

    testWidgets('the caption wraps instead of overflowing on a narrow card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(240, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DailyGlanceCard(
              stats: _stats(
                completed: 10,
                total: 12,
                skipped: 1,
                cancelled: 1,
                planned: 725,
                actual: 700,
              ),
              insights: _insights(3),
              future: false,
              isToday: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ReviewMoodCard', () {
    testWidgets('selected tile: fill, check and a slight scale up', (
      tester,
    ) async {
      var selected = 1;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => ReviewMoodCard(
              selected: selected,
              enabled: true,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('review-mood-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, 3);
      double scaleOf(int level) => tester
          .widget<AnimatedScale>(
            find
                .ancestor(
                  of: find.byKey(ValueKey('review-mood-$level')),
                  matching: find.byType(AnimatedScale),
                )
                .first,
          )
          .scale;
      double checkOpacity(int level) => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byKey(ValueKey('review-mood-$level')),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(scaleOf(3), closeTo(1.04, 1e-9));
      expect(scaleOf(1), 1.0);
      expect(checkOpacity(3), 1, reason: 'a check, not only a colour');
      expect(checkOpacity(1), 0);
    });

    testWidgets('the rating row is centred in a stretched card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ReviewMoodCard(selected: 2, enabled: true, onChanged: (_) {}),
          height: 360,
        ),
      );
      final card = tester.getRect(find.byType(ReviewMoodCard));
      final title = tester.getRect(find.text('How was the day?'));
      final first = tester.getRect(find.byKey(const ValueKey('review-mood-1')));
      final last = tester.getRect(find.byKey(const ValueKey('review-mood-4')));
      final above = first.top - (title.bottom + 8);
      final below = (card.bottom - 16) - last.bottom;
      expect(above, greaterThan(10), reason: 'free space above the tiles');
      expect(above, closeTo(below, 1), reason: 'and as much below');
    });

    testWidgets('labels never truncate; 4 in a row or 2 x 2', (tester) async {
      // The test font is about twice as wide as a real one, so these are the
      // narrowest cards (and the widest) whose labels fit in either layout.
      for (final width in [270.0, 330.0, 520.0]) {
        tester.view.physicalSize = Size(width + 64, 600);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: ReviewMoodCard(
                  selected: 0,
                  enabled: true,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        final tops = {
          for (var l = 1; l <= 4; l++)
            tester.getTopLeft(find.byKey(ValueKey('review-mood-$l'))).dy,
        };
        expect(tops.length, anyOf(1, 2), reason: '$width dp');
        expect(tester.takeException(), isNull, reason: '$width dp');
        for (final label in ['Good', 'Great', 'Excellent', 'Legendary']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        }
      }
      addTearDown(tester.view.reset);
    });
  });

  group('ReviewSaveBar', () {
    Widget bar({
      ReviewSaveStatus status = ReviewSaveStatus.idle,
      bool differs = false,
      bool hint = true,
    }) => _host(
      ReviewSaveBar(
        status: status,
        enabled: true,
        differsFromSaved: differs,
        focusNode: FocusNode(),
        onSave: () {},
        showShortcutHint: hint,
      ),
    );

    testWidgets('Ctrl + Enter hint: desktop only, never on touch platforms', (
      tester,
    ) async {
      for (final (platform, shown) in [
        (TargetPlatform.linux, true),
        (TargetPlatform.macOS, true),
        (TargetPlatform.windows, true),
        (TargetPlatform.android, false),
        (TargetPlatform.iOS, false),
        (TargetPlatform.fuchsia, false),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(bar());
        expect(
          find.text('Ctrl + Enter'),
          shown ? findsOneWidget : findsNothing,
          reason: '$platform',
        );
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(bar(hint: false));
      expect(find.text('Ctrl + Enter'), findsNothing, reason: 'narrow layout');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Save review cross-fades to Saved; the unsaved pill follows', (
      tester,
    ) async {
      await tester.pumpWidget(bar(differs: true));
      expect(find.text('Save review'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-unsaved-hint')), findsOneWidget);
      await tester.pumpWidget(bar(status: ReviewSaveStatus.saved));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Save review'), findsOneWidget, reason: 'mid-fade');
      expect(find.text('Saved'), findsOneWidget, reason: 'mid-fade');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Save review'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-unsaved-hint')), findsNothing);
    });
  });

  group('the bottom bar in the page', () {
    testWidgets('the last card ends 16 dp above the bar after scrolling', (
      tester,
    ) async {
      final container = await pumpDaily(
        tester,
        surface: const Size(390, 700),
        seeds: [
          for (var i = 0; i < 6; i++)
            DailySeed('Task $i', status: TaskStatus.skipped),
        ],
      );
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final bar = tester.getRect(find.byType(ReviewSaveBar));
      final note = tester.getRect(cardOf('Anything worth remembering?'));
      expect(note.bottom, lessThanOrEqualTo(bar.top - 16 + 0.5));
      expect(bar.bottom, closeTo(700, 80), reason: 'bar at the screen bottom');
      expect(tester.takeException(), isNull);
      await finish(tester, container);
    });

    testWidgets('with the keyboard open the bar rises above it', (
      tester,
    ) async {
      final container = await pumpDaily(
        tester,
        surface: const Size(390, 800),
        seeds: [const DailySeed('Task', status: TaskStatus.skipped)],
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final bar = tester.getRect(find.byType(ReviewSaveBar));
      expect(bar.bottom, lessThanOrEqualTo(500 + 0.5));
      for (var i = 0; i < 20; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final note = tester.getRect(cardOf('Anything worth remembering?'));
      expect(note.bottom, lessThanOrEqualTo(bar.top - 16 + 0.5));
      expect(tester.takeException(), isNull);
      await finish(tester, container);
    });

    testWidgets('the bar is outside the scrolling list', (tester) async {
      final container = await pumpDaily(tester, surface: const Size(1100, 900));
      expect(
        find.descendant(
          of: find.byType(ListView).first,
          matching: find.byKey(const ValueKey('review-save')),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('review-save')), findsOneWidget);
      await finish(tester, container);
    });
  });

  group('reduced motion', () {
    testWidgets('chips and fields rebuild without animation', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      late List<String> ids;
      final container = await pumpDaily(
        tester,
        surface: const Size(1100, 900),
        seeds: [const DailySeed('Left undone', status: TaskStatus.skipped)],
        onSeeded: (v) => ids = v,
      );
      // Typing adds the ghost chip (the grid resizes): no AnimatedSize assert.
      await tester.enterText(
        find.byKey(ValueKey('review-reason-${ids.single}')),
        'Custom reason',
      );
      await settle(tester);
      expect(find.byType(AnimatedSize), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('review-edit-presets')),
      );
      await tester.tap(find.byKey(const ValueKey('review-edit-presets')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await finish(tester, container);
    });
  });
}
