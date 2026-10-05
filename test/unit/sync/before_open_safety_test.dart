import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('beforeOpen outbox safety (DB-003)', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('planner_before_open');
      dbPath = p.join(tempDir.path, 'planner.sqlite3');
    });

    tearDown(() => tempDir.delete(recursive: true));

    test(
      'kill mid-beforeOpen then reopen still records local writes',
      () async {
        final first = AppDatabase(NativeDatabase(File(dbPath)));
        await first.customSelect('SELECT 1').get();
        // A process killed mid-normalization at HEAD left this row committed.
        await first.customStatement(
          "INSERT OR REPLACE INTO app_settings VALUES ('sync.apply_mode','1')",
        );
        await first.close();

        final reopened = AppDatabase(NativeDatabase(File(dbPath)));
        addTearDown(reopened.close);
        expect(await reopened.syncDao.getSetting('sync.apply_mode'), isNull);

        final now = DateTime.utc(2026, 3, 1, 9);
        await TaskRepository(reopened).insertTask(
          Task(id: '', title: 'After restart', createdAt: now, updatedAt: now),
        );

        final outbox = await reopened
            .customSelect('SELECT COUNT(*) AS c FROM sync_log')
            .getSingle();
        expect(outbox.read<int>('c'), 1);
      },
    );

    test('normalizer never commits the apply-mode flag', () async {
      final seed = AppDatabase(
        NativeDatabase(File(dbPath), setup: AppDatabase.configureConnection),
      );
      // Rows for the open-time normalizers to scan, so A's reopen spans the
      // polling window.
      await seed.customStatement('''
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 2000)
        INSERT INTO tasks (id, title, created_at, updated_at)
        SELECT 'seed-' || i, 'Seed ' || i,
               '2026-01-01T09:00:00+05:30', '2026-01-01T09:00:00+05:30'
        FROM n
      ''');
      await seed.close();

      final observer = sqlite3.open(dbPath);
      addTearDown(observer.dispose);
      observer.execute('PRAGMA busy_timeout = 30000');

      final a = AppDatabase(
        NativeDatabase.createInBackground(
          File(dbPath),
          setup: AppDatabase.configureConnection,
          isolateSetup: _overrideSqliteLibrary,
        ),
      );
      addTearDown(a.close);
      final opening = a.customSelect('SELECT 1').get();

      final seen = <String>[];
      for (var i = 0; i < 200; i++) {
        final rows = observer.select(
          "SELECT value FROM app_settings WHERE key='sync.apply_mode'",
        );
        seen.addAll(rows.map((row) => row['value'] as String));
        await Future<void>.delayed(const Duration(microseconds: 500));
      }
      await opening;

      expect(seen, isNot(contains('1')));
      expect(await a.syncDao.getSetting('sync.apply_mode'), isNull);
    });
  });
}

void _overrideSqliteLibrary() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}
