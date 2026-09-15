import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/reactive_stats_stream.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test(
    'context-only local and remote writes refresh active Insights',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = PlannerTimeZone.calendarDate(2026, 9, 21, hour: 12);
      final date = isoDateString(now);
      final tasks = TaskRepository(db);
      final contexts = DayContextRepository(db);
      await tasks.insertTask(
        Task(
          id: '',
          title: 'Context-sensitive plan',
          startTime: PlannerTimeZone.calendarDate(2026, 9, 21, hour: 9),
          endTime: PlannerTimeZone.calendarDate(2026, 9, 21, hour: 10),
          status: TaskStatus.planned,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final values = <InsightsSnapshot>[];
      final stream = watchReactiveStats<InsightsSnapshot>(
        db,
        () =>
            InsightsService(db).compute(weekStart: startOfWeek(now), now: now),
      );
      final subscription = stream.listen(values.add);
      try {
        await _waitForCount(values, 1);
        expect(_day(values.last, date).isNeutral, isFalse);

        final holiday = await contexts.save(date, DayContextKind.holiday, null);
        await _waitForCount(values, 2);
        expect(_day(values.last, date).context, DayContextKind.holiday);
        expect(_day(values.last, date).isNeutral, isTrue);

        await contexts.save(
          date,
          DayContextKind.leave,
          null,
          expectedRevision: holiday.revision,
        );
        await _waitForCount(values, 3);
        expect(_day(values.last, date).context, DayContextKind.leave);
        expect(_day(values.last, date).isNeutral, isTrue);

        await contexts.remove(holiday.id, expectedRevision: 2);
        await _waitForCount(values, 4);
        expect(_day(values.last, date).context, isNull);
        expect(_day(values.last, date).isNeutral, isFalse);

        final remoteNow = now.add(const Duration(minutes: 1));
        final remoteId = holiday.id;
        await SyncRemoteApplier(db).apply(
          SyncRemoteChange(
            changeId: 100,
            operationId: 'remote-context-only',
            tableName: 'day_contexts',
            recordId: remoteId,
            operation: 'insert',
            serverVersion: 100,
            serverTimestamp: remoteNow.toUtc(),
            payload: {
              'id': remoteId,
              'date': date,
              'kind': 'holiday',
              'custom_label': null,
              'created_at': remoteNow.toUtc().toIso8601String(),
              'updated_at': remoteNow.toUtc().toIso8601String(),
              'deleted_at': null,
            },
          ),
        );
        // SyncRepository marks raw-SQL-applied tables after its transaction so
        // Drift watchers receive the same notification as local writes.
        db.markTablesUpdated([db.dayContexts]);
        await _waitForCount(values, 5);
        expect(_day(values.last, date).context, DayContextKind.holiday);
        expect(_day(values.last, date).isNeutral, isTrue);
        expect(await db.select(db.tasks).get(), hasLength(1));
      } finally {
        await subscription.cancel();
        await db.close();
      }
    },
  );
}

ConsistencyDay _day(InsightsSnapshot snapshot, String date) => snapshot
    .consistencyDays
    .firstWhere((day) => isoDateString(day.date) == date);

Future<void> _waitForCount(List<InsightsSnapshot> values, int expected) async {
  for (var i = 0; i < 100; i++) {
    if (values.length >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected $expected Insights emissions, got ${values.length}.');
}
