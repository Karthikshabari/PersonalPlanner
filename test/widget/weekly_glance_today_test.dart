import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_glance_card.dart';

void main() {
  final days = [
    for (var i = 0; i < 7; i++)
      WeeklyDayStats(
        date: DateTime(2026, 9, 28 + i),
        total: 2,
        completed: 1,
        reviewed: false,
      ),
  ];

  Future<void> pump(WidgetTester tester, DateTime today) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WeeklyDayStrip(days: days, today: today),
        ),
      ),
    );
  }

  /// Alpha of the tile's own fill: days after today are dimmed through
  /// colours, not through an Opacity widget.
  double opacityOf(WidgetTester tester, int i) {
    final box = find
        .descendant(
          of: find.byKey(ValueKey('weekly-day-$i')),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final decoration =
        tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
    expect(
      find.descendant(
        of: find.byKey(ValueKey('weekly-day-$i')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    return double.parse(decoration.color!.a.toStringAsFixed(2));
  }

  testWidgets('the week containing today marks it and dims later days', (
    tester,
  ) async {
    await pump(tester, DateTime(2026, 9, 30, 14, 5));
    expect(opacityOf(tester, 1), 1);
    expect(opacityOf(tester, 2), 1);
    expect(opacityOf(tester, 3), 0.6);
    expect(opacityOf(tester, 6), 0.6);
  });

  testWidgets('a week without today has no highlight and no dimming', (
    tester,
  ) async {
    await pump(tester, DateTime(2026, 10, 20));
    for (var i = 0; i < 7; i++) {
      expect(opacityOf(tester, i), 1);
    }
  });
}
