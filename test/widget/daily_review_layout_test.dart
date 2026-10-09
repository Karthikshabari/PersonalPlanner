import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_layout.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

/// The Daily review at every supported width and at text scale 1.0 and 1.3,
/// with long titles and a long reason: nothing overflows, the layout is the
/// expected one (one or two columns, card order) and the Save bar stays on
/// screen.
void main() {
  const widths = [320.0, 360.0, 700.0, 1100.0, 1600.0, 2000.0];
  const scales = [1.0, 1.3];

  final seeds = [
    const DailySeed('Done early', status: TaskStatus.completed),
    DailySeed(longTitle(80), status: TaskStatus.skipped),
    const DailySeed('Skipped short', status: TaskStatus.skipped),
    const DailySeed('Cancelled one', status: TaskStatus.cancelled),
    const DailySeed('Still open'),
  ];

  Future<void> scrollThrough(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'scroll step $i');
    }
  }

  for (final width in widths) {
    for (final scale in scales) {
      testWidgets('layout at $width dp, text scale $scale', (tester) async {
        final surface = Size(width, 900);
        final container = await pumpDaily(
          tester,
          surface: surface,
          textScale: scale,
          seeds: seeds,
        );
        expect(tester.takeException(), isNull);

        final glance = tester.getRect(cardOf('Day at a glance'));
        final outcomes = tester.getRect(cardOf('Task outcomes'));
        final mood = tester.getRect(cardOf('How was the day?'));
        final note = tester.getRect(cardOf('Anything worth remembering?'));
        final wide = ReviewLayout.isWide(width);

        for (final card in [glance, outcomes, mood, note]) {
          expect(card.left, greaterThanOrEqualTo(0));
          expect(card.right, lessThanOrEqualTo(width + 0.01));
        }
        if (wide) {
          expect(mood.left, greaterThan(glance.left));
          expect(note.left, closeTo(mood.left, 0.01), reason: 'right column');
          expect(outcomes.left, closeTo(glance.left, 0.01), reason: 'left');
          expect(mood.top, closeTo(glance.top, 0.01), reason: 'top row top');
          expect(
            mood.height,
            closeTo(glance.height, 0.01),
            reason: 'top row, equal height',
          );
          expect(
            note.top,
            closeTo(outcomes.top, 0.01),
            reason: 'second row top-aligned',
          );
          expect(outcomes.top, greaterThan(glance.bottom));
          // About 3 parts to 2.
          expect(glance.width / mood.width, closeTo(1.5, 0.02));
          expect(outcomes.width / note.width, closeTo(1.5, 0.02));
        } else {
          for (final card in [outcomes, mood, note]) {
            expect(card.left, closeTo(glance.left, 0.01), reason: 'one column');
            expect(card.width, closeTo(glance.width, 0.01));
          }
          expect(glance.top, lessThan(outcomes.top));
          expect(outcomes.top, lessThan(mood.top));
          expect(mood.top, lessThan(note.top));
        }

        // The Save bar is always on screen, without scrolling.
        final save = tester.getRect(find.byKey(const ValueKey('review-save')));
        expect(save.top, greaterThanOrEqualTo(0));
        expect(save.bottom, lessThanOrEqualTo(surface.height));
        expect(find.text('Save review'), findsOneWidget);

        // Narrow header: the date sits above the Today button.
        if (width < 560) {
          final date = tester.getTopLeft(
            find.byKey(const ValueKey('review-today')),
          );
          final prev = tester.getTopLeft(
            find.byKey(const ValueKey('review-prev-day')),
          );
          expect(date.dy, greaterThan(prev.dy));
        }

        await scrollThrough(tester);
        expect(find.byKey(const ValueKey('review-save')), findsOneWidget);
        await drainStreams(tester);
        await finish(tester, container);
      });
    }
  }

  testWidgets('the date used by the header is today', (tester) async {
    final container = await pumpDaily(tester, surface: const Size(1100, 900));
    expect(find.byKey(const ValueKey('review-glance-today')), findsOneWidget);
    expect(isSameDay(dailyToday(), DateTime.now()), isTrue);
    await finish(tester, container);
  });
}
