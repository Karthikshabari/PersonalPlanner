// The dates panel of the Inbox (plan 7.4): quick picks, the 14-day strip, one
// time and length, per-date times, Day's overlap warning, the experiment hint,
// and Save / Cancel. Fixed clock: Monday 2026-10-12 12:00 in the planner zone.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';

import '../helpers/inbox_fixtures.dart';
import '../helpers/inbox_screen_harness.dart';
import '../helpers/test_container.dart';

/// Types [hour]:[minute] into the open 24-hour time picker and confirms.
Future<void> pickTime(WidgetTester tester, int hour, int minute) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pump();
  final fields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), '$hour');
  await tester.enterText(fields.at(1), '$minute');
  await tester.tap(find.text('OK'));
  await settle(tester);
}

const _windowDates = [
  '2026-10-12',
  '2026-10-13',
  '2026-10-14',
  '2026-10-15',
  '2026-10-16',
  '2026-10-17',
  '2026-10-18',
  '2026-10-19',
  '2026-10-20',
  '2026-10-21',
  '2026-10-22',
  '2026-10-23',
  '2026-10-24',
  '2026-10-25',
];

Finder inPanel(Finder finder) => find.descendant(
  of: find.byKey(const ValueKey('inbox-dates-panel')),
  matching: finder,
);

bool selected(WidgetTester tester, String date) =>
    tester.widget<FilterChip>(dateChip(date)).selected;

bool enabled(WidgetTester tester, String date) =>
    tester.widget<FilterChip>(dateChip(date)).onSelected != null;

List<String> pickedDates(WidgetTester tester) => [
  for (final date in _windowDates)
    if (selected(tester, date)) date,
];

Future<void> tapChip(WidgetTester tester, String date) async {
  await tester.tap(dateChip(date));
  // The panel grows and shrinks with its rows (AnimatedSize); let it finish
  // before the next tap lands on a button below.
  await settle(tester);
}

Future<void> quickPick(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settle(tester);
}

Future<void> openDates(WidgetTester tester, Task idea) async {
  await expandRow(tester, idea.id);
  await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
  await settle(tester);
}

Future<void> save(WidgetTester tester) async {
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('inbox-panel-submit')));
  await settle(tester);
}

Future<void> setAllTime(WidgetTester tester, int hour, int minute) async {
  await tester.tap(find.byKey(const ValueKey('inbox-time-all')));
  await settle(tester);
  await pickTime(tester, hour, minute);
}

/// The idea's sessions that are not deleted, soonest first.
Future<List<Task>> liveSessions(
  WidgetTester tester,
  InboxHarness h,
  String ideaId,
) async {
  final all = await runDb(tester, () => h.sessionsOf(ideaId));
  return [
    for (final task in all)
      if (task.deletedAt == null) task,
  ]..sort((a, b) => a.startTime!.compareTo(b.startTime!));
}

