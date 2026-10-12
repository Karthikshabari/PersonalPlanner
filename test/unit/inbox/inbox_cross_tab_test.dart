// The point of Inbox Phase 3 (plan section 6): the same Day rows feed Day,
// Review, Insights and Experiments, so closing an idea or carrying a missed
// session must change only what it should and never count anything twice.
//
// The scenario (fixed clock: Monday 2026-10-12 12:00, planner zone):
//   idea "Sort the garage" with three sessions
//     done    Fri Oct 9  09:00-10:00  completed
//     missed  Sat Oct 10 09:00-10:00  planned, ended
//     future  Wed Oct 14 09:00-10:00  planned
//   plain Day tasks next to each, and a running experiment with one tagged
//   completed block, so a double count would show.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/domain/experiment_dashboard.dart';
import 'package:personal_planner/features/inbox/domain/inbox_commands.dart';
import 'package:personal_planner/features/review/domain/review_overview.dart';
import 'package:personal_planner/features/review/domain/task_outcome_service.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/domain/weekly_review_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timeline/presentation/providers/day_tasks_provider.dart';

import '../../helpers/inbox_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

/// Everything the other tabs show about the scenario, as comparable values.
class Snap {
  Snap({
    required this.outcomes,
    required this.weeks,
    required this.overview,
    required this.consistency,
    required this.insightsWeeks,
    required this.visible,
    required this.experiments,
  });

  /// Review > Daily: date -> task id -> "outcome|planned|tracked".
  final Map<String, Map<String, String>> outcomes;

  /// Review > Weekly numbers: week -> (total, completed, skipped, rescheduled).
  final Map<String, (int, int, int, int)> weeks;

  /// Review > Overview: date -> (total, completed), up to today.
  final Map<String, (int, int)> overview;

  /// Insights Consistency, days before today: date -> (planned, completed
  /// planned, actual) minutes.
  final Map<String, (int, int, int)> consistency;

  /// Insights week totals: week -> (planned, completed planned, actual).
  final Map<String, (int, int, int)> insightsWeeks;

  /// Day: date -> ids on the timeline (carried predecessors hidden).
  final Map<String, List<String>> visible;

