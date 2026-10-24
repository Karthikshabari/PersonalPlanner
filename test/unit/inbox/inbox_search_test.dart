import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/domain/inbox_board.dart';
import 'package:personal_planner/features/inbox/domain/inbox_search.dart';
import 'package:personal_planner/features/inbox/domain/inbox_source.dart';
import 'package:personal_planner/features/inbox/domain/inbox_status.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  // Monday 2026-10-12 12:00 in the planner zone, as plain UTC values.
  DateTime utc(DateTime planner) => DateTime.fromMicrosecondsSinceEpoch(
    planner.microsecondsSinceEpoch,
    isUtc: true,
  );
  final now = utc(PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12));
  DateTime at(int day, int hour) =>
      utc(PlannerTimeZone.calendarDate(2026, 10, 12 + day, hour: hour));

  InboxItemFacts item(
    String id,
    String text, {
    List<InboxClosure> history = const [],
  }) => InboxItemFacts(
    id: id,
    text: text,
    createdAt: at(-10, 8),
    history: history,
  );

  InboxSessionFacts session(
    String id,
    String itemId,
    DateTime start, {
    TaskStatus status = TaskStatus.planned,
  }) => InboxSessionFacts(
    id: id,
    itemId: itemId,
    title: 'Session $id',
    start: start,
    end: start.add(const Duration(hours: 1)),
    status: status,
    createdAt: at(-9, 8),
  );

  InboxClosure closure(InboxCloseKind kind, int day, {String? reason}) =>
      InboxClosure(kind: kind, at: at(day, 10), reason: reason);

  // idea-a     Ideas       "Plan the zanzibar trip\nBook flights"
  // soon-b     Coming up   text "Call the bank", session reason none
  // left-c     Left over   missed session with the saved reason "ran out of battery"
  // fin-d      Done        text "Finish report"
  // closed-e   Dropped     closed with reason "superseded by the Tokyo plan"
  // gone-f     Dropped     let go; an earlier closure (since brought back)
  //                        carried the reason "too expensive"
  final board = buildInboxBoard(
    InboxSource(
      items: [
        item('idea-a', 'Plan the zanzibar trip\nBook flights'),
        item('soon-b', 'Call the bank'),
        item('left-c', 'Water the plants'),
        item('fin-d', 'Finish report'),
        item(
          'closed-e',
          'Old plan',
          history: [
            closure(
              InboxCloseKind.closed,
              -2,
              reason: 'superseded by the Tokyo plan',
            ),
          ],
        ),
        item(
          'gone-f',
          'Gym membership',
          history: [
            InboxClosure(
              kind: InboxCloseKind.closed,
              at: at(-8, 10),
              reason: 'Too Expensive',
              reopenedAt: at(-7, 10),
            ),
            closure(InboxCloseKind.letGo, -1),
          ],
        ),
      ],
      sessions: [
        session('s1', 'soon-b', at(2, 9)),
        session('s2', 'left-c', at(-1, 9)),
        session('s3', 'fin-d', at(-3, 9), status: TaskStatus.completed),
      ],
      reasons: const {'s2': 'Ran out of battery'},
    ),
    now: now,
    breakDates: const {},
  );

  group('sections of the fixture board', () {
    test('every idea is where the fixture comment says', () {
      expect(board.ideas, ['idea-a']);
      expect(board.comingUp, ['soon-b']);
      expect(board.leftOver, ['left-c']);
      expect(board.done, ['fin-d']);
      expect(board.dropped.toSet(), {'closed-e', 'gone-f'});
    });
  });

  group('matchInbox', () {
    test('is null without a board or with an empty needle', () {
      expect(matchInbox(null, 'bank'), isNull);
      expect(matchInbox(board, ''), isNull);
    });

    test('matches the idea text, including lines after the first', () {
      expect(matchInbox(board, 'zanzibar')!.ids, {'idea-a'});
      expect(matchInbox(board, 'book flights')!.ids, {'idea-a'});
    });

    test('ignores case', () {
      expect(matchInbox(board, 'call the bank')!.ids, {'soon-b'});
    });

    test('matches the reason the idea was closed with', () {
      expect(matchInbox(board, 'tokyo')!.ids, {'closed-e'});
    });

    test('matches a reason in the history of a brought-back idea', () {
      expect(matchInbox(board, 'too expensive')!.ids, {'gone-f'});
    });

    test('matches the saved Review reason of a session', () {
      expect(matchInbox(board, 'battery')!.ids, {'left-c'});
    });

    test('is contiguous: a different word order does not match', () {
      expect(matchInbox(board, 'bank the'), isNotNull);
      expect(matchInbox(board, 'bank the')!.ids, isEmpty);
    });

    test('counts matches per segment', () {
      // "plan" is in idea-a and left-c ("plants", both Open) and in
      // closed-e ("Old plan", Dropped).
      final plan = matchInbox(board, 'plan')!;
      expect(plan.ids, {'idea-a', 'left-c', 'closed-e'});
      expect(plan.open, 2);
      expect(plan.done, 0);
      expect(plan.dropped, 1);

      final report = matchInbox(board, 'report')!;
      expect(report.open, 0);
      expect(report.done, 1);
      expect(report.dropped, 0);

      // Left over, Ideas and Coming up all count as Open.
      final everything = matchInbox(board, 'a')!;
      expect(everything.open, 3);
    });

    test('an equal result compares equal, a different one does not', () {
      expect(matchInbox(board, 'bank'), matchInbox(board, 'bank'));
      expect(
        matchInbox(board, 'bank').hashCode,
        matchInbox(board, 'bank').hashCode,
      );
      expect(matchInbox(board, 'bank'), isNot(matchInbox(board, 'plan')));
    });

    test('no match gives an empty result, not null', () {
      final none = matchInbox(board, 'zzz')!;
      expect(none.ids, isEmpty);
      expect(none.open + none.done + none.dropped, 0);
    });
  });
}
