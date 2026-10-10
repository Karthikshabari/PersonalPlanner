import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';

import '../../helpers/sqlite_setup.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  // The Insights clock registers a lifecycle observer.
  TestWidgetsFlutterBinding.ensureInitialized();
  setupSqliteForTests();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  final stamp = DateTime.utc(2026, 1, 1);

  Future<void> addCompletedBlock(String id, int hour) {
    final today = startOfDay(DateTime.now());
    final start = PlannerTimeZone.calendarDate(
      today.year,
      today.month,
      today.day,
      hour: hour,
    );
    return db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: id,
            startTime: Value(start),
            endTime: Value(start.add(const Duration(minutes: 60))),
            status: const Value('completed'),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  }

  Future<InsightsSnapshot> open() async {
    final first = Completer<InsightsSnapshot>();
    final sub = container.listen<AsyncValue<InsightsSnapshot>>(
      insightsSnapshotProvider,
      (_, next) {
        if (next.hasValue && !first.isCompleted) first.complete(next.value);
      },
      fireImmediately: true,
    );
    final snapshot = await first.future.timeout(const Duration(seconds: 20));
    sub.close();
    await _settle();
    return snapshot;
  }

  int plannedToday(InsightsSnapshot snapshot) =>
      snapshot.consistencyDays.last.plannedMinutes;

  test(
    'the cached snapshot is reused only while nothing it reads changed',
    () async {
      await addCompletedBlock('a', 9);
      final first = await open();
      expect(plannedToday(first), 60);

      // Nothing changed: the cache offers exactly that snapshot.
      expect(container.read(insightsCachedSnapshotProvider), same(first));

      // A Daily Review save is not an Insights source: still cached.
      await db
          .into(db.dailyReviews)
          .insert(
            DailyReviewsCompanion.insert(
              id: 'dr',
              date: isoDateString(DateTime.now()),
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await _settle();
      expect(container.read(insightsCachedSnapshotProvider), same(first));

      // A block is added while Insights is hidden: the cache must not be used.
      await addCompletedBlock('b', 11);
      await _settle();
      expect(container.read(insightsCachedSnapshotProvider), isNull);

      // Reopening shows the new number, never the old one.
      final second = await open();
      expect(plannedToday(second), 120);
      expect(container.read(insightsCachedSnapshotProvider), same(second));

      // While Insights is open, a write that changes nothing it shows (here a
      // soft-deleted block) does not notify the screen; a real change does.
      var emissions = 0;
      InsightsSnapshot? latest;
      final live = container.listen<AsyncValue<InsightsSnapshot>>(
        insightsSnapshotProvider,
        (_, next) {
          if (next.hasValue) {
            emissions++;
            latest = next.value;
          }
        },
        fireImmediately: true,
      );
      await _settle();
      final before = emissions;
      final today = startOfDay(DateTime.now());
      final start = PlannerTimeZone.calendarDate(
        today.year,
        today.month,
        today.day,
        hour: 15,
      );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'gone',
              title: 'gone',
              startTime: Value(start),
              endTime: Value(start.add(const Duration(minutes: 60))),
              status: const Value('completed'),
              deletedAt: Value(stamp),
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await _settle();
      expect(emissions, before);
      await addCompletedBlock('c', 13);
      await _settle();
      expect(emissions, before + 1);
      expect(plannedToday(latest!), 180);
      live.close();
    },
  );
}
