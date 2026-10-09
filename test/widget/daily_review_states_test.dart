import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/review_reason_presets.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

/// Empty, one-task, fifteen-task, long-text, preset-count and past-date
/// states of the Daily review.
void main() {
  Finder row(String id) => find.byKey(ValueKey('review-outcome-row-$id'));
  Finder reason(String id) => find.byKey(ValueKey('review-reason-$id'));

  group('empty and small days', () {
    testWidgets('no tasks: friendly lines, never 0 / 0 or NaN', (tester) async {
      final container = await pumpDaily(tester, surface: const Size(1100, 900));
      expect(find.text('No tasks planned'), findsOneWidget);
      expect(find.text('No tasks to review for this day'), findsOneWidget);
      expect(find.textContaining('0 / 0'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
      expect(
        find.byKey(const ValueKey('review-glance-progress')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('review-reason-counter')), findsNothing);
      // Rating, note and the bar are still there.
      expect(find.text('How was the day?'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('review-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, container);
    });

    testWidgets('one skipped task: reason UI, 0 / 1 and an empty bar', (
      tester,
    ) async {
      late List<String> ids;
      final container = await pumpDaily(
        tester,
        surface: const Size(1100, 900),
        seeds: [const DailySeed('Only task', status: TaskStatus.skipped)],
        onSeeded: (v) => ids = v,
      );
      expect(find.text('0 / 1 completed'), findsOneWidget);
      expect(find.text('1 without a reason'), findsOneWidget);
      expect(find.text('1 skipped'), findsNothing, reason: 'in the caption');
      expect(find.textContaining('1 skipped'), findsOneWidget);
      expect(reason(ids.single), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('review-glance-progress')),
      );
      expect(bar.value, 0);

      await tester.tap(find.widgetWithText(ActionChip, 'Blocked'));
      await settle(tester);
      expect(find.text('All reasons added'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, container);
    });

    testWidgets('only completed tasks: no reason UI at all', (tester) async {
      late List<String> ids;
      final container = await pumpDaily(
        tester,
        surface: const Size(700, 900),
        seeds: [
          const DailySeed('Done one', status: TaskStatus.completed),
          const DailySeed('Done two', status: TaskStatus.completed),
        ],
        onSeeded: (v) => ids = v,
      );
      expect(find.text('2 / 2 completed'), findsOneWidget);
      expect(find.text('All reasons added'), findsOneWidget);
      for (final id in ids) {
        expect(reason(id), findsNothing);
      }
      expect(find.byType(ActionChip), findsNothing);
      await finish(tester, container);
    });
  });

  group('long content', () {
    for (final width in [320.0, 700.0, 1600.0]) {
      testWidgets('15 tasks, an 80-character title and a long reason at '
          '$width dp', (tester) async {
        late List<String> ids;
        final title80 = longTitle(80);
        expect(title80.length, 80);
        final container = await pumpDaily(
          tester,
          surface: Size(width, 900),
          textScale: 1.3,
          seeds: [
            for (var i = 0; i < 15; i++)
              DailySeed(
                i == 1 ? title80 : 'Task number ${i + 1}',
                status: i.isEven ? TaskStatus.skipped : TaskStatus.completed,
              ),
          ],
          onSeeded: (v) => ids = v,
        );
        expect(find.text('0 / 15 completed'), findsNothing);
        expect(find.byType(ActionChip), findsWidgets);

        // The long title keeps its two lines, then ellipsizes with a tooltip.
        final title = tester.widget<Text>(find.text(title80));
        expect(title.maxLines, 2);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(
          find.ancestor(of: find.text(title80), matching: find.byType(Tooltip)),
          findsOneWidget,
        );

        // A reason at the 140-character limit.
        final first = reason(ids.first);
        await tester.ensureVisible(first);
        await tester.pump();
        await tester.enterText(first, 'r' * maxReviewReasonLength);
        await settle(tester);
        expect(tester.takeException(), isNull);

        // Every row starts at the same left edge: the icon column is fixed.
        final lefts = {for (final id in ids) tester.getTopLeft(row(id)).dx};
        expect(lefts.length, 1);

        for (var i = 0; i < 20; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -500));
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull, reason: 'scroll step $i');
        }
        await finish(tester, container);
      });
    }

    testWidgets('rows have the same structure and vertical padding', (
      tester,
    ) async {
      late List<String> ids;
      final container = await pumpDaily(
        tester,
        surface: const Size(1100, 900),
        seeds: [
          const DailySeed('Finished', status: TaskStatus.completed),
          const DailySeed('Left undone', status: TaskStatus.skipped),
        ],
        onSeeded: (v) => ids = v,
      );
      final icons = [
        for (final id in ids)
          tester
                  .getTopLeft(
                    find
                        .descendant(of: row(id), matching: find.byType(Icon))
                        .first,
                  )
                  .dx -
              tester.getTopLeft(row(id)).dx,
      ];
      expect(icons.toSet().length, 1, reason: 'icon column at the same x');
      // The two pills have the same height.
      final pillHeights = {
        tester.getSize(find.text('Completed')).height,
        tester.getSize(find.text('Skipped')).height,
      };
      expect(pillHeights.length, 1);
      final completedPill = find
          .ancestor(
            of: find.text('Completed'),
            matching: find.byType(Container),
          )
          .first;
      final skippedPill = find
          .ancestor(of: find.text('Skipped'), matching: find.byType(Container))
          .first;
      expect(
        tester.getSize(completedPill).height,
        tester.getSize(skippedPill).height,
      );
      await finish(tester, container);
    });
  });

  group('dates', () {
    testWidgets('today shows the Today pill, a past date does not', (
      tester,
    ) async {
      final container = await pumpDaily(
        tester,
        surface: const Size(1100, 900),
        seeds: [const DailySeed('Today task', status: TaskStatus.skipped)],
      );
      expect(find.byKey(const ValueKey('review-glance-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('review-status-chip')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('review-prev-day')));
      await settle(tester);
      expect(find.byKey(const ValueKey('review-glance-today')), findsNothing);
      expect(find.text('No tasks planned'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await drainStreams(tester);
      await finish(tester, container);
    });

    testWidgets('a past day with tasks shows its summary', (tester) async {
      final yesterday = addDays(dailyToday(), -1);
      final container = await pumpDaily(
        tester,
        surface: const Size(700, 900),
        date: yesterday,
        seeds: [
          const DailySeed('Old done', status: TaskStatus.completed),
          const DailySeed('Old skipped', status: TaskStatus.skipped),
          const DailySeed('Old cancelled', status: TaskStatus.cancelled),
        ],
      );
      expect(find.byKey(const ValueKey('review-glance-today')), findsNothing);
      expect(find.text('1 / 3 completed'), findsOneWidget);
      expect(find.textContaining('1 skipped'), findsOneWidget);
      expect(find.textContaining('1 cancelled'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('review-glance-progress')),
      );
      expect(bar.value, closeTo(1 / 3, 0.001));
      await drainStreams(tester);
      await finish(tester, container);
    });

    testWidgets('a future day says it has not happened yet', (tester) async {
      final container = await pumpDaily(
        tester,
        surface: const Size(700, 900),
        date: addDays(dailyToday(), 2),
        seeds: [const DailySeed('Later')],
      );
      expect(find.text('This day has not happened yet.'), findsOneWidget);
      expect(find.text('1 planned'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-glance-progress')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('review-status-chip')), findsNothing);
      await drainStreams(tester);
      await finish(tester, container);
    });
  });

  group('quick-reason chips', () {
    const names = [
      'Ran out of time',
      'Interrupted',
      'Lower priority',
      'Blocked',
      'Low energy',
      'Waiting on others',
    ];

    for (final count in [3, 5, maxReviewReasonPresets]) {
      testWidgets('$count presets: equal cells at every width', (tester) async {
        for (final width in [320.0, 700.0, 1600.0]) {
          late List<String> ids;
          final container = await pumpDaily(
            tester,
            surface: Size(width, 900),
            presets: names.take(count).toList(),
            seeds: [const DailySeed('Left undone', status: TaskStatus.skipped)],
            onSeeded: (v) => ids = v,
          );
          // Type something so the "+ Save as preset" ghost chip shows too
          // (it never does once the list is full).
          await tester.ensureVisible(reason(ids.single));
          await tester.pump();
          await tester.enterText(reason(ids.single), 'Custom reason');
          await settle(tester);

          final chips = find.byType(ActionChip);
          expect(chips, findsNWidgets(count));
          final ghost = find.byKey(
            ValueKey('review-save-as-preset-${ids.single}'),
          );
          final full = count >= maxReviewReasonPresets;
          expect(ghost, full ? findsNothing : findsOneWidget);
          final cells = [
            for (var i = 0; i < count; i++) tester.getRect(chips.at(i)),
            if (!full) tester.getRect(ghost),
          ];
          expect(
            {for (final c in cells) c.width.toStringAsFixed(1)}.length,
            1,
            reason: '$width dp: every cell has one width',
          );
          expect({for (final c in cells) c.height}.length, 1);
          for (final c in cells) {
            expect(c.height, greaterThanOrEqualTo(48), reason: 'tap area');
          }
          if (!full) {
            final g = cells.last;
            for (var i = 0; i < count; i++) {
              expect(
                cells[i].top < g.top ||
                    (cells[i].top == g.top && cells[i].left < g.left),
                isTrue,
                reason: 'the ghost chip is the last cell',
              );
            }
          }
          // Columns come from the card's own width (a 1600 dp window has a
          // narrower Task outcomes card than a 700 dp one): 1 on the narrowest
          // card, at most 3, and the first row spans the reason field above.
          final columns = cells.where((c) => c.top == cells.first.top).length;
          expect(columns, inInclusiveRange(1, 3));
          if (width == 320.0) expect(columns, 1);
          final field = tester.getRect(reason(ids.single));
          expect(
            cells.first.left,
            closeTo(field.left, 0.5),
            reason: 'grid starts at the content edge',
          );
          final rowEnd = cells[columns - 1].right;
          expect(
            rowEnd,
            closeTo(field.right, 0.5),
            reason: 'and fills the row',
          );
          // With more than one column no label is cut short.
          if (columns > 1) {
            for (var i = 0; i < count; i++) {
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: chips.at(i),
                  matching: find.byType(RichText),
                ),
              );
              expect(paragraph.didExceedMaxLines, isFalse);
            }
          }
          expect(tester.takeException(), isNull);
          await finish(tester, container);
        }
      });
    }
  });
}
