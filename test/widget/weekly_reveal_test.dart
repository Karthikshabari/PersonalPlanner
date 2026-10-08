import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_reveal_card.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';
import '../helpers/weekly_review_fixtures.dart';

void main() {
  DateTime thisWeek() => startOfWeek(DateTime.now());
  final save = find.byKey(const ValueKey('weekly-save'));

  double stepOpacity(WidgetTester tester, String key) => tester
      .widget<Opacity>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  WeeklyRingPainter ring(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(find.byKey(const ValueKey('weekly-ring')))
              .painter!
          as WeeklyRingPainter;

  Future<ProviderContainer> pumpWeekly(
    WidgetTester tester, {
    int? savedMood,
  }) async {
    final container = await buildTestContainer(tester);
    final start = thisWeek().add(const Duration(hours: 9));
    await runDb(tester, () async {
      final tasks = container.read(taskRepositoryProvider);
      for (final (title, status) in [
        ('Write report', TaskStatus.completed),
        ('Read docs', TaskStatus.planned),
      ]) {
        await tasks.insertTask(
          Task(
            id: '',
            title: title,
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            status: status,
            createdAt: start,
            updatedAt: start,
          ),
        );
      }
      if (savedMood != null) {
        await container
            .read(reviewRepositoryProvider)
            .saveWeeklyReviewDraft(
              weekStart: thisWeek(),
              mood: savedMood,
              feeling: '',
              note: '',
            );
      }
    });
    appRouter.go('/review/weekly');
    await pumpApp(tester, container, surface: const Size(1400, 1200));
    await settle(tester);
    return container;
  }

  /// Taps Save and pumps frame by frame until the "after" state is built.
  Future<void> saveAndWaitForReveal(WidgetTester tester, String words) async {
    await tester.tap(save);
    for (var i = 0; i < 30 && find.text(words).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text(words), findsOneWidget);
  }

  testWidgets('before the first save: placeholder and dashed dots', (
    tester,
  ) async {
    final container = await pumpWeekly(tester);

    expect(find.text('Your week'), findsOneWidget);
    expect(find.text('Save your review to reveal your week.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-reveal-placeholder')),
      findsOneWidget,
    );
    expect(find.text('0 of 8 weeks reviewed'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('first save plays the 1500 ms reveal once', (tester) async {
    final container = await pumpWeekly(tester);
    await tester.tap(find.byKey(const ValueKey('weekly-mood-3')));
    await settle(tester);
    await tester.tap(find.text('Calm'));
    await settle(tester);

    await saveAndWaitForReveal(tester, 'Excellent week');
    expect(stepOpacity(tester, 'weekly-step-mood'), lessThan(1));
    expect(ring(tester).fraction, lessThan(0.5));

    await tester.pump(const Duration(milliseconds: 1600));
    expect(stepOpacity(tester, 'weekly-step-mood'), 1);
    expect(stepOpacity(tester, 'weekly-step-message'), 1);
    expect(find.text('A strong week. Well done.'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('weekly-reveal-count')))
          .data,
      '50%',
    );
    expect(find.text('“Calm”'), findsOneWidget);
    expect(find.text('1 of 8 weeks reviewed'), findsOneWidget);
    expect(ring(tester).fraction, closeTo(0.5, 0.001));
    expect(ring(tester).glow, isTrue);

    // A later save updates the card statically.
    await tester.tap(find.text('Proud'));
    await settle(tester);
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 16));
    expect(stepOpacity(tester, 'weekly-step-mood'), 1);
    await settle(tester);
    expect(find.text('“Calm, proud”'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('the reveal announces once', (tester) async {
    final container = await pumpWeekly(tester);
    await tester.tap(find.byKey(const ValueKey('weekly-mood-2')));
    await settle(tester);

    await saveAndWaitForReveal(tester, 'Great week');
    await tester.pump(const Duration(milliseconds: 1600));
    expect(
      tester.takeAnnouncements(),
      contains(
        isAccessibilityAnnouncement('Great week. 50 percent completed.'),
      ),
    );

    await tester.tap(find.text('Busy'));
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    expect(tester.takeAnnouncements(), isEmpty);
    await finish(tester, container);
  });

  testWidgets('reduced motion shows the final state at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final container = await pumpWeekly(tester);

    await saveAndWaitForReveal(tester, 'Good week');
    expect(stepOpacity(tester, 'weekly-step-mood'), 1);
    expect(ring(tester).fraction, closeTo(0.5, 0.001));
    await finish(tester, container);
  });

  testWidgets('a week saved earlier opens in its final state', (tester) async {
    final container = await pumpWeekly(tester, savedMood: 4);
    final handle = tester.ensureSemantics();

    expect(find.text('Legendary week'), findsOneWidget);
    expect(find.text('Your best kind of week.'), findsOneWidget);
    expect(stepOpacity(tester, 'weekly-step-mood'), 1);
    expect(
      tester.getSemantics(
        find
            .ancestor(
              of: find.byKey(const ValueKey('weekly-ring')),
              matching: find.byType(Semantics),
            )
            .first,
      ),
      isSemantics(label: '50 percent completed, Legendary week'),
    );
    expect(find.text('Reviewed · Legendary'), findsOneWidget);
    handle.dispose();
    await finish(tester, container);
  });

  group('per-mood flourishes', () {
    Future<void> pumpCard(WidgetTester tester, int mood) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final numbers = computeWeeklyNumbers(fixtureWeek('great'));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ListView(
              children: [
                WeeklyRevealCard(
                  revealed: true,
                  mood: mood,
                  percent: numbers.percent,
                  deltaText: weeklyDeltaText(
                    percent: numbers.percent,
                    previous: fixtureHistory(),
                  ),
                  highlights: numbers.highlights,
                  feeling: 'Tired mid-week, but proud of the sync work.',
                  dots: weeklyDots(fixtureHistory()),
                  playToken: 0,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final (mood, sparkles, glow, badge) in [
      (1, 0, false, true),
      (2, 1, false, false),
      (3, 2, true, false),
      (4, 3, true, false),
    ]) {
      testWidgets('mood $mood: $sparkles sparkles, glow $glow, badge $badge', (
        tester,
      ) async {
        await pumpCard(tester, mood);

        for (var i = 0; i < 3; i++) {
          expect(
            find.byKey(ValueKey('weekly-sparkle-$i')),
            i < sparkles ? findsOneWidget : findsNothing,
          );
        }
        expect(ring(tester).glow, glow);
        expect(ring(tester).badge, badge);
        expect(find.text('Up 5 points from last week'), findsOneWidget);
        expect(find.text('Every missed task has a reason'), findsOneWidget);
        expect(find.text('7 of 8 weeks reviewed'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(WeeklyRevealCard),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('fits 360 dp at text scale 1.3', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCard(tester, 4);
      expect(tester.takeException(), isNull);
    });
  });
}
