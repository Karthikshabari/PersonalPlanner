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
    directory = Directory.systemTemp.createTempSync('planner_migration_v4');
    dbFile = File('${directory.path}/migrate.sqlite3');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('v4 snapshot upgrades to v6 and preserves reviews/cache rows', () async {
    MigrationSchema.create(dbFile, 4);
    final db = AppDatabase(NativeDatabase(dbFile));
    try {
      expect(
        (await db.select(db.dailyReviews).get()).single.reflection,
        'legacy reflection',
      );
      expect(
        (await db.select(db.weeklyReviews).get()).single.overallRating,
        5,
      );
      final cache = (await db.select(db.dailyStatsCache).get()).single;
      expect(cache.totalTasks, 1);
      expect(cache.plannedTasks, 0);
      expect(cache.inProgressTasks, 0);
      expect(await db.select(db.timerSessions).get(), isEmpty);
    } finally {
      await db.close();
    }
  });
}
