import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('v8 fixture upgrades to v10', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v10',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 8);
      final raw = sqlite3.sqlite3.open(file.path);
      // Inserted in this order; created_at puts them in the order b, c, a.
      for (final (operationId, createdAt) in [
        ('op-a', '2026-01-01T00:00:03.000Z'),
        ('op-b', '2026-01-01T00:00:01.000Z'),
        ('op-c', '2026-01-01T00:00:02.000Z'),
      ]) {
        raw.execute(
          'INSERT INTO sync_log(operation_id, table_name, record_id, '
          'operation, payload, state, attempt_count, created_at, updated_at) '
          "VALUES (?, 'tasks', 'task-1', 'update', '{}', 'pending', 0, ?, ?)",
          [operationId, createdAt, createdAt],
        );
      }
      raw.execute(
        'INSERT INTO timer_sessions(id, task_id, started_at, ended_at, '
        'duration_sec, created_at, updated_at, state, running_since) '
        "VALUES ('timer-bad', 'task-1', '2026-01-01T00:00:00.000Z', NULL, 0, "
        "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 'paused', "
        "'2026-01-01T00:00:00.000Z')",
      );
      raw.dispose();

      final db = AppDatabase(NativeDatabase(file));
      try {
        // (a)
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          12,
        );

        // (b)
        final bySeq = await db
            .customSelect(
              'SELECT operation_id FROM sync_log '
              "WHERE operation_id IN ('op-a', 'op-b', 'op-c') ORDER BY seq",
            )
            .get();
        final byTime = await db
            .customSelect(
              'SELECT operation_id FROM sync_log '
              "WHERE operation_id IN ('op-a', 'op-b', 'op-c') "
              'ORDER BY julianday(created_at)',
            )
            .get();
        expect(
          bySeq.map((row) => row.read<String>('operation_id')).toList(),
          byTime.map((row) => row.read<String>('operation_id')).toList(),
        );
        expect(bySeq.map((row) => row.read<String>('operation_id')).toList(), [
          'op-b',
          'op-c',
          'op-a',
        ]);

        Future<String> tableSql(String name) async =>
            (await db
                    .customSelect(
                      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                      variables: [Variable<String>(name)],
                    )
                    .getSingle())
                .read<String>('sql');

        // (c)
        expect(
          await tableSql('tasks'),
          contains('json_valid(plan_title_history_json)'),
        );
        // (d)
        expect(
          await tableSql('timer_sessions'),
          contains("state IN ('running', 'paused', 'finished')"),
        );

        // (e)
        await expectLater(
          db.customStatement(
            'INSERT INTO timer_sessions(id, task_id, started_at, ended_at, '
            'duration_sec, created_at, updated_at, state) '
            "VALUES ('timer-bogus', 'task-1', '2026-01-01T00:00:00.000Z', "
            "NULL, 0, '2026-01-01T00:00:00.000Z', "
            "'2026-01-01T00:00:00.000Z', 'bogus')",
          ),
          throwsA(isA<sqlite3.SqliteException>()),
        );

        final indexNames =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'index'",
                    )
                    .get())
                .map((row) => row.read<String>('name'))
                .toSet();
        // (f)
        expect(
          indexNames,
          containsAll(<String>[
            'idx_tasks_rescheduled_from_fk',
            'idx_tasks_rescheduled_to_fk',
            'idx_tasks_category_fk',
            'idx_tasks_recurring_rule_fk',
            'idx_task_tags_tag_fk',
            'idx_subtasks_task_fk',
            'idx_timer_sessions_task_fk',
            'idx_recurring_rules_category_fk',
            'idx_task_templates_category_fk',
          ]),
        );
        // (g)
        expect(indexNames, isNot(contains('idx_sync_log_pending')));
        expect(
          indexNames,
          containsAll(<String>['idx_sync_log_state_seq', 'idx_sync_log_seq']),
        );
        final triggers = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'trigger' "
              "AND name = 'sync_log_assign_seq'",
            )
            .get();
        expect(triggers, hasLength(1));
        final plan =
            (await db
                    .customSelect(
                      'EXPLAIN QUERY PLAN SELECT 1 FROM tasks '
                      "WHERE rescheduled_from_id = 'x'",
                    )
                    .get())
                .map((row) => row.data.values.join(' '))
                .join('\n');
        expect(plan, contains('idx_tasks_rescheduled_from_fk'));

        // (h)
        final repaired = await db
            .customSelect(
              'SELECT state, running_since FROM timer_sessions '
              "WHERE id = 'timer-bad'",
            )
            .getSingle();
        expect(repaired.readNullable<String>('running_since'), isNull);
        final ledger = await db
            .customSelect(
              'SELECT recovery_id FROM planner_migration_recovery '
              "WHERE recovery_id LIKE 'v10:timer_sessions:%:state_bounds'",
            )
            .get();
        expect(ledger.map((row) => row.read<String>('recovery_id')), [
          'v10:timer_sessions:timer-bad:state_bounds',
        ]);

        // (i)
        final matches = await db.taskDao.searchTasks('"Legacy"');
        expect(matches.map((row) => row.id), contains('task-1'));
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
