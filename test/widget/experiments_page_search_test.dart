// Page search on Insights: Ctrl+F (laptop) or the top-bar icon (phone) opens a
// field in the title and filters the Experiments card by name and description.
// Saturday 2026-10-10, midday planner time.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/domain/kept_copy.dart';

import '../helpers/test_container.dart';

const laptop = Size(1280, 800);
const phone = Size(393, 844);

const _field = ValueKey('page-search-field');
const _icon = ValueKey('page-search-action');
const _close = ValueKey('page-search-close');

late Experiment _learn;
late Experiment _cold;
late Experiment _read;
late Experiment _pages;
late Experiment _stretch;

/// Running: "Learn C" (about a guitar book) and "Cold showers". Concluded:
/// "Read daily" (dropped; its note mentions tennis). Kept: "Morning pages"
/// (a journal habit) and "Stretching".
Future<void> _seed(ExperimentRepository repo) async {
  Future<Experiment> create(
    String name, {
    String? purpose,
    String start = '2026-10-05',
    String end = '2026-10-11',
  }) => repo.createExperiment(
    name: name,
    purpose: purpose,
    startDate: start,
    endDate: end,
    weekdayTargetMin: 60,
    weekendTargetMin: 90,
    checkInEveryDays: 7,
  );
  Future<void> conclude(
    Experiment e,
    ExperimentOutcome outcome, {
    String? note,
  }) async {
    await repo.concludeExperiment(
      e.id,
      outcome: outcome,
      note: note,
      today: '2026-10-09',
      expectedRevision: e.revision,
    );
  }

  _learn = await create('Learn C', purpose: 'Finish the Guitar book');
  _cold = await create('Cold showers');
  _read = await create('Read daily', start: '2026-09-01', end: '2026-09-30');
  await conclude(_read, ExperimentOutcome.drop, note: 'More tennis instead');
  _pages = await create(
    'Morning pages',
    purpose: 'A journal habit',
    start: '2026-09-04',
    end: '2026-10-03',
  );
  await conclude(_pages, ExperimentOutcome.keep);
  _stretch = await create('Stretching', start: '2026-09-04', end: '2026-10-03');
  await conclude(_stretch, ExperimentOutcome.keep);
}

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Size surface = laptop,
}) async {
  // Ctrl+F is a desktop-platform shortcut; `finish` resets the override.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final now = PlannerTimeZone.calendarDate(2026, 10, 10, hour: 12);
  final container = await buildTestContainer(
    tester,
    insightsNowFactory: () => now,
  );
  await runDb(
    tester,
    () => _seed(ExperimentRepository(container.read(appDatabaseProvider))),
  );
  appRouter.go('/analytics');
  await pumpApp(tester, container, surface: surface);
  return container;
}

Future<void> _ctrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  // The needle is published after the 150 ms debounce.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

/// The AppBar title; the rail also has an "Insights" label.
final _title = find.descendant(
  of: find.byType(AppBar),
  matching: find.text('Insights'),
);

Finder _running(int n) => find.text('Running ($n)');
Finder _kept(int n) => find.text(keptSegmentLabel(n));
Finder _concluded(int n) => find.text('Concluded ($n)');

Finder _row(Experiment e) => find.byKey(ValueKey('experiment-row-${e.id}'));
Finder _keptRow(Experiment e) => find.byKey(ValueKey('kept-row-${e.id}'));

Future<void> _pickSegment(WidgetTester tester, Finder label) async {
  await tester.ensureVisible(label);
  await tester.tap(label);
  await settle(tester);
}

