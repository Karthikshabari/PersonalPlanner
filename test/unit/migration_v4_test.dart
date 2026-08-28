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
    directory = Directory.systemTemp.createTempSync('planner_migration_v3');
    dbFile = File('${directory.path}/migrate.sqlite3');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('v3 snapshot upgrades to v6 and preserves recurrence/template rows',
      () async {
    MigrationSchema.create(dbFile, 3);
    final db = AppDatabase(NativeDatabase(dbFile));
    try {
      expect(
        (await db.select(db.recurringRules).get()).single.rrule,
        'FREQ=DAILY',
      );
      expect(
        (await db.select(db.taskTemplates).get()).single.name,
        'Legacy template',
      );
      expect(
        (await db.select(db.tasks).get()).single.recurringRuleId,
        'rule-1',
      );
      expect(
        (await db.select(db.recurringRules).get()).single.categoryId,
        'cat-1',
      );
    } finally {
      await db.close();
    }
  });
}
