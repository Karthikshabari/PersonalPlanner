import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Exact hand-written snapshots of the schemas shipped by v1 through v5.
///
/// These deliberately omit the v6 foreign keys, checks, task-tag tombstone
/// columns, and partial indexes.  The migration tests use these snapshots so
/// that a current generated schema cannot accidentally test only a fresh
/// install.
class MigrationSchema {
  static const timestamp = '2026-01-01T00:00:00.000Z';

  static void create(File file, int version) {
    if (version < 1 || version > 5) {
      throw ArgumentError.value(version, 'version', 'must be between 1 and 5');
    }
    final db = sqlite3.open(file.path);
    try {
      db.execute('PRAGMA foreign_keys = OFF');
      _createV1(db);
      if (version >= 2) _createV2(db);
      if (version >= 3) _createV3(db);
      if (version >= 4) _createV4(db);
      if (version >= 5) _createV5(db);
      db.execute('PRAGMA user_version = $version');
      _seed(db, version);
    } finally {
      db.dispose();
    }
  }

  static void _createV1(Database db) {
    db.execute('''
      CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NULL,
        start_time TEXT NULL,
        end_time TEXT NULL,
        estimated_duration_min INTEGER NULL,
        actual_duration_min INTEGER NULL,
        category_id TEXT NULL,
        priority INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'planned',
        notes TEXT NULL,
        recurring_rule_id TEXT NULL,
        rescheduled_from_id TEXT NULL,
        rescheduled_to_id TEXT NULL,
        is_inbox INTEGER NOT NULL DEFAULT 0,
        missed_at TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute('''
      CREATE TABLE categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_focus INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute(
      'CREATE TABLE app_settings '
      '(key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  static void _createV2(Database db) {
    db.execute('''
      CREATE TABLE subtasks (
        id TEXT NOT NULL PRIMARY KEY,
        task_id TEXT NOT NULL,
        title TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute('''
      CREATE TABLE tags (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    // v2 task_tags had only its creation metadata.  v6 adds the tombstone
    // metadata while retaining the composite primary key.
    db.execute('''
      CREATE TABLE task_tags (
        task_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (task_id, tag_id)
      )
    ''');
  }

  static void _createV3(Database db) {
    db.execute('''
      CREATE TABLE recurring_rules (
        id TEXT NOT NULL PRIMARY KEY,
        rrule TEXT NOT NULL,
        task_title TEXT NOT NULL,
        task_description TEXT NULL,
        duration_min INTEGER NOT NULL,
        category_id TEXT NULL,
        priority INTEGER NOT NULL DEFAULT 0,
        tags_json TEXT NULL,
        start_time_of_day TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        exceptions_json TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute('''
      CREATE TABLE task_templates (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NULL,
        duration_min INTEGER NOT NULL,
        category_id TEXT NULL,
        priority INTEGER NOT NULL DEFAULT 0,
        tags_json TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static void _createV4(Database db) {
    db.execute('''
      CREATE TABLE daily_reviews (
        id TEXT NOT NULL PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        reflection TEXT NULL,
        energy_level INTEGER NULL,
        productivity_rating INTEGER NULL,
        planning_accuracy_rating INTEGER NULL,
        wins_json TEXT NULL,
        improvements_json TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute('''
      CREATE TABLE weekly_reviews (
        id TEXT NOT NULL PRIMARY KEY,
        week_start_date TEXT NOT NULL UNIQUE,
        reflection TEXT NULL,
        overall_rating INTEGER NULL,
        goals_met_json TEXT NULL,
        goals_missed_json TEXT NULL,
        next_week_focus_json TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute('''
      CREATE TABLE daily_stats_cache (
        date TEXT NOT NULL PRIMARY KEY,
        total_tasks INTEGER NOT NULL DEFAULT 0,
        completed_tasks INTEGER NOT NULL DEFAULT 0,
        missed_tasks INTEGER NOT NULL DEFAULT 0,
        skipped_tasks INTEGER NOT NULL DEFAULT 0,
        cancelled_tasks INTEGER NOT NULL DEFAULT 0,
        rescheduled_tasks INTEGER NOT NULL DEFAULT 0,
        planned_duration_min INTEGER NOT NULL DEFAULT 0,
        actual_duration_min INTEGER NOT NULL DEFAULT 0,
        focus_duration_min INTEGER NOT NULL DEFAULT 0,
        energy_level INTEGER NULL,
        productivity_rating INTEGER NULL,
        planning_accuracy_pct REAL NULL,
        computed_at TEXT NOT NULL
      )
    ''');
  }

  static void _createV5(Database db) {
    db.execute('''
      CREATE TABLE timer_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        task_id TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT NULL,
        duration_sec INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static void _seed(Database db, int version) {
    db.execute('''
      INSERT INTO categories
        (id, name, color_hex, created_at, updated_at)
      VALUES ('cat-1', 'Work', '#4285F4', '$timestamp', '$timestamp')
    ''');
    db.execute('''
      INSERT INTO tasks
        (id, title, description, start_time, end_time, estimated_duration_min,
         actual_duration_min, category_id, notes, created_at, updated_at)
      VALUES ('task-1', 'Legacy task', 'legacy description',
        '2026-01-01T09:00:00.000Z', '2026-01-01T10:00:00.000Z', 60, 15,
        'cat-1', 'legacy notes', '$timestamp', '$timestamp')
    ''');
    db.execute(
      "INSERT INTO app_settings (key, value) VALUES ('theme', 'dark')",
    );

    if (version >= 2) {
      db.execute('''
        INSERT INTO subtasks
          (id, task_id, title, sort_order, created_at, updated_at)
        VALUES ('sub-1', 'task-1', 'Legacy subtask', 0, '$timestamp', '$timestamp')
      ''');
      db.execute('''
        INSERT INTO tags (id, name, created_at, updated_at)
        VALUES ('tag-1', 'legacy', '$timestamp', '$timestamp')
      ''');
      db.execute('''
        INSERT INTO task_tags (task_id, tag_id, created_at)
        VALUES ('task-1', 'tag-1', '$timestamp')
      ''');
    }

    if (version >= 3) {
      db.execute('''
        INSERT INTO recurring_rules
          (id, rrule, task_title, task_description, duration_min, category_id,
           start_time_of_day, start_date, created_at, updated_at)
        VALUES ('rule-1', 'FREQ=DAILY', 'Legacy recurring', 'rule description',
          60, 'cat-1', '09:00', '2026-01-01', '$timestamp', '$timestamp')
      ''');
      db.execute('''
        INSERT INTO task_templates
          (id, name, description, duration_min, category_id, created_at, updated_at)
        VALUES ('template-1', 'Legacy template', 'template description', 45,
          'cat-1', '$timestamp', '$timestamp')
      ''');
      db.execute(
        "UPDATE tasks SET recurring_rule_id = 'rule-1' WHERE id = 'task-1'",
      );
    }

    if (version >= 4) {
      db.execute('''
        INSERT INTO daily_reviews
          (id, date, reflection, energy_level, created_at, updated_at)
        VALUES ('daily-1', '2026-01-01', 'legacy reflection', 4,
          '$timestamp', '$timestamp')
      ''');
      db.execute('''
        INSERT INTO weekly_reviews
          (id, week_start_date, reflection, overall_rating, created_at, updated_at)
        VALUES ('weekly-1', '2025-12-29', 'legacy weekly', 5,
          '$timestamp', '$timestamp')
      ''');
      db.execute('''
        INSERT INTO daily_stats_cache
          (date, total_tasks, completed_tasks, computed_at)
        VALUES ('2026-01-01', 1, 0, '$timestamp')
      ''');
    }

    if (version >= 5) {
      db.execute('''
        INSERT INTO timer_sessions
          (id, task_id, started_at, ended_at, duration_sec, created_at, updated_at)
        VALUES ('timer-1', 'task-1', '2026-01-01T09:00:00.000Z',
          '2026-01-01T09:00:30.000Z', 30, '$timestamp', '$timestamp')
      ''');
    }
  }
}
