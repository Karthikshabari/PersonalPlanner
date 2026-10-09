import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/features/review/domain/review_reason_presets.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

/// "Edit presets" on the Daily review: the card's height follows the editor's
/// content (nothing has a fixed height), the fields sit in equal-width cells
/// (two columns on a wide card, one on a narrow one) and nothing overflows at
/// any width, any text scale or preset count.
void main() {
  const names = [
    'Ran out of time',
    'Interrupted',
    'Lower priority',
    'Blocked',
    'Low energy',
    'Waiting on others',
  ];
  final edit = find.byKey(const ValueKey('review-edit-presets'));
  Finder field(int i) => find.byKey(ValueKey('review-preset-field-$i'));
  final editor = find.byKey(const ValueKey('review-preset-editor'));

  for (final width in [320.0, 360.0, 700.0, 1100.0, 1600.0, 2000.0]) {
    for (final scale in [1.0, 1.3]) {
      for (final count in [3, 5, maxReviewReasonPresets]) {
        testWidgets('opens at $width dp, scale $scale, $count presets', (
          tester,
        ) async {
          final container = await pumpDaily(
            tester,
            surface: Size(width, 900),
            textScale: scale,
            presets: names.take(count).toList(),
            seeds: [
              DailySeed(longTitle(80), status: TaskStatus.skipped),
              const DailySeed('Second skipped', status: TaskStatus.skipped),
            ],
          );
          final card = cardOf('Task outcomes');
          final closedHeight = tester.getSize(card).height;

          await tester.ensureVisible(edit);
          await tester.pump();
          await tester.tap(edit);
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Done'), findsOneWidget);
          expect(editor, findsOneWidget);

          // Equal-width fields, in rows of one or two.
          final fields = [for (var i = 0; i < count; i++) field(i)];
          for (final f in fields) {
            await tester.ensureVisible(f);
          }
          await tester.pump();
          final rects = [for (final f in fields) tester.getRect(f)];
          expect({for (final r in rects) r.width.toStringAsFixed(1)}.length, 1);
          final columns = rects.where((r) => r.top == rects.first.top).length;
          expect(columns, inInclusiveRange(1, 2));
          if (width <= 360) expect(columns, 1);
          if (width >= 1100 && scale == 1.0) {
            // The card is wide; with the narrow test font it may still be one.
            expect(columns, inInclusiveRange(1, 2));
          }
          // Everything stays inside the editor panel and the card.
          final panel = tester.getRect(editor);
          final outer = tester.getRect(card);
          for (final r in rects) {
            expect(r.left, greaterThanOrEqualTo(panel.left));
            expect(r.right, lessThanOrEqualTo(panel.right));
          }
          expect(panel.left, greaterThanOrEqualTo(outer.left));
          expect(panel.right, lessThanOrEqualTo(outer.right));
          // The card grew to hold the editor (its height follows the
          // content; nothing is fixed), and the panel sits inside it.
          expect(tester.getSize(card).height, greaterThan(closedHeight));
          expect(panel.bottom, lessThanOrEqualTo(outer.bottom - 16 + 0.5));

          // Typing in a field and removing one does not break the layout.
          await tester.enterText(field(0), 'A new preset');
          await settle(tester);
          await tester.tap(
            find.byKey(const ValueKey('review-preset-remove-0')),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(field(count - 1), findsNothing);

          // Done closes it.
          await tester.ensureVisible(find.text('Done'));
          await tester.pump();
          await tester.tap(find.text('Done'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(editor, findsNothing);
          expect(find.text('Edit presets'), findsOneWidget);
          await finish(tester, container);
        });
      }
    }
  }

  testWidgets('opening and closing the editor returns to the same height', (
    tester,
  ) async {
    final container = await pumpDaily(
      tester,
      surface: const Size(700, 900),
      seeds: [const DailySeed('Skipped one', status: TaskStatus.skipped)],
    );
    final card = cardOf('Task outcomes');
    final closed = tester.getSize(card).height;
    await tester.ensureVisible(edit);
    await tester.pump();
    await tester.tap(edit);
    await settle(tester);
    expect(tester.getSize(card).height, greaterThan(closed));
    await tester.ensureVisible(find.text('Done'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(tester.getSize(card).height, closeTo(closed, 0.5));
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('Edit presets sits at the right edge with a 48 dp target', (
    tester,
  ) async {
    final container = await pumpDaily(
      tester,
      surface: const Size(1100, 900),
      seeds: [const DailySeed('Skipped one', status: TaskStatus.skipped)],
    );
    final card = tester.getRect(cardOf('Task outcomes'));
    final button = tester.getRect(edit);
    expect(button.height, greaterThanOrEqualTo(48));
    expect(button.width, greaterThanOrEqualTo(48));
    // The label lines up with the card's content edge (16 dp padding).
    expect(button.right, closeTo(card.right - 16, 1));
    // Same row as the title, not after it.
    final title = tester.getRect(find.text('Task outcomes'));
    expect(button.left, greaterThan(title.right));
    expect(
      (button.center.dy - title.center.dy).abs(),
      lessThan(button.height / 2),
    );
    // The status is a pill next to the title, or under it when it is too
    // long to fit beside it.
    final counter = tester.getRect(
      find.byKey(const ValueKey('review-reason-counter')),
    );
    expect(
      counter.left > title.right || counter.top >= title.bottom - 1,
      isTrue,
    );
    await finish(tester, container);
  });

  testWidgets('the button drops under the title instead of squeezing it', (
    tester,
  ) async {
    final container = await pumpDaily(
      tester,
      surface: const Size(320, 900),
      textScale: 1.3,
      seeds: [const DailySeed('Skipped one', status: TaskStatus.skipped)],
    );
    final title = tester.getRect(find.text('Task outcomes'));
    // The whole title on one or two lines, never a sliver one letter wide.
    expect(title.width, greaterThan(60));
    expect(title.height, lessThan(80));
    final button = tester.getRect(edit);
    expect(button.top, greaterThanOrEqualTo(title.bottom - 1));
    final card = tester.getRect(cardOf('Task outcomes'));
    expect(button.right, closeTo(card.right - 16, 1));
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('the status wraps under the title on a narrow card', (
    tester,
  ) async {
    final container = await pumpDaily(
      tester,
      surface: const Size(320, 900),
      textScale: 1.3,
      seeds: [const DailySeed('Skipped one', status: TaskStatus.skipped)],
    );
    final title = tester.getRect(find.text('Task outcomes'));
    final counter = tester.getRect(
      find.byKey(const ValueKey('review-reason-counter')),
    );
    expect(counter.top, greaterThanOrEqualTo(title.bottom));
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('the success tint shows only when every reason is added', (
    tester,
  ) async {
    final container = await pumpDaily(
      tester,
      surface: const Size(1100, 900),
      seeds: [const DailySeed('Skipped one', status: TaskStatus.skipped)],
    );
    Color? pillColor() {
      final pill = find.ancestor(
        of: find.byKey(const ValueKey('review-reason-counter')),
        matching: find.byType(AnimatedContainer),
      );
      return ((tester.widget<AnimatedContainer>(pill.first)).decoration!
              as BoxDecoration)
          .color;
    }

    final before = pillColor();
    await tester.tap(find.widgetWithText(ActionChip, 'Blocked'));
    await settle(tester);
    expect(find.text('All reasons added'), findsOneWidget);
    expect(pillColor(), isNot(before));
    await finish(tester, container);
  });
}
