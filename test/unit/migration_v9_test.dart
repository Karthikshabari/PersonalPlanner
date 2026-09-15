import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('v8 upgrades to v9 with conservative recurrence provenance', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v9',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 8);
      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          9,
        );
        final task = await db.taskDao.getTaskById('task-1');
        expect(task?.title, 'Legacy task');
        expect(task?.recurrenceRemovalReason, isNull);
        final columns = await db.customSelect('PRAGMA table_info(tasks)').get();
        expect(
          columns.map((row) => row.read<String>('name')),
          contains('recurrence_removal_reason'),
        );
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
