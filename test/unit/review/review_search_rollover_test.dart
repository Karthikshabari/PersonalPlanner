import 'dart:async';

import 'package:drift/drift.dart' show Value;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/review/domain/review_search.dart';
import 'package:personal_planner/features/review/providers/review_search_providers.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late StreamController<DateTime> clock;
  late DateTime now;
  late ProviderContainer container;

  final stamp = DateTime.utc(2026, 1, 1);

  Future<void> task(String id, String title, DateTime start) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          title: title,
          startTime: Value(start),
          endTime: Value(start.add(const Duration(minutes: 30))),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = StreamController<DateTime>.broadcast();
    // Wednesday 2026-10-14, late in the evening.
    now = PlannerTimeZone.calendarDate(2026, 10, 14, hour: 23);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        insightsNowFactoryProvider.overrideWithValue(() => now),
        insightsClockFactoryProvider.overrideWithValue(() => clock.stream),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await clock.close();
    await db.close();
  });

  Future<ReviewSearchIndex> next(
    List<ReviewSearchIndex> seen,
    int count,
  ) async {
    while (seen.length < count) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return seen[count - 1];
  }

  test('a change of day reloads the index with the new today', () async {
    final seen = <ReviewSearchIndex>[];
    final subscription = container.listen(reviewSearchIndexProvider, (
      _,
      state,
    ) {
      final index = state.value;
      if (index != null) seen.add(index);
    }, fireImmediately: true);
    addTearDown(subscription.close);
    await task(
      'thu',
      'Thursday dentist',
      PlannerTimeZone.calendarDate(2026, 10, 15, hour: 9),
    );

    final before = await next(seen, 1);
    expect(before.today, PlannerTimeZone.calendarDate(2026, 10, 14));

    // Midnight passes: Thursday is now today.
    now = PlannerTimeZone.calendarDate(2026, 10, 15, hour: 0, minute: 1);
    clock.add(now);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = seen.last;
    expect(identical(after, before), isFalse);
    expect(after.today, PlannerTimeZone.calendarDate(2026, 10, 15));
    expect(searchReviewDays(after, 'dentist'), hasLength(1));
  });

  test('a clock event on the same day does not reload', () async {
    final seen = <ReviewSearchIndex>[];
    final subscription = container.listen(reviewSearchIndexProvider, (
      _,
      state,
    ) {
      final index = state.value;
      if (index != null) seen.add(index);
    }, fireImmediately: true);
    addTearDown(subscription.close);
    await next(seen, 1);

    now = PlannerTimeZone.calendarDate(2026, 10, 14, hour: 23, minute: 30);
    clock.add(now);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(seen, hasLength(1));
  });

  test('the first load takes today from the clock factory', () async {
    final seen = <ReviewSearchIndex>[];
    final subscription = container.listen(reviewSearchIndexProvider, (
      _,
      state,
    ) {
      final index = state.value;
      if (index != null) seen.add(index);
    }, fireImmediately: true);
    addTearDown(subscription.close);

    expect(isoDateString((await next(seen, 1)).today), '2026-10-14');
  });
}
