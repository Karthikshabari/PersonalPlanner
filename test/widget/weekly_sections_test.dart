import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_theme.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_glance_card.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_outcomes_card.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_reasons_card.dart';

import '../helpers/weekly_review_fixtures.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(
    body: ListView(padding: const EdgeInsets.all(12), children: [child]),
  ),
);

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1200, 1000),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(_host(child));
  await tester.pump();
}

void main() {
  group('Week at a glance', () {
    testWidgets('percent, counts line and seven day cards', (tester) async {
      final numbers = computeWeeklyNumbers(fixtureWeek('great'));
      await _pumpAt(tester, WeeklyGlanceCard(numbers: numbers, future: false));

      expect(find.text('Week at a glance'), findsOneWidget);
      expect(find.text('50% completed'), findsOneWidget);
      expect(
        find.text('7 of 14 tasks · 2 skipped · 3 rescheduled · 1 plan changed'),
        findsOneWidget,
      );
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(ValueKey('weekly-day-$i')), findsOneWidget);
      }
      expect(find.text('Office'), findsNWidgets(3));
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Not reviewed'), findsOneWidget);
      expect(find.text('No tasks'), findsNWidgets(2));
      expect(find.textContaining('planned'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('day cards carry a full semantics label', (tester) async {
      final numbers = computeWeeklyNumbers(fixtureWeek('great'));
      await _pumpAt(tester, WeeklyGlanceCard(numbers: numbers, future: false));
      final handle = tester.ensureSemantics();

      expect(
        tester.getSemantics(find.byKey(const ValueKey('weekly-day-0'))),
        isSemantics(label: 'Mon Sep 28: 50% done, Good, Office'),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('weekly-day-4'))),
        isSemantics(label: 'Fri Oct 2: 50% done, Not reviewed, Leave'),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('weekly-day-5'))),
        isSemantics(label: 'Sat Oct 3: No tasks'),
      );
      handle.dispose();
    });

    testWidgets('future and empty weeks', (tester) async {
      final numbers = computeWeeklyNumbers(fixtureWeek('great'));
      await _pumpAt(tester, WeeklyGlanceCard(numbers: numbers, future: true));
      expect(find.text('This week has not happened yet.'), findsOneWidget);

      final empty = computeWeeklyNumbers([
        WeeklyDayInput(
          date: DateTime(2026, 9, 28),
          reviewed: false,
          tasks: const [],
        ),
      ]);
      await _pumpAt(tester, WeeklyGlanceCard(numbers: empty, future: false));
      expect(find.text('No tasks this week'), findsOneWidget);
      expect(find.byKey(const ValueKey('weekly-glance-subline')), findsNothing);
    });

    testWidgets('the strip scrolls sideways on a phone', (tester) async {
      final numbers = computeWeeklyNumbers(fixtureWeek('good'));
      await _pumpAt(
        tester,
        WeeklyGlanceCard(numbers: numbers, future: false),
        size: const Size(360, 800),
        textScale: 1.3,
      );

      expect(find.byKey(const ValueKey('weekly-day-strip')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('weekly-day-0'))).width,
        WeeklyDayCard.width,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('What got in the way', () {
    testWidgets('reason bars, No reason given and day types', (tester) async {
      final numbers = computeWeeklyNumbers(fixtureWeek('great'));
      await _pumpAt(tester, WeeklyReasonsCard(numbers: numbers));

      expect(find.text('What got in the way'), findsOneWidget);
      expect(find.text('Low energy'), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      expect(find.text('No reason given'), findsOneWidget);
      final barTops = [
        'weekly-reason-Low energy',
        'weekly-reason-Interrupted',
        'weekly-reason-Blocked',
        'weekly-reason-none',
      ].map((k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy).toList();
      expect(barTops, orderedEquals([...barTops]..sort()));
      expect(find.text('Day types'), findsOneWidget);
      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('5 of 10 tasks done'), findsOneWidget);
      expect(find.text('2 days'), findsOneWidget);
      expect(find.text('2 of 4 tasks done'), findsOneWidget);
      expect(find.textContaining('Added during the week'), findsNothing);
    });

    testWidgets('empty states', (tester) async {
      final allDone = computeWeeklyNumbers([
        WeeklyDayInput(
          date: DateTime(2026, 9, 28),
          reviewed: true,
          contextLabel: 'Travel',
          tasks: const [
            WeeklyTaskInput(
              taskId: 'a',
              title: 'A',
              outcome: TaskOutcome.completed,
            ),
          ],
        ),
      ]);
      await _pumpAt(tester, WeeklyReasonsCard(numbers: allDone));
      expect(
        find.text('Nothing to show. Everything planned got done.'),
        findsOneWidget,
      );
      expect(find.text('1 day'), findsOneWidget);

      final none = computeWeeklyNumbers(const []);
      await _pumpAt(tester, WeeklyReasonsCard(numbers: none));
      expect(find.text('No tasks this week.'), findsOneWidget);
      expect(find.text('Day types'), findsNothing);
    });
  });

  group('Task outcomes', () {
    testWidgets('only skipped or rescheduled rows; plan change in its row', (
      tester,
    ) async {
      final numbers = computeWeeklyNumbers(fixtureWeek('good'));
      await _pumpAt(tester, WeeklyOutcomesCard(rows: numbers.outcomeRows));

      expect(find.text('Skipped or rescheduled · 5'), findsOneWidget);
      // Five rows: the first four show, the rest sit behind "Show all 5".
      await tester.tap(find.text('Show all 5'));
      await tester.pump();
      expect(find.text('Refactor tests'), findsOneWidget);
      expect(
        find.textContaining('PLAN CHANGED · Scope grew', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Refactor sync tests'), findsOneWidget);
      expect(find.text('Rescheduled'), findsNWidgets(3));
      expect(find.text('Skipped'), findsNWidgets(2));
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Partly done'), findsNothing);
      expect(find.text('Not started'), findsNothing);
      expect(find.text('Blocked'), findsOneWidget);
      final oldTitle = tester.widget<Text>(find.text('Refactor tests'));
      expect(oldTitle.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('meta line without a reason', (tester) async {
      final numbers = computeWeeklyNumbers([
        WeeklyDayInput(
          date: DateTime(2026, 9, 28),
          reviewed: true,
          tasks: const [
            WeeklyTaskInput(
              taskId: 'a',
              title: 'Reviewed day',
              outcome: TaskOutcome.skipped,
            ),
          ],
        ),
        WeeklyDayInput(
          date: DateTime(2026, 9, 29),
          reviewed: false,
          tasks: const [
            WeeklyTaskInput(
              taskId: 'b',
              title: 'Unreviewed day',
              outcome: TaskOutcome.rescheduled,
            ),
          ],
        ),
      ]);
      await _pumpAt(tester, WeeklyOutcomesCard(rows: numbers.outcomeRows));

      expect(find.text('No reason given'), findsOneWidget);
      expect(find.text('No reason (day not reviewed)'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await _pumpAt(tester, const WeeklyOutcomesCard(rows: []));
      expect(find.text('Skipped or rescheduled · 0'), findsOneWidget);
      expect(
        find.text('Nothing skipped or rescheduled this week.'),
        findsOneWidget,
      );
    });

    test('Rescheduled uses the Great colour', () {
      expect(ReviewColors.dark.blue, ReviewColors.dark.mood2);
      expect(ReviewColors.light.blue, ReviewColors.light.mood2);
    });
  });

  testWidgets('all three cards fit 360 dp at text scale 1.3', (tester) async {
    final numbers = computeWeeklyNumbers(fixtureWeek('good'));
    await _pumpAt(
      tester,
      Column(
        children: [
          WeeklyGlanceCard(numbers: numbers, future: false),
          WeeklyReasonsCard(numbers: numbers),
          WeeklyOutcomesCard(rows: numbers.outcomeRows),
        ],
      ),
      size: const Size(360, 800),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
