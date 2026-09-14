import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/task_actual_duration_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('remote updates and tombstones do not echo into the outbox', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 1, 1, 9);
      final applier = SyncRemoteApplier(db);
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'remote-category',
                name: 'Original',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
              ),
            );
      });

      await db.syncDao.runWithoutOutbound(
        () => applier.apply(
          SyncRemoteChange(
            changeId: 1,
            operationId: 'server-operation-1',
            tableName: 'categories',
            recordId: 'remote-category',
            operation: 'update',
            serverVersion: 4,
            serverTimestamp: now,
            payload: {
              'id': 'remote-category',
              'name': 'From server',
              'color_hex': '#34A853',
              'sort_order': 0,
              'is_focus': 0,
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'deleted_at': null,
            },
          ),
        ),
      );
      expect(await db.syncDao.pendingCount(), 0);
      expect(
        (await db.categoryDao.getCategoryById('remote-category'))?.name,
        'From server',
      );
      expect(
        (await db.categoryDao.getCategoryById('remote-category'))
            ?.serverVersion,
        4,
      );

      await db.syncDao.runWithoutOutbound(
        () => applier.apply(
          SyncRemoteChange(
            changeId: 2,
            operationId: 'server-operation-2',
            tableName: 'categories',
            recordId: 'remote-category',
            operation: 'delete',
            serverVersion: 5,
            serverTimestamp: now,
            payload: {
              'id': 'remote-category',
              'name': 'From server',
              'color_hex': '#34A853',
              'sort_order': 0,
              'is_focus': 0,
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'deleted_at': now.toIso8601String(),
            },
          ),
        ),
      );
      final row = await db.categoryDao.getCategoryById('remote-category');
      expect(row?.deletedAt, isNotNull);
      expect(row?.syncStatus, 0);
      expect(row?.serverVersion, 5);
      expect(await db.syncDao.pendingCount(), 0);
    } finally {
      await db.close();
    }
  });

  test('remote task application derives estimate from its interval', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 1, 1, 9);
      final applier = SyncRemoteApplier(db);
      await db.syncDao.runWithoutOutbound(
        () => applier.apply(
          SyncRemoteChange(
            changeId: 1,
            operationId: 'remote-task-projection',
            tableName: 'tasks',
            recordId: 'remote-task-projection',
            operation: 'insert',
            serverVersion: 1,
            serverTimestamp: now,
            payload: {
              'id': 'remote-task-projection',
              'title': 'Projected',
              'description': null,
              'start_time': now.toIso8601String(),
              'end_time': now
                  .add(const Duration(minutes: 90))
                  .toIso8601String(),
              'estimated_duration_min': 16,
              'actual_duration_min': null,
              'manual_duration_adjustment_min': 0,
              'category_id': null,
              'priority': 0,
              'status': 'planned',
              'notes': null,
              'recurring_rule_id': null,
              'rescheduled_from_id': null,
              'rescheduled_to_id': null,
              'is_inbox': 0,
              'missed_at': null,
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'deleted_at': null,
            },
          ),
        ),
      );
      final row = await db.taskDao.getTaskById('remote-task-projection');
      expect(row?.estimatedDurationMin, 90);
      expect(await db.syncDao.pendingCount(), 0);
    } finally {
      await db.close();
    }
  });

  test(
    'legacy remote Inbox payload preserves content and defaults due date',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final now = DateTime.utc(2026, 1, 1, 9);
        final applier = SyncRemoteApplier(db);
        await db.syncDao.runWithoutOutbound(
          () => applier.apply(
            SyncRemoteChange(
              changeId: 2,
              operationId: 'legacy-inbox-content',
              tableName: 'tasks',
              recordId: 'legacy-inbox-content',
              operation: 'insert',
              serverVersion: 1,
              serverTimestamp: now,
              payload: {
                'id': 'legacy-inbox-content',
                'title': 'Legacy title',
                'description': 'Legacy details',
                'start_time': now.toIso8601String(),
                'end_time': now.add(const Duration(hours: 1)).toIso8601String(),
                'estimated_duration_min': 60,
                'actual_duration_min': null,
                'manual_duration_adjustment_min': 0,
                'category_id': null,
                'priority': 0,
                'status': 'planned',
                'notes': null,
                'recurring_rule_id': null,
                'rescheduled_from_id': null,
                'rescheduled_to_id': null,
                'is_inbox': 1,
                'missed_at': null,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
                'deleted_at': null,
              },
            ),
          ),
        );
        final row = await db.taskDao.getTaskById('legacy-inbox-content');
        expect(row?.description, 'Legacy title\n\nLegacy details');
        expect(row?.inboxContentVersion, 1);
        expect(row?.dueDate, isNull);
        expect(row?.startTime, isNull);
        expect(row?.endTime, isNull);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'a remote title edit cannot overwrite the local derived actual cache',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final now = DateTime.utc(2026, 1, 1, 9);
        final task = await TaskRepository(db).insertTask(
          Task(id: '', title: 'Original', createdAt: now, updatedAt: now),
        );
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.timerSessions)
              .insert(
                TimerSessionsCompanion.insert(
                  id: 'finished-source',
                  taskId: task.id,
                  startedAt: now,
                  endedAt: Value(now.add(const Duration(minutes: 20))),
                  durationSec: const Value(20 * 60),
                  state: const Value('finished'),
                  workIntervalsJson: const Value('[]'),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        });
        final actuals = TaskActualDurationService(db);
        await actuals.setDisplayedTotal(task.id, 30);
        final before = await db.taskDao.getTaskById(task.id);

        await db.syncDao.runWithoutOutbound(
          () => SyncRemoteApplier(db).apply(
            SyncRemoteChange(
              changeId: 1,
              operationId: 'remote-title-only',
              tableName: 'tasks',
              recordId: task.id,
              operation: 'update',
              serverVersion: 4,
              serverTimestamp: now,
              payload: {
                'id': task.id,
                'title': 'Renamed remotely',
                'description': null,
                'start_time': null,
                'end_time': null,
                'estimated_duration_min': null,
                // This is an untrusted derived projection. The remote applier
                // must preserve/recompute the local canonical value instead.
                'actual_duration_min': 999,
                'manual_duration_adjustment_min': 10,
                'manual_actual_set': 1,
                'category_id': null,
                'priority': 0,
                'status': 'planned',
                'notes': null,
                'recurring_rule_id': null,
                'rescheduled_from_id': null,
                'rescheduled_to_id': null,
                'is_inbox': 0,
                'inbox_content_version': 0,
                'due_date': null,
                'missed_at': null,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
                'deleted_at': null,
              },
            ),
          ),
        );

        final after = await db.taskDao.getTaskById(task.id);
        expect(after?.title, 'Renamed remotely');
        expect(after?.actualDurationMin, 30);
        expect(after?.revision, greaterThan(before!.revision));
        expect(await db.syncDao.pendingCount(), greaterThan(0));
      } finally {
        await db.close();
      }
    },
  );
}
