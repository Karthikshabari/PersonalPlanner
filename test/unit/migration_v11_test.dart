import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('v8 fixture upgrades to v11 with defaulted review fields', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v11',
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
          14,
        );

        Future<Set<String>> columns(String table) async =>
            (await db.customSelect('PRAGMA table_info($table)').get())
                .map((row) => row.read<String>('name'))
                .toSet();

        expect(
          await columns('daily_reviews'),
          containsAll(<String>['mood', 'task_reasons_json']),
        );
        expect(await columns('tasks'), contains('plan_change_reasons_json'));

        final task = await db.taskDao.getTaskById('task-1');
        expect(task, isNotNull);
        expect(task!.planChangeReasonsJson, '{}');
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('mood outside 1..4 is rejected by SQLite', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_migration_v11_mood',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      MigrationSchema.create(file, 8);

      final db = AppDatabase(NativeDatabase(file));
      try {
        Future<void> insertReview(String id, String date, int mood) =>
            db.customStatement(
              'INSERT INTO daily_reviews(id, date, mood, created_at, '
              'updated_at) VALUES (?, ?, ?, '
              "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
              [id, date, mood],
            );

        await insertReview('review-ok', '2026-03-01', 4);
        await expectLater(
          insertReview('review-bad', '2026-03-02', 5),
          throwsA(isA<sqlite3.SqliteException>()),
        );
      } finally {
        await db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
