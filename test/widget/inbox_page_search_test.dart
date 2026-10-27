// Page search on the Inbox: Ctrl+F (laptop) or the top-bar icon (phone) opens
// a field in the title and filters the ideas already in memory. Fixed clock:
// Monday 2026-10-12 12:00 in the planner zone.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/inbox_fixtures.dart';
import '../helpers/inbox_screen_harness.dart';
import '../helpers/test_container.dart';

const laptop = Size(1280, 800);
const phone = Size(393, 844);

const _field = ValueKey('page-search-field');
const _icon = ValueKey('page-search-action');
const _close = ValueKey('page-search-close');

late Task _plan;
late Task _bank;
late Task _plants;
late Task _visa;
late Task _old;

/// Open: "Plan the zanzibar trip" and "Water the plants" (Ideas), "Call the
/// bank" (Coming up). Done: "Zanzibar visa". Dropped: "Old plan", closed with
/// the reason "moved to Zanzibar".
Future<void> _seed(InboxHarness h) async {
  _plants = await h.idea('Water the plants');
  _plan = await h.idea('Plan the zanzibar trip');
  _bank = await h.idea('Call the bank');
  await h.session(_bank.id, start: h.at(2, 9));
  _visa = await h.idea('Zanzibar visa');
  await h.session(_visa.id, start: h.at(-3, 9), status: TaskStatus.completed);
  _old = await h.idea('Old plan');
  await h.inbox.closeItem(_old.id, 'moved to Zanzibar', h.now);
}

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Size surface = laptop,
  Future<void> Function(InboxHarness h) seed = _seed,
}) async {
  // Ctrl+F is a desktop-platform shortcut; `finish` resets the override.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final (container, _) = await pumpInbox(tester, seed: seed, surface: surface);
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

/// The AppBar title; the rail also has an "Inbox" label.
final _title = find.descendant(
  of: find.byType(AppBar),
  matching: find.text('Inbox'),
);

double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('inbox-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

void main() {
  testWidgets('closed: no field, original labels and rows', (tester) async {
    final container = await _open(tester);
    expect(find.byKey(_field), findsNothing);
    expect(_title, findsOneWidget);
    expect(find.text('Open (3)'), findsOneWidget);
    expect(find.text('Done (1)'), findsOneWidget);
    expect(find.text('Dropped (1)'), findsOneWidget);
    expect(rowOf(_plan.id), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Ctrl+F opens the field; typing filters and counts', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(_title, findsNothing);

    await _type(tester, 'zanzibar');
    expect(find.text('Open (1)'), findsOneWidget);
    expect(find.text('Done (1)'), findsOneWidget);
    expect(find.text('Dropped (1)'), findsOneWidget);
    expect(rowOf(_plan.id), findsOneWidget);
    expect(rowOf(_plants.id), findsNothing);
    expect(rowOf(_bank.id), findsNothing);
    // Sections keep their headers, with filtered counts.
    expect(find.byKey(const ValueKey('inbox-section-Ideas')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-section-Coming up')), findsNothing);

    // Switching segment keeps the filter.
    await pickSegment(tester, 'Done (1)');
    expect(rowOf(_visa.id), findsOneWidget);
    await pickSegment(tester, 'Dropped (1)');
    // Matched through the closing reason, not the text.
    expect(rowOf(_old.id), findsOneWidget);
    await pickSegment(tester, 'Open (1)');
    expect(rowOf(_plan.id), findsOneWidget);
    expect(find.byKey(_field), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('the match is the whole query, case-insensitive, contiguous', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, '  CALL THE BANK ');
    expect(rowOf(_bank.id), findsOneWidget);
    expect(find.text('Open (1)'), findsOneWidget);

    await _type(tester, 'bank the call');
    expect(find.byKey(const ValueKey('inbox-search-empty')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('no match shows No matches with a way to Search', (tester) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'zzz');
    expect(find.byKey(const ValueKey('inbox-search-empty')), findsOneWidget);
    expect(find.text('No matches'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('page-search-everything')),
      findsOneWidget,
    );
    expect(find.text('Open (0)'), findsOneWidget);
    expect(find.text('Done (0)'), findsOneWidget);
    expect(find.text('Dropped (0)'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-empty-open')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('page-search-everything')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'zzz'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Esc restores every row and the original counts', (tester) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'zanzibar');
    expect(rowOf(_plants.id), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(_title, findsOneWidget);
    expect(find.text('Open (3)'), findsOneWidget);
    expect(find.text('Done (1)'), findsOneWidget);
    expect(find.text('Dropped (1)'), findsOneWidget);
    expect(rowOf(_plants.id), findsOneWidget);
    expect(rowOf(_bank.id), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('the close button restores the list and the scroll offset', (
    tester,
  ) async {
    final container = await _open(
      tester,
      seed: (h) async {
        for (var i = 0; i < 40; i++) {
          await h.idea('Errand number $i');
        }
        await h.idea('Needle in the pile');
      },
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('inbox-list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(600);
    await tester.pump();
    final before = _offset(tester);
    expect(before, 600);

    await _ctrlF(tester);
    await _type(tester, 'needle');
    expect(find.text('Open (1)'), findsOneWidget);
    expect(_offset(tester), lessThan(before));

    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(find.text('Open (41)'), findsOneWidget);
    expect(_offset(tester), before);
    await finish(tester, container);
  });

  testWidgets('leaving to Day and coming back shows search closed', (
    tester,
  ) async {
    final container = await _open(tester);
    await _ctrlF(tester);
    await _type(tester, 'zanzibar');

    appRouter.go('/day');
    await settle(tester);
    appRouter.go('/inbox');
    await settle(tester);
    expect(find.byKey(_field), findsNothing);
    expect(find.text('Open (3)'), findsOneWidget);
    expect(rowOf(_plants.id), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Ctrl+F in the quick-add field opens search and keeps its text', (
    tester,
  ) async {
    final container = await _open(tester);
    final quickAdd = find.byKey(const ValueKey('inbox-quick-add'));
    await tester.enterText(quickAdd, 'half typed idea');
    await tester.pump();

    await _ctrlF(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(
      tester.widget<TextField>(quickAdd).controller!.text,
      'half typed idea',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(
      tester.widget<TextField>(quickAdd).controller!.text,
      'half typed idea',
    );
    await finish(tester, container);
  });

  testWidgets('phone: the top-bar icon opens the field', (tester) async {
    final container = await _open(tester, surface: phone);
    expect(find.byKey(_icon), findsOneWidget);
    await tester.tap(find.byKey(_icon));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsOneWidget);
    expect(find.byKey(_icon), findsNothing);

    await _type(tester, 'plants');
    expect(rowOf(_plants.id), findsOneWidget);
    expect(rowOf(_plan.id), findsNothing);
    expect(find.text('Open (1)'), findsOneWidget);

    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(_icon), findsOneWidget);
    expect(rowOf(_plan.id), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('searching never writes to the outbox', (tester) async {
    final container = await _open(tester);
    final harness = InboxHarness(container.read(appDatabaseProvider));
    final before = await runDb(tester, harness.syncLogCount);
    await _ctrlF(tester);
    await _type(tester, 'zanzibar');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(await runDb(tester, harness.syncLogCount), before);
    await finish(tester, container);
  });
}
