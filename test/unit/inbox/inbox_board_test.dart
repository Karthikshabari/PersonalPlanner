import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/domain/inbox_board.dart';
import 'package:personal_planner/features/inbox/domain/inbox_source.dart';
import 'package:personal_planner/features/inbox/domain/inbox_status.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  // Monday 2026-10-12 12:00 in the planner zone (Asia/Kolkata in tests).
  // Plain UTC values, as the repository reads them.
  DateTime utc(DateTime planner) => DateTime.fromMicrosecondsSinceEpoch(
    planner.microsecondsSinceEpoch,
    isUtc: true,
  );
  final now = utc(PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12));
  DateTime at(int day, int hour, [int minute = 0]) => utc(
    PlannerTimeZone.calendarDate(
      2026,
      10,
      12 + day,
      hour: hour,
      minute: minute,
    ),
  );
  final created = at(-10, 8);

  InboxItemFacts item(
    String id, {
    DateTime? createdAt,
    List<InboxClosure> history = const [],
    String? dueDate,
  }) => InboxItemFacts(
    id: id,
    text: 'Idea $id',
    createdAt: createdAt ?? created,
    history: history,
    dueDate: dueDate,
  );

  InboxSessionFacts session(
    String id,
    String itemId,
    DateTime start, {
    int minutes = 60,
    TaskStatus status = TaskStatus.planned,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) => InboxSessionFacts(
    id: id,
    itemId: itemId,
    title: 'Session $id',
    start: start,
    end: start.add(Duration(minutes: minutes)),
    status: status,
    deletedAt: deletedAt,
    createdAt: createdAt ?? at(-9, 8),
  );

  InboxClosure closure(
    InboxCloseKind kind,
    DateTime when, {
    String? reason,
    String? experimentId,
    DateTime? reopenedAt,
  }) => InboxClosure(
    kind: kind,
    at: when,
    reason: kind == InboxCloseKind.closed ? (reason ?? 'Not needed') : reason,
    experimentId: experimentId,
    reopenedAt: reopenedAt,
  );

  InboxBoard build(
    InboxSource source, {
    Map<String, String> breakDates = const {},
    DateTime? clock,
  }) => buildInboxBoard(source, now: clock ?? now, breakDates: breakDates);

  group('sections, order and counts', () {
    // idea: newest capture first. soon: soonest upcoming first. left: most
    // recent missed first. done: newest resolution first.
    final source = InboxSource(
      items: [
        item('idea-old', createdAt: at(-8, 9)),
        item('idea-new', createdAt: at(-2, 9)),
        item('soon-late'),
        item('soon-early'),
        item('left-old'),
        item('left-new'),
        item('fin-old'),
        item('fin-new'),
        item(
          'closed-mid',
          history: [closure(InboxCloseKind.closed, at(-1, 10))],
        ),
        item('let-go', history: [closure(InboxCloseKind.letGo, at(-4, 10))]),
      ],
      sessions: [
        session('s1', 'soon-late', at(5, 9)),
        session('s2', 'soon-early', at(1, 9)),
        session('s3', 'left-old', at(-5, 9)),
        session('s4', 'left-new', at(-1, 9)),
        session('s5', 'fin-old', at(-6, 9), status: TaskStatus.completed),
        session('s6', 'fin-new', at(-3, 9), status: TaskStatus.completed),
      ],
    );

    test('each idea lands in the section its status says', () {
      final board = build(source);
      expect(board.ideas, ['idea-new', 'idea-old']);
      expect(board.comingUp, ['soon-early', 'soon-late']);
      expect(board.leftOver, ['left-new', 'left-old']);
      expect(board.done, [
        'closed-mid', // closed yesterday 10:00
        'fin-new', // last done session ended 3 days ago
        'let-go', // closed 4 days ago
        'fin-old', // ended 6 days ago
      ]);
    });

    test('counts: open = left + ideas + coming up; done = done list', () {
      final board = build(source);
      expect(board.openCount, 6);
      expect(board.doneCount, 4);
      expect(board.byId.keys.toSet(), {for (final i in source.items) i.id});
    });

    test('Left over is ordered by the missed end, not the start', () {
      final board = build(
        InboxSource(
          items: [item('long-early'), item('short-late')],
          sessions: [
            // Starts earlier but ends later than the other one.
            session('a', 'long-early', at(-2, 8), minutes: 27 * 60),
            session('b', 'short-late', at(-1, 9)),
          ],
        ),
      );
      expect(board.leftOver, ['long-early', 'short-late']);
      expect(board.byId['long-early']!.lastMissedEnd, at(-1, 11));
    });

    test('a soon idea that also has a missed session is Coming up (I2)', () {
      final board = build(
        InboxSource(
          items: [item('both')],
          sessions: [
            session('m', 'both', at(-1, 9)),
            session('u', 'both', at(2, 9)),
          ],
        ),
      );
      expect(board.comingUp, ['both']);
      expect(board.leftOver, isEmpty);
    });

    test(
      'an idea whose only session was skipped or deleted is an idea again',
      () {
        final board = build(
          InboxSource(
            items: [item('a'), item('b')],
            sessions: [
              session('x', 'a', at(1, 9), status: TaskStatus.skipped),
              session('y', 'b', at(1, 9), deletedAt: at(0, 1)),
            ],
          ),
        );
        expect(board.ideas.toSet(), {'a', 'b'});
      },
    );

    test(
      'sessions of an idea that is not listed (deleted idea) are ignored',
      () {
        final board = build(
          InboxSource(
            items: [item('a')],
            sessions: [session('orphan', 'gone', at(-1, 9))],
          ),
        );
        expect(board.byId.keys, ['a']);
        expect(board.reasonsMissing.count, 0);
      },
    );

    test(
      'Bring back of an idea with old done sessions lands in Ideas (I4)',
      () {
        final reopened = at(-2, 9);
        final board = build(
          InboxSource(
            items: [
              item(
                'back',
                history: [
                  closure(
                    InboxCloseKind.closed,
                    at(-3, 9),
                    reopenedAt: reopened,
                  ),
                ],
              ),
            ],
            sessions: [
              session(
                'old-done',
                'back',
                at(-6, 9),
                status: TaskStatus.completed,
                createdAt: at(-7, 9),
              ),
            ],
          ),
        );
        expect(board.ideas, ['back']);
      },
    );

    test('Add days on a finished idea makes it soon again', () {
      final board = build(
        InboxSource(
          items: [item('fin')],
          sessions: [
            session('d', 'fin', at(-3, 9), status: TaskStatus.completed),
            session('n', 'fin', at(2, 9)),
          ],
        ),
      );
      expect(board.comingUp, ['fin']);
      expect(board.doneCount, 0);
    });

    test('row numbers: next start, upcoming count, last missed start', () {
      final board = build(
        InboxSource(
          items: [item('a')],
          sessions: [
            session('u1', 'a', at(3, 9)),
            session('u2', 'a', at(1, 9)),
            session('m1', 'a', at(-2, 9)),
            session('m2', 'a', at(-1, 9)),
          ],
        ),
      );
      final view = board.byId['a']!;
      expect(view.status, InboxItemStatus.soon);
      expect(view.upcomingCount, 2);
      expect(view.nextStart, at(1, 9));
      expect(view.lastMissedStart, at(-1, 9));
      expect(view.sessions.map((s) => s.facts.id), ['m1', 'm2', 'u2', 'u1']);
    });
  });

  group('Done chips and the experiment chip', () {
    InboxExperimentFacts experiment({
      ExperimentStatus status = ExperimentStatus.running,
      String start = '2026-10-10',
      String end = '2026-11-08',
      ExperimentOutcome? outcome,
      String? concludedOn,
      DateTime? retiredAt,
      DateTime? deletedAt,
    }) => InboxExperimentFacts(
      id: 'experiment:t',
      name: 'Run',
      startDate: start,
      endDate: end,
      status: status,
      outcome: outcome,
      concludedOn: concludedOn,
      retiredAt: retiredAt,
      deletedAt: deletedAt,
    );

    String? chipFor(InboxExperimentFacts? facts) {
      final board = build(
        InboxSource(
          items: [
            item(
              'x',
              history: [
                closure(
                  InboxCloseKind.experiment,
                  at(0, 9),
                  experimentId: 'experiment:t',
                ),
              ],
            ),
          ],
          experiments: {?facts?.id: ?facts},
        ),
      );
      return board.byId['x']!.chip;
    }

    test('running: Day X of N, counted from the date parts', () {
      expect(chipFor(experiment()), 'Experiment · Day 3 of 30');
    });

    test('not started yet', () {
      expect(
        chipFor(experiment(start: '2026-10-14', end: '2026-11-12')),
        'Experiment · Starts Oct 14',
      );
    });

    test('concluded', () {
      expect(
        chipFor(
          experiment(
            status: ExperimentStatus.concluded,
            outcome: ExperimentOutcome.drop,
            concludedOn: '2026-10-09',
          ),
        ),
        'Experiment · Concluded Oct 9',
      );
    });

    test('kept, and a retired kept experiment reads Concluded', () {
      final kept = experiment(
        status: ExperimentStatus.concluded,
        outcome: ExperimentOutcome.keep,
        concludedOn: '2026-10-09',
      );
      expect(chipFor(kept), 'Experiment · Kept');
      expect(
        chipFor(
          experiment(
            status: ExperimentStatus.concluded,
            outcome: ExperimentOutcome.keep,
            concludedOn: '2026-10-09',
            retiredAt: at(0, 8),
          ),
        ),
        'Experiment · Concluded Oct 9',
      );
    });

    test('missing row and tombstone read Removed and flag the idea', () {
      expect(chipFor(null), 'Experiment · Removed');
      expect(chipFor(experiment(deletedAt: at(0, 8))), 'Experiment · Removed');
      final board = build(
        InboxSource(
          items: [
            item(
              'x',
              history: [
                closure(
                  InboxCloseKind.experiment,
                  at(0, 9),
                  experimentId: 'experiment:t',
                ),
              ],
            ),
          ],
        ),
      );
      expect(board.byId['x']!.experimentMissing, isTrue);
      expect(board.byId['x']!.experimentId, 'experiment:t');
    });

    test('Finished, Closed and Let go', () {
      final board = build(
        InboxSource(
          items: [
            item('fin'),
            item('cl', history: [closure(InboxCloseKind.closed, at(-1, 9))]),
            item('lg', history: [closure(InboxCloseKind.letGo, at(-1, 9))]),
          ],
          sessions: [
            session('d', 'fin', at(-1, 9), status: TaskStatus.completed),
          ],
        ),
      );
      expect(board.byId['fin']!.chip, 'Finished');
      expect(board.byId['cl']!.chip, 'Closed');
      expect(board.byId['lg']!.chip, 'Let go');
      expect(board.byId['cl']!.closure!.reason, 'Not needed');
    });

    test('an idea that is not in Done has no chip', () {
      final board = build(InboxSource(items: [item('plain')]));
      expect(board.byId['plain']!.chip, isNull);
      expect(board.byId['plain']!.closure, isNull);
    });
  });

  group('the Review line (sessions without a reason)', () {
    InboxSource withReasons(Map<String, String> reasons) => InboxSource(
      items: [
        item('a', history: [closure(InboxCloseKind.closed, at(-1, 20))]),
        item('b'),
      ],
      sessions: [
        // a: skipped by Close it; missed on a break day; carried
        session('skipped', 'a', at(-2, 9), status: TaskStatus.skipped),
        session('carried', 'b', at(-3, 9), status: TaskStatus.rescheduled),
        session('missed', 'b', at(-1, 9)),
        session('done', 'b', at(-4, 9), status: TaskStatus.completed),
        session('future', 'b', at(2, 9)),
        session('dropped', 'b', at(-5, 9), deletedAt: at(-4, 1)),
      ],
      reasons: reasons,
    );

    test('missed, carried and skipped sessions count; others do not', () {
      final board = build(withReasons(const {}));
      expect(board.reasonsMissing.count, 3);
      final b = board.byId['b']!;
      bool needs(String id) =>
          b.sessions.singleWhere((s) => s.facts.id == id).needsReason;
      expect(needs('carried'), isTrue);
      expect(needs('missed'), isTrue);
      expect(needs('done'), isFalse);
      expect(needs('future'), isFalse);
      expect(needs('dropped'), isFalse);
      expect(board.byId['a']!.sessions.single.needsReason, isTrue);
      expect(board.byId['a']!.needsReasonCount, 1);
      expect(b.needsReasonCount, 2);
    });

    test('the most recent date is reported', () {
      expect(
        build(withReasons(const {})).reasonsMissing.latestDate,
        '2026-10-11',
      );
    });

    test('a saved reason is not counted and is shown', () {
      final board = build(withReasons({'missed': 'Ran late'}));
      expect(board.reasonsMissing.count, 2);
      final missed = board.byId['b']!.sessions.singleWhere(
        (s) => s.facts.id == 'missed',
      );
      expect(missed.reason, 'Ran late');
      expect(board.reasonsMissing.latestDate, '2026-10-10');
    });

    test(
      'a blank reason is not a reason; an unsaved draft is simply absent',
      () {
        expect(build(withReasons({'missed': '   '})).reasonsMissing.count, 3);
      },
    );

    test('a break day asks no reason and is flagged', () {
      final board = build(
        withReasons(const {}),
        breakDates: {'2026-10-11': 'Rest day'},
      );
      expect(board.reasonsMissing.count, 2);
      final missed = board.byId['b']!.sessions.singleWhere(
        (s) => s.facts.id == 'missed',
      );
      expect(missed.breakDay, isTrue);
      expect(missed.needsReason, isFalse);
      // Its status is still Missed: the errand needs a decision.
      expect(missed.status, InboxSessionStatus.missed);
      expect(board.reasonsMissing.latestDate, '2026-10-10');
    });

    test('a session that has not ended is not counted', () {
      final board = build(
        InboxSource(
          items: [item('a')],
          sessions: [
            session('running', 'a', at(0, 11, 30), status: TaskStatus.skipped),
          ],
        ),
      );
      expect(board.reasonsMissing.count, 0);
    });

    test(
      'the date is the planner date of the start (a session crossing midnight)',
      () {
        final board = build(
          InboxSource(
            items: [item('a')],
            sessions: [session('late', 'a', at(-1, 23, 30), minutes: 120)],
          ),
        );
        expect(board.reasonsMissing.latestDate, '2026-10-11');
      },
    );
  });

  group('nextBoundary', () {
    test('is the earliest upcoming start or end after now', () {
      final board = build(
        InboxSource(
          items: [item('a')],
          sessions: [
            session('later', 'a', at(2, 9)),
            session('soon', 'a', at(0, 14), minutes: 30),
          ],
        ),
      );
      expect(board.nextBoundary, at(0, 14));
    });

    test('a session in progress contributes its end', () {
      final board = build(
        InboxSource(
          items: [item('a')],
          sessions: [session('now', 'a', at(0, 11, 30))],
        ),
      );
      expect(board.nextBoundary, at(0, 12, 30));
    });

    test(
      'with nothing upcoming (or far away) it is the next planner midnight',
      () {
        final midnight = at(1, 0);
        expect(build(InboxSource(items: [item('a')])).nextBoundary, midnight);
        final far = build(
          InboxSource(
            items: [item('a')],
            sessions: [session('far', 'a', at(5, 9))],
          ),
        );
        expect(far.nextBoundary, midnight);
      },
    );

    test('done, skipped, deleted and unlisted sessions are ignored', () {
      final board = build(
        InboxSource(
          items: [item('a')],
          sessions: [
            session('d', 'a', at(0, 13), status: TaskStatus.completed),
            session('s', 'a', at(0, 13), status: TaskStatus.skipped),
            session('x', 'a', at(0, 13), deletedAt: at(0, 1)),
            session('o', 'other', at(0, 13)),
          ],
        ),
      );
      expect(board.nextBoundary, at(1, 0));
    });

    test('at the boundary the status has changed (end == now is missed)', () {
      final source = InboxSource(
        items: [item('a')],
        sessions: [session('s', 'a', at(0, 14), minutes: 30)],
      );
      final before = build(source);
      expect(before.byId['a']!.status, InboxItemStatus.soon);
      final after = build(source, clock: at(0, 14, 30));
      expect(after.byId['a']!.status, InboxItemStatus.left);
      expect(after.nextBoundary, at(1, 0));
    });
  });

  group('equality (so a row rebuilds only when it changed)', () {
    test('building twice gives equal boards and equal views', () {
      final source = InboxSource(
        items: [item('a'), item('b')],
        sessions: [session('s', 'a', at(1, 9))],
      );
      final first = build(source);
      final second = build(source);
      expect(first, second);
      expect(first.byId['a'], second.byId['a']);
    });

    test('changing one idea leaves the other view equal', () {
      InboxSource sourceWith(DateTime start) => InboxSource(
        items: [item('a'), item('b')],
        sessions: [session('s1', 'a', start), session('s2', 'b', at(2, 9))],
      );
      final first = build(sourceWith(at(1, 9)));
      final second = build(sourceWith(at(1, 10)));
      expect(first == second, isFalse);
      expect(first.byId['a'] == second.byId['a'], isFalse);
      expect(first.byId['b'], second.byId['b']);
    });
  });
}
