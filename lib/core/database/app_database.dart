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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
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
          // Indexes are idempotent — always ensure they exist.
          await _createIndexes();
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_day ON tasks (start_time, end_time) WHERE deleted_at IS NULL AND is_inbox = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_inbox ON tasks (is_inbox, status) WHERE deleted_at IS NULL');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_overdue ON tasks (start_time, status, missed_at) WHERE deleted_at IS NULL AND is_inbox = 0 AND status IN (\'planned\', \'in_progress\')');
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
  }
}
