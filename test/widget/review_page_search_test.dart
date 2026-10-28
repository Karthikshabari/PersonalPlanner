// Page search on Review Daily and Weekly: Ctrl+F (laptop) or the top-bar icon
// (phone) opens a field in the title; a query lists the saved days or weeks
// that match, and tapping one jumps there. The cards stay mounted underneath.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

const laptop = Size(1280, 800);
const phone = Size(393, 844);

const _field = ValueKey('page-search-field');
const _icon = ValueKey('page-search-action');
const _close = ValueKey('page-search-close');
const _note = ValueKey('review-note');

DateTime _daysAgo(int n) => addDays(dailyToday(), -n);
String _hit(DateTime date) => 'review-search-hit-${isoDateString(date)}';

Future<void> _task(
  WidgetTester tester,
  ProviderContainer container,
  String title,
  DateTime day,
) {
  final start = PlannerTimeZone.calendarDate(
    day.year,
    day.month,
    day.day,
    hour: 9,
  );
  return runDb(
    tester,
    () => container
        .read(taskRepositoryProvider)
        .insertTask(
          Task(
            id: '',
            title: title,
            startTime: start,
            endTime: start.add(const Duration(minutes: 30)),
            createdAt: start,
            updatedAt: start,
          ),
        ),
  );
}

late ProviderContainer _container;

/// `testWidgets` that drains the streams and unmounts the app at the end
/// (resetting the platform override before the test's invariants are checked).
void _test(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await drainStreams(tester);
      await finish(tester, _container);
    });

/// Today: "Zebra standup". 2 days ago: "Plan the zanzibar trip" and a note.
/// 5 days ago: a note mentioning Zanzibar. Last week: a weekly feeling.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  Size surface = laptop,
  String route = '/review',
}) async {
  // Ctrl+F is a desktop-platform shortcut; `finish` resets the override.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final container = await buildTestContainer(tester);
  await _task(tester, container, 'Zebra standup', _daysAgo(0));
  await _task(tester, container, 'Plan the zanzibar trip', _daysAgo(2));
  final reviews = container.read(reviewRepositoryProvider);
  await runDb(tester, () async {
    await reviews.saveReviewDraft(
      date: _daysAgo(2),
      mood: 3,
      note: 'Quiet evening',
      taskReasons: const {},
    );
    await reviews.saveReviewDraft(
      date: _daysAgo(5),
      mood: 2,
      note: 'Dreamt about Zanzibar beaches',
      taskReasons: const {},
    );
    await reviews.saveWeeklyReviewDraft(
      weekStart: addDays(startOfWeek(dailyToday()), -7),
      mood: 2,
      feeling: 'A muddy zanzibar week',
      note: '',
    );
  });
  appRouter.go(route);
  await pumpApp(tester, container, surface: surface);
  _container = container;
  return container;
}

Future<void> _ctrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> _ctrlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
}

/// Types into the field, waits out the debounce, and lets the index load.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await settle(tester);
}

final _title = find.descendant(
  of: find.byType(AppBar),
  matching: find.text('Daily Review'),
);

