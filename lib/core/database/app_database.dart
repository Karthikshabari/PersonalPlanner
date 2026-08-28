// TableMigration is Drift's supported SQLite table-rebuild primitive. Schema
// v6 needs it to add foreign keys and remove legacy inline uniqueness safely.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/category_dao.dart';
import 'daos/recurring_rule_dao.dart';
import 'daos/review_dao.dart';
import 'daos/stats_dao.dart';
import 'daos/subtask_dao.dart';
import 'daos/tag_dao.dart';
import 'daos/task_dao.dart';
import 'daos/template_dao.dart';
import 'daos/timer_dao.dart';
import 'converters.dart';
import 'tables/app_settings_table.dart';
import 'tables/categories_table.dart';
import 'tables/daily_reviews_table.dart';
import 'tables/daily_stats_cache_table.dart';
import 'tables/recurring_rules_table.dart';
import 'tables/subtasks_table.dart';
import 'tables/tags_table.dart';
import 'tables/tasks_table.dart';
import 'tables/task_templates_table.dart';
import 'tables/timer_sessions_table.dart';
import 'tables/weekly_reviews_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    Categories,
    AppSettings,
    Subtasks,
    Tags,
    TaskTags,
    RecurringRules,
    TaskTemplates,
    DailyReviews,
    WeeklyReviews,
    DailyStatsCache,
    TimerSessions,
  ],
  daos: [
    TaskDao,
    CategoryDao,
    SubtaskDao,
    TagDao,
    RecurringRuleDao,
    TemplateDao,
    ReviewDao,
    StatsDao,
    TimerDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    return AppDatabase(_openConnection(p.join(dir.path, 'personal_planner.sqlite3')));
  }

  static QueryExecutor _openConnection(String path) =>
      NativeDatabase.createInBackground(
        File(path),
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      );

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
          await _createFts();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(subtasks);
            await m.createTable(tags);
            await m.createTable(taskTags);
          }
          if (from < 3) {
            await m.createTable(recurringRules);
            await m.createTable(taskTemplates);
          }
          if (from < 4) {
            await m.createTable(dailyReviews);
            await m.createTable(weeklyReviews);
            await m.createTable(dailyStatsCache);
          }
          if (from < 5) {
            await m.createTable(timerSessions);
          }
          if (from < 6) {
            await _migrateToV6(m, from);
          }
          // Indexes are idempotent — always ensure they exist.
          await _createIndexes();
          await _createFts();
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Schema-v6 is the audit stabilization migration. It upgrades every
  /// released v1-v5 database without resetting user data, then rebuilds the
  /// tables whose constraints or foreign keys changed.
  Future<void> _migrateToV6(Migrator m, int originalVersion) async {
    await _normalizeLegacyRows();

    await m.alterTable(TableMigration(categories));
    await m.alterTable(TableMigration(
      tasks,
      newColumns: [tasks.manualDurationAdjustmentMin],
    ));
    // Tables introduced while upgrading directly from an older version were
    // just created from the v6 definitions and must not be rebuilt again.
    if (originalVersion >= 2) {
      await m.alterTable(TableMigration(subtasks));
      await m.alterTable(TableMigration(tags));
      await m.alterTable(TableMigration(
        taskTags,
        newColumns: [
          taskTags.updatedAt,
          taskTags.deletedAt,
          taskTags.revision,
        ],
        columnTransformer: {
          taskTags.updatedAt: taskTags.createdAt,
        },
      ));
    }
    if (originalVersion >= 3) {
      await m.alterTable(TableMigration(recurringRules));
      await m.alterTable(TableMigration(taskTemplates));
    }
    if (originalVersion >= 4) {
      await m.alterTable(TableMigration(dailyReviews));
      await m.alterTable(TableMigration(weeklyReviews));
      await m.alterTable(TableMigration(
        dailyStatsCache,
        newColumns: [
          dailyStatsCache.plannedTasks,
          dailyStatsCache.inProgressTasks,
        ],
      ));
    }
    if (originalVersion >= 5) {
      await m.alterTable(TableMigration(timerSessions));
    }

    await _rejectUnsafeActiveDuplicates();

    final violations = await customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      throw StateError(
        'Schema v6 migration left ${violations.length} foreign-key violation(s)',
      );
    }
  }

  Future<void> _normalizeLegacyRows() async {
    // Optional references can be repaired without losing their owning row.
    await _customStatementIfTables(['tasks', 'categories'],
      'UPDATE tasks SET category_id = NULL '
      'WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = tasks.category_id)',
    );
    await _customStatementIfTables(['tasks', 'recurring_rules'],
      'UPDATE tasks SET recurring_rule_id = NULL '
      'WHERE recurring_rule_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM recurring_rules r WHERE r.id = tasks.recurring_rule_id)',
    );
    await _customStatementIfTables(['tasks'],
      'UPDATE tasks SET rescheduled_from_id = NULL '
      'WHERE rescheduled_from_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM tasks parent WHERE parent.id = tasks.rescheduled_from_id)',
    );
    await _customStatementIfTables(['tasks'],
      'UPDATE tasks SET rescheduled_to_id = NULL '
      'WHERE rescheduled_to_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM tasks child WHERE child.id = tasks.rescheduled_to_id)',
    );
    await _customStatementIfTables(['recurring_rules', 'categories'],
      'UPDATE recurring_rules SET category_id = NULL '
      'WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = recurring_rules.category_id)',
    );
    await _customStatementIfTables(['task_templates', 'categories'],
      'UPDATE task_templates SET category_id = NULL '
      'WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = task_templates.category_id)',
    );

    // Child rows without a parent are already unreachable in the application.
    await _customStatementIfTables(['task_tags', 'tasks', 'tags'],
      'DELETE FROM task_tags WHERE '
      'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_tags.task_id) '
      'OR NOT EXISTS (SELECT 1 FROM tags g WHERE g.id = task_tags.tag_id)',
    );
    await _customStatementIfTables(['subtasks', 'tasks'],
      'DELETE FROM subtasks WHERE '
      'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = subtasks.task_id)',
    );
    await _customStatementIfTables(['timer_sessions', 'tasks'],
      'DELETE FROM timer_sessions WHERE '
      'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = timer_sessions.task_id)',
    );

    // Preserve the editor's historical overnight interpretation before the
    // database starts enforcing end > start. New overnight writes are rejected.
    await _customStatementIfTables(['tasks'],
      "UPDATE tasks SET end_time = strftime('%Y-%m-%dT%H:%M:%fZ', end_time, '+1 day') "
      'WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time <= start_time',
    );
    await _customStatementIfTables(['tasks'],
      'UPDATE tasks SET priority = MIN(4, MAX(0, priority)), '
      "status = CASE WHEN status IN ('planned', 'in_progress', 'completed', 'skipped', 'cancelled', 'rescheduled') THEN status ELSE 'planned' END, "
      'estimated_duration_min = CASE WHEN estimated_duration_min > 0 THEN estimated_duration_min ELSE NULL END, '
      'actual_duration_min = CASE WHEN actual_duration_min >= 0 THEN actual_duration_min ELSE NULL END',
    );
    await _customStatementIfTables(['categories'],
      "UPDATE categories SET color_hex = '#4285F4' "
      "WHERE color_hex NOT GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]'",
    );
    await _customStatementIfTables(['categories'],
      'UPDATE categories SET sort_order = MAX(0, sort_order)',
    );
    await _customStatementIfTables(['subtasks'],
      'UPDATE subtasks SET sort_order = MAX(0, sort_order)',
    );
    await _customStatementIfTables(['recurring_rules'],
      "UPDATE recurring_rules SET duration_min = MAX(1, duration_min), "
      "priority = MIN(4, MAX(0, priority)), "
      "start_time_of_day = CASE WHEN start_time_of_day GLOB '[01][0-9]:[0-5][0-9]' OR start_time_of_day GLOB '2[0-3]:[0-5][0-9]' THEN start_time_of_day ELSE '09:00' END",
    );
    await _customStatementIfTables(['task_templates'],
      'UPDATE task_templates SET duration_min = MAX(1, duration_min), '
      'priority = MIN(4, MAX(0, priority))',
    );
    await _customStatementIfTables(['daily_reviews'],
      'UPDATE daily_reviews SET '
      'energy_level = CASE WHEN energy_level BETWEEN 1 AND 5 THEN energy_level ELSE NULL END, '
      'productivity_rating = CASE WHEN productivity_rating BETWEEN 1 AND 5 THEN productivity_rating ELSE NULL END, '
      'planning_accuracy_rating = CASE WHEN planning_accuracy_rating BETWEEN 1 AND 5 THEN planning_accuracy_rating ELSE NULL END',
    );
    await _customStatementIfTables(['weekly_reviews'],
      'UPDATE weekly_reviews SET overall_rating = '
      'CASE WHEN overall_rating BETWEEN 1 AND 5 THEN overall_rating ELSE NULL END',
    );
    await _customStatementIfTables(['timer_sessions'],
      'UPDATE timer_sessions SET duration_sec = MAX(0, duration_sec), '
      'ended_at = CASE WHEN ended_at IS NOT NULL AND ended_at < started_at '
      'THEN started_at ELSE ended_at END',
    );

    // A previous service-level race could leave more than one open session.
    // Keep the newest and finalize every older one at the next session start.
    await _customStatementIfTables(['timer_sessions'],
      'UPDATE timer_sessions AS current SET '
      'ended_at = COALESCE((SELECT MIN(newer.started_at) FROM timer_sessions newer '
      'WHERE newer.ended_at IS NULL AND newer.deleted_at IS NULL '
      'AND (newer.started_at > current.started_at OR '
      '(newer.started_at = current.started_at AND newer.id > current.id))), current.started_at), '
      'duration_sec = MAX(0, CAST(strftime(\'%s\', COALESCE((SELECT MIN(newer.started_at) '
      'FROM timer_sessions newer WHERE newer.ended_at IS NULL AND newer.deleted_at IS NULL '
      'AND (newer.started_at > current.started_at OR '
      '(newer.started_at = current.started_at AND newer.id > current.id))), current.started_at)) AS INTEGER) '
      '- CAST(strftime(\'%s\', current.started_at) AS INTEGER)) '
      'WHERE current.ended_at IS NULL AND current.deleted_at IS NULL '
      'AND current.id != (SELECT id FROM timer_sessions '
      'WHERE ended_at IS NULL AND deleted_at IS NULL '
      'ORDER BY started_at DESC, id DESC LIMIT 1)',
    );
  }

  Future<void> _customStatementIfTables(
    Iterable<String> tableNames,
    String statement,
  ) async {
    for (final tableName in tableNames) {
      final exists = await customSelect(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '$tableName'",
      ).getSingleOrNull();
      if (exists == null) return;
    }
    await customStatement(statement);
  }

  Future<void> _rejectUnsafeActiveDuplicates() async {
    final duplicateQueries = <String, String>{
      'tag names':
          'SELECT name FROM tags WHERE deleted_at IS NULL GROUP BY name HAVING COUNT(*) > 1 LIMIT 1',
      'daily review dates':
          'SELECT date FROM daily_reviews WHERE deleted_at IS NULL GROUP BY date HAVING COUNT(*) > 1 LIMIT 1',
      'weekly review weeks':
          'SELECT week_start_date FROM weekly_reviews WHERE deleted_at IS NULL GROUP BY week_start_date HAVING COUNT(*) > 1 LIMIT 1',
    };
    for (final entry in duplicateQueries.entries) {
      final duplicate = await customSelect(entry.value).getSingleOrNull();
      if (duplicate != null) {
        throw StateError(
          'Schema v6 migration cannot continue: duplicate active ${entry.key} '
          'exist. Delete or tombstone the duplicate row(s), then retry.',
        );
      }
    }
  }

  Future<void> _createIndexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_day ON tasks (start_time, end_time) WHERE deleted_at IS NULL AND is_inbox = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_inbox ON tasks (is_inbox, status) WHERE deleted_at IS NULL');
    await customStatement('DROP INDEX IF EXISTS idx_tasks_overdue');
    await customStatement(
        'CREATE INDEX idx_tasks_overdue ON tasks (end_time, status, missed_at) WHERE deleted_at IS NULL AND is_inbox = 0 AND status IN (\'planned\', \'in_progress\')');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_overlap ON tasks (start_time, end_time, status) WHERE deleted_at IS NULL AND is_inbox = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_sync ON tasks (sync_status) WHERE sync_status != 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_category_date ON tasks (category_id, start_time) WHERE deleted_at IS NULL AND is_inbox = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_recurring ON tasks (recurring_rule_id, start_time) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks (task_id, sort_order) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_timer_sessions_task ON timer_sessions (task_id, started_at) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_active ON tags (name) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_reviews_date_active ON daily_reviews (date) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_reviews_week_active ON weekly_reviews (week_start_date) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_task_tags_task_active ON task_tags (task_id, tag_id) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_timer_one_active ON timer_sessions ((1)) WHERE ended_at IS NULL AND deleted_at IS NULL');
  }

  Future<void> _createFts() async {
    // Recreate the v6 object so databases created during the partial v6
    // remediation cannot retain the old, non-external-content shape.
    await customStatement('DROP TRIGGER IF EXISTS tasks_fts_insert');
    await customStatement('DROP TRIGGER IF EXISTS tasks_fts_update');
    await customStatement('DROP TRIGGER IF EXISTS tasks_fts_delete');
    await customStatement('DROP TABLE IF EXISTS tasks_fts');
    await customStatement(
      'CREATE VIRTUAL TABLE tasks_fts USING fts5('
      'title, description, notes, content=tasks, content_rowid=rowid)',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS tasks_fts_insert AFTER INSERT ON tasks '
      'WHEN NEW.deleted_at IS NULL BEGIN '
      'INSERT INTO tasks_fts(rowid, title, description, notes) '
      "VALUES (NEW.rowid, NEW.title, COALESCE(NEW.description, ''), COALESCE(NEW.notes, '')); END",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS tasks_fts_update '
      'AFTER UPDATE OF title, description, notes, deleted_at ON tasks BEGIN '
      "INSERT INTO tasks_fts(tasks_fts, rowid, title, description, notes) "
      "SELECT 'delete', OLD.rowid, OLD.title, COALESCE(OLD.description, ''), COALESCE(OLD.notes, '') "
      'WHERE OLD.deleted_at IS NULL; '
      'INSERT INTO tasks_fts(rowid, title, description, notes) '
      "SELECT NEW.rowid, NEW.title, COALESCE(NEW.description, ''), COALESCE(NEW.notes, '') "
      'WHERE NEW.deleted_at IS NULL; END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS tasks_fts_delete AFTER DELETE ON tasks '
      'WHEN OLD.deleted_at IS NULL BEGIN '
      "INSERT INTO tasks_fts(tasks_fts, rowid, title, description, notes) "
      "VALUES ('delete', OLD.rowid, OLD.title, COALESCE(OLD.description, ''), COALESCE(OLD.notes, '')); END",
    );
    await customStatement(
      'INSERT INTO tasks_fts(rowid, title, description, notes) '
      "SELECT rowid, title, COALESCE(description, ''), COALESCE(notes, '') "
      'FROM tasks WHERE deleted_at IS NULL',
    );
  }
}