void main() {
  testWidgets('the strip has 14 chips from today', (tester) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);

    expect(inPanel(find.byType(FilterChip)), findsNWidgets(14));
    for (final date in _windowDates) {
      expect(dateChip(date), findsOneWidget, reason: date);
    }
    expect(
      find.descendant(of: dateChip('2026-10-12'), matching: find.text('Today')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dateChip('2026-10-13'),
        matching: find.text('Tue 13'),
      ),
      findsOneWidget,
    );
    expect(pickedDates(tester), isEmpty);
    expect(submitEnabled(tester), isFalse);
    await finish(tester, container);
  });

  testWidgets(
    'today is offered at the next whole hour, with a reason when off',
    (tester) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async => idea = await h.idea('Research SAP'),
      );
      await openDates(tester, idea);
      // It is 12:00, so 09:00 has passed and the default is 13:00.
      expect(find.text('Time for all 13:00 ▾'), findsOneWidget);
      expect(enabled(tester, '2026-10-12'), isTrue);
      expect(find.byKey(const ValueKey('inbox-today-off')), findsNothing);
      await tapChip(tester, '2026-10-12');
      expect(pickedDates(tester), ['2026-10-12']);
      expect(find.text('13:00 ▾'), findsOneWidget);
      await tapChip(tester, '2026-10-12');

      await setAllTime(tester, 9, 0);
      expect(enabled(tester, '2026-10-12'), isFalse);
      expect(enabled(tester, '2026-10-13'), isTrue);
      expect(find.textContaining('Pick a later time for all'), findsOneWidget);
      await finish(tester, container);
    },
  );

  testWidgets('today stays off with a visible reason after 23:00', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      clock: () =>
          PlannerTimeZone.calendarDate(2026, 10, 12, hour: 23, minute: 30),
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    expect(find.text('Time for all 09:00 ▾'), findsOneWidget);
    expect(enabled(tester, '2026-10-12'), isFalse);
    expect(find.textContaining('no time is left today'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Edit dates keeps each session length and Length changes them', (
    tester,
  ) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        await h.session(idea.id, start: h.at(2, 9), minutes: 30);
        await h.session(idea.id, start: h.at(3, 9), minutes: 120);
      },
    );
    await openDates(tester, idea);
    await tapChip(tester, '2026-10-16');
    await save(tester);
    List<int> lengths(List<Task> tasks) => [
      for (final t in tasks) t.endTime!.difference(t.startTime!).inMinutes,
    ];
    expect(lengths(await liveSessions(tester, h, idea.id)), [30, 120, 30]);

    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('inbox-length-90')));
    await settle(tester);
    await save(tester);
    expect(lengths(await liveSessions(tester, h, idea.id)), [90, 90, 90]);
    await finish(tester, container);
  });

  testWidgets('a left over idea opens with tomorrow at its last missed slot', (
    tester,
  ) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        await h.session(idea.id, start: h.at(-3, 9), minutes: 30);
        await h.session(idea.id, start: h.at(-1, 15), minutes: 90);
      },
    );
    await openDates(tester, idea);
    expect(pickedDates(tester), ['2026-10-13']);
    expect(find.text('Time for all 15:00 ▾'), findsOneWidget);
    expect(submitEnabled(tester), isTrue);
    await save(tester);
    final sessions = await liveSessions(tester, h, idea.id);
    expect(sessions.last.startTime, sameInstant(h.at(1, 15)));
    expect(sessions.last.endTime, sameInstant(h.at(1, 16, 30)));
    await finish(tester, container);
  });

  testWidgets('the picks of one idea survive opening another', (tester) async {
    late Task first;
    late Task second;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        first = await h.idea('First idea');
        second = await h.idea('Second idea');
      },
    );
    await openDates(tester, first);
    await tapChip(tester, '2026-10-14');
    await expandRow(tester, second.id);
    await expandRow(tester, first.id);
    expect(pickedDates(tester), ['2026-10-14']);
    expect(submitEnabled(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('inbox-panel-cancel')));
    await settle(tester);
    expect(container.read(inboxDatesDraftProvider(first.id)), isNull);
    await expandRow(tester, second.id);
    await expandRow(tester, first.id);
    expect(find.byKey(const ValueKey('inbox-dates-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    await tapChip(tester, '2026-10-15');
    expect(container.read(inboxDatesDraftProvider(first.id)), isNotNull);
    await save(tester);
    expect(container.read(inboxDatesDraftProvider(first.id)), isNull);
    await finish(tester, container);
  });

  testWidgets('quick picks replace the selection', (tester) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);

    await quickPick(tester, 'inbox-quick-tomorrow');
    expect(pickedDates(tester), ['2026-10-13']);

    await quickPick(tester, 'inbox-quick-3days');
    expect(pickedDates(tester), ['2026-10-13', '2026-10-14', '2026-10-15']);

    // Monday today: the next five weekdays from tomorrow skip the weekend.
    await quickPick(tester, 'inbox-quick-5weekdays');
    expect(pickedDates(tester), [
      '2026-10-13',
      '2026-10-14',
      '2026-10-15',
      '2026-10-16',
      '2026-10-19',
    ]);

    await quickPick(tester, 'inbox-quick-clear');
    expect(pickedDates(tester), isEmpty);
    await finish(tester, container);
  });

  testWidgets('Save creates sessions Day can read, with time and length', (
    tester,
  ) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    await quickPick(tester, 'inbox-quick-3days');
    await setAllTime(tester, 18, 0);
    await tester.tap(find.byKey(const ValueKey('inbox-length-90')));
    await tester.pump();
    expect(find.text('ends 19:30'), findsNWidgets(3));
    expect(submitEnabled(tester), isTrue);
    await save(tester);

    final sessions = await liveSessions(tester, h, idea.id);
    expect(sessions, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(sessions[i].startTime, sameInstant(h.at(1 + i, 18)));
      expect(sessions[i].endTime, sameInstant(h.at(1 + i, 19, 30)));
      expect(sessions[i].inboxItemId, idea.id);
    }
    // Day reads the same rows.
    final onDay = await runDb(
      tester,
      () => h.tasks.getScheduledTasksBetween(h.at(0, 0), h.at(5, 0)),
    );
    expect(onDay.map((t) => t.id), containsAll(sessions.map((s) => s.id)));
    // The panel closed, the toast said so, and the idea is under Coming up.
    expect(find.byKey(const ValueKey('inbox-dates-panel')), findsNothing);
    expect(find.text('Dates saved'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inbox-section-Coming up')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets('a date has its own time and Time for all overwrites it', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    await tapChip(tester, '2026-10-13');
    await tapChip(tester, '2026-10-14');

    String timeOf(String date) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('inbox-time-$date')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(timeOf('2026-10-14'), '13:00 ▾');

    await tester.tap(find.byKey(const ValueKey('inbox-time-2026-10-14')));
    await settle(tester);
    await pickTime(tester, 18, 30);
    expect(timeOf('2026-10-13'), '13:00 ▾');
    expect(timeOf('2026-10-14'), '18:30 ▾');

    await setAllTime(tester, 20, 0);
    expect(timeOf('2026-10-13'), '20:00 ▾');
    expect(timeOf('2026-10-14'), '20:00 ▾');
    await finish(tester, container);
  });

  testWidgets('a session that passes midnight says so', (tester) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Late work'),
    );
    await openDates(tester, idea);
    await tapChip(tester, '2026-10-13');
    await setAllTime(tester, 23, 30);
    await tester.tap(find.byKey(const ValueKey('inbox-length-90')));
    await tester.pump();
    expect(find.text('ends next day 01:00'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('an overlap with a Day block is a warning, and Save keeps both', (
    tester,
  ) async {
    late Task idea;
    late Task gym;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        gym = await h.tasks.insertTask(
          Task(
            id: '',
            title: 'Gym',
            startTime: h.at(2, 13, 30),
            endTime: h.at(2, 14, 30),
            createdAt: h.now,
            updatedAt: h.now,
          ),
        );
      },
    );
    await openDates(tester, idea);
    await tapChip(tester, '2026-10-13');
    expect(
      find.byKey(const ValueKey('inbox-overlap-2026-10-13')),
      findsNothing,
    );
    await tapChip(tester, '2026-10-14');
    expect(
      find.text(
        'Overlaps "Gym" 13:30–14:30. Change the time or save to keep both.',
      ),
      findsOneWidget,
    );
    // A warning, not an error: Save stays on.
    expect(submitEnabled(tester), isTrue);
    await save(tester);

    final sessions = await liveSessions(tester, h, idea.id);
    expect(sessions, hasLength(2));
    final stillThere = await runDb(tester, () => h.reload(gym.id));
    expect(stillThere.startTime, sameInstant(h.at(2, 13, 30)));
    await finish(tester, container);
  });

  testWidgets('more than seven dates shows the experiment hint', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    for (final date in _windowDates.sublist(1, 8)) {
      await tapChip(tester, date);
    }
    expect(pickedDates(tester), hasLength(7));
    expect(find.byKey(const ValueKey('inbox-experiment-hint')), findsNothing);

    await tapChip(tester, '2026-10-20');
    expect(find.byKey(const ValueKey('inbox-experiment-hint')), findsOneWidget);
    expect(
      find.text(
        'That is a lot of days for one errand. If you want to see how it is '
        'going, start an experiment in Insights instead.',
      ),
      findsOneWidget,
    );
    await tapChip(tester, '2026-10-20');
    expect(find.byKey(const ValueKey('inbox-experiment-hint')), findsNothing);
    await finish(tester, container);
  });

  testWidgets('the horizon copy and Open Insights', (tester) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    expect(
      find.text(
        'You can plan up to 2 weeks ahead. Errands planned further out '
        'usually get moved before you reach them, and Review looks at one '
        'week at a time. To repeat something for a month, start an '
        'experiment in Insights.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('inbox-open-insights')));
    await settle(tester);
    expect(
      appRouter.routerDelegate.currentConfiguration.uri.path,
      '/analytics',
    );
    await finish(tester, container);
  });

  testWidgets(
    'Edit dates moves a session, drops one and carries a missed one',
    (tester) async {
      late Task idea;
      late Task kept;
      late Task dropped;
      late Task missed;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Research SAP');
          missed = await h.session(idea.id, start: h.at(-2, 9));
          kept = await h.session(idea.id, start: h.at(2, 9));
          dropped = await h.session(idea.id, start: h.at(3, 9));
        },
      );
      await openDates(tester, idea);
      // Prefilled with the two upcoming sessions, each with its own time.
      expect(pickedDates(tester), ['2026-10-14', '2026-10-15']);
      // The idea's own sessions are not overlaps.
      expect(
        find.byKey(const ValueKey('inbox-overlap-2026-10-14')),
        findsNothing,
      );
      expect(submitEnabled(tester), isFalse);

      await tapChip(tester, '2026-10-15');
      await tester.tap(find.byKey(const ValueKey('inbox-time-2026-10-14')));
      await settle(tester);
      await pickTime(tester, 10, 0);
      await save(tester);

      final movedRow = await runDb(tester, () => h.reload(kept.id));
      expect(movedRow.deletedAt, isNull);
      expect(movedRow.startTime, sameInstant(h.at(2, 10)));
      expect(movedRow.endTime, sameInstant(h.at(2, 11)));
      final droppedRow = await runDb(tester, () => h.reload(dropped.id));
      expect(droppedRow.deletedAt, isNotNull);
      final missedRow = await runDb(tester, () => h.reload(missed.id));
      expect(missedRow.status, TaskStatus.rescheduled);
      expect(missedRow.rescheduledToId, kept.id);
      expect(await liveSessions(tester, h, idea.id), hasLength(2));
      await finish(tester, container);
    },
  );

  testWidgets('Cancel writes nothing', (tester) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    final before = await runDb(tester, h.syncLogCount);
    await openDates(tester, idea);
    await quickPick(tester, 'inbox-quick-3days');
    await tester.tap(find.byKey(const ValueKey('inbox-panel-cancel')));
    await settle(tester);

    expect(find.byKey(const ValueKey('inbox-dates-panel')), findsNothing);
    expect(await liveSessions(tester, h, idea.id), isEmpty);
    expect(await runDb(tester, h.syncLogCount), before);
    await finish(tester, container);
  });

  testWidgets('Ctrl+Enter saves and Esc cancels', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    await tapChip(tester, '2026-10-13');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(const ValueKey('inbox-dates-panel')), findsNothing);
    expect(trailOf(idea.id), findsOneWidget);
    expect(await liveSessions(tester, h, idea.id), isEmpty);

    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    await tapChip(tester, '2026-10-13');
    await ctrlEnter(tester);
    expect(find.byKey(const ValueKey('inbox-dates-panel')), findsNothing);
    expect(await liveSessions(tester, h, idea.id), hasLength(1));
    await finish(tester, container);
  });

  testWidgets('Save is off until something changes, and off for a past time', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    expect(submitEnabled(tester), isFalse);
    await tapChip(tester, '2026-10-13');
    expect(submitEnabled(tester), isTrue);
    await tapChip(tester, '2026-10-13');
    expect(submitEnabled(tester), isFalse);

    // Today at 23:00 is fine; moving the time back to 08:00 is not.
    await setAllTime(tester, 23, 0);
    await tapChip(tester, '2026-10-12');
    expect(submitEnabled(tester), isTrue);
    await setAllTime(tester, 8, 0);
    expect(
      find.byKey(const ValueKey('inbox-invalid-2026-10-12')),
      findsOneWidget,
    );
    expect(find.text('That time has passed.'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    await finish(tester, container);
  });

  testWidgets('a new day drops yesterday from the picks and says so', (
    tester,
  ) async {
    late Task idea;
    var now = PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12);
    final (container, _) = await pumpInbox(
      tester,
      clock: () => now,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    await setAllTime(tester, 23, 0);
    await tapChip(tester, '2026-10-12');
    await tapChip(tester, '2026-10-14');
    expect(pickedDates(tester), ['2026-10-12', '2026-10-14']);

    now = PlannerTimeZone.calendarDate(2026, 10, 13, hour: 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(dateChip('2026-10-12'), findsNothing);
    expect(dateChip('2026-10-26'), findsOneWidget);
    expect(
      find.text('It is a new day. Yesterday was removed from your picks.'),
      findsOneWidget,
    );
    expect(selected(tester, '2026-10-14'), isTrue);
    await finish(tester, container);
  });

  testWidgets('the footer offers Set dates, Edit dates or Add days by status', (
    tester,
  ) async {
    late Task fresh;
    late Task soon;
    late Task left;
    late Task finished;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        fresh = await h.idea('Fresh idea');
        soon = await h.idea('Soon idea');
        await h.session(soon.id, start: h.at(2, 9));
        left = await h.idea('Left idea');
        await h.session(left.id, start: h.at(-1, 9));
        finished = await h.idea('Finished idea');
        await h.session(
          finished.id,
          start: h.at(-2, 9),
          status: TaskStatus.completed,
        );
      },
    );
    Future<void> check(Task idea, List<String> labels) async {
      await expandRow(tester, idea.id);
      for (final label in labels) {
        expect(
          find.descendant(of: trailOf(idea.id), matching: find.text(label)),
          findsOneWidget,
          reason: '${idea.id} $label',
        );
      }
    }

    await check(fresh, ['Set dates', 'Start as an experiment', 'Let go']);
    await check(soon, ['Edit dates', 'Start as an experiment', 'Close it']);
    await check(left, ['Add days', 'Start as an experiment', 'Close it']);
    await pickSegment(tester, 'Done (1)');
    await check(finished, ['Add days']);
    expect(find.text('Start as an experiment'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('a legacy due date inside the window is offered as a pick', (
    tester,
  ) async {
    late Task dated;
    late Task stale;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        dated = await h.idea('Dated idea', dueDate: '2026-10-14');
        stale = await h.idea('Stale idea', dueDate: '2026-10-05');
      },
    );
    expect(find.textContaining('· Due Oct 14'), findsOneWidget);
    expect(find.textContaining('· Was due Oct 5'), findsOneWidget);

    await openDates(tester, dated);
    expect(pickedDates(tester), ['2026-10-14']);
    expect(submitEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('inbox-panel-cancel')));
    await settle(tester);

    await expandRow(tester, stale.id);
    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    expect(pickedDates(tester), isEmpty);
    await finish(tester, container);
  });

  testWidgets('a session after the window stays as planned in Day', (
    tester,
  ) async {
    late Task idea;
    late Task far;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        far = await h.session(idea.id, start: h.at(18, 9));
      },
    );
    await openDates(tester, idea);
    expect(
      find.text('1 session after the 2-week window stays as planned in Day.'),
      findsOneWidget,
    );
    expect(pickedDates(tester), isEmpty);
    await tapChip(tester, '2026-10-13');
    await save(tester);

    final untouched = await runDb(tester, () => h.reload(far.id));
    expect(untouched.deletedAt, isNull);
    expect(untouched.status, TaskStatus.planned);
    expect(untouched.startTime, sameInstant(h.at(18, 9)));
    expect(await liveSessions(tester, h, idea.id), hasLength(2));
    await finish(tester, container);
  });

  testWidgets('dates with a done session are shown locked', (tester) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        await h.session(
          idea.id,
          start: h.at(0, 9),
          status: TaskStatus.completed,
        );
        await h.session(idea.id, start: h.at(1, 8));
      },
    );
    await openDates(tester, idea);
    expect(
      find.byKey(const ValueKey('inbox-locked-2026-10-12')),
      findsOneWidget,
    );
    expect(find.text('Mon, Oct 12   Done (locked)'), findsOneWidget);
    expect(selected(tester, '2026-10-12'), isTrue);
    expect(enabled(tester, '2026-10-12'), isFalse);
    // A later upcoming session is an ordinary pick.
    expect(selected(tester, '2026-10-13'), isTrue);
    expect(enabled(tester, '2026-10-13'), isTrue);
    await finish(tester, container);
  });

  testWidgets('a repository refusal is shown under the fields', (tester) async {
    late Task idea;
    final (container, h) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Research SAP');
        await h.session(
          idea.id,
          start: h.at(-2, 9),
          status: TaskStatus.completed,
        );
      },
    );
    await pickSegment(tester, 'Done (1)');
    await openDates(tester, idea);
    await tapChip(tester, '2026-10-13');
    // The idea becomes an experiment on another device while the panel is
    // open. (A plain close would move the row to Dropped and take the panel
    // with it; an experiment stays in Done.)
    await runDb(
      tester,
      () =>
          h.inbox.markBecameExperiment(idea.id, 'experiment:elsewhere', h.now),
    );
    await settle(tester);
    await save(tester);

    expect(find.byKey(const ValueKey('inbox-panel-error')), findsOneWidget);
    expect(
      find.text('This idea changed elsewhere. Close it and open it again.'),
      findsOneWidget,
    );
    expect(await liveSessions(tester, h, idea.id), hasLength(1));
    await finish(tester, container);
  });

  testWidgets('Save re-checks the clock: a time that passed is refused', (
    tester,
  ) async {
    late Task idea;
    var now = PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12);
    final (container, h) = await pumpInbox(
      tester,
      clock: () => now,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    await setAllTime(tester, 12, 30);
    await tapChip(tester, '2026-10-12');
    expect(submitEnabled(tester), isTrue);

    // No clock event fired, but 12:30 has passed by the time of Save.
    now = PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12, minute: 45);
    await save(tester);
    expect(find.text('That time has passed.'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    expect(await liveSessions(tester, h, idea.id), isEmpty);
    await finish(tester, container);
  });

  testWidgets('chips read out their date, time and state', (tester) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Research SAP'),
    );
    await openDates(tester, idea);
    await setAllTime(tester, 18, 0);
    await tester.tap(find.byKey(const ValueKey('inbox-length-90')));
    await tapChip(tester, '2026-10-13');
    expect(
      find.bySemanticsLabel(
        'Tuesday, October 13, selected, 18:00 for 90 minutes',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Wednesday, October 14, not selected'),
      findsOneWidget,
    );
    await setAllTime(tester, 8, 0);
    await tapChip(tester, '2026-10-13');
    expect(
      find.bySemanticsLabel('Today, not available, that time has passed'),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets('the panel, trail and rows fit a phone with large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    late Task idea;
    late Task gym;
    final (container, _) = await pumpInbox(
      tester,
      surface: const Size(360, 800),
      seed: (h) async {
        idea = await h.idea(
          'A fairly long idea title that needs to wrap on a phone',
        );
        await h.session(idea.id, start: h.at(-1, 9));
        await h.session(idea.id, start: h.at(2, 9));
        gym = await h.idea('Another idea');
        await h.session(gym.id, start: h.at(-2, 9), status: TaskStatus.skipped);
      },
    );
    expect(tester.takeException(), isNull);
    // The Review line is tall at this size and scrolls with the list.
    await tester.scrollUntilVisible(
      headerOf(idea.id),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('inbox-list')),
        matching: find.byType(Scrollable),
      ),
    );
    // Fully on screen, clear of the bottom navigation bar.
    await tester.ensureVisible(headerOf(idea.id));
    await tester.pump();
    await expandRow(tester, idea.id);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('inbox-action-dates')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('inbox-action-dates')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(dateChip('2026-10-20'));
    await tester.pump();
    await tester.tap(dateChip('2026-10-20'));
    await settle(tester);
    for (final date in ['2026-10-16', '2026-10-17', '2026-10-18']) {
      await tester.ensureVisible(dateChip(date));
      await tester.pump();
      await tester.tap(dateChip(date));
      await settle(tester);
    }
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });
}
