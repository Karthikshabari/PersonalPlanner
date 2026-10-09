import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

/// How often each Daily card (and each task row) is rebuilt. A rating tap, a
/// preset chip or a keystroke must rebuild only what shows that value.
const _cards = [
  'DailyGlanceCard',
  'TaskOutcomesCard',
  'ReviewMoodCard',
  'ReviewNoteCard',
  'ReviewSaveBar',
];

void main() {
  late Map<String, int> counts;
  late Map<String, int> rows;
  late List<String> ids;

  void startCounting() {
    counts = {for (final c in _cards) c: 0};
    rows = {for (final id in ids) id: 0};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final name = element.widget.runtimeType.toString();
      if (counts.containsKey(name)) counts[name] = counts[name]! + 1;
      if (name == 'TaskOutcomeRowView') {
        final key = element.widget.key! as ValueKey<String>;
        final id = key.value.replaceFirst('review-outcome-row-', '');
        rows[id] = (rows[id] ?? 0) + 1;
      }
    };
  }

  Future<void> pumpReview(WidgetTester tester) async {
    final container = await pumpDaily(
      tester,
      surface: const Size(1600, 1400),
      seeds: [
        const DailySeed('Alpha', status: TaskStatus.skipped),
        const DailySeed('Beta', status: TaskStatus.skipped),
        const DailySeed('Gamma', status: TaskStatus.skipped),
      ],
      onSeeded: (v) => ids = v,
    );
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await drainStreams(tester);
      await finish(tester, container);
    });
  }

  void expectOthersQuiet({
    required Set<String> except,
    Set<String> exceptRows = const {},
  }) {
    for (final name in _cards) {
      if (except.contains(name)) continue;
      expect(counts[name], 0, reason: '$name rebuilt: $counts');
    }
    for (final id in ids) {
      if (exceptRows.contains(id)) continue;
      expect(rows[id], 0, reason: 'row $id rebuilt: $rows');
    }
  }

  testWidgets('selecting a rating rebuilds the rating card (and the bar)', (
    tester,
  ) async {
    await pumpReview(tester);
    startCounting();
    await tester.tap(find.byKey(const ValueKey('review-mood-3')));
    await settle(tester);
    expect(counts['ReviewMoodCard'], greaterThan(0));
    expectOthersQuiet(except: {'ReviewMoodCard', 'ReviewSaveBar'});
  });

  testWidgets('typing in one reason rebuilds only that row', (tester) async {
    await pumpReview(tester);
    final field = find.byKey(ValueKey('review-reason-${ids[1]}'));
    await tester.ensureVisible(field);
    await settle(tester);
    startCounting();
    await tester.enterText(field, 'Meeting ran long');
    await settle(tester);
    await tester.enterText(field, 'Meeting ran long, again');
    await settle(tester);
    expectOthersQuiet(except: {'ReviewSaveBar'}, exceptRows: {ids[1]});
    expect(rows[ids[1]], greaterThan(0));
  });

  testWidgets('tapping a preset chip rebuilds only that row', (tester) async {
    await pumpReview(tester);
    final chip = find.descendant(
      of: find.byKey(ValueKey('review-outcome-row-${ids[2]}')),
      matching: find.widgetWithText(ActionChip, 'Blocked'),
    );
    await tester.ensureVisible(chip);
    await settle(tester);
    startCounting();
    await tester.tap(chip);
    await settle(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('review-reason-${ids[2]}')))
          .controller!
          .text,
      'Blocked',
    );
    // The other rows' fields were not touched.
    for (final id in [ids[0], ids[1]]) {
      expect(
        tester
            .widget<TextField>(find.byKey(ValueKey('review-reason-$id')))
            .controller!
            .text,
        isEmpty,
      );
    }
    expectOthersQuiet(except: {'ReviewSaveBar'}, exceptRows: {ids[2]});
  });

  testWidgets('typing in the note rebuilds only the note field', (
    tester,
  ) async {
    await pumpReview(tester);
    final field = find.byKey(const ValueKey('review-note'));
    await tester.ensureVisible(field);
    await settle(tester);
    startCounting();
    await tester.enterText(field, 'A steady day');
    await settle(tester);
    await tester.enterText(field, 'A steady day, mostly');
    await settle(tester);
    // The card and the rows do not listen to the text; only the bar's
    // "Not saved yet" fact flips.
    expectOthersQuiet(except: {'ReviewSaveBar'});
  });

  testWidgets('every row keeps its controller across unrelated rebuilds', (
    tester,
  ) async {
    await pumpReview(tester);
    final field = find.byKey(ValueKey('review-reason-${ids[0]}'));
    await tester.ensureVisible(field);
    final controller = tester.widget<TextField>(field).controller!;
    await tester.enterText(field, 'Kept');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('review-mood-2')));
    await settle(tester);
    expect(tester.widget<TextField>(field).controller, same(controller));
    expect(controller.text, 'Kept');
  });
}
