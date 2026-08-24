import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/category_dao.dart';
import 'daos/task_dao.dart';
import 'converters.dart';
import 'tables/app_settings_table.dart';
import 'tables/categories_table.dart';
import 'tables/tasks_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Tasks, Categories, AppSettings],
  daos: [TaskDao, CategoryDao],
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
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
  }
}
