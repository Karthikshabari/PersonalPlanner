import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test(
    'every exact v1-v5 snapshot upgrades to v7 with valid data intact',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'planner_migration_v6',
      );
      try {
        for (var version = 1; version <= 5; version++) {
          final file = File('${directory.path}/v$version.sqlite3');
          MigrationSchema.create(file, version);
          final db = AppDatabase(NativeDatabase(file));
          try {
            expect(
              (await db.customSelect('PRAGMA user_version').getSingle())
                  .read<int>('user_version'),
              7,
              reason: 'v$version did not reach schema v7',
            );
            expect(
              (await db.select(db.tasks).get()).single.title,
              'Legacy task',
            );
            expect((await db.select(db.categories).get()).single.name, 'Work');
            expect(
              (await db.select(db.appSettings).get()).single.value,
              'dark',
            );
            if (version >= 2) {
              expect(
                (await db.select(db.taskTags).get()).single.updatedAt.toUtc(),
                DateTime.parse(MigrationSchema.timestamp),
              );
            }
            if (version >= 3) {
              expect(
                (await db.select(db.recurringRules).get()).single.id,
                'rule-1',
              );
              expect(
                (await db.select(db.taskTemplates).get()).single.id,
                'template-1',
              );
            }
            if (version >= 4) {
              expect(
                (await db.select(db.dailyReviews).get()).single.id,
                'daily-1',
              );
              expect(
                (await db.select(db.weeklyReviews).get()).single.id,
                'weekly-1',
              );
              expect(
                (await db.select(db.dailyStatsCache).get()).single.totalTasks,
                1,
              );
            }
            if (version >= 5) {
              expect(
                (await db.select(db.timerSessions).get()).single.durationSec,
                30,
              );
            }
          } finally {
            await db.close();
          }
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('v6 migration records orphan child history before cleanup', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v6_orphans',
    );
    final file = File('${directory.path}/orphans.sqlite3');
    try {
      MigrationSchema.create(file, 5);
      final legacy = sqlite3.open(file.path);
      legacy.execute('''
        INSERT INTO subtasks
          (id, task_id, title, created_at, updated_at)
        VALUES ('orphan-subtask', 'missing-task', 'Keep this title',
          '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}')
      ''');
      legacy.execute('''
        INSERT INTO timer_sessions
          (id, task_id, started_at, ended_at, duration_sec, created_at, updated_at)
        VALUES ('orphan-timer', 'missing-task', '${MigrationSchema.timestamp}',
          '${MigrationSchema.timestamp}', 90, '${MigrationSchema.timestamp}',
          '${MigrationSchema.timestamp}')
      ''');
      legacy.execute('''
        INSERT INTO task_tags (task_id, tag_id, created_at)
        VALUES ('missing-task', 'missing-tag', '${MigrationSchema.timestamp}')
      ''');
      legacy.dispose();

      final db = AppDatabase(NativeDatabase(file));
      try {
        final recovered = await db
            .customSelect(
              'SELECT table_name, row_id, payload, reason '
              'FROM planner_migration_recovery ORDER BY table_name, row_id',
            )
            .get();
        expect(recovered, hasLength(3));
        expect(
          recovered.map((row) => row.read<String>('row_id')),
          containsAll(<String>[
            'missing-task:missing-tag',
            'orphan-subtask',
            'orphan-timer',
          ]),
        );
        expect(
          recovered.map((row) => row.read<String>('payload')),
          everyElement(isNotEmpty),
        );
        expect(
          recovered.map((row) => row.read<String>('reason')),
          everyElement(contains('Missing')),
        );
        expect(await db.select(db.subtasks).get(), hasLength(1));
        expect(await db.select(db.timerSessions).get(), hasLength(1));
        expect(await db.select(db.taskTags).get(), hasLength(1));
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('v6 creates and enforces foreign keys, checks, partial indexes, and FTS', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final tableSql = <String, String>{};
      final tables = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type IN ('table', 'index', 'trigger')",
          )
          .get();
      for (final row in tables) {
        final name = row.read<String>('name');
        final sql = row.read<String?>('sql');
        if (sql != null) tableSql[name] = sql;
      }

      expect(tableSql['tasks'], contains('REFERENCES'));
      expect(tableSql['tasks'], contains('CHECK'));
      expect(tableSql['subtasks'], contains('REFERENCES'));
      expect(tableSql['task_tags'], contains('REFERENCES'));
      expect(tableSql['recurring_rules'], contains('REFERENCES'));
      expect(tableSql['task_templates'], contains('REFERENCES'));
      expect(tableSql['timer_sessions'], contains('REFERENCES'));
      expect(tableSql['tasks_fts'], contains('fts5'));
      expect(tableSql['tasks_fts_insert'], contains('AFTER INSERT'));
      expect(tableSql['tasks_fts_update'], contains('AFTER UPDATE'));
      expect(tableSql['tasks_fts_delete'], contains('AFTER DELETE'));

      final indexes = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index'",
          )
          .get();
      final indexSql = <String, String>{
        for (final row in indexes)
          row.read<String>('name'): row.read<String?>('sql') ?? '',
      };
      for (final name in [
        'idx_tags_name_active',
        'idx_daily_reviews_date_active',
        'idx_weekly_reviews_week_active',
      ]) {
        expect(indexSql, contains(name));
        expect(indexSql[name], contains('WHERE deleted_at IS NULL'));
      }
      expect(indexSql, contains('idx_timer_one_active'));
      expect(indexSql['idx_timer_one_active'], contains('ended_at IS NULL'));
      expect(indexSql['idx_timer_one_active'], contains('deleted_at IS NULL'));

      final taskForeignKeys = await db
          .customSelect('PRAGMA foreign_key_list(tasks)')
          .get();
      expect(
        taskForeignKeys.map((row) => row.read<String>('table')),
        containsAll(<String>['categories', 'recurring_rules', 'tasks']),
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      Future<void> expectFailure(Future<void> Function() action) async {
        try {
          await action();
          fail('Expected SQLite constraint failure');
        } catch (error) {
          expect(error, isNot(isA<TestFailure>()));
        }
      }

      await expectFailure(
        () => db.customStatement('''
        INSERT INTO tasks
          (id, title, created_at, updated_at, priority)
        VALUES ('invalid-priority', 'Invalid', '${MigrationSchema.timestamp}',
          '${MigrationSchema.timestamp}', 5)
      '''),
      );
      await expectFailure(
        () => db.customStatement('''
        INSERT INTO timer_sessions
          (id, task_id, started_at, created_at, updated_at)
        VALUES ('orphan-timer', 'missing-task', '${MigrationSchema.timestamp}',
          '${MigrationSchema.timestamp}', '${MigrationSchema.timestamp}')
      '''),
      );

      Future<int> match(String query) async {
        final row = await db
            .customSelect(
              'SELECT count(*) AS count FROM tasks_fts WHERE tasks_fts MATCH ?',
              variables: [Variable<String>(query)],
            )
            .getSingle();
        return row.read<int>('count');
      }

      final task = TasksCompanion.insert(
        id: 'fts-task',
        title: 'Searchable title',
        description: const Value('searchable description'),
        notes: const Value('searchable notes'),
        createdAt: DateTime.parse(MigrationSchema.timestamp),
        updatedAt: DateTime.parse(MigrationSchema.timestamp),
      );
      await db.into(db.tasks).insert(task);
      expect(await match('Searchable'), 1);

      await db.customStatement(
        "UPDATE tasks SET title = 'Updated needle', description = 'updated detail', "
        "notes = 'updated memo' WHERE id = 'fts-task'",
      );
      expect(await match('needle'), 1);
      expect(await match('Searchable'), 0);

      await db.customStatement(
        "UPDATE tasks SET deleted_at = '${MigrationSchema.timestamp}' "
        "WHERE id = 'fts-task'",
      );
      expect(await match('needle'), 0);

      await db.customStatement(
        "UPDATE tasks SET deleted_at = NULL WHERE id = 'fts-task'",
      );
      expect(await match('needle'), 1);

      await db.customStatement("DELETE FROM tasks WHERE id = 'fts-task'");
      expect(await match('needle'), 0);
    } finally {
      await db.close();
    }
  });

  test(
    'v6 rejects unsafe duplicate active identities with an actionable error',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'planner_migration_v6_reject',
      );
      final file = File('${directory.path}/duplicate.sqlite3');
      try {
        MigrationSchema.create(file, 2);
        final legacy = sqlite3.open(file.path);
        legacy.execute('''
        INSERT INTO tags (id, name, created_at, updated_at)
        VALUES ('tag-duplicate', 'legacy', '${MigrationSchema.timestamp}',
          '${MigrationSchema.timestamp}')
      ''');
        legacy.dispose();

        final db = AppDatabase(NativeDatabase(file));
        try {
          await expectLater(
            db.select(db.tasks).get(),
            throwsA(
              predicate(
                (error) =>
                    error.toString().contains('duplicate active tag names'),
              ),
            ),
          );
        } finally {
          await db.close();
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
}
