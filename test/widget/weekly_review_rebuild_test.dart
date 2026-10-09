import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/test_container.dart';

/// How often each Review-tab card's element is rebuilt. A rating tap, a chip
/// toggle or a keystroke must rebuild only the cards that show that value.
const _cards = [
  'WeeklyGlanceCard',
  'WeeklyReasonsCard',
  'WeeklyOutcomesCard',
  'WeeklyMoodCard',
  'WeeklyRevealCard',
  'WeeklyFeelingCard',
];

void main() {
  late Map<String, int> counts;

  void startCounting() {
    counts = {for (final c in _cards) c: 0};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final name = element.widget.runtimeType.toString();
      if (counts.containsKey(name)) counts[name] = counts[name]! + 1;
    };
  }

  Future<void> pumpReview(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/review/weekly');
    await pumpApp(tester, container, surface: const Size(1600, 1000));
    await settle(tester);
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);
      await finish(tester, container);
    });
  }

  testWidgets('selecting a rating rebuilds only the cards that show it', (
    tester,
  ) async {
    await pumpReview(tester);
    startCounting();
    await tester.tap(find.byKey(const ValueKey('weekly-mood-3')));
    await settle(tester);
    // ignore: avoid_print
    print('RATING $counts');
    expect(counts['WeeklyGlanceCard'], 0);
    expect(counts['WeeklyReasonsCard'], 0);
    expect(counts['WeeklyOutcomesCard'], 0);
    expect(counts['WeeklyFeelingCard'], 0);
  });

  testWidgets('toggling a chip rebuilds only the feeling card', (tester) async {
    await pumpReview(tester);
    final chip = find.byKey(const ValueKey('weekly-feeling-word-Calm'));
    await tester.ensureVisible(chip);
    await settle(tester);
    startCounting();
    await tester.tap(chip);
    await settle(tester);
    // ignore: avoid_print
    print('CHIP $counts');
    expect(counts['WeeklyGlanceCard'], 0);
    expect(counts['WeeklyReasonsCard'], 0);
    expect(counts['WeeklyOutcomesCard'], 0);
    expect(counts['WeeklyMoodCard'], 0);
    expect(counts['WeeklyRevealCard'], 0);
  });

  testWidgets('a keystroke in the note rebuilds only the feeling card', (
    tester,
  ) async {
    await pumpReview(tester);
    final field = find.byKey(const ValueKey('weekly-feeling'));
    await tester.ensureVisible(field);
    await settle(tester);
    startCounting();
    await tester.enterText(field, 'a');
    await settle(tester);
    // ignore: avoid_print
    print('KEY $counts');
    expect(counts['WeeklyGlanceCard'], 0);
    expect(counts['WeeklyReasonsCard'], 0);
    expect(counts['WeeklyOutcomesCard'], 0);
    expect(counts['WeeklyMoodCard'], 0);
    expect(counts['WeeklyRevealCard'], 0);
  });
}
