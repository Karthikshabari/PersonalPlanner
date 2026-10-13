import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/day_context/domain/break_day.dart';
import 'package:personal_planner/features/inbox/domain/inbox_board.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/task_outcome_service.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/inbox_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

/// The Inbox "N sessions without a reason" line must equal what Review shows
/// for the same database (plan matrix row "Review reasons"). Review's side is
/// computed with Review's own code: `TaskOutcomeService.forDay` for the rows,
/// `awaitsReason` for the rule, the saved daily review for the reasons and
/// `BreakDayRule` for break days. Nothing here copies the rule.
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

  /// Review's "without a reason" rows for every day in the window the tests
  /// use: rows that await a reason, on a day that is not a break day, with no
  /// saved non-blank reason.
  Future<({Set<String> ids, String? latestDate, Map<String, TaskOutcome> all})>
  reviewMissing() async {
    final contexts = await DayContextRepository(db).watchAll().first;
    final rule = BreakDayRule.defaults;
    final breakDates = rule.breakDates(contexts);
    final ids = <String>{};
    final all = <String, TaskOutcome>{};
    String? latest;
    for (var offset = -14; offset <= 3; offset++) {
      final day = h.at(offset, 0);
      final date = isoDateString(day);
      final rows = await TaskOutcomeService(db).forDay(day);
      final review = await ReviewRepository(db).getReviewForDate(day);
      for (final row in rows) {
        all[row.taskId] = row.outcome;
        if (breakDates.containsKey(date)) continue;
        final saved = review?.taskReasons[row.taskId]?.trim();
        final hasReason = saved != null && saved.isNotEmpty;
        if (awaitsReason(row.outcome, row.endTime, now: h.now) && !hasReason) {
          ids.add(row.taskId);
          if (latest == null || date.compareTo(latest) > 0) latest = date;
        }
      }
    }
    return (ids: ids, latestDate: latest, all: all);
  }

  Future<InboxBoard> inboxBoard() async {
    final contexts = await DayContextRepository(db).watchAll().first;
    return buildInboxBoard(
      await h.inbox.readSource(),
      now: h.now,
      breakDates: BreakDayRule.defaults.breakDates(contexts),
    );
  }

  Set<String> inboxIds(InboxBoard board) => {
    for (final view in board.byId.values)
      for (final session in view.sessions)
        if (session.needsReason) session.facts.id,
  };

  Future<void> saveReason(DateTime day, Map<String, String> reasons) =>
      ReviewRepository(db)
          .saveReviewDraft(date: day, mood: 3, note: '', taskReasons: reasons);

  // Each case seeds one idea with one session (or two), and says what both
  // sides must report. The expected count is stated, so a rule that drifts on
  // both sides at once is also caught.
  final cases =
      <
        ({
          String name,
          int expected,
          TaskOutcome? outcome,
          Future<void> Function(InboxHarness h, AppDatabase db) seed,
        })
      >[
        (
          name: 'a missed session with no reason',
          expected: 1,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(idea.id, start: h.at(-1, 9));
          },
        ),
        (
          name: 'a missed session with a saved reason',
          expected: 0,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(idea.id, start: h.at(-2, 9));
            await saveReason(h.at(-2, 0), {s.id: 'Ran late'});
          },
        ),
        (
          name: 'a reason typed in Review but never saved (draft) still counts',
          expected: 1,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(idea.id, start: h.at(-3, 9));
            // Review keeps the typed text in memory until Save. What is
            // stored is a review of that day with no reason for the session.
            await saveReason(h.at(-3, 0), const {});
          },
        ),
        (
          name: 'a stored blank reason is not a reason',
          expected: 1,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(idea.id, start: h.at(-3, 9));
            await h.saveReviewReason('2026-10-09', {s.id: '   '});
          },
        ),
        (
          name: 'a missed session on a break day',
          expected: 0,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(idea.id, start: h.at(-4, 9));
            await DayContextRepository(db)
                .save(isoDateString(h.at(-4, 0)), DayContextKind.holiday, null);
          },
        ),
        (
          name: 'a Partly done session (tracked time, not completed)',
          expected: 1,
          outcome: TaskOutcome.partlyDone,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(idea.id, start: h.at(-5, 9));
            await TimerService(db).setManualActual(s.id, 25);
          },
        ),
        (
          name: 'a carried session',
          expected: 1,
          outcome: TaskOutcome.rescheduled,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(
              idea.id,
              start: h.at(-6, 9),
              status: TaskStatus.rescheduled,
            );
          },
        ),
        (
          name: 'a skipped session',
          expected: 1,
          outcome: TaskOutcome.skipped,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(
              idea.id,
              start: h.at(-7, 9),
              status: TaskStatus.skipped,
            );
          },
        ),
        (
          name: 'a skipped session that has tracked time is Partly done',
          expected: 1,
          outcome: TaskOutcome.partlyDone,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(
              idea.id,
              start: h.at(-7, 9),
              status: TaskStatus.skipped,
            );
            await TimerService(db).setManualActual(s.id, 10);
          },
        ),
        (
          name: 'a cancelled session',
          expected: 1,
          outcome: TaskOutcome.cancelled,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(
              idea.id,
              start: h.at(-8, 9),
              status: TaskStatus.cancelled,
            );
          },
        ),
        (
          name: 'an in-progress block whose end has passed',
          expected: 1,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(
              idea.id,
              start: h.at(-1, 14),
              status: TaskStatus.inProgress,
            );
          },
        ),
        (
          name: 'a completed session never counts',
          expected: 0,
          outcome: TaskOutcome.completed,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(
              idea.id,
              start: h.at(-9, 9),
              status: TaskStatus.completed,
            );
          },
        ),
        (
          name: 'a session still to come never counts',
          expected: 0,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(idea.id, start: h.at(2, 9));
          },
        ),
        (
          name: 'a session that ends exactly now has ended',
          expected: 1,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(idea.id, start: h.at(0, 11));
          },
        ),
        (
          name: 'a dropped (deleted) session never counts',
          expected: 0,
          outcome: null,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(idea.id, start: h.at(-10, 9));
            await h.tasks.deleteTask(s.id);
          },
        ),
        (
          name: 'a late evening session is read on its own planner date',
          expected: 1,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            await h.session(idea.id, start: h.at(-2, 23, 30), minutes: 30);
          },
        ),
        (
          name: 'a late evening session with a saved reason on that date',
          expected: 0,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(
              idea.id,
              start: h.at(-2, 23, 30),
              minutes: 30,
            );
            await saveReason(h.at(-2, 0), {s.id: 'Fell asleep'});
          },
        ),
        (
          name: 'a session just after midnight with a saved reason',
          expected: 0,
          outcome: TaskOutcome.notStarted,
          seed: (h, db) async {
            final idea = await h.idea('Idea');
            final s = await h.session(
              idea.id,
              start: h.at(-3, 0, 15),
              minutes: 30,
            );
            await saveReason(h.at(-3, 0), {s.id: 'Overslept'});
          },
        ),
      ];

  group('the Review line equals Review\'s own count', () {
    for (final c in cases) {
      test(c.name, () async {
        await c.seed(h, db);
        final review = await reviewMissing();
        final board = await inboxBoard();

        expect(review.ids, hasLength(c.expected), reason: 'Review');
        expect(board.reasonsMissing.count, review.ids.length);
        expect(inboxIds(board), review.ids);
        expect(board.reasonsMissing.latestDate, review.latestDate);
        if (c.outcome != null) {
          // The case exercises the outcome it names.
          expect(review.all.values.single, c.outcome);
        }
      });
    }

    test('all cases together, in one database', () async {
      // Each case uses its own idea; sessions of different cases may share a
      // day, which Review and the Inbox both handle row by row.
      for (final c in cases) {
        await c.seed(h, db);
      }
      final review = await reviewMissing();
      final board = await inboxBoard();

      expect(review.ids, isNotEmpty);
      expect(board.reasonsMissing.count, review.ids.length);
      expect(inboxIds(board), review.ids);
      expect(board.reasonsMissing.latestDate, review.latestDate);
    });
  });
}
