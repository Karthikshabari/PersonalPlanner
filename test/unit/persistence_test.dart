import '../helpers/sqlite_setup.dart' as sqlite_setup;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

void main() {
  sqlite_setup.setupSqliteForTests();
  test('data persists across database restart (SQLite file)', () async {
    final tempDir = await Directory.systemTemp.createTemp('planner_persist');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'planner.sqlite3');

    final db1 = AppDatabase(NativeDatabase(File(dbPath)));
    final taskRepo1 = TaskRepository(db1);
    final categoryRepo1 = CategoryRepository(db1);

    await categoryRepo1.seedDefaultsIfEmpty();
    final day = DateTime(2026, 7, 23, 14);
    final inserted = await taskRepo1.insertTask(
      Task(
        id: '',
        title: 'Persistent task',
        startTime: day,
        endTime: day.add(const Duration(hours: 2)),
        estimatedDurationMin: 120,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(File(dbPath)));
    final taskRepo2 = TaskRepository(db2);
    final categoryRepo2 = CategoryRepository(db2);

    final fetched = await taskRepo2.getTaskById(inserted.id);
    expect(fetched, isNotNull);
    expect(fetched!.title, 'Persistent task');
    expect(fetched.startTime!.hour, 14);
    expect(
      fetched.endTime!.difference(fetched.startTime!),
      const Duration(hours: 2),
    );

    final categories = await categoryRepo2.getAllCategories();
    expect(categories, hasLength(4));
    await categoryRepo2.seedDefaultsIfEmpty();
    expect(await categoryRepo2.getAllCategories(), hasLength(4));

    await db2.close();
  });

  test('reopening does not recreate sync triggers', () async {
    final tempDir = await Directory.systemTemp.createTemp('planner_triggers');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'planner.sqlite3');

    Future<int> schemaVersion(AppDatabase db) async =>
        (await db.customSelect('PRAGMA schema_version').getSingle())
                .data
                .values
                .single
            as int;

    final db1 = AppDatabase(NativeDatabase(File(dbPath)));
    final first = await schemaVersion(db1);
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(File(dbPath)));
    final second = await schemaVersion(db2);
    final triggers = await db2
        .customSelect(
          "SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'trigger' "
          r"AND name LIKE 'sync\_%' ESCAPE '\'",
        )
        .getSingle();
    final stamp = await db2.syncDao.getSetting('schema.sync_trigger_version');
    await db2.close();

    expect(second, first);
    expect(triggers.read<int>('c'), 34);
    expect(stamp, '${AppDatabase.syncTriggerVersion}');
  });

  test('malformed instants are repaired and recorded', () async {
    final tempDir = await Directory.systemTemp.createTemp('planner_malformed');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'planner.sqlite3'));

    final first = AppDatabase(NativeDatabase(file));
    await first.customSelect('SELECT 1').get();
    await first.close();

    const good = '2026-01-01T09:00:00.000Z';
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute(
      'INSERT INTO tasks (id, title, created_at, updated_at) '
      "VALUES ('bad-task', 'Bad', '$good', 'garbage')",
    );
    raw.execute(
      'INSERT INTO timer_sessions '
      '(id, task_id, started_at, ended_at, duration_sec, state, '
      'created_at, updated_at) '
      "VALUES ('bad-timer', 'bad-task', '$good', 'bad', 60, 'finished', "
      "'$good', '$good')",
    );
    raw.execute(
      "DELETE FROM app_settings WHERE key = 'schema.maintenance_version'",
    );
    raw.dispose();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final tasks = await db.select(db.tasks).get();
    final task = tasks.singleWhere((t) => t.id == 'bad-task');
    expect(task.updatedAt, isNotNull);
    final timer = await db
        .customSelect(
          "SELECT started_at, ended_at FROM timer_sessions WHERE id = 'bad-timer'",
        )
        .getSingle();
    expect(timer.read<String>('ended_at'), timer.read<String>('started_at'));
    final ledger = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM planner_migration_recovery '
          "WHERE recovery_id LIKE 'timestamp:%'",
        )
        .getSingle();
    expect(ledger.read<int>('c'), 2);
  });

  /// Creates a database file, lets [seed] write rows through a raw
  /// connection, and clears the maintenance marker so the next open repairs.
  Future<File> seededDatabase(
    String name,
    void Function(sqlite3.Database raw) seed,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp(name);
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'planner.sqlite3'));
    final first = AppDatabase(NativeDatabase(file));
    await first.customSelect('SELECT 1').get();
    await first.close();
    final raw = sqlite3.sqlite3.open(file.path);
    seed(raw);
    raw.execute(
      "DELETE FROM app_settings WHERE key = 'schema.maintenance_version'",
    );
    raw.dispose();
    return file;
  }

  Future<String?> maintenanceVersion(AppDatabase db) async =>
      (await db
              .customSelect(
                "SELECT value FROM app_settings "
                "WHERE key = 'schema.maintenance_version'",
              )
              .getSingleOrNull())
          ?.read<String>('value');

  test(
    'a malformed task start with a non-canonical end is repaired as a whole',
    () async {
      const good = '2026-01-01T09:00:00.000Z';
      final file = await seededDatabase('planner_half_task', (raw) {
        // The malformed start sorts below the end, so the stored row
        // satisfies end_time > start_time.
        raw.execute(
          'INSERT INTO tasks (id, title, start_time, end_time, '
          'estimated_duration_min, created_at, updated_at) '
          "VALUES ('half-task', 'Half', '2026-01-01 broken', "
          "'2026-01-01T11:00:00+02:00', 60, '$good', '$good')",
        );
      });

      final db = AppDatabase(NativeDatabase(file));
      try {
        final row = await db
            .customSelect(
              'SELECT start_time, end_time, estimated_duration_min '
              "FROM tasks WHERE id = 'half-task'",
            )
            .getSingle();
        expect(row.readNullable<String>('start_time'), isNull);
        expect(row.readNullable<String>('end_time'), isNull);
        expect(row.readNullable<int>('estimated_duration_min'), isNull);
        final ledger = await db
            .customSelect(
              'SELECT payload FROM planner_migration_recovery '
              "WHERE recovery_id = 'timestamp:tasks:half-task:start_time'",
            )
            .getSingle();
        final payload = jsonDecode(ledger.read<String>('payload')) as Map;
        expect(payload['value'], '2026-01-01 broken');
        expect(
          (payload['row'] as Map)['end_time'],
          '2026-01-01T11:00:00+02:00',
        );
        expect(
          await maintenanceVersion(db),
          '${AppDatabase.maintenanceVersion}',
        );
      } finally {
        await db.close();
      }

      final reopened = AppDatabase(NativeDatabase(file));
      try {
        final task = await reopened.taskDao.getTaskById('half-task');
        expect(task, isNotNull);
        expect(task!.startTime, isNull);
        expect(task.endTime, isNull);
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'a malformed timer start whose fallback lands after its end is clamped',
    () async {
      const good = '2026-01-01T09:00:00.000Z';
      const ended = '2026-01-01T09:30:00.000Z';
      const later = '2026-01-02T09:00:00.000Z';
      final file = await seededDatabase('planner_late_timer', (raw) {
        raw.execute(
          'INSERT INTO tasks (id, title, created_at, updated_at) '
          "VALUES ('timer-task', 'Timer', '$good', '$good')",
        );
        // Each malformed start sorts below its end, so the stored rows
        // satisfy ended_at >= started_at. The created_at fallback is after
        // the end; a malformed created_at falls back to now, also after it.
        raw.execute(
          'INSERT INTO timer_sessions '
          '(id, task_id, started_at, ended_at, duration_sec, state, '
          'created_at, updated_at) VALUES '
          "('created-fallback', 'timer-task', '2026-01-01 broken', '$ended', "
          "1800, 'finished', '$later', '$later'), "
          "('now-fallback', 'timer-task', '2026-01-01 broken', '$ended', "
          "1800, 'finished', 'bad', '$later')",
        );
      });

      final db = AppDatabase(NativeDatabase(file));
      try {
        final rows = await db
            .customSelect(
              'SELECT id, started_at, ended_at, duration_sec '
              'FROM timer_sessions ORDER BY id',
            )
            .get();
        expect(rows, hasLength(2));
        for (final row in rows) {
          expect(row.read<String>('started_at'), ended);
          expect(row.read<String>('ended_at'), ended);
          expect(row.read<int>('duration_sec'), 1800);
        }
        final ledger = await db
            .customSelect(
              'SELECT recovery_id FROM planner_migration_recovery '
              "WHERE table_name = 'timer_sessions' ORDER BY recovery_id",
            )
            .get();
        expect(ledger.map((row) => row.read<String>('recovery_id')), [
          'timestamp:timer_sessions:created-fallback:started_at',
          'timestamp:timer_sessions:now-fallback:created_at',
          'timestamp:timer_sessions:now-fallback:started_at',
        ]);
        expect(
          await maintenanceVersion(db),
          '${AppDatabase.maintenanceVersion}',
        );
      } finally {
        await db.close();
      }

      final reopened = AppDatabase(NativeDatabase(file));
      try {
        for (final id in ['created-fallback', 'now-fallback']) {
          final session = await reopened.timerDao.getSessionById(id);
          expect(session, isNotNull);
          expect(session!.startedAt, session.endedAt);
        }
      } finally {
        await reopened.close();
      }
    },
  );

  test('a row repair that would violate a table CHECK is rolled back alone and '
      'recorded', () async {
    const good = '2026-01-01T09:00:00.000Z';
    final file = await seededDatabase('planner_flip_task', (raw) {
      // Stored text satisfies end_time > start_time, but in UTC the end
      // (03:00Z) precedes the start (05:00Z), so canonical text cannot.
      raw.execute(
        'INSERT INTO tasks (id, title, start_time, end_time, '
        'created_at, updated_at) VALUES '
        "('flip-task', 'Flip', '2026-01-01T10:00:00+05:00', "
        "'2026-01-01T11:00:00+08:00', '$good', '$good'), "
        "('sibling-task', 'Sibling', NULL, NULL, '$good', "
        "'2026-01-01T10:00:00+01:00')",
      );
    });

    final db = AppDatabase(NativeDatabase(file));
    try {
      final flip = await db
          .customSelect(
            "SELECT start_time, end_time FROM tasks WHERE id = 'flip-task'",
          )
          .getSingle();
      expect(flip.read<String>('start_time'), '2026-01-01T10:00:00+05:00');
      expect(flip.read<String>('end_time'), '2026-01-01T11:00:00+08:00');
      final sibling = await db
          .customSelect(
            "SELECT updated_at FROM tasks WHERE id = 'sibling-task'",
          )
          .getSingle();
      expect(sibling.read<String>('updated_at'), good);
      final ledger = await db
          .customSelect(
            'SELECT row_id, payload FROM planner_migration_recovery '
            "WHERE recovery_id = 'timestamp-rollback:tasks:flip-task'",
          )
          .getSingle();
      final payload = jsonDecode(ledger.read<String>('payload')) as Map;
      expect(
        (payload['row'] as Map)['start_time'],
        '2026-01-01T10:00:00+05:00',
      );
      expect(payload['attempted'], {
        'start_time': '2026-01-01T05:00:00.000Z',
        'end_time': '2026-01-01T03:00:00.000Z',
      });
      expect(payload['error'], contains('CHECK constraint failed'));
      expect(await maintenanceVersion(db), '${AppDatabase.maintenanceVersion}');
    } finally {
      await db.close();
    }

    final reopened = AppDatabase(NativeDatabase(file));
    try {
      expect(await reopened.taskDao.getTaskById('flip-task'), isNotNull);
    } finally {
      await reopened.close();
    }
  });

  test('open-time maintenance runs once per maintenance version', () async {
    final tempDir = await Directory.systemTemp.createTemp('planner_maint');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'planner.sqlite3'));

    final first = AppDatabase(NativeDatabase(file));
    await first.customSelect('SELECT 1').get();
    await first.close();

    const start = '2026-01-01T09:00:00.000Z';
    const end = '2026-01-01T11:00:00.000Z';
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute(
      'INSERT INTO tasks (id, title, start_time, end_time, '
      'estimated_duration_min, created_at, updated_at) '
      "VALUES ('wrong-estimate', 'Wrong', '$start', '$end', 999, "
      "'$start', '$start')",
    );
    raw.dispose();

    Future<int?> estimateAfterReopen() async {
      final db = AppDatabase(NativeDatabase(file));
      try {
        final row = await db
            .customSelect(
              'SELECT estimated_duration_min AS e FROM tasks '
              "WHERE id = 'wrong-estimate'",
            )
            .getSingle();
        return row.readNullable<int>('e');
      } finally {
        await db.close();
      }
    }

    expect(await estimateAfterReopen(), 999);

    final clear = sqlite3.sqlite3.open(file.path);
    clear.execute(
      "DELETE FROM app_settings WHERE key = 'schema.maintenance_version'",
    );
    clear.dispose();

    expect(await estimateAfterReopen(), 120);
  });
}
