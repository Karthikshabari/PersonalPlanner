import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/undo_stack_provider.dart';

import '../helpers/test_container.dart';

/// The overdue triage rows on Day: groups, age, swipe, hover and focus
/// actions, the overflow menu, the bulk move and the explicit-capture row.
///
/// The clock is fixed twice because Day reads two: `minuteClockFactory`
/// (what `dayAttentionProvider` and the rows see) and `inboxNowFactory`.
DateTime at(int month, int day, [int hour = 0, int minute = 0]) =>
    PlannerTimeZone.calendarDate(2026, month, day, hour: hour, minute: minute);

/// Tue, March 10, 10:30 planner time.
final DateTime fixedNow = at(3, 10, 10, 30);

Task seed(String title, DateTime start, {int minutes = 60}) => Task(
  id: '',
  title: title,
  startTime: start,
  endTime: start.add(Duration(minutes: minutes)),
  createdAt: at(3, 1),
  updatedAt: at(3, 1),
);

Future<ProviderContainer> pumpTriage(
  WidgetTester tester, {
  required Size size,
  List<Task> overdue = const [],
  List<String> captures = const [],
  DateTime? now,
  Map<String, String>? ids,
}) async {
  final clock = now ?? fixedNow;
  final container = await buildTestContainer(
    tester,
    inboxNowFactory: () => clock,
    minuteClockFactory: () => Stream<DateTime>.value(clock),
  );
  final repo = container.read(taskRepositoryProvider);
  for (final task in overdue) {
    final saved = await runDb(tester, () => repo.insertTask(task));
    ids?[task.title] = saved.id;
  }
  for (final capture in captures) {
    final saved = await runDb(
      tester,
      () => container
          .read(inboxRepositoryProvider)
          .addToInbox(capture, dueDate: '2026-03-10'),
    );
    ids?[capture] = saved.id;
  }
  container.read(selectedDateProvider.notifier).state = at(3, 10);
  appRouter.go('/day');
  await pumpApp(tester, container, surface: size);
  container.read(selectedDateProvider.notifier).state = at(3, 10);
  await settle(tester);
  return container;
}

Future<Task?> taskById(
  WidgetTester tester,
  ProviderContainer container,
  String id,
) =>
    runDb(tester, () => container.read(taskRepositoryProvider).getTaskById(id));

Future<List<Task>> todaysBlocks(
  WidgetTester tester,
  ProviderContainer container,
) {
  final (start, end) = PlannerTimeZone.dayBounds(at(3, 10));
  return runDb(
    tester,
    () => container
        .read(taskRepositoryProvider)
        .getScheduledTasksBetween(start, end),
  );
}

/// Equal instants: the repository returns plain `DateTime`s, the test builds
/// `TZDateTime`s, and `==` between those types is false.
Matcher sameInstant(DateTime expected) => predicate<DateTime?>(
  (value) => value != null && value.isAtSameMomentAs(expected),
  'is the instant $expected',
);

Finder row(String id) => find.byKey(ValueKey('day-attention-$id'));
Finder swipe(String id) => find.byKey(ValueKey('day-attention-swipe-$id'));
Finder tooltip(String text) => find.byTooltip(text);

double actionsOpacity(WidgetTester tester, String id) => tester
    .widget<AnimatedOpacity>(find.byKey(ValueKey('day-attention-actions-$id')))
    .opacity;

/// A swipe far enough to pass the 0.35 threshold of the row's width.
Future<void> swipeRow(
  WidgetTester tester,
  String id, {
  required bool right,
}) async {
  final width = tester.getSize(swipe(id)).width;
  await tester.drag(swipe(id), Offset((right ? 1 : -1) * width * 0.7, 0));
  await settle(tester);
}