ScrollPosition _listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('closed: no field, original labels and rows', (tester) async {
    final container = await _open(tester);
    expect(find.byKey(_field), findsNothing);
    expect(_title, findsOneWidget);
    expect(_running(2), findsOneWidget);
    expect(_kept(2), findsOneWidget);
    expect(_concluded(3), findsOneWidget);
    expect(_row(_learn), findsOneWidget);
    expect(_row(_cold), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Ctrl+F opens the field; the name and description filter', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(_title, findsNothing);

    // By name, any case.
    await _type(tester, 'COLD sho');
    expect(_running(1), findsOneWidget);
    expect(_kept(0), findsOneWidget);
    expect(_concluded(0), findsOneWidget);
    expect(_row(_cold), findsOneWidget);
    expect(_row(_learn), findsNothing);

    // By description.
    await _type(tester, 'guitar book');
    expect(_running(1), findsOneWidget);
    expect(_row(_learn), findsOneWidget);
    expect(_row(_cold), findsNothing);

    // The consistency card is not searched and stays.
    expect(find.byKey(const ValueKey('consistency-section')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('all three labels count the matches and the filter follows the '
      'segment', (tester) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    // "ing" is only in the two kept names (Morning pages, Stretching).
    await _type(tester, 'ing');
    expect(_running(0), findsOneWidget);
    expect(_kept(2), findsOneWidget);
    expect(_concluded(2), findsOneWidget);

    await _pickSegment(tester, _kept(2));
    expect(_keptRow(_pages), findsOneWidget);
    expect(_keptRow(_stretch), findsOneWidget);

    await _type(tester, 'stretch');
    expect(_kept(1), findsOneWidget);
    expect(_keptRow(_stretch), findsOneWidget);
    expect(_keptRow(_pages), findsNothing);

    // Concluded lists kept experiments too, as it does without a search.
    await _pickSegment(tester, _concluded(1));
    expect(_row(_stretch), findsOneWidget);
    expect(_row(_read), findsNothing);
    await finish(tester, container);
  });

  testWidgets('the conclusion note is not searched', (tester) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'tennis');
    expect(_running(0), findsOneWidget);
    expect(_kept(0), findsOneWidget);
    expect(_concluded(0), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('an empty segment says No matches in place of its own text', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'zzz');

    expect(
      find.byKey(const ValueKey('experiments-search-empty')),
      findsOneWidget,
    );
    expect(find.text('No matches'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('experiments-filter-empty')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('experiments-start-empty')), findsNothing);
    // The header button stays.
    expect(find.byKey(const ValueKey('experiments-start')), findsOneWidget);

    await _pickSegment(tester, _kept(0));
    expect(find.byKey(const ValueKey('kept-search-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('kept-empty')), findsNothing);

    await _pickSegment(tester, _concluded(0));
    expect(
      find.byKey(const ValueKey('experiments-search-empty')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('page-search-everything')),
    );
    await tester.tap(find.byKey(const ValueKey('page-search-everything')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Esc restores every row and the original labels', (tester) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'guitar');
    expect(_row(_cold), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(_title, findsOneWidget);
    expect(_running(2), findsOneWidget);
    expect(_kept(2), findsOneWidget);
    expect(_concluded(3), findsOneWidget);
    expect(_row(_cold), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('phone: the icon opens the field, nothing scrolls, close puts '
      'the scroll offset back', (tester) async {
    final container = await _open(tester, surface: phone);
    expect(find.byKey(_icon), findsOneWidget);

    final position = _listPosition(tester);
    expect(position.maxScrollExtent, greaterThan(50));
    final offset = position.maxScrollExtent / 2;
    position.jumpTo(offset);
    await tester.pump();

    await tester.tap(find.byKey(_icon));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsOneWidget);
    expect(find.byKey(_icon), findsNothing);
    // Opening the field does not move the list.
    expect(_listPosition(tester).pixels, offset);

    await _type(tester, 'cold');
    expect(_running(1), findsOneWidget);

    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(_icon), findsOneWidget);
    expect(_listPosition(tester).pixels, offset);
    await finish(tester, container);
  });

  testWidgets('leaving to Day and coming back shows search closed', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'guitar');

    appRouter.go('/day');
    await settle(tester);
    appRouter.go('/analytics');
    await settle(tester);
    expect(find.byKey(_field), findsNothing);
    expect(_running(2), findsOneWidget);
    expect(_row(_cold), findsOneWidget);
    await finish(tester, container);
  });
}
