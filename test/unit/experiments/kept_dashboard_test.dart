import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/experiment_dao.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/domain/experiment_dashboard.dart';
import 'package:personal_planner/features/experiments/domain/experiment_days.dart';
import 'package:personal_planner/features/experiments/domain/kept_copy.dart';
import 'package:personal_planner/features/experiments/domain/kept_experiment.dart';
import 'package:personal_planner/features/experiments/providers/experiment_providers.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

/// Counts the SELECT statements that reach the database.
class _SelectCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}

/// A planner-local time in 2026.
DateTime dt(int month, int day, int hour, [int minute = 0]) =>
    PlannerTimeZone.calendarDate(2026, month, day, hour: hour, minute: minute);

void main() {
  setupSqliteForTests();

  late _SelectCounter counter;
  late AppDatabase db;
  late ExperimentRepository experiments;
  late TaskRepository tasks;

  setUp(() {
    counter = _SelectCounter();
    db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    experiments = ExperimentRepository(db);
    tasks = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ExperimentDashboardService service() =>
      ExperimentDashboardService(db, formatDuration: formatMinutes);

  Future<Task> block({
    required DateTime start,
    required DateTime end,
    String? tagId,
    TaskStatus status = TaskStatus.completed,
    int? actual,
  }) => tasks.insertTask(
    Task(
      id: '',
      title: 'Block',
      startTime: start,
      endTime: end,
      status: status,
      actualDurationMin: actual,
      tagId: tagId,
      createdAt: start,
      updatedAt: start,
    ),
  );

  Future<Experiment> keepExperiment(
    String name, {
    String start = '2026-09-04',
    String end = '2026-10-03',
    int weekday = 60,
    int weekend = 90,
    String concludedOn = '2026-10-09',
    String? note,
  }) async {
    final created = await experiments.createExperiment(
      name: name,
      startDate: start,
      endDate: end,
      weekdayTargetMin: weekday,
      weekendTargetMin: weekend,
      checkInEveryDays: 7,
    );
    return experiments.concludeExperiment(
      created.id,
      outcome: ExperimentOutcome.keep,
      note: note,
      today: concludedOn,
      expectedRevision: created.revision,
    );
  }

  /// V1 for real, with every noise block of the plan.
  Future<Experiment> seedV1() async {
    final e = await keepExperiment(
      'Morning pages',
      note: 'Mornings beat evenings.',
    );
    final tag = e.tagId;
    // Counted: Mon, Wed, Thu, Fri of this week and a long Monday last month.
    await block(
      start: dt(10, 5, 9),
      end: dt(10, 5, 10),
      tagId: tag,
      actual: 60,
    );
    await block(
      start: dt(10, 7, 9),
      end: dt(10, 7, 10, 30),
      tagId: tag,
      actual: 90,
    );
    await block(
      start: dt(10, 8, 9),
      end: dt(10, 8, 10, 30),
      tagId: tag,
      actual: 90,
    );
    await block(
      start: dt(10, 9, 9),
      end: dt(10, 9, 10, 30),
      tagId: tag,
      actual: 90,
    );
    await block(start: dt(9, 7, 6), end: dt(9, 7, 12), tagId: tag, actual: 360);
    // Planned from today on: Sat 60 and Sun 90.
    await block(
      start: dt(10, 10, 14),
      end: dt(10, 10, 15),
      tagId: tag,
      status: TaskStatus.planned,
    );
    await block(
      start: dt(10, 11, 10),
      end: dt(10, 11, 11, 30),
      tagId: tag,
      status: TaskStatus.planned,
    );
    // Noise that must not count.
    await block(
      start: dt(10, 8, 18),
      end: dt(10, 8, 19),
      tagId: tag,
      status: TaskStatus.planned,
    ); // overdue planned
    await block(
      start: dt(10, 6, 9),
      end: dt(10, 6, 10),
      actual: 99,
    ); // untagged
    final deleted = await block(
      start: dt(10, 6, 11),
      end: dt(10, 6, 12),
      tagId: tag,
      actual: 99,
    );
    await tasks.deleteTask(deleted.id);
    final inbox = await block(
      start: dt(10, 6, 13),
      end: dt(10, 6, 14),
      tagId: tag,
      actual: 99,
    );
    await db.customStatement('UPDATE tasks SET is_inbox = 1 WHERE id = ?', [
      inbox.id,
    ]);
    await block(
      start: dt(10, 10, 8),
      end: dt(10, 10, 9),
      tagId: tag,
      status: TaskStatus.skipped,
    );
    // Crosses midnight from Sunday into Monday: counts on Sunday, in the week
    // of Sep 28 (no Actual, so its planned 60 minutes).
    await block(start: dt(10, 4, 23, 30), end: dt(10, 5, 0, 30), tagId: tag);
    // Before the start date.
    await block(start: dt(9, 3, 9), end: dt(9, 3, 10), tagId: tag);
    return e;
  }

  group('V1 seeded for real', () {
    test('gives the numbers of the plan', () async {
      await seedV1();
      final dashboard = await service().load(today: '2026-10-10');
      expect(dashboard.keptCount, 1);
      expect(dashboard.concludedCount, 1);
      expect(dashboard.runningCount, 0);
      final view = dashboard.kept.views.single;
      expect(view.name, 'Morning pages');
      expect(view.why, 'Mornings beat evenings.');
      expect(view.targetMin, 480);
      expect(view.doneMin, 330);
      expect(view.expectedMin, 300);
      expect(view.paceMin, 30);
      expect(view.plannedMin, 150);
      expect(view.chipText, '30m ahead');
      expect(view.planState, KeptPlanState.reachesMinimum);
      expect(view.doneFraction, 0.6875);
      expect(view.plannedEndFraction, 1.0);
      expect(view.tickFraction, 0.625);
      expect([for (final d in view.days) d.doneMin], [60, 0, 90, 90, 90, 0, 0]);
      expect(view.bars.last.heightPercent, 69);

      final september = view.bars.firstWhere(
        (b) => b.weekStart == '2026-09-07',
      );
      expect(september.doneMin, 360);
      expect(september.targetMin, 480);
      expect(september.heightPercent, 75);
      final crossing = view.bars.firstWhere((b) => b.weekStart == '2026-09-28');
      expect(crossing.doneMin, 60);
      final first = view.bars.firstWhere((b) => b.weekStart == '2026-08-31');
      expect(first.targetMin, 240);
      expect(first.doneMin, 0);
      expect(view.bars, hasLength(6));
    });

    test('a raw-SQL continue_habit row counts as kept', () async {
      final created = await experiments.createExperiment(
        name: 'Old habit',
        startDate: '2026-09-04',
        endDate: '2026-10-03',
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        checkInEveryDays: 7,
      );
      await db.customStatement(
        "UPDATE experiments SET status = 'concluded', "
        "outcome = 'continue_habit', concluded_on = '2026-10-04' "
        'WHERE id = ?',
        [created.id],
      );
      final dashboard = await service().load(today: '2026-10-10');
      expect(dashboard.keptCount, 1);
      expect(dashboard.kept.views.single.name, 'Old habit');
      expect(dashboard.kept.views.single.keptSince, '2026-10-04');
    });

    test('retiring removes the row from Kept but not from Concluded', () async {
      final e = await seedV1();
      await experiments.retireKeptExperiment(
        e.id,
        note: 'Done.',
        expectedRevision: e.revision,
      );
      final dashboard = await service().load(today: '2026-10-10');
      expect(dashboard.keptCount, 0);
      expect(dashboard.kept, emptyKeptSegment);
      expect(dashboard.concludedCount, 1);
    });

    test('a drop outcome is not kept', () async {
      final created = await experiments.createExperiment(
        name: 'Dropped',
        startDate: '2026-09-04',
        endDate: '2026-10-03',
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        checkInEveryDays: 7,
      );
      await experiments.concludeExperiment(
        created.id,
        outcome: ExperimentOutcome.drop,
        today: '2026-10-09',
        expectedRevision: created.revision,
      );
      final dashboard = await service().load(today: '2026-10-10');
      expect(dashboard.keptCount, 0);
      expect(dashboard.concludedCount, 1);
    });

    test('kept rows are ordered newest first, then name, then id', () async {
      await keepExperiment('beta', concludedOn: '2026-10-05');
      await keepExperiment('Zulu', concludedOn: '2026-10-08');
      await keepExperiment('alpha', concludedOn: '2026-10-05');
      await keepExperiment('Charlie', concludedOn: '2026-10-05');
      final dashboard = await service().load(today: '2026-10-10');
      expect(
        [for (final v in dashboard.kept.views) v.name],
        ['Zulu', 'alpha', 'beta', 'Charlie'],
      );
    });

    test('the kept queries run only when a kept experiment exists', () async {
      final running = await experiments.createExperiment(
        name: 'Running',
        startDate: '2026-10-05',
        endDate: '2026-10-11',
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        checkInEveryDays: 7,
      );
      counter.selects = 0;
      await service().load(today: '2026-10-10');
      final withoutKept = counter.selects;
      await db.customStatement(
        "UPDATE experiments SET status = 'concluded', "
        "outcome = 'continue_habit', concluded_on = '2026-10-09' WHERE id = ?",
        [running.id],
      );
      counter.selects = 0;
      final dashboard = await service().load(today: '2026-10-10');
      expect(dashboard.keptCount, 1);
      expect(counter.selects, withoutKept + 3, reason: 'weeks, days, planned');
    });
  });

  test('E3 counts DST-day blocks in the right week', () async {
    PlannerTimeZone.initialize(identifier: 'America/New_York');
    addTearDown(() => PlannerTimeZone.initialize(identifier: 'Asia/Kolkata'));
    final e = await keepExperiment('Dst walk');
    await block(
      start: dt(10, 26, 9),
      end: dt(10, 26, 10),
      tagId: e.tagId,
      actual: 30,
    );
    // Sunday after the change, 25 hour day: counts in the week of Oct 26.
    await block(
      start: dt(11, 1, 23, 30),
      end: dt(11, 2, 0, 15),
      tagId: e.tagId,
      actual: 45,
    );
    // Monday 00:30: next week.
    await block(
      start: dt(11, 2, 0, 30),
      end: dt(11, 2, 1),
      tagId: e.tagId,
      actual: 99,
    );
    final view = (await service().load(today: '2026-10-31')).kept.views.single;
    expect(view.weekStart, '2026-10-26');
    expect(view.bars.last.doneMin, 75);
    expect(view.days.last.date, '2026-11-01');
    expect(view.days.last.doneMin, 45);
    expect(view.days.first.doneMin, 30);
    expect(view.nextWeekStart, '2026-11-02');
  });

  group('query plans', () {
    final bound = [
      for (var i = 0; i < 40; i++) Variable<String>('2026-10-01T00:00:00.000Z'),
    ];

    Future<List<String>> plan(String sql, List<Variable> variables) async {
      final rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: variables)
          .get();
      return [for (final r in rows) r.read<String>('detail')];
    }

    List<Variable> completedVariables(int kept, int buckets) => [
      for (var k = 0; k < kept; k++) ...[
        Variable<String>('tag$k'),
        Variable<String>('2026-09-04T00:00:00.000Z'),
      ],
      for (var b = 0; b < buckets; b++) ...[
        Variable<int>(b),
        Variable<String>('2026-10-05T00:00:00.000Z'),
        Variable<String>('2026-10-12T00:00:00.000Z'),
      ],
    ];

    test('use idx_tasks_tag_date', () async {
      final plans = {
        'completed, 9 week buckets': await plan(
          keptCompletedMinutesSql(1, 9),
          completedVariables(1, 9),
        ),
        'completed, 7 day buckets': await plan(
          keptCompletedMinutesSql(1, 7),
          completedVariables(1, 7),
        ),
        'planned': await plan(keptPlannedMinutesSql(1), bound.take(3).toList()),
      };
      for (final entry in plans.entries) {
        debugPrint('QUERY PLAN ${entry.key}:');
        for (final line in entry.value) {
          debugPrint('  $line');
        }
        expect(
          entry.value.any((d) => d.contains('idx_tasks_tag_date')),
          isTrue,
          reason: '${entry.key} plan was: ${entry.value}',
        );
      }
    });

    test('repeat the index conditions as literal SQL, never bound values', () {
      final sqls = [
        keptCompletedMinutesSql(2, 9),
        keptCompletedMinutesSql(1, 7),
        keptPlannedMinutesSql(3),
      ];
      for (final sql in sqls) {
        expect(sql, contains('deleted_at IS NULL'));
        expect(sql, contains('is_inbox = 0'));
        expect(sql, contains('tag_id IS NOT NULL'));
        expect(sql, isNot(contains('is_inbox = ?')));
        expect(sql, isNot(contains('deleted_at = ?')));
      }
      // Bound values: (tag, from) per kept experiment and (index, start, end)
      // per bucket; tag ids plus the two bounds for the planned query.
      expect(
        '?'.allMatches(keptCompletedMinutesSql(2, 9)).length,
        2 * 2 + 3 * 9,
      );
      expect('?'.allMatches(keptCompletedMinutesSql(1, 7)).length, 2 + 3 * 7);
      expect('?'.allMatches(keptPlannedMinutesSql(3)).length, 3 + 2);
    });
  });

  test('the SQL aggregates agree with groupBlocksByDay', () async {
    final e = await seedV1();
    final weekStarts = keptWeekStarts('2026-10-10');
    final weekBuckets = [
      for (final s in weekStarts)
        (parseIsoDate(s), addDays(parseIsoDate(s), 7)),
    ];
    final thisWeek = parseIsoDate(weekStarts.last);
    final dayBuckets = [
      for (var i = 0; i < 7; i++)
        PlannerTimeZone.dayBounds(addDays(thisWeek, i)),
    ];
    final windows = [(tagId: e.tagId, countedFrom: parseIsoDate(e.startDate))];
    final sqlWeeks = (await db.experimentDao.keptCompletedMinutes(
      windows,
      weekBuckets,
    ))[e.tagId]!;
    final sqlDays = (await db.experimentDao.keptCompletedMinutes(
      windows,
      dayBuckets,
    ))[e.tagId]!;

    Future<int> dartDone((DateTime, DateTime) bucket) async {
      final rows = await db.experimentDao.taggedBlocksInRange(
        e.tagId,
        bucket.$1,
        bucket.$2,
      );
      final byDay = groupBlocksByDay(
        rows,
        startDate: e.startDate,
        endDate: '9999-12-31',
      );
      return byDay.values.fold<int>(0, (sum, d) => sum + d.doneMin);
    }

    for (var i = 0; i < weekBuckets.length; i++) {
      expect(
        sqlWeeks[i] ?? 0,
        await dartDone(weekBuckets[i]),
        reason: 'week $i',
      );
    }
    for (var i = 0; i < dayBuckets.length; i++) {
      expect(sqlDays[i] ?? 0, await dartDone(dayBuckets[i]), reason: 'day $i');
    }
    expect(sqlWeeks[8], 330);
    expect(sqlWeeks[4], 360);
    final planned = await db.experimentDao.keptPlannedMinutes(
      [e.tagId],
      from: dt(10, 10, 0),
      to: dt(10, 12, 0),
    );
    expect(planned[e.tagId], 150);
  });

  test('an untagged task insert leaves the kept segment equal', () async {
    await seedV1();
    final previous = await service().load(today: '2026-10-10');
    await block(start: dt(10, 7, 20), end: dt(10, 7, 21), actual: 45);
    final reloaded = await service().load(today: '2026-10-10');
    expect(reloaded, isNot(same(previous)));
    expect(reloaded.kept, previous.kept);
  });

  test('a tagged task insert changes the kept segment', () async {
    final e = await seedV1();
    final previous = await service().load(today: '2026-10-10');
    await block(
      start: dt(10, 10, 7),
      end: dt(10, 10, 8),
      tagId: e.tagId,
      actual: 20,
    );
    final reloaded = await service().load(today: '2026-10-10');
    expect(reloaded.kept, isNot(previous.kept));
    expect(reloaded.kept.views.single.doneMin, 350);
  });

  test('keptSegmentProvider notifies only when the kept rows change', () async {
    final e = await seedV1();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        insightsNowProvider.overrideWith((ref) => dt(10, 10, 12)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(experimentDashboardProvider.future);
    final notified = <KeptSegment>[];
    container.listen(keptSegmentProvider, (_, next) => notified.add(next));
    final first = container.read(keptSegmentProvider);
    expect(first.views.single.name, 'Morning pages');
    expect(first.views.single.doneMin, 330);

    Future<void> reload() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await container.read(experimentDashboardProvider.future);
      await Future<void>.delayed(Duration.zero);
    }

    // An untagged write reloads the dashboard but leaves the kept rows equal.
    await block(start: dt(10, 7, 20), end: dt(10, 7, 21), actual: 45);
    await reload();
    expect(notified, isEmpty);

    // A tagged write changes them.
    await block(
      start: dt(10, 10, 7),
      end: dt(10, 10, 8),
      tagId: e.tagId,
      actual: 20,
    );
    await reload();
    expect(notified, hasLength(1));
    expect(notified.single.views.single.doneMin, 350);
  });

  test('the copy for the seeded row reads as the plan says', () async {
    await seedV1();
    final view = (await service().load(today: '2026-10-10')).kept.views.single;
    expect(view.subtitle, 'Kept since Oct 9 · #Morning pages');
    expect(
      keptPartsText(
        keptPlannedStripParts(
          view.planState,
          planned: view.plannedMin,
          short: view.shortMin,
          remaining: view.remainingMin,
          formatDuration: formatMinutes,
        ),
      ),
      'Planned: 2h 30m more this week. That reaches the minimum.',
    );
  });
}