void main() {
  // Before any `at(...)`: the helpers build planner-zone times.
  PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');

  testWidgets('groups are Due today, Today, Yesterday, Earlier; oldest first', (
    tester,
  ) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      overdue: [
        seed('Today task', at(3, 10, 8)),
        seed('Yesterday task', at(3, 9, 14)),
        seed('Earlier newer', at(3, 5, 9)),
        seed('Earlier older', at(3, 2, 9)),
      ],
      captures: ['Pay the invoice'],
    );

    double top(Finder f) => tester.getTopLeft(f).dy;
    final headers = [
      for (final kind in ['dueToday', 'today', 'yesterday', 'earlier'])
        find.byKey(ValueKey('day-attention-group-$kind')),
    ];
    for (final header in headers) {
      expect(header, findsOneWidget);
    }
    expect(find.text('Due today · 1'), findsOneWidget);
    expect(find.text('Today · 1'), findsOneWidget);
    expect(find.text('Yesterday · 1'), findsOneWidget);
    expect(find.text('Earlier · 2'), findsOneWidget);

    final order = [
      headers[0],
      row(ids['Pay the invoice']!),
      headers[1],
      row(ids['Today task']!),
      headers[2],
      row(ids['Yesterday task']!),
      headers[3],
      row(ids['Earlier older']!),
      row(ids['Earlier newer']!),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        top(order[i]),
        greaterThan(top(order[i - 1])),
        reason: 'item $i is below item ${i - 1}',
      );
    }
    // The header counts everything on the list.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-attention-count')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets(
    'the age is relative, the exact time is in the tooltip and label',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await pumpTriage(
        tester,
        size: const Size(1280, 800),
        overdue: [
          seed('Today task', at(3, 10, 8)), // ended 09:00, now 10:30
          seed('Yesterday task', at(3, 9, 14)),
          seed('Earlier task', at(3, 5, 9)),
        ],
      );

      expect(find.text('1 hour ago'), findsOneWidget);
      expect(
        find.text('Yesterday'),
        findsOneWidget,
      ); // the age, not the heading
      expect(find.text('5 days ago'), findsOneWidget);
      // The exact time is the block's end (when it became overdue).
      expect(tooltip('Tue, Mar 10 · 09:00'), findsOneWidget);
      expect(tooltip('Mon, Mar 9 · 15:00'), findsOneWidget);
      expect(tooltip('Thu, Mar 5 · 10:00'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Today task, overdue, missed Tue, Mar 10 · 09:00',
        ),
        findsOneWidget,
      );
      semantics.dispose();
      await finish(tester, container);
    },
  );

  testWidgets(
    'swipe right marks the task done and the snack bar Undo restores it',
    (tester) async {
      final ids = <String, String>{};
      final container = await pumpTriage(
        tester,
        size: const Size(1280, 800),
        ids: ids,
        overdue: [seed('Swipe me', at(3, 9, 14)), seed('Stay', at(3, 9, 16))],
      );
      final id = ids['Swipe me']!;

      await swipeRow(tester, id, right: true);

      expect(
        (await taskById(tester, container, id))?.status,
        TaskStatus.completed,
      );
      expect(row(id), findsNothing);
      expect(row(ids['Stay']!), findsOneWidget);
      expect(find.text('Marked done'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(
        (await taskById(tester, container, id))?.status,
        TaskStatus.planned,
      );
      expect(row(id), findsOneWidget);
      await finish(tester, container);
    },
  );

  testWidgets('swipe left moves the task to today; Undo reverts it', (
    tester,
  ) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      overdue: [
        seed('Afternoon yesterday', at(3, 9, 14)),
        seed('Early today', at(3, 10, 7)),
      ],
    );
    final id = ids['Afternoon yesterday']!;

    await swipeRow(tester, id, right: false);

    // The same clock time today: 14:00 is more than 15 minutes ahead of 10:30.
    final original = await taskById(tester, container, id);
    expect(original?.status, TaskStatus.rescheduled);
    final blocks = await todaysBlocks(tester, container);
    final successor = blocks.singleWhere((t) => t.rescheduledFromId == id);
    expect(successor.startTime, sameInstant(at(3, 10, 14)));
    expect(successor.endTime, sameInstant(at(3, 10, 15)));
    expect(original?.rescheduledToId, successor.id);
    expect(find.text('Moved to 14:00'), findsOneWidget);
    expect(row(id), findsNothing);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect((await taskById(tester, container, id))?.status, TaskStatus.planned);
    expect(
      (await todaysBlocks(
        tester,
        container,
      )).where((t) => t.rescheduledFromId == id),
      isEmpty,
    );
    expect(row(id), findsOneWidget);

    // A clock time already past goes to the next grid slot after 10:30
    // (the default grid is 60 minutes).
    final early = ids['Early today']!;
    await swipeRow(tester, early, right: false);
    final moved = (await todaysBlocks(
      tester,
      container,
    )).singleWhere((t) => t.rescheduledFromId == early);
    expect(moved.startTime, sameInstant(at(3, 10, 11)));
    expect(find.text('Moved to 11:00'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('hover shows the actions, leaving hides them; Tab reveals them', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      overdue: [seed('Hover me', at(3, 9, 14)), seed('Other', at(3, 9, 16))],
    );
    final id = ids['Hover me']!;
    final other = ids['Other']!;

    // The panel rows are narrower than 520, so the actions are hidden.
    expect(actionsOpacity(tester, id), 0);
    final hidden = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byKey(ValueKey('day-attention-actions-$id')),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(hidden.ignoring, isTrue);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row(id)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(actionsOpacity(tester, id), 1);
    expect(actionsOpacity(tester, other), 0);
    for (final label in ['Done', 'Move to today', 'Pick a new time', 'Skip']) {
      expect(
        find.descendant(of: row(id), matching: tooltip(label)),
        findsOneWidget,
        reason: label,
      );
    }
    // Their icon buttons are at least 48 x 48.
    final done = find.byKey(ValueKey('day-attention-done-$id'));
    expect(tester.getSize(done).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(done).height, greaterThanOrEqualTo(48));

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(actionsOpacity(tester, id), 0);

    // Keyboard: Tab until focus enters a row.
    var focusedRow = false;
    for (var i = 0; i < 120 && !focusedRow; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 200));
      focusedRow =
          actionsOpacity(tester, id) == 1 || actionsOpacity(tester, other) == 1;
    }
    expect(focusedRow, isTrue, reason: 'Tab reached a row');
    final focused = FocusManager.instance.primaryFocus!.context!;
    final shownId = actionsOpacity(tester, id) == 1 ? id : other;
    expect(
      find.descendant(
        of: row(shownId),
        matching: find.byElementPredicate((e) => e == focused),
      ),
      findsOneWidget,
      reason: 'focus is inside the row whose actions are shown',
    );
    await finish(tester, container);
  });

  testWidgets('the action fade is 140 ms, and zero with reduced motion', (
    tester,
  ) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      overdue: [seed('Motion', at(3, 9, 14))],
    );
    final key = ValueKey('day-attention-actions-${ids['Motion']}');
    expect(
      tester.widget<AnimatedOpacity>(find.byKey(key)).duration,
      const Duration(milliseconds: 140),
    );

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byKey(key)).duration,
      Duration.zero,
    );
    await finish(tester, container);
  });

  testWidgets('a wide row shows its actions without hover', (tester) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(800, 1280), // medium: the strip rows are ~770 wide
      ids: ids,
      overdue: [seed('Wide row', at(3, 9, 14))],
    );
    final id = ids['Wide row']!;
    expect(tester.getSize(row(id)).width, greaterThanOrEqualTo(520));
    for (final key in ['done', 'move', 'pick', 'skip']) {
      expect(find.byKey(ValueKey('day-attention-$key-$id')), findsOneWidget);
    }
    // Inline: no floating, fading group.
    expect(find.byKey(ValueKey('day-attention-actions-$id')), findsNothing);
    // A drag handle, because the timeline is visible under the strip.
    expect(find.byKey(ValueKey('day-attention-handle-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('day-attention-skip-$id')));
    await settle(tester);
    expect((await taskById(tester, container, id))?.status, TaskStatus.skipped);
    expect(find.text('Skipped'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('the overflow menu has all six actions and they work', (
    tester,
  ) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      overdue: [seed('Menu task', at(3, 9, 14))],
    );
    final id = ids['Menu task']!;

    await tester.tap(find.byKey(ValueKey('day-attention-menu-$id')));
    await settle(tester);
    for (final label in [
      'Done',
      'Move to today',
      'Pick a new time',
      'Skip',
      'Edit',
      'Delete',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect((await taskById(tester, container, id))?.status, TaskStatus.skipped);
    expect(find.text('Skipped'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Pick a new time opens the scheduling form for the task', (
    tester,
  ) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      overdue: [seed('Pick task', at(3, 9, 14))],
    );
    await tester.tap(
      find.byKey(ValueKey('day-attention-menu-${ids['Pick task']}')),
    );
    await settle(tester);
    await tester.tap(find.text('Pick a new time'));
    await settle(tester);
    expect(find.text('Reschedule overdue task'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets(
    'Move all to today: one confirm, one undo step, Undo restores all 13',
    (tester) async {
      final ids = <String, String>{};
      final container = await pumpTriage(
        tester,
        size: const Size(1280, 800),
        ids: ids,
        overdue: [
          // Oldest first is Overdue 13 ... Overdue 1.
          for (var i = 1; i <= 13; i++)
            seed(
              'Overdue $i',
              at(
                3,
                10,
                0,
              ).subtract(Duration(days: i)).add(const Duration(hours: 9)),
            ),
        ],
      );
      final undoStack = container.read(undoStackProvider.notifier);
      expect(container.read(undoStackProvider).undoStack, isEmpty);

      await tester.tap(find.byKey(const ValueKey('day-attention-move-all')));
      await settle(tester);
      expect(find.text('Move 13 overdue tasks to today?'), findsOneWidget);
      // Nothing moved yet.
      expect(
        (await taskById(tester, container, ids['Overdue 1']!))?.status,
        TaskStatus.planned,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Move to today'));
      await settle(tester);

      // All 13 fit exactly: 11:00 ... 24:00 on the 60-minute grid.
      final blocks = await todaysBlocks(tester, container);
      final successors = [
        for (final t in blocks)
          if (t.rescheduledFromId != null) t,
      ]..sort((a, b) => a.startTime!.compareTo(b.startTime!));
      expect(successors, hasLength(13));
      expect(successors.first.startTime, sameInstant(at(3, 10, 11)));
      expect(successors.last.endTime, sameInstant(at(3, 11)));
      // Oldest first: Overdue 13 takes the first slot, Overdue 1 the last.
      expect(successors.first.rescheduledFromId, ids['Overdue 13']);
      expect(successors.last.rescheduledFromId, ids['Overdue 1']);
      for (var i = 1; i < successors.length; i++) {
        expect(successors[i].startTime, successors[i - 1].endTime);
      }
      for (var i = 1; i <= 13; i++) {
        expect(
          (await taskById(tester, container, ids['Overdue $i']!))?.status,
          TaskStatus.rescheduled,
        );
      }
      expect(container.read(undoStackProvider).undoStack, hasLength(1));
      expect(find.text('Moved 13 to today'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('day-attention-move-all')),
        findsNothing,
      );

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(container.read(undoStackProvider).undoStack, isEmpty);
      for (var i = 1; i <= 13; i++) {
        expect(
          (await taskById(tester, container, ids['Overdue $i']!))?.status,
          TaskStatus.planned,
          reason: 'Overdue $i',
        );
      }
      expect(
        (await todaysBlocks(
          tester,
          container,
        )).where((t) => t.rescheduledFromId != null),
        isEmpty,
      );
      expect(undoStack, isNotNull);
      await finish(tester, container);
    },
  );

  testWidgets(
    'Move all places oldest original first, whatever the group display order',
    (tester) async {
      final ids = <String, String>{};
      final container = await pumpTriage(
        tester,
        size: const Size(1280, 800),
        ids: ids,
        overdue: [
          // Seeded newest first on purpose.
          seed('Today task', at(3, 10, 8)),
          seed('Yesterday task', at(3, 9, 14)),
          seed('Earlier task', at(3, 5, 9)),
        ],
        captures: ['Pay the invoice'],
      );
      // Displayed: Due today, Today, Yesterday, Earlier.
      await tester.tap(find.byKey(const ValueKey('day-attention-move-all')));
      await settle(tester);
      expect(find.text('Move 3 overdue tasks to today?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Move to today'));
      await settle(tester);

      final successors = [
        for (final t in await todaysBlocks(tester, container))
          if (t.rescheduledFromId != null) t,
      ]..sort((a, b) => a.startTime!.compareTo(b.startTime!));
      expect(successors, hasLength(3));
      expect(successors[0].startTime, sameInstant(at(3, 10, 11)));
      expect(
        [for (final t in successors) t.rescheduledFromId],
        [ids['Earlier task'], ids['Yesterday task'], ids['Today task']],
      );
      // The capture is not an overdue task and is not moved.
      expect(
        (await taskById(tester, container, ids['Pay the invoice']!))?.status,
        isNot(TaskStatus.rescheduled),
      );
      await finish(tester, container);
    },
  );

  testWidgets('Move all says how many fit and leaves the rest overdue', (
    tester,
  ) async {
    final ids = <String, String>{};
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      ids: ids,
      now: at(3, 10, 20, 30), // from 21:00: 21, 22, 23 fit, the rest do not
      overdue: [for (var i = 1; i <= 5; i++) seed('Late $i', at(3, 10 - i, 9))],
    );
    await tester.tap(find.byKey(const ValueKey('day-attention-move-all')));
    await settle(tester);
    expect(find.text('Move 3 of 5 overdue tasks to today?'), findsOneWidget);
    expect(find.textContaining('Only 3 fit before midnight'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Move to today'));
    await settle(tester);

    // The three oldest moved; the two newest stay overdue.
    for (final title in ['Late 5', 'Late 4', 'Late 3']) {
      expect(
        (await taskById(tester, container, ids[title]!))?.status,
        TaskStatus.rescheduled,
        reason: title,
      );
    }
    for (final title in ['Late 2', 'Late 1']) {
      expect(
        (await taskById(tester, container, ids[title]!))?.status,
        TaskStatus.planned,
        reason: title,
      );
      expect(row(ids[title]!), findsOneWidget);
    }
    expect(find.text('Moved 3 to today'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Move all is hidden with fewer than two overdue tasks', (
    tester,
  ) async {
    final container = await pumpTriage(
      tester,
      size: const Size(1280, 800),
      overdue: [seed('Only one', at(3, 9, 14))],
      captures: ['A capture'],
    );
    expect(find.byKey(const ValueKey('day-attention-move-all')), findsNothing);
    await finish(tester, container);
  });

  testWidgets(
    'a due-today capture has Schedule, Edit and Open Inbox, and no swipe',
    (tester) async {
      final ids = <String, String>{};
      final container = await pumpTriage(
        tester,
        size: const Size(800, 1280),
        ids: ids,
        captures: ['Pay the invoice'],
      );
      final id = ids['Pay the invoice']!;
      expect(row(id), findsOneWidget);
      expect(find.text('Due today'), findsWidgets);
      expect(swipe(id), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      for (final key in ['schedule', 'edit', 'open-inbox']) {
        expect(find.byKey(ValueKey('day-attention-$key-$id')), findsOneWidget);
      }
      expect(find.byKey(ValueKey('day-attention-done-$id')), findsNothing);

      await tester.tap(find.byKey(ValueKey('day-attention-schedule-$id')));
      await settle(tester);
      expect(find.text('Schedule Inbox capture'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await tester.tap(find.byKey(ValueKey('day-attention-open-inbox-$id')));
      await settle(tester);
      expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/inbox');
      await finish(tester, container);
    },
  );

  testWidgets(
    'a touch drag on a row scrolls the strip instead of dragging it',
    (tester) async {
      final container = await pumpTriage(
        tester,
        size: const Size(800, 1280),
        overdue: [
          for (var i = 1; i <= 12; i++) seed('Strip $i', at(3, 10 - i % 9, 9)),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('day-attention-toggle')));
      await settle(tester);
      final strip = find.byKey(const ValueKey('day-needs-attention'));
      final scrollable = find.descendant(
        of: strip,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable.first).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final before = position.pixels;
      final firstRow = find
          .descendant(of: strip, matching: find.byType(Dismissible))
          .first;
      await tester.drag(firstRow, const Offset(0, -120));
      await settle(tester);
      expect(position.pixels, greaterThan(before));
      await finish(tester, container);
    },
  );

  testWidgets(
    'compact sheet: no drag handle, swipe works and Undo is reachable',
    (tester) async {
      final ids = <String, String>{};
      final container = await pumpTriage(
        tester,
        size: const Size(360, 800),
        ids: ids,
        overdue: [
          seed('Sheet row', at(3, 9, 14)),
          seed('Other row', at(3, 9, 16)),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('day-attention-banner')));
      await settle(tester);
      final id = ids['Sheet row']!;
      expect(row(id), findsOneWidget);
      expect(find.byKey(ValueKey('day-attention-handle-$id')), findsNothing);

      await swipeRow(tester, id, right: true);
      expect(
        (await taskById(tester, container, id))?.status,
        TaskStatus.completed,
      );
      // The bar is shown inside the sheet, so the tap really reaches Undo.
      final undo = find.text('Undo');
      expect(undo, findsOneWidget);
      await tester.tap(undo);
      await settle(tester);
      expect(
        (await taskById(tester, container, id))?.status,
        TaskStatus.planned,
      );
      await finish(tester, container);
    },
  );

  testWidgets(
    'dragging the handle onto the timeline still opens the scheduling form',
    (tester) async {
      final ids = <String, String>{};
      final container = await pumpTriage(
        tester,
        size: const Size(1280, 800),
        ids: ids,
        overdue: [seed('Drag me', at(3, 9, 14))],
      );
      final handle = find.byKey(
        ValueKey('day-attention-handle-${ids['Drag me']}'),
      );
      expect(handle, findsOneWidget);
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveTo(const Offset(500, 300));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(find.text('Reschedule overdue task'), findsOneWidget);
      await finish(tester, container);
    },
  );
}
