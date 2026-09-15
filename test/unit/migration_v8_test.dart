import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('v8 repairs stale task projections and preserves recovery evidence', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v8',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 7);
      final raw = sqlite3.sqlite3.open(file.path);
      raw.execute('''
        INSERT INTO tasks
          (id, title, start_time, end_time, estimated_duration_min,
           is_inbox, created_at, updated_at)
        VALUES
          ('inbox-1', 'Inbox', '2026-01-01T09:00:00.000Z',
           '2026-01-01T10:00:00.000Z', 90, 1,
           '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}')
      ''');
      raw.execute('''
        INSERT INTO tasks (id, title, description, is_inbox, created_at, updated_at)
        VALUES
          ('legacy-null', 'Legacy title', NULL, 1, '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}'),
          ('legacy-equal', 'Same text', 'Same text', 1, '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}'),
          ('legacy-different', 'Original title', 'Original notes', 1, '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}'),
          ('legacy-whitespace', 'Whitespace title', '  ', 1, '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}'),
          ('legacy-tombstone', 'Deleted capture', 'Deleted details', 1, '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}')
      ''');
      raw.execute(
        "UPDATE tasks SET deleted_at = '${MigrationSchema.timestamp}' "
        "WHERE id = 'legacy-tombstone'",
      );
      raw.execute(
        "UPDATE tasks SET estimated_duration_min = 16 WHERE id = 'task-1'",
      );
      raw.execute('''
        INSERT INTO tasks (id, title, start_time, end_time, created_at, updated_at)
        VALUES ('task-2', 'Rescheduled successor',
          '2026-01-02T09:00:00.000Z', '2026-01-02T10:00:00.000Z',
          '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}')
      ''');
      raw.execute(
        "UPDATE tasks SET rescheduled_to_id = 'task-2', server_version = 41, "
        "sync_status = 1 WHERE id = 'task-1'",
      );
      raw.execute(
        "UPDATE tasks SET rescheduled_from_id = 'task-1' WHERE id = 'task-2'",
      );
      raw.execute('''
        INSERT INTO sync_log(
          operation_id, table_name, record_id, operation,
          expected_server_version, payload, state, attempt_count,
          created_at, updated_at
        ) VALUES (
          'preserved-operation', 'tasks', 'task-1', 'update', 41,
          '{"historical":true}', 'error', 3,
          '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}'
        )
      ''');
      raw.execute('''
        INSERT INTO sync_conflicts(
          id, operation_id, table_name, record_id, expected_server_version,
          actual_server_version, local_snapshot, remote_snapshot, created_at
        ) VALUES (
          'preserved-conflict', 'preserved-operation', 'tasks', 'task-1',
          41, 42, '{"local":true}', '{"remote":true}',
          '${MigrationSchema.timestamp}'
        )
      ''');
      raw.execute('''
        INSERT INTO sync_state(account_id, last_change_id, updated_at)
        VALUES ('preserved-account', 77, '${MigrationSchema.timestamp}')
      ''');
      raw.execute('''
        INSERT INTO timer_sessions
          (id, task_id, started_at, ended_at, duration_sec, created_at, updated_at)
        VALUES
          ('legacy-open', 'task-1', '2026-01-01T10:00:00.000Z', NULL, 0,
           '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}')
      ''');
      raw.dispose();

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          8,
        );
        expect(
          (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'day_contexts'",
              )
              .get()),
          hasLength(1),
        );
        final scheduled = await db.taskDao.getTaskById('task-1');
        expect(scheduled?.estimatedDurationMin, 60);
        expect(scheduled?.serverVersion, 41);
        expect(scheduled?.rescheduledToId, 'task-2');
        expect(scheduled?.planTitleHistoryJson, '[]');
        expect(scheduled?.displayPlanChangeId, isNull);
        expect(scheduled?.dueDate, isNull);
        expect(
          (await db.taskDao.getTaskById('task-2'))?.rescheduledFromId,
          'task-1',
        );
        expect(
          await db
              .customSelect(
                "SELECT id FROM subtasks WHERE id = 'sub-1' AND task_id = 'task-1'",
              )
              .get(),
          hasLength(1),
        );
        expect(
          await db
              .customSelect(
                "SELECT task_id FROM task_tags "
                "WHERE task_id = 'task-1' AND tag_id = 'tag-1'",
              )
              .get(),
          hasLength(1),
        );
        expect(
          await db
              .customSelect(
                "SELECT id FROM recurring_rules WHERE id = 'rule-1'",
              )
              .get(),
          hasLength(1),
        );
        // The historical open row remains the same ID but is intentionally
        // unclaimed/running and excluded from the completed Actual source.
        final legacyOpen = await db.timerDao.getSessionById('legacy-open');
        expect(legacyOpen?.state, 'running');
        expect(legacyOpen?.runningSince, isNotNull);
        expect(legacyOpen?.ownerDeviceId, isNull);
        expect(scheduled?.actualDurationMin, 15);
        final inbox = await db.taskDao.getTaskById('inbox-1');
        expect(inbox?.title, 'Inbox');
        expect(inbox?.description, 'Inbox');
        expect(inbox?.inboxContentVersion, 1);
        expect(inbox?.startTime, isNull);
        expect(inbox?.endTime, isNull);
        expect(inbox?.estimatedDurationMin, isNull);
        expect(
          (await db.taskDao.getTaskById('legacy-null'))?.description,
          'Legacy title',
        );
        expect(
          (await db.taskDao.getTaskById('legacy-equal'))?.description,
          'Same text',
        );
        expect(
          (await db.taskDao.getTaskById('legacy-different'))?.description,
          'Original title\n\nOriginal notes',
        );
        expect(
          (await db.taskDao.getTaskById('legacy-whitespace'))?.description,
          'Whitespace title\n\n  ',
        );
        final tombstone = await db.taskDao.getTaskById('legacy-tombstone');
        expect(tombstone?.description, 'Deleted capture\n\nDeleted details');
        expect(tombstone?.deletedAt, isNotNull);
        expect(tombstone?.inboxContentVersion, 1);
        final recovery = await db
            .customSelect(
              'SELECT recovery_id, payload FROM planner_migration_recovery '
              "WHERE recovery_id IN ('v8:tasks:task-1', 'v8:tasks:inbox-1', 'v8:tasks:legacy-tombstone')",
            )
            .get();
        expect(
          recovery.map((row) => row.read<String>('recovery_id')),
          containsAll(<String>[
            'v8:tasks:task-1',
            'v8:tasks:inbox-1',
            'v8:tasks:legacy-tombstone',
          ]),
        );
        expect(
          recovery.map((row) => row.read<String>('payload')),
          everyElement(isNotEmpty),
        );
        final reconciliation = await db
            .customSelect(
              'SELECT record_id, operation, payload FROM sync_log '
              "WHERE table_name = 'tasks' AND record_id IN "
              "('inbox-1', 'legacy-null', 'legacy-equal', 'legacy-different', "
              "'legacy-whitespace', 'legacy-tombstone') "
              'ORDER BY record_id',
            )
            .get();
        expect(reconciliation, hasLength(6));
        expect(
          reconciliation.map((row) => row.read<String>('operation')),
          everyElement(anyOf('insert', 'update', 'delete')),
        );
        expect(
          reconciliation.map((row) => row.read<String>('payload')),
          everyElement(contains('inbox_content_version')),
        );
        final manualReconciliation = await db
            .customSelect(
              "SELECT payload FROM sync_log WHERE table_name = 'tasks' "
              "AND record_id = 'task-1' AND operation_id <> 'preserved-operation' "
              "AND payload LIKE '%\"_planner_payload_version\":2%'",
            )
            .getSingle();
        expect(
          manualReconciliation.read<String>('payload'),
          allOf(
            contains('"manual_actual_set":1'),
            contains('"manual_duration_adjustment_min":15'),
          ),
        );
        final preservedOperation = await db
            .customSelect(
              "SELECT expected_server_version, payload, state, attempt_count "
              "FROM sync_log WHERE operation_id = 'preserved-operation'",
            )
            .getSingle();
        expect(preservedOperation.read<int>('expected_server_version'), 41);
        expect(
          preservedOperation.read<String>('payload'),
          '{"historical":true}',
        );
        expect(preservedOperation.read<String>('state'), 'error');
        expect(preservedOperation.read<int>('attempt_count'), 3);
        expect(
          await db
              .customSelect(
                "SELECT id FROM sync_conflicts WHERE id = 'preserved-conflict'",
              )
              .get(),
          hasLength(1),
        );
        expect(await db.syncDao.getCursor('preserved-account'), 77);
        final indexes = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .get();
        final indexNames = indexes
            .map((row) => row.read<String>('name'))
            .toSet();
        expect(indexNames, contains('idx_day_contexts_date'));
        expect(indexNames, contains('idx_timer_one_running_owner'));
        expect(indexNames, contains('idx_timer_one_unfinished_owner_task'));
        final taskUpdateTrigger = await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'trigger' "
              "AND name = 'sync_tasks_update'",
            )
            .getSingle();
        expect(
          taskUpdateTrigger.read<String>('sql'),
          allOf(
            contains('plan_title_history_json'),
            contains('display_plan_change_id'),
            contains('_planner_payload_version'),
          ),
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final integrity = await db
            .customSelect('PRAGMA integrity_check')
            .getSingle();
        expect(integrity.data.values.single, 'ok');
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('v8 restores a pre-existing sync apply-mode setting', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v8_apply_mode',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 7);
      final raw = sqlite3.sqlite3.open(file.path);
      raw.execute(
        "INSERT INTO app_settings(key, value) "
        "VALUES ('sync.apply_mode', 'legacy')",
      );
      raw.dispose();

      final db = AppDatabase(NativeDatabase(file));
      try {
        final setting = await db
            .customSelect(
              "SELECT value FROM app_settings WHERE key = 'sync.apply_mode'",
            )
            .getSingle();
        expect(setting.read<String>('value'), 'legacy');
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test(
    'existing v8 databases receive the R3 table without resetting data',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'planner_migration_v8_day_contexts',
      );
      final file = File('${directory.path}/planner.sqlite3');
      try {
        final initial = AppDatabase(NativeDatabase(file));
        expect(await initial.select(initial.dayContexts).get(), isEmpty);
        await initial.close();
        final raw = sqlite3.sqlite3.open(file.path);
        raw.execute('DROP TABLE day_contexts');
        raw.execute('PRAGMA user_version = 8');
        raw.dispose();

        final db = AppDatabase(NativeDatabase(file));
        try {
          expect(
            (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'day_contexts'",
                )
                .get()),
            hasLength(1),
          );
          final context = await DayContextRepository(db)
              .save('2026-09-18', DayContextKind.travel, null);
          expect(context.kind, DayContextKind.travel);
          expect(await db.syncDao.pendingCount(), 1);
        } finally {
          await db.close();
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'partial v8 gains empty plan-title history without a schema bump',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'planner_migration_v8_title_history',
      );
      final file = File('${directory.path}/planner.sqlite3');
      try {
        MigrationSchema.create(file, 8);
        final db = AppDatabase(NativeDatabase(file));
        try {
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            8,
          );
          final task = await db.taskDao.getTaskById('task-1');
          expect(task?.planTitleHistoryJson, '[]');
          expect(task?.displayPlanChangeId, isNull);
          // A database already advertising v8 has no migration provenance.
          // Its ambiguous cache is not promoted to a manual source on open.
          expect(task?.actualDurationMin, 15);
          expect(task?.manualDurationAdjustmentMin, 0);
          expect(task?.manualActualSet, isFalse);
        } finally {
          await db.close();
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('v8 reconciliation and recovery are retry-safe across reopen', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v8_retry',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 7);
      final first = AppDatabase(NativeDatabase(file));
      final firstOperationCount = await first
          .customSelect(
            "SELECT COUNT(*) AS count FROM sync_log "
            "WHERE table_name = 'tasks' AND record_id = 'task-1' "
            "AND payload LIKE '%\"_planner_payload_version\":2%'",
          )
          .getSingle();
      final firstRecoveryCount = await first
          .customSelect(
            "SELECT COUNT(*) AS count FROM planner_migration_recovery "
            "WHERE recovery_id = 'v8:tasks:task-1'",
          )
          .getSingle();
      expect(firstOperationCount.read<int>('count'), 1);
      expect(firstRecoveryCount.read<int>('count'), 1);
      await first.close();

      final reopened = AppDatabase(NativeDatabase(file));
      try {
        final operationCount = await reopened
            .customSelect(
              "SELECT COUNT(*) AS count FROM sync_log "
              "WHERE table_name = 'tasks' AND record_id = 'task-1' "
              "AND payload LIKE '%\"_planner_payload_version\":2%'",
            )
            .getSingle();
        final recoveryCount = await reopened
            .customSelect(
              "SELECT COUNT(*) AS count FROM planner_migration_recovery "
              "WHERE recovery_id = 'v8:tasks:task-1'",
            )
            .getSingle();
        expect(operationCount.read<int>('count'), 1);
        expect(recoveryCount.read<int>('count'), 1);
      } finally {
        await reopened.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