  /// Insights > Experiments, one line per experiment.
  final List<String> experiments;
}

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late InboxHarness h;
  late Task idea;
  late Task done;
  late Task missed;
  late Task future;
  late Task plainDone;
  late Task plainMissed;
  late Task plainFuture;

  const dates = [-3, -2, 2, 3]; // Oct 9, 10, 14, 15

  String iso(int offset) => isoDateString(h.at(offset, 0));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    h = InboxHarness(db);
    idea = await h.idea('Sort the garage\nstart with the shelves');
    done = await h.session(
      idea.id,
      start: h.at(-3, 9),
      status: TaskStatus.completed,
      title: 'Sort the garage',
    );
    missed = await h.session(
      idea.id,
      start: h.at(-2, 9),
      title: 'Sort the garage',
    );
    future = await h.session(
      idea.id,
      start: h.at(2, 9),
      title: 'Sort the garage',
    );
    Future<Task> plain(
      int day,
      int hour,
      TaskStatus status, [
      String? tag,
    ]) async {
      final created = await h.tasks.insertTask(
        Task(
          id: '',
          title: 'Plain $day',
          startTime: h.at(day, hour),
          endTime: h.at(day, hour + 1),
          tagId: tag,
          createdAt: h.now,
          updatedAt: h.now,
        ),
      );
      return status == TaskStatus.planned
          ? created
          : h.tasks.updateTask(created.copyWith(status: status));
    }

    final experiment = await ExperimentRepository(db).createExperiment(
      name: 'Garage habit',
      startDate: '2026-10-05',
      endDate: '2026-11-03',
      weekdayTargetMin: 60,
      weekendTargetMin: 60,
      checkInEveryDays: 7,
    );
    plainDone = await plain(-3, 11, TaskStatus.completed, experiment.tagId);
    plainMissed = await plain(-2, 11, TaskStatus.planned);
    plainFuture = await plain(2, 11, TaskStatus.planned);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Snap> snap() async {
    final outcomes = <String, Map<String, String>>{};
    for (final offset in dates) {
      final rows = await TaskOutcomeService(db).forDay(h.at(offset, 0));
      outcomes[iso(offset)] = {
        for (final r in rows)
          r.taskId: '${r.outcome.name}|${r.plannedMinutes}|${r.trackedMinutes}',
      };
    }

    final currentWeek = startOfWeek(h.at(0, 0));
    final previousWeek = addDays(currentWeek, -7);
    final weeks = <String, (int, int, int, int)>{};
    for (final entry in {
      'previous': previousWeek,
      'current': currentWeek,
    }.entries) {
      final days = await WeeklyReviewService(db).loadWeek(entry.value);
      final numbers = computeWeeklyNumbers(days, now: h.now);
      weeks[entry.key] = (
        numbers.total,
        numbers.completed,
        numbers.skipped,
        numbers.rescheduled,
      );
    }

    final window = await ReviewOverviewService(db)
        .window(today: h.now, dayCount: 14);
    final overview = {
      for (final day in window)
        isoDateString(day.date): (day.totalTasks, day.completedTasks),
    };

    final insights = InsightsService(db);
    final currentInsights = await insights.compute(
      weekStart: currentWeek,
      now: h.now,
    );
    final previousInsights = await insights.compute(
      weekStart: previousWeek,
      now: h.now,
    );
    final today = startOfDay(h.now);
    final consistency = {
      for (final day in currentInsights.consistencyDays)
        if (day.date.isBefore(today))
          isoDateString(day.date): (
            day.plannedMinutes,
            day.completedPlannedMinutes,
            day.actualMinutes,
          ),
    };
    final insightsWeeks = {
      'previous': (
        previousInsights.plannedMinutes,
        previousInsights.completedPlannedMinutes,
        previousInsights.actualMinutes,
      ),
      'current': (
        currentInsights.plannedMinutes,
        currentInsights.completedPlannedMinutes,
        currentInsights.actualMinutes,
      ),
    };

    final visible = <String, List<String>>{};
    for (final offset in dates) {
      final (start, end) = (
        startOfDay(h.at(offset, 0)),
        addDays(h.at(offset, 0), 1),
      );
      final rows = await db.taskDao.getTasksBetween(start, end);
      visible[iso(offset)] = [
        for (final row in rows)
          if (isActiveTimelineTask(TaskRepository.fromRow(row))) row.id,
      ]..sort();
    }

    final dashboard = await ExperimentDashboardService(
      db,
      formatDuration: formatMinutes,
    ).load(today: isoDateString(h.now));
    final experiments = [
      for (final view in dashboard.views)
        '${view.experiment.id}|${view.progress.totalMin}|'
            '${view.progress.expectedMin}|${view.progress.doneMin}|'
            '${view.progress.statusChip}|'
            '${[for (final e in view.minutesByDay.entries) '${e.key}:${e.value.doneMin}/${e.value.stillPlannedMin}']}',
    ];

    return Snap(
      outcomes: outcomes,
      weeks: weeks,
      overview: overview,
      consistency: consistency,
      insightsWeeks: insightsWeeks,
      visible: visible,
      experiments: experiments,
    );
  }

  /// What must be identical whatever happened to the idea.
  void expectUntouched(Snap before, Snap after) {
    expect(
      after.overview,
      before.overview,
      reason: 'Review overview (past days)',
    );
    expect(
      after.consistency,
      before.consistency,
      reason: 'Consistency, past days',
    );
    expect(
      after.insightsWeeks['previous'],
      before.insightsWeeks['previous'],
      reason: 'Insights, previous week',
    );
    expect(after.experiments, before.experiments, reason: 'Experiments');
    expect(
      after.outcomes[iso(-3)],
      before.outcomes[iso(-3)],
      reason: 'the done day has the same rows',
    );
    expect(after.visible[iso(-3)], before.visible[iso(-3)]);
    expect(
      after.weeks['previous']!.$1,
      before.weeks['previous']!.$1,
      reason: 'previous week total',
    );
    expect(
      after.weeks['previous']!.$2,
      before.weeks['previous']!.$2,
      reason: 'previous week completed',
    );
  }

  test('the idea row itself is on no other tab', () async {
    final all = await snap();
    for (final day in all.visible.values) {
      expect(day, isNot(contains(idea.id)));
    }
    for (final day in all.outcomes.values) {
      expect(day.keys, isNot(contains(idea.id)));
    }
    // And the sessions are ordinary rows everywhere: counted once each.
    expect(all.outcomes[iso(-3)]!.keys, containsAll([done.id, plainDone.id]));
    expect(
      all.outcomes[iso(-2)]!.keys,
      containsAll([missed.id, plainMissed.id]),
    );
    expect(
      all.outcomes[iso(2)]!.keys,
      containsAll([future.id, plainFuture.id]),
    );
    expect(all.visible[iso(-2)], containsAll([missed.id, plainMissed.id]));
    expect(all.overview[iso(-3)], (2, 2), reason: 'done day: 2 tasks, 2 done');
    expect(all.overview[iso(-2)], (2, 0));
    expect(all.weeks['previous'], (4, 2, 0, 0));
    expect(all.weeks['current'], (2, 0, 0, 0));
    // The comparisons below are not vacuous: Consistency and the week totals
    // do hold the scenario's minutes (done day 2 x 60 planned, 2 x 60 done).
    expect(all.consistency[iso(-3)]!.$1, 120);
    expect(all.consistency[iso(-3)]!.$2, 120);
    expect(all.consistency[iso(-2)]!.$1, 120);
    expect(all.insightsWeeks['previous']!.$1, 240);
    expect(all.insightsWeeks['current']!.$1, 120);
    // Sessions have no tag, so only the tagged plain block counts.
    expect(all.experiments, hasLength(1));
  });

  group('close it', () {
    test('Review rows, totals, Consistency and Day change only as intended', () async {
      final before = await snap();
      await h.inbox.closeItem(idea.id, 'Not worth the weekend', h.now);
      final after = await snap();

      expectUntouched(before, after);

      // Review > Daily, past days: the same rows with the same minutes; only
      // the missed session's label changes: Not started -> Skipped.
      expect(before.outcomes[iso(-2)]![missed.id], startsWith('notStarted|'));
      expect(after.outcomes[iso(-2)]![missed.id], startsWith('skipped|'));
      expect(
        after.outcomes[iso(-2)]![missed.id]!.split('|').skip(1).toList(),
        before.outcomes[iso(-2)]![missed.id]!.split('|').skip(1).toList(),
        reason: 'planned and tracked minutes unchanged',
      );
      expect(
        after.outcomes[iso(-2)]![plainMissed.id],
        before.outcomes[iso(-2)]![plainMissed.id],
      );
      expect(after.outcomes[iso(-2)]!.keys, before.outcomes[iso(-2)]!.keys);

      // Review > Weekly, previous week: total and completed unchanged, the
      // missed one moves from "not started" to Skipped.
      expect(after.weeks['previous'], (4, 2, 1, 0));
      expect(before.weeks['previous'], (4, 2, 0, 0));

      // The future session is dropped: gone from Day, Review and the totals of
      // the current week, and from the current week's planned minutes.
      expect(before.outcomes[iso(2)]!.keys, contains(future.id));
      expect(after.outcomes[iso(2)]!.keys, isNot(contains(future.id)));
      expect(after.visible[iso(2)], isNot(contains(future.id)));
      expect(after.visible[iso(2)], contains(plainFuture.id));
      expect(after.weeks['current'], (1, 0, 0, 0));
      expect(
        after.insightsWeeks['current']!.$1,
        before.insightsWeeks['current']!.$1 - 60,
        reason: 'only the dropped session leaves the planned minutes',
      );
      expect(
        after.insightsWeeks['current']!.$2,
        before.insightsWeeks['current']!.$2,
      );

      // Day, past: the skipped session stays on its day.
      expect(after.visible[iso(-2)], before.visible[iso(-2)]);
    });
  });

  group('carry', () {
    test(
      'Save dates: old rows stay as history, the new block is counted once',
      () async {
        final before = await snap();
        await h.inbox.saveDates(idea.id, [h.slot(3, 9)], h.now);
        final after = await snap();

        expectUntouched(before, after);

        // Review: the old row reads Rescheduled with the same minutes.
        expect(after.outcomes[iso(-2)]![missed.id], startsWith('rescheduled|'));
        expect(
          after.outcomes[iso(-2)]![missed.id]!.split('|').skip(1).toList(),
          before.outcomes[iso(-2)]![missed.id]!.split('|').skip(1).toList(),
        );
        expect(after.weeks['previous'], (4, 2, 0, 1));

        // The new session appears once on its own day, as a normal row.
        final carriedTo = (await h.reload(missed.id)).rescheduledToId!;
        expect(after.outcomes[iso(3)]!.keys, [carriedTo]);
        expect(
          after.outcomes[iso(3)]![carriedTo],
          startsWith('notStarted|60|'),
        );
        expect((await h.reload(carriedTo)).rescheduledFromId, missed.id);

        // The unpicked future session is dropped, the new one added: the
        // current week's total and planned minutes net out.
        expect(after.outcomes[iso(2)]!.keys, isNot(contains(future.id)));
        expect(after.weeks['current']!.$1, before.weeks['current']!.$1);
        expect(after.insightsWeeks['current'], before.insightsWeeks['current']);

        // Day: the carried predecessor is hidden, the successor shown.
        expect(before.visible[iso(-2)], contains(missed.id));
        expect(after.visible[iso(-2)], [plainMissed.id]);
        expect(after.visible[iso(3)], [carriedTo]);
        expect(await h.reload(missed.id).then(isActiveTimelineTask), isFalse);
      },
    );

    test("Day's own Reschedule writes the same history as Save dates", () async {
      final before = await snap();
      final command = RescheduleOverdueCommand(
        repository: h.inbox,
        originalId: missed.id,
        start: h.at(3, 9),
        end: h.at(3, 10),
      );
      await command.execute();
      final after = await snap();

      expectUntouched(before, after);
      expect(after.outcomes[iso(-2)]![missed.id], startsWith('rescheduled|'));
      expect(after.weeks['previous'], (4, 2, 0, 1));
      // The successor keeps the link, so the Inbox follows the carried session.
      final successor = await h.reload(command.successorId);
      expect(successor.inboxItemId, idea.id);
      expect(after.visible[iso(-2)], [plainMissed.id]);
      expect(after.visible[iso(3)], [command.successorId]);
      // Nothing else on the future day changed.
      expect(after.outcomes[iso(2)], before.outcomes[iso(2)]);
    });

    test('Save dates with no dates: the missed session is skipped, totals unchanged', () async {
      final before = await snap();
      await h.inbox.saveDates(idea.id, [], h.now);
      final after = await snap();
      expectUntouched(before, after);
      expect(after.outcomes[iso(-2)]![missed.id], startsWith('skipped|'));
      expect(after.weeks['previous'], (4, 2, 1, 0));
      expect(after.visible[iso(-2)], before.visible[iso(-2)]);
    });
  });

  group('doing the work', () {
    test(
      'completing the missed session late counts once, on its own day',
      () async {
        final before = await snap();
        final current = await h.reload(missed.id);
        await h.tasks.updateTask(
          current.copyWith(status: TaskStatus.completed),
        );
        final after = await snap();

        expect(after.outcomes[iso(-2)]![missed.id], startsWith('completed|'));
        expect(after.overview[iso(-2)], (2, 1));
        expect(after.weeks['previous'], (4, 3, 0, 0));
        expect(after.weeks['previous']!.$1, before.weeks['previous']!.$1);
        expect(
          after.consistency[iso(-2)]!.$2,
          60,
          reason: 'completed planned minutes rise by the session length',
        );
        expect(
          after.consistency[iso(-2)]!.$1,
          before.consistency[iso(-2)]!.$1,
          reason: 'planned minutes do not',
        );
        expect(after.experiments, before.experiments);
      },
    );
  });
}
