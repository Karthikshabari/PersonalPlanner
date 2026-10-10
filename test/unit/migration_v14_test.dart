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

  const stamp = '2026-10-09T10:00:00.000Z';
  const tagId = '11111111-1111-4111-8111-111111111111';
  const experimentId = '6a921905-9a5c-51c0-b898-e0c6985d8a72';
  const keptColumns = {'retired_at', 'retire_note', 'target_changes_json'};

  Future<Set<String>> columns(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((row) => row.read<String>('name'))
          .toSet();

  Future<int> userVersion(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      );

  Future<int> syncTriggerCount(AppDatabase db) async =>
      (await db
              .customSelect(
                "SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'trigger' "
                r"AND name LIKE 'sync\_%' ESCAPE '\'",
              )
              .getSingle())
          .read<int>('c');

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

  test('(a) a v8 fixture upgrades to v14 with the three columns', () {
    return withTempFile('planner_migration_v14_from_v8', (file) async {
      MigrationSchema.create(file, 8);

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 14);
        expect(await columns(db, 'experiments'), containsAll(keptColumns));
        expect(await syncTriggerCount(db), 40);
        expect(
          await db.syncDao.getSetting('schema.sync_trigger_version'),
          '${AppDatabase.syncTriggerVersion}',
        );
      } finally {
        await db.close();
      }
    });
  });

  test('(b) a genuine v13 file upgrades and keeps its kept experiment', () {
    return withTempFile('planner_migration_v13_to_v14', (file) async {
      // Build a real v13 file: create the current schema, then remove what
      // v14 added and stamp the v13 version numbers.
      final fresh = AppDatabase(NativeDatabase(file));
      await fresh.customSelect('SELECT 1').get();
      await fresh.close();
      final raw = sqlite3.sqlite3.open(file.path);
      try {
        for (final suffix in ['insert', 'update', 'delete']) {
          raw.execute('DROP TRIGGER IF EXISTS sync_experiments_$suffix');
        }
        raw.execute('ALTER TABLE experiments DROP COLUMN target_changes_json');
        raw.execute('ALTER TABLE experiments DROP COLUMN retire_note');
        raw.execute('ALTER TABLE experiments DROP COLUMN retired_at');
        raw.execute(
          'INSERT INTO tags(id, name, created_at, updated_at) '
          "VALUES ('$tagId', 'Learn C', '$stamp', '$stamp')",
        );
        raw.execute(
          'INSERT INTO experiments(id, tag_id, start_date, end_date, '
          'weekday_target_min, weekend_target_min, check_in_every_days, '
          'status, outcome, concluded_on, created_at, updated_at) VALUES '
          "('$experimentId', '$tagId', '2026-09-04', '2026-10-03', 60, 90, 7, "
          "'concluded', 'continue_habit', '2026-10-09', '$stamp', '$stamp')",
        );
        raw.execute(
          "UPDATE app_settings SET value = '5' "
          "WHERE key = 'schema.sync_trigger_version'",
        );
        raw.execute('PRAGMA user_version = 13');
      } finally {
        raw.dispose();
      }

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 14);
        expect(await columns(db, 'experiments'), containsAll(keptColumns));
        final row = await db.experimentDao.getExperimentById(experimentId);
        expect(row, isNotNull);
        expect(row!.status, 'concluded');
        expect(row.outcome, 'continue_habit');
        expect(row.concludedOn, '2026-10-09');
        expect(row.weekdayTargetMin, 60);
        expect(row.weekendTargetMin, 90);
        expect(row.retiredAt, isNull);
        expect(row.retireNote, isNull);
        expect(row.targetChangesJson, '[]');
        expect(
          await db.syncDao.getSetting('schema.sync_trigger_version'),
          '${AppDatabase.syncTriggerVersion}',
        );
        expect(await syncTriggerCount(db), 40);
        // The upgrade itself must not queue any operation for the experiment.
        final log = await db.select(db.syncLog).get();
        expect(log.where((entry) => entry.recordId == experimentId), isEmpty);

        // The recreated triggers now carry the kept fields.
        await db.customStatement(
          "UPDATE experiments SET retired_at = '2026-10-10T08:00:00.000Z' "
          "WHERE id = '$experimentId'",
        );
        final queued = (await db.select(db.syncLog).get()).lastWhere(
          (entry) => entry.entityTableName == 'experiments',
        );
        final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
        expect(payload.containsKey('retired_at'), isTrue);
        expect(payload.containsKey('retire_note'), isTrue);
        expect(payload.containsKey('target_changes_json'), isTrue);
        expect(payload['retired_at'], '2026-10-10T08:00:00.000Z');
        expect(payload['retire_note'], isNull);
        expect(payload['target_changes_json'], '[]');
      } finally {
        await db.close();
      }
    });
  });

  test('(c) a retire note of 4001 characters is rejected by SQLite', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customStatement(
        'INSERT INTO tags(id, name, created_at, updated_at) '
        "VALUES ('$tagId', 'Learn C', '$stamp', '$stamp')",
      );
      Future<void> insertWithNote(String note) => db.customStatement(
        'INSERT INTO experiments(id, tag_id, start_date, end_date, '
        'weekday_target_min, weekend_target_min, check_in_every_days, '
        'status, outcome, concluded_on, retired_at, retire_note, created_at, '
        "updated_at) VALUES ('$experimentId', '$tagId', '2026-09-04', "
        "'2026-10-03', 60, 90, 7, 'concluded', 'continue_habit', "
        "'2026-10-09', '$stamp', ?, '$stamp', '$stamp')",
        [note],
      );
      await expectLater(
        insertWithNote('a' * 4001),
        throwsA(isA<sqlite3.SqliteException>()),
      );
      await insertWithNote('a' * 4000);
    } finally {
      await db.close();
    }
  });

  test('(d) the sync trigger version is 6', () {
    expect(AppDatabase.syncTriggerVersion, 6);
  });
}
