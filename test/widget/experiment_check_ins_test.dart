import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/experiment_check_in_box.dart';

import '../helpers/test_container.dart';

void main() {
  const desktop = Size(1400, 1000);

  // Wednesday Oct 7 2026, midday planner time.
  final now = PlannerTimeZone.calendarDate(2026, 10, 7, hour: 12);
  DateTime clock() => now;

  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: clock,
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: desktop);
    return container;
  }

  Future<Experiment> create(
    WidgetTester tester,
    ProviderContainer container, {
    String name = 'Learn C',
    String start = '2026-10-05',
    String end = '2026-10-31',
    int every = 1,
  }) => runDb(
    tester,
    () =>
        ExperimentRepository(container.read(appDatabaseProvider))
            .createExperiment(
              name: name,
              startDate: start,
              endDate: end,
              weekdayTargetMin: 60,
              weekendTargetMin: 90,
              checkInEveryDays: every,
            ),
  );

  Finder box(Experiment e) => find.byKey(ValueKey('checkin-box-${e.id}'));

  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> writeNote(WidgetTester tester, Experiment e, String text) async {
    final field = find.byKey(ValueKey('checkin-note-${e.id}'));
    await show(tester, field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester, Experiment e) async {
    final button = find.byKey(ValueKey('checkin-save-${e.id}'));
    await show(tester, button);
    await tester.tap(button);
    await settle(tester);
  }

  String statistic(WidgetTester tester, Experiment e) {
    final stat = find.byKey(ValueKey('experiment-check-ins-${e.id}'));
    final texts = find.descendant(of: stat, matching: find.byType(Text));
    return tester.widget<Text>(texts.last).data!;
  }

  testWidgets('the box appears only while a slot is pending', (tester) async {
    final container = await open(tester);
    // A weekly experiment that starts today has its first slot in 6 days.
    final weekly = await create(
      tester,
      container,
      name: 'Weekly',
      start: '2026-10-07',
      every: 7,
    );
    await settle(tester);

    expect(find.byKey(ValueKey('experiment-${weekly.id}')), findsOneWidget);
    expect(box(weekly), findsNothing);
    expect(find.text('Share your experience'), findsNothing);
    expect(statistic(tester, weekly), '0 written · next Oct 13');

    final daily = await create(tester, container);
    await settle(tester);
    expect(box(daily), findsOneWidget);
    expect(find.text('Share your experience'), findsOneWidget);

    await teardownApp(tester, container);
  });

  testWidgets('chips, default date and the label texts', (tester) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);

    expect(find.text('2 missed'), findsOneWidget);
    expect(find.text('1 due today'), findsOneWidget);
    expect(
      find.text(
        'Which day is this for? Missed days stay here until you write them.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'How is it going? What did you notice, and is it what you expected?',
      ),
      findsOneWidget,
    );
    expect(find.text('A few lines is enough.'), findsOneWidget);
    // The latest pending date is selected by default.
    expect(
      find.descendant(
        of: find.byKey(ValueKey('checkin-date-${e.id}')),
        matching: find.text('Wed Oct 7'),
      ),
      findsOneWidget,
    );
    expect(find.text('Save check-in for Oct 7'), findsOneWidget);
    expect(statistic(tester, e), '0 written · 2 missed');

    // Only a due-today slot: no "missed" chip.
    final fresh = await create(
      tester,
      container,
      name: 'Fresh',
      start: '2026-10-07',
    );
    await settle(tester);
    expect(find.text('1 due today'), findsNWidgets(2));
    expect(find.text('2 missed'), findsOneWidget);
    expect(box(fresh), findsOneWidget);

    await teardownApp(tester, container);
  });

  testWidgets('Save needs a note and a chosen date is used', (tester) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);

    FilledButton button() => tester.widget<FilledButton>(
      find.byKey(ValueKey('checkin-save-${e.id}')),
    );
    expect(button().onPressed, isNull);
    await writeNote(tester, e, '   \n ');
    expect(button().onPressed, isNull, reason: 'blank notes are not saved');
    await writeNote(tester, e, 'It went fine');
    expect(button().onPressed, isNotNull);

    // Pick the oldest pending date; the button follows.
    final dropdown = find.byKey(ValueKey('checkin-date-${e.id}'));
    await show(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon Oct 5').last);
    await tester.pumpAndSettle();
    expect(find.text('Save check-in for Oct 5'), findsOneWidget);

    await save(tester, e);
    final rows = await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .experimentDao
          .getCheckInsForExperiment(e.id),
    );
    expect([for (final r in rows) r.slotDate], ['2026-10-05']);
    expect(rows.single.note, 'It went fine');

    await teardownApp(tester, container);
  });

  testWidgets(
    'saving fills the slot and the box disappears when none is left',
    (tester) async {
      final container = await open(tester);
      final e = await create(tester, container);
      await settle(tester);

      await writeNote(tester, e, 'Today went well');
      await save(tester, e);
      expect(find.text('1 due today'), findsNothing);
      expect(find.text('1 missed'), findsNothing);
      expect(find.text('2 missed'), findsOneWidget);
      // The note is cleared and the new latest pending date is selected.
      expect(
        tester
            .widget<TextField>(find.byKey(ValueKey('checkin-note-${e.id}')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Save check-in for Oct 6'), findsOneWidget);
      expect(statistic(tester, e), '1 written · 2 missed');

      await writeNote(tester, e, 'Yesterday I forgot');
      await save(tester, e);
      expect(find.text('Save check-in for Oct 5'), findsOneWidget);
      expect(find.text('2 missed'), findsNothing);
      expect(find.text('1 missed'), findsOneWidget);

      await writeNote(tester, e, 'Day one');
      await save(tester, e);
      expect(box(e), findsNothing);
      expect(find.text('Share your experience'), findsNothing);
      expect(statistic(tester, e), '3 written · next Oct 8');

      await teardownApp(tester, container);
    },
  );

  testWidgets('past check-ins list newest first and the toggle reads right', (
    tester,
  ) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);

    final toggle = find.byKey(ValueKey('checkin-past-${e.id}'));
    await show(tester, toggle);
    expect(find.text('Show past check-ins (0)'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Hide past check-ins (0)'), findsOneWidget);
    expect(find.text('No check-ins written yet.'), findsOneWidget);

    await writeNote(tester, e, 'Third note');
    await save(tester, e);
    await writeNote(tester, e, 'Second note');
    await save(tester, e);
    await writeNote(tester, e, 'First note');
    await save(tester, e);

    expect(find.text('Hide past check-ins (3)'), findsOneWidget);
    expect(find.text('No check-ins written yet.'), findsNothing);
    final list = find.byKey(ValueKey('checkin-past-list-${e.id}'));
    expect(list, findsOneWidget);
    // Newest slot first: Oct 7, Oct 6, Oct 5.
    final notes = [
      for (final text in ['Third note', 'Second note', 'First note'])
        tester.getTopLeft(find.text(text)).dy,
    ];
    expect(notes[0], lessThan(notes[1]));
    expect(notes[1], lessThan(notes[2]));
    expect(
      find.descendant(of: list, matching: find.text('Oct 7')),
      findsOneWidget,
    );
    // There is nothing to edit or delete.
    expect(
      find.descendant(of: list, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: list, matching: find.byType(TextButton)),
      findsNothing,
    );

    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Show past check-ins (3)'), findsOneWidget);
    expect(list, findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets(
    'the box is hidden after conclusion and missed slots still count',
    (tester) async {
      final container = await open(tester);
      final e = await create(tester, container, end: '2026-10-07');
      await settle(tester);
      expect(box(e), findsOneWidget);

      await runDb(
        tester,
        () => ExperimentRepository(container.read(appDatabaseProvider))
            .concludeExperiment(
              e.id,
              outcome: ExperimentOutcome.drop,
              today: '2026-10-07',
              expectedRevision: e.revision,
            ),
      );
      await settle(tester);

      expect(box(e), findsNothing);
      expect(find.text('Share your experience'), findsNothing);
      expect(find.byKey(ValueKey('end-panel-${e.id}')), findsNothing);
      // Slots Oct 5, 6 and 7 stay unwritten and count as missed.
      expect(statistic(tester, e), '0 written · 3 missed');

      await teardownApp(tester, container);
    },
  );

  test('the note field limits code points and keeps emoji whole', () {
    const formatter = CodePointLimitingTextInputFormatter(4);
    TextEditingValue format(String text) => formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text),
    );
    expect(format('abcd').text, 'abcd');
    expect(format('abcde').text, 'abcd');
    // Each emoji is 1 code point (2 UTF-16 units): 4 fit, a 5th is dropped.
    expect(format('😀😀😀😀😀').text, '😀😀😀😀');
    // A family emoji is one cluster of 7 code points; it never gets split.
    expect(format('ab👨‍👩‍👧').text, 'ab');
  });
}
