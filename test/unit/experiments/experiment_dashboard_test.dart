import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/experiment_dao.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/domain/experiment_dashboard.dart';
import 'package:personal_planner/features/experiments/domain/experiment_progress.dart';
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

DateTime at(int day, int hour, [int minute = 0]) =>
    PlannerTimeZone.calendarDate(2026, 10, day, hour: hour, minute: minute);

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

  Future<Experiment> start(
    String name, {
    String startDate = '2026-10-05',
    String endDate = '2026-10-11',
  }) => experiments.createExperiment(
    name: name,
    startDate: startDate,
    endDate: endDate,
    weekdayTargetMin: 60,
    weekendTargetMin: 90,
    checkInEveryDays: 1,
  );

  Future<Task> block({
    required DateTime start,
    required DateTime end,
    String? tagId,
    TaskStatus status = TaskStatus.completed,
    int? actual,
    String title = 'Block',
  }) => tasks.insertTask(
    Task(
      id: '',
      title: title,
      startTime: start,
      endTime: end,
      status: status,
      actualDurationMin: actual,
      tagId: tagId,
      createdAt: start,
      updatedAt: start,
    ),
  );

  ExperimentDashboardService service() =>
      ExperimentDashboardService(db, formatDuration: formatMinutes);

  group('aggregate', () {
    test('sums the tagged blocks of the window per planner day', () async {
      final e = await start('Learn C');
      await block(start: at(5, 9), end: at(5, 10), tagId: e.tagId, actual: 50);
      // No recorded Actual: counts the planned 45 minutes.
      await block(start: at(6, 9), end: at(6, 9, 45), tagId: e.tagId);
      // An explicit Actual of 0 counts 0.
      await block(start: at(7, 9), end: at(7, 10), tagId: e.tagId, actual: 0);
      await block(
        start: at(7, 11),
        end: at(7, 12),
        tagId: e.tagId,
        status: TaskStatus.inProgress,
      );
      await block(
        start: at(7, 13),
        end: at(7, 14),
        tagId: e.tagId,
        status: TaskStatus.skipped,
      );
      // Crosses midnight: counts on its start date.
      await block(start: at(8, 23), end: at(9, 1), tagId: e.tagId);
      // Not counted: outside the window, untagged, deleted, Inbox capture.
      await block(start: at(4, 9), end: at(4, 10), tagId: e.tagId, actual: 99);
      await block(
        start: at(12, 9),
        end: at(12, 10),
        tagId: e.tagId,
        actual: 99,
      );
      await block(start: at(5, 15), end: at(5, 16), actual: 99);
      final deleted = await block(
        start: at(5, 17),
        end: at(5, 18),
        tagId: e.tagId,
        actual: 99,
      );
      await tasks.deleteTask(deleted.id);
      final inbox = await block(
        start: at(5, 19),
        end: at(5, 20),
        tagId: e.tagId,
        actual: 99,
      );
      await db.customStatement('UPDATE tasks SET is_inbox = 1 WHERE id = ?', [
        inbox.id,
      ]);

      final dashboard = await service().load(today: '2026-10-07');
      final view = dashboard.views.single;
      final byDay = view.minutesByDay;
      expect(byDay['2026-10-05']!.doneMin, 50);
      expect(byDay['2026-10-06']!.doneMin, 45);
      expect(byDay['2026-10-07']!.doneMin, 0);
      expect(byDay['2026-10-07']!.stillPlannedMin, 60);
      expect(byDay['2026-10-08']!.doneMin, 120);
      expect(byDay.containsKey('2026-10-09'), isFalse);
      expect(byDay.keys.toSet(), {
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
        '2026-10-08',
      });
      // Today (Oct 7): done 0 of target 60, 60 still planned.
      expect(view.progress.todayLine, contains('0m done · 1h still planned'));
      expect(view.progress.doneMin, 95);
    });

    test('Leave and Holiday days come from day contexts', () async {
      final e = await start('Learn C');
      await db.customStatement(
        "INSERT INTO day_contexts (id, date, kind, created_at, updated_at) "
        "VALUES ('c1', '2026-10-06', 'leave', '2026-10-01T00:00:00.000Z', "
        "'2026-10-01T00:00:00.000Z'), "
        "('c2', '2026-10-07', 'office', '2026-10-01T00:00:00.000Z', "
        "'2026-10-01T00:00:00.000Z'), "
        "('c3', '2026-10-08', 'holiday', '2026-10-01T00:00:00.000Z', "
        "'2026-10-01T00:00:00.000Z'), "
        "('c4', '2026-10-30', 'leave', '2026-10-01T00:00:00.000Z', "
        "'2026-10-01T00:00:00.000Z')",
      );
      expect(
        await db.experimentDao.leaveOrHolidayDates('2026-10-05', '2026-10-11'),
        {'2026-10-06', '2026-10-08'},
      );
      final view = (await service().load(today: '2026-10-12')).views.single;
      expect(view.days[1].targetMin, 0);
      expect(view.days[3].targetMin, 0);
      expect(view.days[2].targetMin, 60);
      expect(view.progress.totalMin, 60 * 3 + 90 * 2);
      expect(e.tagName, 'Learn C');
    });

    test('empty database gives the empty dashboard', () async {
      final dashboard = await service().load(today: '2026-10-07');
      expect(dashboard.isEmpty, isTrue);
      expect(dashboard.runningCount, 0);
      expect(dashboard.concludedCount, 0);
    });

    test(
      'running first by start date and name, then concluded newest first',
      () async {
        await start('Zeta', startDate: '2026-10-05');
        await start('alpha', startDate: '2026-10-05');
        await start('Early', startDate: '2026-10-01', endDate: '2026-10-20');
        final old = await start('Old', endDate: '2026-10-06');
        final newer = await start('Newer', endDate: '2026-10-07');
        await experiments.concludeExperiment(
          old.id,
          outcome: ExperimentOutcome.drop,
          today: '2026-10-08',
          expectedRevision: old.revision,
        );
        await experiments.concludeExperiment(
          newer.id,
          outcome: ExperimentOutcome.keep,
          today: '2026-10-09',
          expectedRevision: newer.revision,
        );
        final dashboard = await service().load(today: '2026-10-09');
        expect(dashboard.views.map((v) => v.experiment.tagName), [
          'Early',
          'alpha',
          'Zeta',
          'Newer',
          'Old',
        ]);
        expect(dashboard.runningCount, 3);
        expect(dashboard.concludedCount, 2);
      },
    );

    test(
      'the extension line reads the history of an extended experiment',
      () async {
        final e = await start('Learn C');
        final extended = await experiments.extendExperiment(
          e.id,
          days: 14,
          reason: 'Travelling',
          today: '2026-10-11',
          expectedRevision: e.revision,
        );
        final view = (await service().load(today: '2026-10-12')).views.single;
        expect(
          experimentExtensionLine(view.experiment),
          'Extended 1 time. Last reason: Travelling',
        );
        expect(view.experiment.endDate, extended.endDate);
        expect(view.days, hasLength(21));
      },
    );
  });

  group('range query', () {
    test('uses the partial index idx_tasks_tag_date (F8)', () async {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN $taggedBlocksInRangeSql',
            variables: [
              Variable<String>('tag'),
              Variable<String>('2026-10-01T00:00:00.000Z'),
              Variable<String>('2026-10-31T00:00:00.000Z'),
            ],
          )
          .get();
      final details = [for (final r in plan) r.read<String>('detail')];
      expect(
        details.any((d) => d.contains('idx_tasks_tag_date')),
        isTrue,
        reason: 'plan was: $details',
      );
    });

    test('repeats the index conditions as literal SQL, never bound values', () {
      // The EXPLAIN check above passes on this SQLite build even for a bound
      // `is_inbox = ?`, so the literal form is pinned by text as well: other
      // SQLite builds only use a partial index when the query's WHERE clause
      // itself contains the index's conditions.
      expect(taggedBlocksInRangeSql, contains('deleted_at IS NULL'));
      expect(taggedBlocksInRangeSql, contains('is_inbox = 0'));
      expect(taggedBlocksInRangeSql, contains('tag_id IS NOT NULL'));
      expect(
        '?'.allMatches(taggedBlocksInRangeSql).length,
        3,
        reason: 'only the tag id and the two range bounds are bound',
      );
    });

    test('returns only the half-open range of the tag', () async {
      final e = await start('Learn C');
      final other = await start('Other');
      await block(start: at(5, 0), end: at(5, 1), tagId: e.tagId, actual: 1);
      await block(start: at(11, 23), end: at(11, 23, 59), tagId: e.tagId);
      await block(start: at(12, 0), end: at(12, 1), tagId: e.tagId);
      await block(start: at(6, 9), end: at(6, 10), tagId: other.tagId);
      final rows = await db.experimentDao.taggedBlocksInRange(
        e.tagId,
        at(5, 0),
        at(12, 0),
      );
      expect(rows, hasLength(2));
    });
  });

  group('cache', () {
    ProviderContainer containerFor(AppDatabase database, String today) {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          insightsNowProvider.overrideWith(
            (ref) => PlannerTimeZone.calendarDate(
              2026,
              10,
              int.parse(today.substring(8)),
              hour: 12,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settleRevision() =>
        Future<void>.delayed(const Duration(milliseconds: 80));

    test('returns the cached dashboard without any query, recomputes after a '
        'task update', () async {
      final e = await start('Learn C');
      await block(start: at(5, 9), end: at(5, 10), tagId: e.tagId, actual: 30);
      final container = containerFor(db, '2026-10-07');

      final first = container.listen(experimentDashboardProvider, (_, _) {});
      final firstDashboard = await container.read(
        experimentDashboardProvider.future,
      );
      expect(firstDashboard.views.single.progress.doneMin, 30);
      first.close();
      await Future<void>.delayed(Duration.zero);

      final selectsBefore = counter.selects;
      final second = container.listen(experimentDashboardProvider, (_, _) {});
      final state = container.read(experimentDashboardProvider);
      expect(state.hasValue, isTrue);
      expect(state.isLoading, isFalse);
      expect(identical(state.value, firstDashboard), isTrue);
      expect(
        counter.selects,
        selectsBefore,
        reason: 'a cache hit must not query the database',
      );
      second.close();
      await Future<void>.delayed(Duration.zero);

      await block(start: at(6, 9), end: at(6, 10), tagId: e.tagId, actual: 20);
      await settleRevision();
      expect(container.read(experimentSourceRevisionProvider), greaterThan(0));
      final third = container.listen(experimentDashboardProvider, (_, _) {});
      final fresh = await container.read(experimentDashboardProvider.future);
      expect(identical(fresh, firstDashboard), isFalse);
      expect(fresh.views.single.progress.doneMin, 50);
      third.close();
    });

    test('a changed date recomputes', () async {
      final e = await start('Learn C');
      await block(start: at(5, 9), end: at(5, 10), tagId: e.tagId, actual: 30);
      final first = containerFor(db, '2026-10-07');
      final a = await first.read(experimentDashboardProvider.future);
      expect(a.views.single.today, '2026-10-07');

      // A new container shares the database but has its own cache and date.
      final second = containerFor(db, '2026-10-08');
      final b = await second.read(experimentDashboardProvider.future);
      expect(b.views.single.today, '2026-10-08');
    });
  });
}
