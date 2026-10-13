// The Dropped group of the Inbox board: closed and let-go ideas leave Done.
// Each idea is in exactly one of Open, Done and Dropped. Monday 2026-10-12
// 12:00 in the planner zone.
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/domain/inbox_board.dart';
import 'package:personal_planner/features/inbox/domain/inbox_source.dart';
import 'package:personal_planner/features/inbox/domain/inbox_status.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  DateTime utc(DateTime planner) => DateTime.fromMicrosecondsSinceEpoch(
    planner.microsecondsSinceEpoch,
    isUtc: true,
  );
  final now = utc(PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12));
  DateTime at(int day, int hour) =>
      utc(PlannerTimeZone.calendarDate(2026, 10, 12 + day, hour: hour));

  InboxItemFacts item(String id, {List<InboxClosure> history = const []}) =>
      InboxItemFacts(
        id: id,
        text: 'Idea $id',
        createdAt: at(-10, 8),
        history: history,
      );

  InboxSessionFacts session(
    String id,
    String itemId,
    DateTime start, {
    TaskStatus status = TaskStatus.planned,
    DateTime? deletedAt,
  }) => InboxSessionFacts(
    id: id,
    itemId: itemId,
    title: 'Session $id',
    start: start,
    end: start.add(const Duration(hours: 1)),
    status: status,
    deletedAt: deletedAt,
    createdAt: at(-9, 8),
  );

  InboxClosure closure(
    InboxCloseKind kind,
    DateTime when, {
    String? experimentId,
  }) => InboxClosure(
    kind: kind,
    at: when,
    reason: kind == InboxCloseKind.closed ? 'Not needed' : null,
    experimentId: experimentId,
  );

  InboxBoard build(InboxSource source) =>
      buildInboxBoard(source, now: now, breakDates: const {});

  final mixed = InboxSource(
    items: [
      item('idea'),
      item('soon'),
      item('left'),
      item('fin'),
      item('closed-new', history: [closure(InboxCloseKind.closed, at(-1, 10))]),
      item('closed-old', history: [closure(InboxCloseKind.closed, at(-5, 10))]),
      item('let-go', history: [closure(InboxCloseKind.letGo, at(-3, 10))]),
      item(
        'exp',
        history: [
          closure(InboxCloseKind.experiment, at(-2, 10), experimentId: 'e1'),
        ],
      ),
      item('skipped-only'),
    ],
    sessions: [
      session('s1', 'soon', at(2, 9)),
      session('s2', 'left', at(-2, 9)),
      session('s3', 'fin', at(-3, 9), status: TaskStatus.completed),
      session('s4', 'skipped-only', at(-3, 9), status: TaskStatus.skipped),
      // The closed idea's missed session was skipped by Close it.
      session('s5', 'closed-new', at(-2, 9), status: TaskStatus.skipped),
    ],
  );

  test('Done holds finished and experiment ideas only', () {
    final board = build(mixed);
    expect(board.done, ['exp', 'fin']);
    expect(board.doneCount, 2);
    expect(board.byId['exp']!.chip, startsWith('Experiment'));
    expect(board.byId['fin']!.chip, 'Finished');
  });

  test('Dropped holds closed and let-go ideas, newest closure first', () {
    final board = build(mixed);
    expect(board.dropped, ['closed-new', 'let-go', 'closed-old']);
    expect(board.droppedCount, 3);
    expect(board.byId['closed-new']!.chip, 'Closed');
    expect(board.byId['let-go']!.chip, 'Let go');
  });

  test('every idea is in exactly one of Open, Done and Dropped', () {
    final board = build(mixed);
    final open = [...board.leftOver, ...board.ideas, ...board.comingUp];
    final all = [...open, ...board.done, ...board.dropped];
    expect(all.length, mixed.items.length);
    expect(all.toSet(), {for (final i in mixed.items) i.id});
    expect(board.openCount, open.length);
    expect(board.doneCount, board.done.length);
    expect(board.droppedCount, board.dropped.length);
    // An idea whose only session was skipped is still an idea.
    expect(board.ideas, contains('skipped-only'));
  });

  test('a closed idea whose session is completed later stays dropped', () {
    final board = build(
      InboxSource(
        items: [
          item('c', history: [closure(InboxCloseKind.closed, at(-1, 10))]),
        ],
        sessions: [session('s', 'c', at(-2, 9), status: TaskStatus.completed)],
      ),
    );
    expect(board.dropped, ['c']);
    expect(board.done, isEmpty);
    expect(board.byId['c']!.chip, 'Closed');
  });

  test('an idea with a dropped (deleted) session and a closure is dropped', () {
    final board = build(
      InboxSource(
        items: [
          item('c', history: [closure(InboxCloseKind.closed, at(-1, 10))]),
        ],
        sessions: [session('s', 'c', at(3, 9), deletedAt: at(-1, 10))],
      ),
    );
    expect(board.dropped, ['c']);
  });
}
