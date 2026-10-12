import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/migration_schema.dart';
import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  const stamp = '2026-10-11T10:00:00.000Z';
  const ideaId = 'idea-1';
  const scheduledId = 'scheduled-1';
  const newColumns = {'inbox_item_id', 'inbox_history_json'};

  Future<Set<String>> columns(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((row) => row.read<String>('name'))
          .toSet();

  Future<int> userVersion(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      );

  Future<int> count(AppDatabase db, String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('c');

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

  /// A genuine v14 file: the current schema with the two v15 columns and the
  /// v15 index removed, holding one Inbox idea and one scheduled task.
  Future<void> buildV14(File file) async {
    final fresh = AppDatabase(NativeDatabase(file));
    await fresh.customSelect('SELECT 1').get();
    await fresh.close();
    final raw = sqlite3.sqlite3.open(file.path);
    try {
      // The tasks triggers may name the new columns in later phases.
      for (final suffix in ['insert', 'update', 'delete']) {
        raw.execute('DROP TRIGGER IF EXISTS sync_tasks_$suffix');
      }
      raw.execute('DROP INDEX IF EXISTS idx_tasks_inbox_item_fk');
      raw.execute('ALTER TABLE tasks DROP COLUMN inbox_item_id');
      raw.execute('ALTER TABLE tasks DROP COLUMN inbox_history_json');
      raw.execute(
        'INSERT INTO tasks(id, title, description, is_inbox, '
        "inbox_content_version, created_at, updated_at) VALUES "
        "('$ideaId', 'Buy a lamp', 'Buy a lamp', 1, 1, '$stamp', '$stamp')",
      );
      raw.execute(
        'INSERT INTO tasks(id, title, start_time, end_time, '
        'estimated_duration_min, created_at, updated_at) VALUES '
        "('$scheduledId', 'Plan', '2026-10-12T09:00:00.000Z', "
        "'2026-10-12T10:00:00.000Z', 60, '$stamp', '$stamp')",
      );
      raw.execute(
        "UPDATE app_settings SET value = '6' "
        "WHERE key = 'schema.sync_trigger_version'",
      );
      raw.execute('PRAGMA user_version = 14');
    } finally {
      raw.dispose();
    }
  }

  test('(a) a v8 fixture upgrades to v15 with both columns', () {
    return withTempFile('planner_migration_v15_from_v8', (file) async {
      MigrationSchema.create(file, 8);

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 15);
        expect(await columns(db, 'tasks'), containsAll(newColumns));
        expect(
          await count(
            db,
            "SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_tasks_inbox_item_fk'",
          ),
          1,
        );
      } finally {
        await db.close();
      }
    });
  });

  test('(b) a genuine v14 file upgrades, keeps its rows and is idempotent', () {
    return withTempFile('planner_migration_v14_to_v15', (file) async {
      await buildV14(file);

      Future<List<Map<String, Object?>>> snapshot(AppDatabase db) async {
        final rows = await db
            .customSelect(
              'SELECT id, inbox_item_id, inbox_history_json, revision, '
              'updated_at, sync_status FROM tasks ORDER BY id',
            )
            .get();
        return [for (final row in rows) row.data];
      }

      late List<Map<String, Object?>> first;
      var db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 15);
        final listed = await db.customSelect('PRAGMA table_info(tasks)').get();
        expect(
          listed.map((row) => row.read<String>('name')),
          containsAll(newColumns),
        );
        first = await snapshot(db);
        expect(first, hasLength(2));
        for (final row in first) {
          expect(row['inbox_item_id'], isNull);
          expect(row['inbox_history_json'], '[]');
        }
        // The upgrade only adds columns: no Day task appears and no outbox
        // operation is queued for the existing rows.
        expect(await count(db, 'SELECT COUNT(*) AS c FROM tasks'), 2);
        expect(await count(db, 'SELECT COUNT(*) AS c FROM sync_log'), 0);
        expect(
          await count(
            db,
            "SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_tasks_inbox_item_fk'",
          ),
          1,
        );
      } finally {
        await db.close();
      }

      // Running the upgrade again (open once more) changes nothing.
      db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 15);
        expect(await snapshot(db), first);
        expect(await count(db, 'SELECT COUNT(*) AS c FROM tasks'), 2);
      } finally {
        await db.close();
      }
    });
  });

  test('(c) the upgrade step is a no-op when the columns already exist', () {
    return withTempFile('planner_migration_v15_partial', (file) async {
      final fresh = AppDatabase(NativeDatabase(file));
      await fresh.customSelect('SELECT 1').get();
      await fresh.close();
      final raw = sqlite3.sqlite3.open(file.path);
      try {
        raw.execute('PRAGMA user_version = 14');
      } finally {
        raw.dispose();
      }

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 15);
        expect(await columns(db, 'tasks'), containsAll(newColumns));
      } finally {
        await db.close();
      }
    });
  });

  group('constraints', () {
    Future<void> insertWithHistory(AppDatabase db, String history) =>
        db.customStatement(
          'INSERT INTO tasks(id, title, is_inbox, inbox_content_version, '
          "inbox_history_json, created_at, updated_at) VALUES "
          "('idea-x', 'Idea', 1, 1, ?, '$stamp', '$stamp')",
          [history],
        );

    test('(d) a history that is not a JSON array fails the CHECK on a '
        'migrated file', () {
      return withTempFile('planner_migration_v15_check', (file) async {
        await buildV14(file);
        final db = AppDatabase(NativeDatabase(file));
        try {
          await expectLater(
            insertWithHistory(db, '{}'),
            throwsA(isA<sqlite3.SqliteException>()),
          );
          await expectLater(
            insertWithHistory(db, 'not json'),
            throwsA(isA<sqlite3.SqliteException>()),
          );
          await insertWithHistory(db, '[]');
        } finally {
          await db.close();
        }
      });
    });

    test('(e) the same CHECK holds on a fresh database', () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await expectLater(
          insertWithHistory(db, '{}'),
          throwsA(isA<sqlite3.SqliteException>()),
        );
        await insertWithHistory(db, '[]');
      } finally {
        await db.close();
      }
    });

    test(
      '(f) inbox_item_id is a foreign key that clears with its idea',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await db.customStatement(
            'INSERT INTO tasks(id, title, is_inbox, inbox_content_version, '
            "created_at, updated_at) VALUES ('$ideaId', 'Idea', 1, 1, "
            "'$stamp', '$stamp')",
          );
          await expectLater(
            db.customStatement(
              'INSERT INTO tasks(id, title, inbox_item_id, created_at, '
              "updated_at) VALUES ('s-bad', 'Session', 'missing', "
              "'$stamp', '$stamp')",
            ),
            throwsA(isA<sqlite3.SqliteException>()),
          );
          await db.customStatement(
            'INSERT INTO tasks(id, title, inbox_item_id, created_at, '
            "updated_at) VALUES ('s-ok', 'Session', '$ideaId', '$stamp', "
            "'$stamp')",
          );
          await db.customStatement("DELETE FROM tasks WHERE id = '$ideaId'");
          final row = await db
              .customSelect("SELECT inbox_item_id FROM tasks WHERE id = 's-ok'")
              .getSingle();
          expect(row.data['inbox_item_id'], isNull);
        } finally {
          await db.close();
        }
      },
    );
  });
}
