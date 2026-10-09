import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/providers/experiment_providers.dart';

import '../../helpers/sqlite_setup.dart';

/// Fails every SELECT once [failing] is set, and counts the attempts.
class _FailingSelects extends QueryInterceptor {
  bool failing = false;
  int attempts = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failing) {
      attempts++;
      throw Exception('database unavailable');
    }
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  setupSqliteForTests();
  // Several in-memory databases are open at once on purpose (two accounts).
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final noon = PlannerTimeZone.calendarDate(2026, 10, 7, hour: 12);

  Future<AppDatabase> databaseWith(String experimentName) async {
    final db = AppDatabase(NativeDatabase.memory());
    await ExperimentRepository(db).createExperiment(
      name: experimentName,
      startDate: '2026-10-05',
      endDate: '2026-10-11',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 1,
    );
    return db;
  }

  List<Override> overridesFor(AppDatabase db) => [
    appDatabaseProvider.overrideWithValue(db),
    insightsNowProvider.overrideWith((ref) => noon),
  ];

  Future<void> afterNotifications() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  Future<List<String>> shownNames(ProviderContainer container) async {
    final dashboard = await container.read(experimentDashboardProvider.future);
    return [for (final v in dashboard.views) v.experiment.tagName];
  }

  test('a cache hit makes the first state data, not loading (ED42)', () async {
    final db = await databaseWith('A');
    addTearDown(db.close);
    final container = ProviderContainer(overrides: overridesFor(db));
    addTearDown(container.dispose);

    final sub = container.listen(experimentDashboardProvider, (_, _) {});
    await container.read(experimentDashboardProvider.future);
    expect(container.read(experimentDashboardCacheProvider), isNotNull);
    sub.close();
    await Future<void>.delayed(Duration.zero);

    final again = container.listen(experimentDashboardProvider, (_, _) {});
    final state = container.read(experimentDashboardProvider);
    expect(state.isLoading, isFalse);
    expect(state.hasValue, isTrue);
    again.close();
  });

  test('a replaced database empties the cache and restarts the counter '
      '(ED44)', () async {
    final dbA = await databaseWith('A');
    final dbB = await databaseWith('B');
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final container = ProviderContainer(overrides: overridesFor(dbA));
    addTearDown(container.dispose);

    final sub = container.listen(experimentDashboardProvider, (_, _) {});
    expect(await shownNames(container), ['A']);
    await ExperimentRepository(dbA).createExperiment(
      name: 'A2',
      startDate: '2026-10-05',
      endDate: '2026-10-11',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 1,
    );
    await afterNotifications();
    expect(container.read(experimentSourceRevisionProvider), greaterThan(0));
    expect(container.read(experimentDashboardCacheProvider), isNotNull);

    container.updateOverrides(overridesFor(dbB));
    expect(container.read(experimentDashboardCacheProvider), isNull);
    expect(container.read(experimentSourceRevisionProvider), 0);
    expect(await shownNames(container), ['B']);
    sub.close();
  });

  test('a new container for another database starts empty (ED44)', () async {
    final dbA = await databaseWith('A');
    final dbB = await databaseWith('B');
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final first = ProviderContainer(overrides: overridesFor(dbA));
    addTearDown(first.dispose);
    final firstSub = first.listen(experimentDashboardProvider, (_, _) {});
    expect(await shownNames(first), ['A']);
    firstSub.close();

    final second = ProviderContainer(overrides: overridesFor(dbB));
    addTearDown(second.dispose);
    expect(second.read(experimentDashboardCacheProvider), isNull);
    expect(second.read(experimentSourceRevisionProvider), 0);
    final secondSub = second.listen(experimentDashboardProvider, (_, _) {});
    expect(await shownNames(second), ['B']);
    secondSub.close();
  });

  test('a burst of changes raises the counter once (ED53)', () async {
    final db = await databaseWith('A');
    addTearDown(db.close);
    final container = ProviderContainer(overrides: overridesFor(db));
    addTearDown(container.dispose);
    expect(container.read(experimentSourceRevisionProvider), 0);

    // Three writes in one event-loop turn.
    await Future.wait([
      db.customStatement("UPDATE tags SET name = 'A1' WHERE 1 = 1"),
      db.customStatement("UPDATE tags SET name = 'A2' WHERE 1 = 1"),
      db.customStatement("UPDATE tags SET name = 'A3' WHERE 1 = 1"),
    ]);
    db.markTablesUpdated([db.tags]);
    db.markTablesUpdated([db.tasks]);
    db.markTablesUpdated([db.experiments]);
    await afterNotifications();
    expect(container.read(experimentSourceRevisionProvider), 1);
  });

  test('a load error is not retried automatically (ED43)', () async {
    final interceptor = _FailingSelects();
    final db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final container = ProviderContainer(overrides: overridesFor(db));
    addTearDown(container.dispose);

    interceptor.failing = true;
    final sub = container.listen(experimentDashboardProvider, (_, _) {});
    await expectLater(
      container.read(experimentDashboardProvider.future),
      throwsException,
    );
    // The default retry would try again after 200 ms.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(interceptor.attempts, 1);
    expect(container.read(experimentDashboardProvider).hasError, isTrue);
    sub.close();
  });
}
