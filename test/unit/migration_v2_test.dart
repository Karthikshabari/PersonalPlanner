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
    directory = Directory.systemTemp.createTempSync('planner_migration_v1');
    dbFile = File('${directory.path}/migrate.sqlite3');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('v1 snapshot upgrades to v8 without losing foundation rows', () async {
    MigrationSchema.create(dbFile, 1);
    final db = AppDatabase(NativeDatabase(dbFile));
    try {
      expect((await db.select(db.tasks).get()).single.title, 'Legacy task');
      expect((await db.select(db.categories).get()).single.name, 'Work');
      expect(await db.select(db.subtasks).get(), isEmpty);
      expect(await db.select(db.tags).get(), isEmpty);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        8,
      );
      expect(
        (await db.select(db.tasks).get()).single.manualDurationAdjustmentMin,
        0,
      );
    } finally {
      await db.close();
    }
  });
}