double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(Scaffold).last,
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void main() {
  _test('closed: no field, no results, the cards are shown', (tester) async {
    await _open(tester);
    expect(find.byKey(_field), findsNothing);
    expect(_title, findsOneWidget);
    expect(find.byKey(_note), findsOneWidget);
    expect(find.text('Zebra standup'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-search-empty')), findsNothing);
  });

  _test('Ctrl+F from the note box keeps the note; Esc restores it', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(find.byKey(_note), 'half typed thought');
    await tester.pump();

    await _ctrlF(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(_title, findsNothing);

    await _type(tester, 'zanzibar');
    // The cards are hidden but mounted; the draft is intact.
    expect(find.byKey(_note), findsNothing);
    expect(find.byKey(_note, skipOffstage: false), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(_note, skipOffstage: false))
          .controller!
          .text,
      'half typed thought',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(_field), findsNothing);
    expect(_title, findsOneWidget);
    expect(find.byKey(_note), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_note)).controller!.text,
      'half typed thought',
    );
    // Focus is back in the note box.
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(_note),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  _test('a query lists matching days newest first; tap jumps there', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, '  ZANZIBAR ');

    final two = find.byKey(ValueKey(_hit(_daysAgo(2))));
    final five = find.byKey(ValueKey(_hit(_daysAgo(5))));
    expect(two, findsOneWidget);
    expect(five, findsOneWidget);
    expect(tester.getTopLeft(two).dy, lessThan(tester.getTopLeft(five).dy));
    expect(find.text('Task: Plan the zanzibar trip'), findsOneWidget);
    expect(
      find.text('Worth remembering: Dreamt about Zanzibar beaches'),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey(_hit(_daysAgo(0)))), findsNothing);

    await tester.tap(five);
    await settle(tester);

    expect(container.read(selectedReviewDateProvider), _daysAgo(5));
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(_note), findsOneWidget);
    expect(find.byKey(ValueKey(_hit(_daysAgo(5)))), findsNothing);
  });

  _test('no match shows No matches with a way into Search', (tester) async {
    await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'qqqq');
    expect(find.byKey(const ValueKey('review-search-empty')), findsOneWidget);
    expect(find.text('No matches'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-search-everything')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
  });

  _test('prev and next day work while results show', (tester) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'zanzibar');

    await tester.tap(find.byKey(const ValueKey('review-prev-day')));
    await settle(tester);
    expect(container.read(selectedReviewDateProvider), _daysAgo(1));
    expect(find.byKey(ValueKey(_hit(_daysAgo(2)))), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review-next-day')));
    await settle(tester);
    expect(container.read(selectedReviewDateProvider), _daysAgo(0));
    expect(find.byKey(_field), findsOneWidget);
  });

  _test('Ctrl+Enter in the note box saves with search open and empty', (
    tester,
  ) async {
    await _open(tester);
    await _ctrlF(tester);
    await tester.tap(find.byKey(_note));
    await tester.enterText(find.byKey(_note), 'Saved while searching');
    await tester.pump();
    await _ctrlEnter(tester);
    expect(find.text('Review saved'), findsOneWidget);
  });

  _test('Ctrl+Enter in the search field does not save', (tester) async {
    await _open(tester);
    await tester.enterText(find.byKey(_note), 'A note that differs');
    await tester.pump();
    await _ctrlF(tester);
    await _type(tester, 'zanzibar');
    await _ctrlEnter(tester);
    expect(find.text('Review saved'), findsNothing);
    expect(find.byKey(_field), findsOneWidget);
  });

  _test('the Save bar is hidden while results show', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('review-save')), findsOneWidget);

    await _ctrlF(tester);
    await _type(tester, 'zanzibar');
    expect(find.byKey(const ValueKey('review-save')), findsNothing);

    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.byKey(const ValueKey('review-save')), findsOneWidget);
  });

  _test('switching to Weekly clears Daily search (laptop)', (tester) async {
    await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'zanzibar');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('review-mode-switcher')),
        matching: find.text('Weekly'),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('weekly-subtabs')), findsOneWidget);
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(const ValueKey('review-search-empty')), findsNothing);
  });

  _test('phone: the icon opens search, Back closes it first', (tester) async {
    await _open(tester, surface: phone);
    expect(find.byKey(_icon), findsOneWidget);
    await tester.tap(find.byKey(_icon));
    await settle(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(find.byKey(_icon), findsNothing);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(_icon), findsOneWidget);
  });

  _test('phone: opening and closing search restores the scroll offset', (
    tester,
  ) async {
    await _open(tester, surface: phone);
    await tester.drag(
      find.byKey(const ValueKey('review-mode-switcher')),
      const Offset(0, -300),
    );
    await settle(tester);
    final before = _offset(tester);
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(_icon));
    await settle(tester);
    await _type(tester, 'zanzibar');
    expect(find.byKey(ValueKey(_hit(_daysAgo(2)))), findsOneWidget);

    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.byKey(_field), findsNothing);
    expect(_offset(tester), before);
  });

  _test('phone: Weekly pushed over Daily closes Daily search', (tester) async {
    await _open(tester, surface: phone);
    await tester.tap(find.byKey(_icon));
    await settle(tester);
    await _type(tester, 'zanzibar');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('review-mode-switcher')),
        matching: find.text('Weekly'),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('weekly-subtabs')), findsOneWidget);
    expect(find.byKey(_field), findsNothing);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(const ValueKey('review-mode-switcher')), findsOneWidget);
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(_note), findsOneWidget);
  });

  group('Weekly', () {
    _test('a query matches the feeling and jumps to that week', (tester) async {
      final container = await _open(tester, route: '/review/weekly');
      final lastWeek = addDays(startOfWeek(dailyToday()), -7);
      await _ctrlF(tester);
      await _type(tester, 'MUDDY');

      final hit = find.byKey(ValueKey(_hit(lastWeek)));
      expect(hit, findsOneWidget);
      expect(
        find.text('How the week felt: A muddy zanzibar week'),
        findsOneWidget,
      );
      // The Review / Next week tabs stay; the tab content is hidden.
      expect(find.byKey(const ValueKey('weekly-subtabs')), findsOneWidget);

      await tester.tap(hit);
      await settle(tester);
      expect(container.read(selectedWeekStartProvider), lastWeek);
      expect(find.byKey(_field), findsNothing);
    });

    _test('task titles of a week are found, not the Daily note', (
      tester,
    ) async {
      await _open(tester, route: '/review/weekly');
      await _ctrlF(tester);
      await _type(tester, 'beaches');
      expect(find.byKey(const ValueKey('review-search-empty')), findsOneWidget);
      await _type(tester, 'zebra');
      expect(
        find.byKey(ValueKey(_hit(startOfWeek(dailyToday())))),
        findsOneWidget,
      );
      expect(find.text('Task: Zebra standup'), findsOneWidget);
    });

    _test('Esc restores the tab; Next week sub-tab still works', (
      tester,
    ) async {
      await _open(tester, route: '/review/weekly');
      await _ctrlF(tester);
      await _type(tester, 'zebra');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(_field), findsNothing);
      await tester.tap(find.text('Next week (optional)'));
      await settle(tester);
      expect(find.byType(TextField), findsWidgets);
    });
  });

  _test('Overview: Ctrl+F still opens the universal Search', (tester) async {
    await _open(tester, route: '/review/overview');
    await _ctrlF(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
    expect(find.byKey(_field), findsNothing);
  });
}
