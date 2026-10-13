// The Dropped segment: closed and let-go ideas leave Done, and Left over is the
// backlog of missed sessions. Fixed clock: Monday 2026-10-12 12:00 in the
// planner zone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';

import '../helpers/inbox_screen_harness.dart';
import '../helpers/test_container.dart';

String _selected(WidgetTester tester) => tester
    .widget<SegmentedButton<dynamic>>(
      find.byKey(const ValueKey('inbox-segments')),
    )
    .selected
    .single
    .toString();

Future<void> _closeWith(WidgetTester tester, String id, String reason) async {
  await expandRow(tester, id);
  await tester.tap(find.byKey(const ValueKey('inbox-action-close')));
  await settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('inbox-reason-field')),
    reason,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('inbox-panel-submit')));
  await settle(tester);
}

void main() {
  testWidgets(
    '(a) a missed session shows Missed and the idea is in Left over',
    (tester) async {
      late Task idea;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Call the bank');
          await h.session(idea.id, start: h.at(-1, 9));
        },
      );
      expect(
        find.byKey(const ValueKey('inbox-section-Left over')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf(idea.id), matching: find.text('Missed')),
        findsOneWidget,
      );
      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Dropped (0)'), findsOneWidget);
      await finish(tester, container);
    },
  );

  testWidgets('(a) with another session upcoming the idea is in Coming up', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Call the bank');
        await h.session(idea.id, start: h.at(-1, 9));
        await h.session(idea.id, start: h.at(2, 9));
      },
    );
    expect(
      find.byKey(const ValueKey('inbox-section-Coming up')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inbox-section-Left over')), findsNothing);
    await expandRow(tester, idea.id);
    // The missed session still carries its Missed badge in the trail.
    expect(
      find.descendant(of: trailOf(idea.id), matching: find.text('Missed')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets(
    '(b) Close it on a Left over idea moves it to Dropped, not Done',
    (tester) async {
      late Task idea;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Call the bank');
          await h.session(idea.id, start: h.at(-1, 9));
        },
      );
      await _closeWith(tester, idea.id, 'Not needed');
      expect(find.text('Closed. Moved to Dropped.'), findsOneWidget);
      expect(find.text('Open (0)'), findsOneWidget);
      expect(find.text('Done (0)'), findsOneWidget);
      expect(find.text('Dropped (1)'), findsOneWidget);

      await pickSegment(tester, 'Done (0)');
      expect(rowOf(idea.id), findsNothing);
      expect(find.text('Nothing finished yet.'), findsOneWidget);

      await pickSegment(tester, 'Dropped (1)');
      expect(
        find.descendant(of: rowOf(idea.id), matching: find.text('Closed')),
        findsOneWidget,
      );
      expect(find.text('Closed Oct 12 · Not needed'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inbox-action-bring-back')));
      await settle(tester);
      expect(find.text('Dropped (0)'), findsOneWidget);
      await pickSegment(tester, 'Open (1)');
      expect(find.byKey(const ValueKey('inbox-section-Ideas')), findsOneWidget);
      // The old events stay in the trail.
      expect(find.text('Closed Oct 12 · Not needed'), findsOneWidget);
      expect(find.text('Brought back Oct 12'), findsOneWidget);
      expect(
        (await runDb(tester, () => h.reload(idea.id))).inboxHistory,
        hasLength(1),
      );
      await finish(tester, container);
    },
  );

  testWidgets('(c) Let go moves the idea to Dropped with the Let go chip', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async => idea = await h.idea('Learn the oboe'),
    );
    await expandRow(tester, idea.id);
    await tester.tap(find.byKey(const ValueKey('inbox-action-let-go')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('inbox-panel-submit')));
    await settle(tester);

    expect(find.text('Let go. Moved to Dropped.'), findsOneWidget);
    expect(find.text('Done (0)'), findsOneWidget);
    expect(find.text('Dropped (1)'), findsOneWidget);
    await pickSegment(tester, 'Dropped (1)');
    expect(
      find.descendant(of: rowOf(idea.id), matching: find.text('Let go')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets('(d) an idea with all sessions done is in Done as Finished', (
    tester,
  ) async {
    late Task idea;
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        idea = await h.idea('Write the report');
        await h.session(
          idea.id,
          start: h.at(-2, 9),
          status: TaskStatus.completed,
        );
        await h.session(
          idea.id,
          start: h.at(-1, 9),
          status: TaskStatus.completed,
        );
      },
    );
    expect(find.text('Done (1)'), findsOneWidget);
    expect(find.text('Dropped (0)'), findsOneWidget);
    await pickSegment(tester, 'Done (1)');
    expect(
      find.descendant(of: rowOf(idea.id), matching: find.text('Finished')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets(
    '(e) a closed idea whose session is completed later stays Dropped',
    (tester) async {
      late Task idea;
      late Task missed;
      final (container, h) = await pumpInbox(
        tester,
        seed: (h) async {
          idea = await h.idea('Call the bank');
          missed = await h.session(idea.id, start: h.at(-1, 9));
        },
      );
      await _closeWith(tester, idea.id, 'Not needed');
      final skipped = await runDb(tester, () => h.reload(missed.id));
      expect(skipped.status, TaskStatus.skipped);

      // Day completes the skipped block afterwards.
      await runDb(
        tester,
        () => h.tasks.updateTask(
          skipped.copyWith(status: TaskStatus.completed),
          allowStatusTransition: true,
        ),
      );
      await settle(tester);
      expect(find.text('Dropped (1)'), findsOneWidget);
      expect(find.text('Done (0)'), findsOneWidget);
      await finish(tester, container);
    },
  );

  testWidgets('Dropped has its own empty text and pages by 30', (tester) async {
    final (container, _) = await pumpInbox(
      tester,
      seed: (h) async {
        for (var i = 0; i < 35; i++) {
          final idea = await h.idea('Gone $i');
          await h.inbox.letGo(idea.id, null, h.now);
        }
      },
    );
    expect(find.text('Dropped (35)'), findsOneWidget);
    expect(find.text('Done (0)'), findsOneWidget);
    await pickSegment(tester, 'Done (0)');
    expect(find.text('Nothing finished yet.'), findsOneWidget);
    await pickSegment(tester, 'Dropped (35)');
    final more = find.byKey(const ValueKey('inbox-show-more'));
    await tester.scrollUntilVisible(
      more,
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('inbox-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(more);
    await settle(tester);
    await tester.tap(more);
    await settle(tester);
    expect(more, findsNothing);
    await finish(tester, container);
  });

  testWidgets('an empty Dropped says so', (tester) async {
    final (container, _) = await pumpInbox(tester);
    await pickSegment(tester, 'Dropped (0)');
    expect(find.text('Nothing dropped.'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets(
    '(g) a focus request selects Dropped for a closed idea, Done for a finished one',
    (tester) async {
      late Task closed;
      late Task finished;
      final (container, _) = await pumpInbox(
        tester,
        seed: (h) async {
          closed = await h.idea('Closed idea');
          await h.inbox.closeItem(closed.id, 'Too far', h.now);
          finished = await h.idea('Finished idea');
          await h.session(
            finished.id,
            start: h.at(-1, 9),
            status: TaskStatus.completed,
          );
        },
        before: (c) =>
            c.read(inboxFocusItemProvider.notifier).state = closed.id,
      );
      expect(_selected(tester), contains('dropped'));
      expect(trailOf(closed.id), findsOneWidget);

      container.read(inboxFocusItemProvider.notifier).state = finished.id;
      await settle(tester);
      expect(_selected(tester), contains('done'));
      expect(trailOf(finished.id), findsOneWidget);
      await finish(tester, container);
    },
  );

  testWidgets('the three segments fit a 360 px phone at large text', (
    tester,
  ) async {
    tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.platformDispatcher.clearAllTestValues);
    final (container, _) = await pumpInbox(
      tester,
      surface: const Size(360, 800),
      seed: (h) async {
        for (var i = 0; i < 12; i++) {
          final idea = await h.idea('Gone $i');
          await h.inbox.letGo(idea.id, null, h.now);
        }
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Dropped (12)'), findsOneWidget);
    final box = tester.getRect(find.byKey(const ValueKey('inbox-segments')));
    // The control scrolls sideways when it must; it never overflows.
    expect(box.left, greaterThanOrEqualTo(0));
    await finish(tester, container);
  });
}
