import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/inbox/domain/inbox_dates.dart';
import 'package:personal_planner/features/inbox/domain/inbox_history.dart';

import '../../helpers/inbox_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late InboxHarness h;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    h = InboxHarness(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('readSource', () {
    test('ideas, sessions with tombstones, and nothing unlinked', () async {
      final open = await h.idea('Open idea');
      final deleted = await h.idea('Deleted idea');
      await h.tasks.deleteTask(deleted.id);
      final s1 = await h.session(open.id, start: h.at(1, 9));
      final s2 = await h.session(open.id, start: h.at(2, 9));
      await h.tasks.deleteTask(s2.id);
      await h.tasks.insertTask(
        Task(
          id: '',
          title: 'Plain Day task',
          startTime: h.at(1, 9),
          endTime: h.at(1, 10),
          createdAt: h.now,
          updatedAt: h.now,
        ),
      );

      final source = await h.inbox.readSource();
      expect(source.items.map((i) => i.id), [open.id]);
      expect(source.items.single.text, 'Open idea');
      expect(source.sessions.map((s) => s.id), unorderedEquals([s1.id, s2.id]));
      final tombstone = source.sessions.singleWhere((s) => s.id == s2.id);
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.itemId, open.id);
      expect(tombstone.start!.isUtc, isTrue);
    });

    test('an idea in a status the old list hides is not an idea', () async {
      final idea = await h.idea('Cancelled long ago');
      await db.customStatement(
        "UPDATE tasks SET status = 'cancelled' WHERE id = ?",
        [idea.id],
      );
      expect((await h.inbox.readSource()).items, isEmpty);
    });

    test('saved Review reasons are read by planner date and trimmed', () async {
      final idea = await h.idea('Errand');
      final missed = await h.session(idea.id, start: h.at(-1, 9));
      final other = await h.session(idea.id, start: h.at(-2, 9));
      final done = await h.session(
        idea.id,
        start: h.at(-3, 9),
        status: TaskStatus.completed,
      );
      await h.saveReviewReason('2026-10-11', {
        missed.id: '  Ran out of time ',
        // A reason filed under another day is not the Review day's reason.
        other.id: 'wrong day',
        done.id: 'never read',
      });
      final source = await h.inbox.readSource();
      expect(source.reasons, {missed.id: 'Ran out of time'});
    });

    test('a blank saved reason is not a reason', () async {
      final idea = await h.idea('Errand');
      final missed = await h.session(idea.id, start: h.at(-1, 9));
      await h.saveReviewReason('2026-10-11', {missed.id: '   '});
      expect((await h.inbox.readSource()).reasons, isEmpty);
    });

    test(
      'experiments named in a history are read; a missing one is absent',
      () async {
        final idea = await h.idea('Run more');
        final experiments = ExperimentRepository(db);
        final created = await experiments.createExperiment(
          name: 'Running',
          startDate: '2026-10-12',
          endDate: '2026-11-10',
          weekdayTargetMin: 30,
          weekendTargetMin: 30,
          checkInEveryDays: 7,
        );
        await h.inbox.markBecameExperiment(idea.id, created.id, h.now);
        final gone = await h.idea('Gone experiment');
        await h.inbox.markBecameExperiment(
          gone.id,
          'experiment:missing',
          h.now,
        );

        final source = await h.inbox.readSource();
        expect(source.experiments.keys, [created.id]);
        final facts = source.experiments[created.id]!;
        expect(facts.name, 'Running');
        expect(facts.startDate, '2026-10-12');
        expect(facts.endDate, '2026-11-10');
        expect(facts.status, ExperimentStatus.running);
      },
    );

    test('two reads of unchanged data are equal (so no rebuild)', () async {
      final idea = await h.idea('Same');
      await h.session(idea.id, start: h.at(1, 9));
      expect(await h.inbox.readSource(), await h.inbox.readSource());
    });
  });

  group('createSession', () {
    test(
      'plans a linked task from the idea text and clears the due date',
      () async {
        final idea = await h.idea(
          'Buy a lamp\n\nfor the desk',
          dueDate: '2026-10-14',
        );
        final session = await h.inbox.createSession(
          idea.id,
          h.at(2, 18),
          h.at(2, 19),
          now: h.now,
        );
        expect(session.id.length, 36);
        expect(session.id[14], '7', reason: 'UUIDv7');
        expect(session.title, 'Buy a lamp');
        expect(session.description, 'for the desk');
        expect(session.inboxItemId, idea.id);
        expect(session.isInbox, isFalse);
        expect(session.status, TaskStatus.planned);
        expect(session.createdAt, sameInstant(h.now));
        final reloaded = await h.reload(idea.id);
        expect(reloaded.isInbox, isTrue);
        expect(reloaded.dueDate, isNull);
      },
    );

    test(
      'a given title and description win; an empty description is null',
      () async {
        final idea = await h.idea('Buy a lamp\nfor the desk');
        final session = await h.inbox.createSession(
          idea.id,
          h.at(2, 18),
          h.at(2, 19),
          now: h.now,
          title: 'Lamp run',
          description: '   ',
        );
        expect(session.title, 'Lamp run');
        expect(session.description, isNull);
      },
    );

    test('does not touch an idea without a due date', () async {
      final idea = await h.idea('No date');
      final revision = await h.revisionOf(idea.id);
      await h.inbox.createSession(idea.id, h.at(1, 9), h.at(1, 10), now: h.now);
      expect(await h.revisionOf(idea.id), revision);
    });

    test(
      'retrying the same session id with the same values is a no-op',
      () async {
        final idea = await h.idea('Retry');
        final first = await h.inbox.createSession(
          idea.id,
          h.at(1, 9),
          h.at(1, 10),
          now: h.now,
          sessionId: 'session-fixed',
        );
        final second = await h.inbox.createSession(
          idea.id,
          h.at(1, 9),
          h.at(1, 10),
          now: h.now,
          sessionId: 'session-fixed',
        );
        expect(second.id, first.id);
        expect(await h.sessionsOf(idea.id), hasLength(1));
        await expectLater(
          h.inbox.createSession(
            idea.id,
            h.at(1, 11),
            h.at(1, 12),
            now: h.now,
            sessionId: 'session-fixed',
          ),
          throwsStateError,
        );
      },
    );

    test('refuses a missing, deleted, scheduled or closed idea', () async {
      await expectLater(
        h.inbox.createSession('nope', h.at(1, 9), h.at(1, 10), now: h.now),
        throwsStateError,
      );
      final deleted = await h.idea('Deleted');
      await h.tasks.deleteTask(deleted.id);
      await expectLater(
        h.inbox.createSession(deleted.id, h.at(1, 9), h.at(1, 10), now: h.now),
        throwsStateError,
      );
      final dayTask = await h.session(
        (await h.idea('Parent')).id,
        start: h.at(1, 9),
      );
      await expectLater(
        h.inbox.createSession(dayTask.id, h.at(1, 9), h.at(1, 10), now: h.now),
        throwsStateError,
      );
      final closed = await h.idea('Closed');
      await h.inbox.closeItem(closed.id, 'Not needed', h.now);
      await expectLater(
        h.inbox.createSession(closed.id, h.at(1, 9), h.at(1, 10), now: h.now),
        throwsStateError,
      );
    });
  });

  group('saveDates (plan 9.A)', () {
    group('step 1: the idea must be open', () {
      test('missing, deleted, not an idea, closed', () async {
        const message =
            'This idea changed elsewhere. Close it and open it again.';
        Matcher changed() => throwsA(
          isA<StateError>().having((e) => e.message, 'message', message),
        );
        await expectLater(h.inbox.saveDates('nope', [], h.now), changed());
        final deleted = await h.idea('Deleted');
        await h.tasks.deleteTask(deleted.id);
        await expectLater(h.inbox.saveDates(deleted.id, [], h.now), changed());
        final plain = await h.tasks.insertTask(
          Task(
            id: '',
            title: 'Plain',
            startTime: h.at(1, 9),
            endTime: h.at(1, 10),
            createdAt: h.now,
            updatedAt: h.now,
          ),
        );
        await expectLater(h.inbox.saveDates(plain.id, [], h.now), changed());
        final closed = await h.idea('Closed');
        await h.inbox.closeItem(closed.id, 'Not needed', h.now);
        await expectLater(
          h.inbox.saveDates(closed.id, [h.slot(1, 9)], h.now),
          changed(),
        );
      });
    });

    group('step 2: slots are validated before anything is written', () {
      late Task idea;
      setUp(() async {
        idea = await h.idea('Validate me');
        await h.session(idea.id, start: h.at(3, 9));
      });

      Future<void> refused(List<InboxSlot> slots, String text) async {
        final before = await h.sessionsOf(idea.id);
        await expectLater(
          h.inbox.saveDates(idea.id, slots, h.now),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains(text),
            ),
          ),
        );
        expect(
          (await h.sessionsOf(idea.id)).map((t) => t.id),
          before.map((t) => t.id),
        );
      }

      test('a time that has passed (today 11:00, and now exactly)', () async {
        await refused([h.slot(0, 11)], 'has not passed');
        await refused([h.slot(0, 12)], 'has not passed');
      });

      test('a date outside today..today+13', () async {
        await refused([h.slot(14, 9)], '2 weeks');
        await refused([h.slot(-1, 9)], 'has not passed');
      });

      test('a length that is not 30, 60, 90 or 120', () async {
        await refused([h.slot(1, 9, minutes: 45)], 'Length');
      });

      test('more than 14 slots, and two slots on one date', () async {
        await refused([for (var i = 0; i < 15; i++) h.slot(i, 18)], 'at most');
        await refused([h.slot(1, 9), h.slot(1, 15)], 'only once');
      });

      test(
        '13 days ahead is the last allowed day; today later is allowed',
        () async {
          final summary = await h.inbox.saveDates(idea.id, [
            h.slot(0, 13),
            h.slot(13, 9),
          ], h.now);
          expect(summary.created, 2);
        },
      );
    });

    group('step 3: only replaceable sessions are ever touched', () {
      test(
        'started, done, skipped, carried and after-window sessions stay',
        () async {
          final idea = await h.idea('Locked');
          final started = await h.session(
            idea.id,
            start: h.at(0, 11, 30),
            minutes: 60,
            status: TaskStatus.inProgress,
          );
          final done = await h.session(
            idea.id,
            start: h.at(1, 9),
            status: TaskStatus.completed,
          );
          final skipped = await h.session(
            idea.id,
            start: h.at(2, 9),
            status: TaskStatus.skipped,
          );
          final cancelled = await h.session(
            idea.id,
            start: h.at(3, 9),
            status: TaskStatus.cancelled,
          );
          final inProgressFuture = await h.session(
            idea.id,
            start: h.at(4, 9),
            status: TaskStatus.inProgress,
          );
          final after = await h.session(idea.id, start: h.at(20, 9));
          final carriedFrom = await h.session(
            idea.id,
            start: h.at(5, 9),
            status: TaskStatus.rescheduled,
          );
          final locked = [
            started,
            done,
            skipped,
            cancelled,
            inProgressFuture,
            after,
            carriedFrom,
          ];
          final revisions = {
            for (final t in locked) t.id: await h.revisionOf(t.id),
          };

          await h.inbox.saveDates(idea.id, [h.slot(6, 9)], h.now);

          for (final t in locked) {
            final reloaded = await h.reload(t.id);
            expect(reloaded.deletedAt, isNull, reason: t.title);
            expect(await h.revisionOf(t.id), revisions[t.id], reason: t.id);
            expect(reloaded.status, t.status);
          }
        },
      );
    });

    group('step 4: a session per picked date', () {
      test('inserts a planned linked session with the idea text', () async {
        final idea = await h.idea('Call the bank\nask about the card');
        final summary = await h.inbox.saveDates(idea.id, [
          h.slot(2, 17, minutes: 90),
          h.slot(1, 9),
        ], h.now);
        expect(summary, const InboxSaveSummary(created: 2));
        final sessions = await h.sessionsOf(idea.id);
        expect(sessions, hasLength(2));
        for (final s in sessions) {
          expect(s.id[14], '7');
          expect(s.title, 'Call the bank');
          expect(s.description, 'ask about the card');
          expect(s.status, TaskStatus.planned);
          expect(s.isInbox, isFalse);
          expect(s.createdAt, sameInstant(h.now));
        }
        final byStart = [...sessions]
          ..sort((a, b) => a.startTime!.compareTo(b.startTime!));
        expect(byStart.first.startTime, sameInstant(h.at(1, 9)));
        expect(byStart.last.endTime, sameInstant(h.at(2, 18, 30)));
      });

      test(
        'an existing session on a picked date is moved, keeping its id',
        () async {
          final idea = await h.idea('Move me');
          final existing = await h.session(idea.id, start: h.at(1, 9));
          final summary = await h.inbox.saveDates(idea.id, [
            h.slot(1, 15, minutes: 30),
          ], h.now);
          expect(summary, const InboxSaveSummary(moved: 1));
          final moved = await h.reload(existing.id);
          expect(moved.startTime, sameInstant(h.at(1, 15)));
          expect(moved.endTime, sameInstant(h.at(1, 15, 30)));
          expect(await h.sessionsOf(idea.id), hasLength(1));
        },
      );

      test(
        'an identical slot writes nothing (no revision, no sync row)',
        () async {
          final idea = await h.idea('Same slot');
          final existing = await h.session(idea.id, start: h.at(1, 9));
          final revision = await h.revisionOf(existing.id);
          final log = await h.syncLogCount();
          final summary = await h.inbox.saveDates(idea.id, [
            h.slot(1, 9),
          ], h.now);
          expect(summary, const InboxSaveSummary());
          expect(await h.revisionOf(existing.id), revision);
          expect(await h.syncLogCount(), log);
        },
      );

      test('a second replaceable session on one date is dropped', () async {
        final idea = await h.idea('Two on a day');
        final first = await h.session(idea.id, start: h.at(1, 9));
        final second = await h.session(idea.id, start: h.at(1, 14));
        final summary = await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        expect(summary, const InboxSaveSummary(dropped: 1));
        expect((await h.reload(first.id)).deletedAt, isNull);
        expect((await h.reload(second.id)).deletedAt, isNotNull);
      });
    });

    group('step 5: unpicked replaceable sessions are dropped', () {
      test('soft-deleted, and a Clear + Save drops them all', () async {
        final idea = await h.idea('Drop me');
        final a = await h.session(idea.id, start: h.at(1, 9));
        final b = await h.session(idea.id, start: h.at(2, 9));
        final keep = await h.session(idea.id, start: h.at(3, 9));
        var summary = await h.inbox.saveDates(idea.id, [h.slot(3, 9)], h.now);
        expect(summary, const InboxSaveSummary(dropped: 2));
        expect((await h.reload(a.id)).deletedAt, isNotNull);
        expect((await h.reload(b.id)).deletedAt, isNotNull);
        expect((await h.reload(keep.id)).deletedAt, isNull);

        summary = await h.inbox.saveDates(idea.id, [], h.now);
        expect(summary, const InboxSaveSummary(dropped: 1));
        expect((await h.reload(keep.id)).deletedAt, isNotNull);
      });
    });

    group('step 6: missed sessions', () {
      test(
        'with a slot they are carried to the earliest slot session',
        () async {
          final idea = await h.idea('Carry me');
          final older = await h.session(idea.id, start: h.at(-2, 9));
          final newer = await h.session(idea.id, start: h.at(-1, 9));
          final summary = await h.inbox.saveDates(idea.id, [
            h.slot(3, 9),
            h.slot(1, 9),
          ], h.now);
          expect(summary.carried, 2);
          expect(summary.created, 2);
          final sessions = await h.sessionsOf(idea.id);
          final target = sessions.firstWhere((s) => s.startTime == h.at(1, 9));
          for (final id in [older.id, newer.id]) {
            final carried = await h.reload(id);
            expect(carried.status, TaskStatus.rescheduled);
            expect(carried.rescheduledToId, target.id);
          }
          // The newest missed one becomes the target's origin.
          expect((await h.reload(target.id)).rescheduledFromId, newer.id);
        },
      );

      test('a kept slot session can be the carry target', () async {
        final idea = await h.idea('Carry onto a kept one');
        final missed = await h.session(idea.id, start: h.at(-1, 9));
        final kept = await h.session(idea.id, start: h.at(1, 9));
        await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        expect((await h.reload(missed.id)).rescheduledToId, kept.id);
        expect((await h.reload(kept.id)).rescheduledFromId, missed.id);
      });

      test('an origin the target already has is kept', () async {
        final idea = await h.idea('Already linked');
        final origin = await h.session(
          idea.id,
          start: h.at(-5, 9),
          status: TaskStatus.rescheduled,
        );
        final missed = await h.session(idea.id, start: h.at(-1, 9));
        final kept = await h.session(idea.id, start: h.at(1, 9));
        await h.tasks.updateTask(kept.copyWith(rescheduledFromId: origin.id));
        await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        expect((await h.reload(missed.id)).rescheduledToId, kept.id);
        expect((await h.reload(kept.id)).rescheduledFromId, origin.id);
      });

      test('an in-progress session that has ended counts as missed', () async {
        final idea = await h.idea('Was in progress');
        final missed = await h.session(
          idea.id,
          start: h.at(0, 8),
          status: TaskStatus.inProgress,
        );
        await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        expect((await h.reload(missed.id)).status, TaskStatus.rescheduled);
      });

      test(
        'without a slot they become skipped, and no link is written',
        () async {
          final idea = await h.idea('No dates for now');
          final missed = await h.session(idea.id, start: h.at(-1, 9));
          final summary = await h.inbox.saveDates(idea.id, [], h.now);
          expect(summary, const InboxSaveSummary(skipped: 1));
          final reloaded = await h.reload(missed.id);
          expect(reloaded.status, TaskStatus.skipped);
          expect(reloaded.rescheduledToId, isNull);
        },
      );

      test(
        'a failure after earlier writes rolls the whole save back',
        () async {
          final idea = await h.idea('Atomic');
          final missed = await h.session(idea.id, start: h.at(-1, 9));
          final kept = await h.session(idea.id, start: h.at(1, 9));
          // kept -> missed already; carrying missed onto kept would be a cycle.
          await h.tasks.updateTask(kept.copyWith(rescheduledToId: missed.id));
          final before = await h.sessionsOf(idea.id);
          final log = await h.syncLogCount();
          await expectLater(
            h.inbox.saveDates(idea.id, [h.slot(1, 9), h.slot(2, 9)], h.now),
            throwsStateError,
          );
          expect(await h.sessionsOf(idea.id), hasLength(before.length));
          expect((await h.reload(missed.id)).status, TaskStatus.planned);
          expect(await h.syncLogCount(), log);
        },
      );
    });

    group('step 7: the legacy due date', () {
      test('is cleared by Save, even with no dates', () async {
        final idea = await h.idea('Dated', dueDate: '2026-10-14');
        await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        expect((await h.reload(idea.id)).dueDate, isNull);
        final other = await h.idea('Dated too', dueDate: '2026-10-15');
        await h.inbox.saveDates(other.id, [], h.now);
        expect((await h.reload(other.id)).dueDate, isNull);
      });

      test('an idea without one is not written', () async {
        final idea = await h.idea('Undated');
        final revision = await h.revisionOf(idea.id);
        await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        expect(await h.revisionOf(idea.id), revision);
      });
    });
  });

  group('close it, let go, experiment, bring back', () {
    Future<({Task idea, Task future, Task missed, Task started, Task done})>
    ideaWithSessions() async {
      final idea = await h.idea('Wrap up the garage');
      final done = await h.session(
        idea.id,
        start: h.at(-3, 9),
        status: TaskStatus.completed,
      );
      final missed = await h.session(idea.id, start: h.at(-1, 9));
      final started = await h.session(
        idea.id,
        start: h.at(0, 11, 30),
        minutes: 60,
      );
      final future = await h.session(idea.id, start: h.at(2, 9));
      return (
        idea: idea,
        future: future,
        missed: missed,
        started: started,
        done: done,
      );
    }

    test(
      'close: future dropped, missed skipped, started and done untouched',
      () async {
        final c = await ideaWithSessions();
        await h.inbox.closeItem(c.idea.id, '  Not worth it  ', h.now);

        expect((await h.reload(c.future.id)).deletedAt, isNotNull);
        final missed = await h.reload(c.missed.id);
        expect(missed.status, TaskStatus.skipped);
        expect(missed.deletedAt, isNull);
        final started = await h.reload(c.started.id);
        expect(started.status, TaskStatus.planned);
        expect(started.deletedAt, isNull);
        expect((await h.reload(c.done.id)).status, TaskStatus.completed);

        final idea = await h.reload(c.idea.id);
        expect(idea.isInbox, isTrue);
        expect(idea.inboxHistory, hasLength(1));
        final event = idea.inboxHistory.single;
        expect(event.kind, InboxCloseKind.closed);
        expect(event.reason, 'Not worth it');
        expect(event.at, sameInstant(h.now.toUtc()));
        expect(event.reopenedAt, isNull);
      },
    );

    test(
      'close: a blank, spaces-only or 201-character reason is refused',
      () async {
        final c = await ideaWithSessions();
        for (final reason in ['', '   ', 'x' * 201]) {
          await expectLater(
            h.inbox.closeItem(c.idea.id, reason, h.now),
            throwsArgumentError,
            reason: '"${reason.length}"',
          );
        }
        expect((await h.reload(c.idea.id)).inboxHistory, isEmpty);
        expect((await h.reload(c.future.id)).deletedAt, isNull);
        expect((await h.reload(c.missed.id)).status, TaskStatus.planned);
      },
    );

    test(
      'close: 200 characters is allowed, and counted in code points',
      () async {
        final a = await h.idea('Exactly 200');
        await h.inbox.closeItem(a.id, 'x' * 200, h.now);
        final b = await h.idea('Emoji reason');
        await h.inbox.closeItem(b.id, '😀' * 200, h.now);
        expect(
          (await h.reload(b.id)).inboxHistory.single.reason!.runes.length,
          200,
        );
      },
    );

    test('close twice is refused; the history keeps one event', () async {
      final idea = await h.idea('Once');
      await h.inbox.closeItem(idea.id, 'Done with it', h.now);
      await expectLater(
        h.inbox.closeItem(idea.id, 'Again', h.now),
        throwsStateError,
      );
      expect((await h.reload(idea.id)).inboxHistory, hasLength(1));
    });

    test('let go: refused while any session is not dropped', () async {
      for (final status in [
        TaskStatus.completed,
        TaskStatus.planned,
        TaskStatus.skipped,
        TaskStatus.rescheduled,
      ]) {
        final idea = await h.idea('Has a ${status.name} session');
        final session = await h.session(
          idea.id,
          start: h.at(1, 9),
          status: status,
        );
        await expectLater(
          h.inbox.letGo(idea.id, null, h.now),
          throwsStateError,
          reason: status.name,
        );
        expect((await h.reload(idea.id)).inboxHistory, isEmpty);
        expect((await h.reload(session.id)).deletedAt, isNull);
      }
    });

    test(
      'let go: allowed with no sessions or only dropped ones; reason optional',
      () async {
        final plain = await h.idea('Never planned');
        await h.inbox.letGo(plain.id, '   ', h.now);
        final event = (await h.reload(plain.id)).inboxHistory.single;
        expect(event.kind, InboxCloseKind.letGo);
        expect(event.reason, isNull);

        final dropped = await h.idea('Planned then dropped');
        final session = await h.session(dropped.id, start: h.at(1, 9));
        await h.tasks.deleteTask(session.id);
        await h.inbox.letGo(dropped.id, ' Changed my mind ', h.now);
        expect(
          (await h.reload(dropped.id)).inboxHistory.single.reason,
          'Changed my mind',
        );
      },
    );

    test(
      'experiment: closes like Close it but stores the id and no reason',
      () async {
        final c = await ideaWithSessions();
        await h.inbox.markBecameExperiment(c.idea.id, 'experiment:abc', h.now);
        final event = (await h.reload(c.idea.id)).inboxHistory.single;
        expect(event.kind, InboxCloseKind.experiment);
        expect(event.experimentId, 'experiment:abc');
        expect(event.reason, isNull);
        expect((await h.reload(c.future.id)).deletedAt, isNotNull);
        expect((await h.reload(c.missed.id)).status, TaskStatus.skipped);
        expect((await h.reload(c.started.id)).status, TaskStatus.planned);
        await expectLater(
          h.inbox.markBecameExperiment((await h.idea('x')).id, '  ', h.now),
          throwsArgumentError,
        );
      },
    );

    test('clock skew: close and bring back succeed when this clock is behind '
        'the last event', () async {
      final idea = await h.idea('Skewed idea');
      final ahead = h.now.add(const Duration(days: 10));
      await h.inbox.letGo(idea.id, 'Device A closed it', ahead);
      // This device's clock (h.now) is behind the event device A wrote.
      await h.inbox.bringBack(idea.id, h.now);
      var history = (await h.reload(idea.id)).inboxHistory;
      expect(history.single.reopenedAt, sameInstant(ahead.toUtc()));

      await h.inbox.closeItem(idea.id, 'Closed on the slow clock', h.now);
      history = (await h.reload(idea.id)).inboxHistory;
      expect(history, hasLength(2));
      expect(history.last.at.isBefore(history.first.at), isFalse);
      expect(InboxHistory.isClosed(history), isTrue);
    });

    test(
      'bring back: sets reopened_at, keeps the event, sessions untouched',
      () async {
        final c = await ideaWithSessions();
        await h.inbox.closeItem(c.idea.id, 'Not now', h.now);
        final later = h.now.add(const Duration(hours: 2));
        await h.inbox.bringBack(c.idea.id, later);

        final idea = await h.reload(c.idea.id);
        expect(idea.inboxHistory, hasLength(1));
        expect(idea.inboxHistory.single.reason, 'Not now');
        expect(idea.inboxHistory.single.reopenedAt, sameInstant(later.toUtc()));
        expect(InboxHistory.isClosed(idea.inboxHistory), isFalse);
        // The dropped and skipped sessions stay as the close left them.
        expect((await h.reload(c.future.id)).deletedAt, isNotNull);
        expect((await h.reload(c.missed.id)).status, TaskStatus.skipped);

        await expectLater(
          h.inbox.bringBack(c.idea.id, later),
          throwsStateError,
        );
      },
    );

    test('closing again after Bring back appends a second event', () async {
      final idea = await h.idea('Back and forth');
      await h.inbox.closeItem(idea.id, 'First', h.now);
      await h.inbox.bringBack(idea.id, h.now.add(const Duration(hours: 1)));
      await h.inbox.closeItem(
        idea.id,
        'Second',
        h.now.add(const Duration(hours: 2)),
      );
      final history = (await h.reload(idea.id)).inboxHistory;
      expect(history.map((e) => e.reason), ['First', 'Second']);
      expect(history.first.reopenedAt, isNotNull);
      expect(history.last.reopenedAt, isNull);
    });

    test('closed ideas leave Day\'s panel; Bring back returns them', () async {
      final idea = await h.idea('Panel check');
      Future<List<String>> panel() async => [
        for (final item in await h.inbox.watchInboxItems(h.now).first)
          item.task.id,
      ];
      expect(await panel(), [idea.id]);
      await h.inbox.closeItem(idea.id, 'Gone', h.now);
      expect(await panel(), isEmpty);
      await h.inbox.bringBack(idea.id, h.now);
      expect(await panel(), [idea.id]);
    });
  });

  group('experiment hook (plan risk R5)', () {
    Future<Experiment> start(Future<void> Function(Experiment created) hook) =>
        ExperimentRepository(db).createExperiment(
          name: 'Garage',
          startDate: '2026-10-12',
          endDate: '2026-11-10',
          weekdayTargetMin: 30,
          weekendTargetMin: 30,
          checkInEveryDays: 7,
          inSameTransaction: hook,
        );

    test('the idea closes as an experiment in the same transaction', () async {
      final idea = await h.idea('Tidy the garage');
      final session = await h.session(idea.id, start: h.at(2, 9));
      final created = await start(
        (e) => h.inbox.markBecameExperiment(idea.id, e.id, h.now),
      );
      final event = (await h.reload(idea.id)).inboxHistory.single;
      expect(event.kind, InboxCloseKind.experiment);
      expect(event.experimentId, created.id);
      expect((await h.reload(session.id)).deletedAt, isNotNull);
    });

    test(
      'a failing hook leaves no experiment, no tag and the idea unchanged',
      () async {
        final idea = await h.idea('Tidy the garage');
        final session = await h.session(idea.id, start: h.at(2, 9));
        final missed = await h.session(idea.id, start: h.at(-1, 9));
        final revision = await h.revisionOf(idea.id);
        final log = await h.syncLogCount();
        await h.inbox.closeItem((await h.idea('Other')).id, 'x', h.now);
        final logAfterOther = await h.syncLogCount();
        expect(logAfterOther, greaterThan(log));

        // The hook writes (sessions are dropped and skipped), then fails.
        await expectLater(
          start((e) async {
            await h.inbox.markBecameExperiment(idea.id, e.id, h.now);
            throw StateError('hook failed after writing');
          }),
          throwsStateError,
        );
        expect(await db.select(db.experiments).get(), isEmpty);
        expect(await db.select(db.tags).get(), isEmpty);
        final reloaded = await h.reload(idea.id);
        expect(reloaded.inboxHistory, isEmpty);
        expect(await h.revisionOf(idea.id), revision);
        expect((await h.reload(session.id)).deletedAt, isNull);
        expect((await h.reload(missed.id)).status, TaskStatus.planned);
        expect(await h.syncLogCount(), logAfterOther);
      },
    );

    test(
      'an idea closed meanwhile makes the hook throw and nothing is created',
      () async {
        final idea = await h.idea('Already closed');
        await h.inbox.closeItem(idea.id, 'Done', h.now);
        await expectLater(
          start((e) => h.inbox.markBecameExperiment(idea.id, e.id, h.now)),
          throwsStateError,
        );
        expect(await db.select(db.experiments).get(), isEmpty);
        expect((await h.reload(idea.id)).inboxHistory, hasLength(1));
      },
    );
  });

  group('rescheduleOverdue keeps the link (a carried session)', () {
    test('the successor stays linked to a live idea', () async {
      final idea = await h.idea('Carry');
      final missed = await h.session(idea.id, start: h.at(-1, 9));
      final successor = await h.inbox.rescheduleOverdue(
        missed.id,
        h.at(1, 9),
        h.at(1, 10),
      );
      expect(successor.inboxItemId, idea.id);
      expect(successor.rescheduledFromId, missed.id);
      expect((await h.reload(missed.id)).status, TaskStatus.rescheduled);
    });

    test('a deleted idea makes the successor a plain Day task', () async {
      final idea = await h.idea('Gone');
      final missed = await h.session(idea.id, start: h.at(-1, 9));
      await h.tasks.deleteTask(idea.id);
      final successor = await h.inbox.rescheduleOverdue(
        missed.id,
        h.at(1, 9),
        h.at(1, 10),
      );
      expect(successor.inboxItemId, isNull);
      expect(successor.rescheduledFromId, missed.id);
    });
  });
}
