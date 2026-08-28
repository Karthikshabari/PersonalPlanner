import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();
  late Directory directory;
  late File dbFile;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('planner_migration_v2');
    dbFile = File('${directory.path}/migrate.sqlite3');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('v2 snapshot upgrades to v6 and migrates task-tag metadata', () async {
    MigrationSchema.create(dbFile, 2);
    final db = AppDatabase(NativeDatabase(dbFile));
    try {
      expect((await db.select(db.tasks).get()).single.title, 'Legacy task');
      expect(
        (await db.select(db.subtasks).get()).single.title,
        'Legacy subtask',
      );
      expect((await db.select(db.tags).get()).single.name, 'legacy');
      final link = (await db.select(db.taskTags).get()).single;
      expect(link.taskId, 'task-1');
      expect(link.updatedAt, link.createdAt);
      expect(link.deletedAt, isNull);
      expect(link.revision, 1);
    } finally {
      await db.close();
    }
  });
}
