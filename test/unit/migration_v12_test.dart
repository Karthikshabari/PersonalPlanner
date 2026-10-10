import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  Future<Set<String>> columns(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((row) => row.read<String>('name'))
          .toSet();

  Future<int> userVersion(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      );

  Future<void> withTempFile(
    String name,
    Future<void> Function(File file) body,
  ) async {
    final directory = Directory.systemTemp.createTempSync(name);
    try {
      await body(File('${directory.path}/planner.sqlite3'));
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  test('v8 fixture upgrades to v12 with empty weekly mood and feeling', () {
    return withTempFile('planner_migration_v12', (file) async {
      MigrationSchema.create(file, 8);

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 14);
        expect(
          await columns(db, 'weekly_reviews'),
          containsAll(<String>['mood', 'feeling']),
        );
        final weekly = await db.reviewDao.getWeeklyReviewById('weekly-1');
        expect(weekly, isNotNull);
        expect(weekly!.reflection, 'legacy weekly');
        expect(weekly.mood, isNull);
        expect(weekly.feeling, isNull);
      } finally {
        await db.close();
      }
    });
  });

  test('a v11 database file upgrades to v12 and syncs the new fields', () {
    return withTempFile('planner_migration_v11_to_v12', (file) async {
      // Build a real v11 file: create the current schema, then remove what
      // v12 added and stamp the v11 version numbers.
      final fresh = AppDatabase(NativeDatabase(file));
      await fresh.customSelect('SELECT 1').get();
      await fresh.close();
      final raw = sqlite3.sqlite3.open(file.path);
      try {
        for (final suffix in ['insert', 'update', 'delete']) {
          raw.execute('DROP TRIGGER IF EXISTS sync_weekly_reviews_$suffix');
        }
        raw.execute('ALTER TABLE weekly_reviews DROP COLUMN mood');
        raw.execute('ALTER TABLE weekly_reviews DROP COLUMN feeling');
        raw.execute(
          "INSERT INTO weekly_reviews(id, week_start_date, reflection, "
          "created_at, updated_at) VALUES ('weekly-v11', '2026-09-28', "
          "'Old note', '2026-10-04T10:00:00.000Z', "
          "'2026-10-04T10:00:00.000Z')",
        );
        raw.execute(
          "UPDATE app_settings SET value = '3' "
          "WHERE key = 'schema.sync_trigger_version'",
        );
        raw.execute('PRAGMA user_version = 11');
      } finally {
        raw.dispose();
      }

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 14);
        expect(
          await columns(db, 'weekly_reviews'),
          containsAll(<String>['mood', 'feeling']),
        );
        final row = await db.reviewDao.getWeeklyReviewById('weekly-v11');
        expect(row!.reflection, 'Old note');
        expect(row.mood, isNull);
        expect(row.feeling, isNull);
        expect(
          await db.syncDao.getSetting('schema.sync_trigger_version'),
          '${AppDatabase.syncTriggerVersion}',
        );

        await db.customStatement(
          "UPDATE weekly_reviews SET mood = 3, feeling = 'Calm', "
          "revision = revision + 1 WHERE id = 'weekly-v11'",
        );
        final log = await db.select(db.syncLog).get();
        final payload = jsonDecode(
          log.lastWhere((r) => r.entityTableName == 'weekly_reviews').payload,
        ) as Map<String, dynamic>;
        expect(payload['mood'], 3);
        expect(payload['feeling'], 'Calm');
      } finally {
        await db.close();
      }
    });
  });

  test('weekly mood outside 1..4 and feeling over 200 are rejected', () {
    return withTempFile('planner_migration_v12_checks', (file) async {
      MigrationSchema.create(file, 8);
      final db = AppDatabase(NativeDatabase(file));
      try {
        Future<void> insertWeekly(
          String id,
          String week,
          int? mood,
          String? feeling,
        ) => db.customStatement(
          'INSERT INTO weekly_reviews(id, week_start_date, mood, feeling, '
          'created_at, updated_at) VALUES (?, ?, ?, ?, '
          "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
          [id, week, mood, feeling],
        );

        await insertWeekly('weekly-ok', '2026-03-02', 4, 'x' * 200);
        await insertWeekly('weekly-null', '2026-03-09', null, null);
        await expectLater(
          insertWeekly('weekly-bad-mood', '2026-03-16', 5, null),
          throwsA(isA<sqlite3.SqliteException>()),
        );
        await expectLater(
          insertWeekly('weekly-bad-feeling', '2026-03-23', 1, 'x' * 201),
          throwsA(isA<sqlite3.SqliteException>()),
        );
      } finally {
        await db.close();
      }
    });
  });
}
