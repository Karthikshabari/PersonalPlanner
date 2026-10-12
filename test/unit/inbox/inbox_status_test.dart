import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/features/inbox/domain/inbox_status.dart';

void main() {
  final now = DateTime.utc(2026, 10, 12, 12);
  final created = DateTime.utc(2026, 10, 1, 8);

  InboxSessionFacts session({
    String id = 's1',
    TaskStatus status = TaskStatus.planned,
    DateTime? start,
    DateTime? end,
    bool timed = true,
    DateTime? deletedAt,
    DateTime? createdAt,
  }) => InboxSessionFacts(
    id: id,
    itemId: 'item',
    title: 'Session',
    start: timed ? (start ?? now.add(const Duration(hours: 1))) : null,
    end: timed ? (end ?? now.add(const Duration(hours: 2))) : null,
    status: status,
    deletedAt: deletedAt,
    createdAt: createdAt ?? created,
  );

  InboxSessionFacts past({
    String id = 's1',
    TaskStatus status = TaskStatus.planned,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) => session(
    id: id,
    status: status,
    start: now.subtract(const Duration(hours: 3)),
    end: now.subtract(const Duration(hours: 2)),
    createdAt: createdAt,
    deletedAt: deletedAt,
  );

  InboxItemFacts item([List<InboxClosure> history = const []]) =>
      InboxItemFacts(
        id: 'item',
        text: 'Buy a lamp',
        createdAt: created,
        history: history,
      );

  InboxClosure closure({
    InboxCloseKind kind = InboxCloseKind.closed,
    required DateTime at,
    DateTime? reopenedAt,
  }) => InboxClosure(
    kind: kind,
    at: at,
    reason: kind == InboxCloseKind.closed ? 'Not needed' : null,
    experimentId: kind == InboxCloseKind.experiment ? 'experiment:t' : null,
    reopenedAt: reopenedAt,
  );

  group('sessionStatusOf (plan section 5)', () {
    test('S1 a deleted session is dropped, whatever its status', () {
      for (final status in TaskStatus.values) {
        expect(
          sessionStatusOf(session(status: status, deletedAt: now), now),
          InboxSessionStatus.dropped,
          reason: status.name,
        );
      }
    });

    test('S1 a session without a start or end is dropped (defensive)', () {
      expect(
        sessionStatusOf(session(timed: false), now),
        InboxSessionStatus.dropped,
      );
      final noEnd = InboxSessionFacts(
        id: 's',
        itemId: 'item',
        title: 't',
        start: now,
        status: TaskStatus.planned,
        createdAt: created,
      );
      expect(sessionStatusOf(noEnd, now), InboxSessionStatus.dropped);
    });

    test('S2 completed is done, also when finished late', () {
      expect(
        sessionStatusOf(session(status: TaskStatus.completed), now),
        InboxSessionStatus.done,
      );
      expect(
        sessionStatusOf(past(status: TaskStatus.completed), now),
        InboxSessionStatus.done,
      );
    });

    test('S3 rescheduled is carried', () {
      expect(
        sessionStatusOf(past(status: TaskStatus.rescheduled), now),
        InboxSessionStatus.carried,
      );
    });

    test('S4 skipped and cancelled are skipped', () {
      for (final status in [TaskStatus.skipped, TaskStatus.cancelled]) {
        expect(
          sessionStatusOf(past(status: status), now),
          InboxSessionStatus.skipped,
          reason: status.name,
        );
      }
    });

    test('S5 planned or in progress with end <= now is missed', () {
      for (final status in [TaskStatus.planned, TaskStatus.inProgress]) {
        expect(
          sessionStatusOf(past(status: status), now),
          InboxSessionStatus.missed,
          reason: status.name,
        );
      }
    });

    test('S5 end == now is already missed', () {
      final ends = session(
        start: now.subtract(const Duration(hours: 1)),
        end: now,
      );
      expect(sessionStatusOf(ends, now), InboxSessionStatus.missed);
      expect(
        sessionStatusOf(ends, now.subtract(const Duration(milliseconds: 1))),
        InboxSessionStatus.upcoming,
      );
    });

    test('S6 planned or in progress with end > now is upcoming', () {
      for (final status in [TaskStatus.planned, TaskStatus.inProgress]) {
        expect(
          sessionStatusOf(session(status: status), now),
          InboxSessionStatus.upcoming,
          reason: status.name,
        );
      }
      // A block that has started but not ended is still upcoming ("Now").
      expect(
        sessionStatusOf(
          session(
            start: now.subtract(const Duration(minutes: 10)),
            end: now.add(const Duration(minutes: 20)),
          ),
          now,
        ),
        InboxSessionStatus.upcoming,
      );
    });
  });

  group('itemStatusOf (plan section 5)', () {
    test('I1 a history whose last event is not reopened is closed', () {
      for (final kind in InboxCloseKind.values) {
        expect(
          itemStatusOf(item([closure(kind: kind, at: now)]), const [], now),
          InboxItemStatus.closed,
          reason: kind.name,
        );
      }
    });

    test('I1 closed wins over upcoming, missed and done sessions', () {
      final status = itemStatusOf(item([closure(at: now)]), [
        session(id: 'a'),
        past(id: 'b'),
        past(id: 'c', status: TaskStatus.completed),
      ], now);
      expect(status, InboxItemStatus.closed);
    });

    test('I2 any upcoming session makes the item soon', () {
      expect(itemStatusOf(item(), [session()], now), InboxItemStatus.soon);
    });

    test('I2 soon wins over missed', () {
      expect(
        itemStatusOf(item(), [past(id: 'a'), session(id: 'b')], now),
        InboxItemStatus.soon,
      );
    });

    test('I3 a missed session with nothing upcoming leaves the item left', () {
      expect(itemStatusOf(item(), [past()], now), InboxItemStatus.left);
    });

    test('I3 left wins over done', () {
      expect(
        itemStatusOf(item(), [
          past(id: 'a'),
          past(id: 'b', status: TaskStatus.completed),
        ], now),
        InboxItemStatus.left,
      );
    });

    test('I4 a done session with nothing open finishes the item', () {
      expect(
        itemStatusOf(item(), [past(status: TaskStatus.completed)], now),
        InboxItemStatus.finished,
      );
    });

    test('I4 a late completion of a missed session finishes the item', () {
      final late = past();
      expect(itemStatusOf(item(), [late], now), InboxItemStatus.left);
      expect(
        itemStatusOf(item(), [
          late.copyWith(status: TaskStatus.completed),
        ], now),
        InboxItemStatus.finished,
      );
    });

    test('I5 no sessions is an idea', () {
      expect(itemStatusOf(item(), const [], now), InboxItemStatus.idea);
    });

    test('I5 only dropped, skipped or carried sessions is an idea', () {
      expect(
        itemStatusOf(item(), [
          past(id: 'a', deletedAt: now),
          past(id: 'b', status: TaskStatus.skipped),
          past(id: 'c', status: TaskStatus.cancelled),
          past(id: 'd', status: TaskStatus.rescheduled),
        ], now),
        InboxItemStatus.idea,
      );
    });

    test('an item whose only session was skipped goes back to Ideas', () {
      expect(
        itemStatusOf(item(), [past(status: TaskStatus.skipped)], now),
        InboxItemStatus.idea,
      );
    });

    test('a deleted done session no longer finishes the item', () {
      expect(
        itemStatusOf(item(), [
          past(status: TaskStatus.completed, deletedAt: now),
        ], now),
        InboxItemStatus.idea,
      );
    });

    test('Bring back with only old done sessions lands in Ideas', () {
      final reopenedAt = now.subtract(const Duration(hours: 1));
      final oldDone = past(
        status: TaskStatus.completed,
        createdAt: now.subtract(const Duration(days: 5)),
      );
      expect(
        itemStatusOf(
          item([
            closure(
              at: now.subtract(const Duration(days: 1)),
              reopenedAt: reopenedAt,
            ),
          ]),
          [oldDone],
          now,
        ),
        InboxItemStatus.idea,
      );
    });

    test('Bring back, then a new done session, is finished', () {
      final reopenedAt = now.subtract(const Duration(hours: 2));
      final history = [
        closure(
          at: now.subtract(const Duration(days: 1)),
          reopenedAt: reopenedAt,
        ),
      ];
      final newDone = past(
        status: TaskStatus.completed,
        createdAt: now.subtract(const Duration(hours: 1)),
      );
      expect(
        itemStatusOf(item(history), [newDone], now),
        InboxItemStatus.finished,
      );
    });

    test('a done session created at the Bring back instant is still old', () {
      final reopenedAt = now.subtract(const Duration(hours: 2));
      final history = [
        closure(
          at: now.subtract(const Duration(days: 1)),
          reopenedAt: reopenedAt,
        ),
      ];
      final sameInstant = past(
        status: TaskStatus.completed,
        createdAt: reopenedAt,
      );
      expect(
        itemStatusOf(item(history), [sameInstant], now),
        InboxItemStatus.idea,
      );
    });

    test('Add days on a finished item makes it soon', () {
      expect(
        itemStatusOf(item(), [
          past(id: 'a', status: TaskStatus.completed),
          session(id: 'b'),
        ], now),
        InboxItemStatus.soon,
      );
    });

    test('a closed-again item uses the latest Bring back for old work', () {
      final history = [
        closure(
          at: now.subtract(const Duration(days: 3)),
          reopenedAt: now.subtract(const Duration(days: 2)),
        ),
        closure(
          kind: InboxCloseKind.letGo,
          at: now.subtract(const Duration(days: 1)),
          reopenedAt: now.subtract(const Duration(hours: 5)),
        ),
      ];
      final doneBetween = past(
        status: TaskStatus.completed,
        createdAt: now.subtract(const Duration(days: 1, hours: 12)),
      );
      expect(
        itemStatusOf(item(history), [doneBetween], now),
        InboxItemStatus.idea,
      );
    });
  });
}
