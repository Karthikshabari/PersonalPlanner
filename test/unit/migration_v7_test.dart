import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test(
    'v8 creates sync tables, metadata and atomic mutation triggers',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          8,
        );
        final tables = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get();
        expect(
          tables.map((row) => row.read<String>('name')),
          containsAll(<String>['sync_log', 'sync_conflicts', 'sync_state']),
        );

        final now = DateTime.utc(2026, 1, 1);
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'category-1',
                name: 'Work',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
              ),
            );
        final row = await db.categoryDao.getCategoryById('category-1');
        expect(row?.serverVersion, isNull);
        expect(row?.syncStatus, 1);
        expect(await db.syncDao.pendingCount(), 1);

        await db.syncDao.runWithoutOutbound(() async {
          await db.customStatement(
            "UPDATE categories SET name = 'Remote Work', server_version = 8 "
            "WHERE id = 'category-1'",
          );
        });
        expect(await db.syncDao.pendingCount(), 1);
        expect(
          (await db.categoryDao.getCategoryById('category-1'))?.name,
          'Remote Work',
        );
        expect(
          (await db.categoryDao.getCategoryById('category-1'))?.serverVersion,
          8,
        );
      } finally {
        await db.close();
      }
    },
  );

  test('all eleven syncable tables create durable outbox entries', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 1, 1, 9);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'category-all',
              name: 'All',
              colorHex: '#4285F4',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-all',
              name: 'all',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: 'rule-all',
              rrule: 'FREQ=DAILY',
              taskTitle: 'Recurring',
              durationMin: 30,
              startTimeOfDay: '09:00',
              startDate: '2026-01-01',
              createdAt: now,
              updatedAt: now,
              categoryId: const Value('category-all'),
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'task-all',
              title: 'Task',
              createdAt: now,
              updatedAt: now,
              categoryId: const Value('category-all'),
              recurringRuleId: const Value('rule-all'),
            ),
          );
      await db
          .into(db.taskTemplates)
          .insert(
            TaskTemplatesCompanion.insert(
              id: 'template-all',
              name: 'Template',
              durationMin: 30,
              createdAt: now,
              updatedAt: now,
              categoryId: const Value('category-all'),
            ),
          );
      await db
          .into(db.dailyReviews)
          .insert(
            DailyReviewsCompanion.insert(
              id: 'daily-all',
              date: '2026-01-01',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.weeklyReviews)
          .insert(
            WeeklyReviewsCompanion.insert(
              id: 'weekly-all',
              weekStartDate: '2025-12-29',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.subtasks)
          .insert(
            SubtasksCompanion.insert(
              id: 'subtask-all',
              taskId: 'task-all',
              title: 'Subtask',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.taskTags)
          .insert(
            TaskTagsCompanion.insert(
              taskId: 'task-all',
              tagId: 'tag-all',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: 'timer-all',
              taskId: 'task-all',
              startedAt: now,
              state: const Value('running'),
              runningSince: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.dayContexts)
          .insert(
            DayContextsCompanion.insert(
              id: '00000000-0000-7000-8000-000000000011',
              date: '2026-01-01',
              kind: 'office',
              createdAt: now,
              updatedAt: now,
            ),
          );

      expect(await db.syncDao.pendingCount(), 11);
      final operations = await db.select(db.syncLog).get();
      expect(
        operations.map((row) => row.entityTableName).toSet(),
        containsAll(<String>[
          'tasks',
          'subtasks',
          'categories',
          'tags',
          'task_tags',
          'recurring_rules',
          'task_templates',
          'daily_reviews',
          'weekly_reviews',
          'timer_sessions',
          'day_contexts',
        ]),
      );
    } finally {
      await db.close();
    }
  });

  test(
    'reopening repairs mixed-format instant text without an outbox echo',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'planner_timestamp_normalization',
      );
      final file = File('${directory.path}/planner.sqlite3');
      try {
        final before = AppDatabase(NativeDatabase(file));
        await before.customStatement('''
        INSERT INTO tasks (
          id, title, estimated_duration_min, actual_duration_min,
          manual_duration_adjustment_min, category_id, priority, status,
          notes, start_time, end_time, recurring_rule_id, rescheduled_from_id,
          rescheduled_to_id, is_inbox, missed_at, created_at, updated_at,
          deleted_at,
          sync_status, revision
        ) VALUES (
          'mixed-format', 'Mixed', 30, NULL, 0, NULL, 0, 'planned',
          NULL, '2026-09-01T23:00:00+00:00', '2026-09-02T00:00:00+00:00',
          NULL, NULL, NULL, 0, NULL,
          '2026-09-01T23:00:00+00:00', '2026-09-02T00:00:00+00:00',
          NULL, 0, 1
        )
      ''');
        final pendingBefore = await before.syncDao.pendingCount();
        await before.close();

        final after = AppDatabase(NativeDatabase(file));
        try {
          final row = await after
              .customSelect(
                'SELECT start_time, updated_at FROM tasks WHERE id = ?',
                variables: [Variable<String>('mixed-format')],
              )
              .getSingle();
          expect(row.read<String>('start_time'), '2026-09-01T23:00:00.000Z');
          expect(row.read<String>('updated_at'), '2026-09-02T00:00:00.000Z');
          expect(await after.syncDao.pendingCount(), pendingBefore);
        } finally {
          await after.close();
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('v6 to v8 upgrade preserves the released FTS objects', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v7_fts',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 6);
      final raw = sqlite3.sqlite3.open(file.path);
      raw.execute(
        "UPDATE tasks SET title = 'Preserved search term' WHERE id = 'task-1'",
      );
      expect(raw.select('PRAGMA user_version').single['user_version'], 6);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('sync_log', 'sync_conflicts', 'sync_state')",
        ),
        isEmpty,
      );
      expect(
        raw
            .select('PRAGMA table_info(tasks)')
            .any((row) => row['name'] == 'server_version'),
        isFalse,
      );
      final beforeObjects = raw
          .select(
            "SELECT name, sql FROM sqlite_master "
            "WHERE name IN ('tasks_fts', 'tasks_fts_insert', 'tasks_fts_update', "
            "'tasks_fts_delete') ORDER BY name",
          )
          .map(
            (row) => <String, Object?>{'name': row['name'], 'sql': row['sql']},
          )
          .toList();
      raw.dispose();

      final after = AppDatabase(NativeDatabase(file));
      try {
        final afterObjects = await after
            .customSelect(
              "SELECT name, sql FROM sqlite_master "
              "WHERE name IN ('tasks_fts', 'tasks_fts_insert', 'tasks_fts_update', "
              "'tasks_fts_delete') ORDER BY name",
            )
            .get();
        expect(afterObjects.map((row) => row.data).toList(), beforeObjects);
        final matches = await after
            .customSelect(
              'SELECT count(*) AS count FROM tasks_fts '
              'WHERE tasks_fts MATCH ?',
              variables: [Variable<String>('Preserved')],
            )
            .getSingle();
        expect(matches.read<int>('count'), 1);
      } finally {
        await after.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
