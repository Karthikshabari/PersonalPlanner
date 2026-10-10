import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
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

  Future<Set<String>> columns(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((row) => row.read<String>('name'))
          .toSet();

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db
              .customSelect(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' "
                'AND name = ?',
                variables: [Variable<String>(table)],
              )
              .get())
          .isNotEmpty;

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

  Future<void> insertTag(AppDatabase db, [String id = tagId]) =>
      db.customStatement(
        'INSERT INTO tags(id, name, created_at, updated_at) '
        "VALUES (?, 'Learn C', '$stamp', '$stamp')",
        [id],
      );

  Future<void> insertExperiment(
    AppDatabase db, {
    Map<String, Object?> overrides = const {},
  }) {
    final values = <String, Object?>{
      'id': experimentId,
      'tag_id': tagId,
      'start_date': '2026-10-05',
      'end_date': '2026-11-03',
      'weekday_target_min': 60,
      'weekend_target_min': 90,
      'check_in_every_days': 1,
      'status': 'running',
      'created_at': stamp,
      'updated_at': stamp,
      ...overrides,
    };
    return db.customStatement(
      'INSERT INTO experiments(${values.keys.join(', ')}) '
      'VALUES (${List.filled(values.length, '?').join(', ')})',
      values.values.toList(),
    );
  }

  Future<Map<String, dynamic>> lastPayload(AppDatabase db, String table) async {
    final rows = await db.select(db.syncLog).get();
    final row = rows.lastWhere((row) => row.entityTableName == table);
    return jsonDecode(row.payload) as Map<String, dynamic>;
  }

  test('v8 fixture upgrades to v13 with the new tables and an empty tag', () {
    return withTempFile('planner_migration_v13', (file) async {
      MigrationSchema.create(file, 8);

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 14);
        expect(await hasTable(db, 'experiments'), isTrue);
        expect(await hasTable(db, 'experiment_check_ins'), isTrue);
        expect(await columns(db, 'tasks'), contains('tag_id'));

        final task = await db.taskDao.getTaskById('task-1');
        expect(task, isNotNull);
        expect(task!.tagId, isNull);
        expect(task.title, 'Legacy task');
        expect(task.description, 'legacy description');
        expect(task.categoryId, 'cat-1');
        expect(task.notes, 'legacy notes');
        expect(task.estimatedDurationMin, 60);
        expect(task.actualDurationMin, 15);
        expect(task.recurringRuleId, 'rule-1');
        final tag = await db.tagDao.getTagById('tag-1');
        expect(tag!.name, 'legacy');
        final withTag = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM tasks WHERE tag_id IS NOT NULL',
            )
            .getSingle();
        expect(withTag.read<int>('c'), 0);
        expect(await syncTriggerCount(db), 40);
        expect(
          await db.syncDao.getSetting('schema.sync_trigger_version'),
          '${AppDatabase.syncTriggerVersion}',
        );
        final indexes =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'index'",
                    )
                    .get())
                .map((row) => row.read<String>('name'))
                .toSet();
        expect(
          indexes,
          containsAll(<String>[
            'idx_experiments_tag',
            'idx_experiment_check_ins_slot',
            'idx_tasks_tag_date',
          ]),
        );
      } finally {
        await db.close();
      }
    });
  });

  test('a fresh database has 40 sync triggers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      expect(await syncTriggerCount(db), 40);
      expect(AppDatabase.syncTriggerVersion, 6);
    } finally {
      await db.close();
    }
  });

  test('a genuine v12 file upgrades to v13 and keeps its task', () {
    return withTempFile('planner_migration_v12_to_v13', (file) async {
      // Build a real v12 file: create the current schema, then remove what
      // v13 added and stamp the v12 version numbers.
      final fresh = AppDatabase(NativeDatabase(file));
      await fresh.customSelect('SELECT 1').get();
      await fresh.close();
      final raw = sqlite3.sqlite3.open(file.path);
      try {
        for (final table in ['tasks', 'experiments', 'experiment_check_ins']) {
          for (final suffix in ['insert', 'update', 'delete']) {
            raw.execute('DROP TRIGGER IF EXISTS sync_${table}_$suffix');
          }
        }
        raw.execute('DROP INDEX IF EXISTS idx_tasks_tag_date');
        raw.execute('DROP TABLE experiment_check_ins');
        raw.execute('DROP TABLE experiments');
        raw.execute('ALTER TABLE tasks DROP COLUMN tag_id');
        raw.execute(
          'INSERT INTO tasks(id, title, start_time, end_time, '
          'estimated_duration_min, created_at, updated_at) VALUES '
          "('task-v12', 'Kept task', '2026-10-05T09:00:00.000Z', "
          "'2026-10-05T10:00:00.000Z', 60, '$stamp', '$stamp')",
        );
        raw.execute(
          "UPDATE app_settings SET value = '4' "
          "WHERE key = 'schema.sync_trigger_version'",
        );
        raw.execute('PRAGMA user_version = 12');
      } finally {
        raw.dispose();
      }

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 14);
        expect(await hasTable(db, 'experiments'), isTrue);
        expect(await hasTable(db, 'experiment_check_ins'), isTrue);
        expect(await columns(db, 'tasks'), contains('tag_id'));
        final task = await db.taskDao.getTaskById('task-v12');
        expect(task!.title, 'Kept task');
        expect(task.tagId, isNull);
        expect(task.estimatedDurationMin, 60);
        expect(
          await db.syncDao.getSetting('schema.sync_trigger_version'),
          '${AppDatabase.syncTriggerVersion}',
        );
        expect(await syncTriggerCount(db), 40);
        // The upgrade itself must not queue any operation for the kept task.
        final log = await db.select(db.syncLog).get();
        expect(log.where((row) => row.recordId == 'task-v12'), isEmpty);

        // The recreated triggers now carry the tag.
        await insertTag(db);
        await db.customStatement(
          "UPDATE tasks SET tag_id = '$tagId' WHERE id = 'task-v12'",
        );
        expect((await lastPayload(db, 'tasks'))['tag_id'], tagId);
      } finally {
        await db.close();
      }
    });
  });

  group('local constraints', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await insertTag(db);
    });
    tearDown(() => db.close());

    final rejected = throwsA(isA<sqlite3.SqliteException>());

    test('a valid experiment and check-in are accepted', () async {
      await insertExperiment(db);
      await db.customStatement(
        'INSERT INTO experiment_check_ins(id, experiment_id, slot_date, note, '
        "created_at, updated_at) VALUES ('c1', '$experimentId', "
        "'2026-10-05', 'Went fine', '$stamp', '$stamp')",
      );
    });

    test('a negative target is rejected', () async {
      await expectLater(
        insertExperiment(db, overrides: {'weekday_target_min': -1}),
        rejected,
      );
      await expectLater(
        insertExperiment(db, overrides: {'weekend_target_min': 10000}),
        rejected,
      );
    });

    test('a frequency outside 1, 3, 7, 10, 15 is rejected', () async {
      await expectLater(
        insertExperiment(db, overrides: {'check_in_every_days': 2}),
        rejected,
      );
    });

    test('an end date before the start date is rejected', () async {
      await expectLater(
        insertExperiment(
          db,
          overrides: {'start_date': '2026-10-05', 'end_date': '2026-10-04'},
        ),
        rejected,
      );
    });

    test('an impossible date is rejected', () async {
      await expectLater(
        insertExperiment(db, overrides: {'start_date': '2026-02-30'}),
        rejected,
      );
    });

    test('a concluded experiment without an outcome is rejected', () async {
      await expectLater(
        insertExperiment(
          db,
          overrides: {'status': 'concluded', 'concluded_on': '2026-11-03'},
        ),
        rejected,
      );
      await expectLater(
        insertExperiment(db, overrides: {'outcome': 'drop'}),
        rejected,
      );
      await insertExperiment(
        db,
        overrides: {
          'status': 'concluded',
          'outcome': 'drop',
          'concluded_on': '2026-11-03',
        },
      );
    });

    test('extensions_json must be a JSON array', () async {
      await expectLater(
        insertExperiment(db, overrides: {'extensions_json': '{}'}),
        rejected,
      );
      await expectLater(
        insertExperiment(db, overrides: {'extensions_json': 'not json'}),
        rejected,
      );
    });

    test('a second experiment for the same tag is rejected', () async {
      await insertExperiment(db);
      await expectLater(
        insertExperiment(db, overrides: {'id': 'another-experiment'}),
        rejected,
      );
    });

    test('an empty check-in note is rejected', () async {
      await insertExperiment(db);
      Future<void> insertNote(String id, String note) => db.customStatement(
        'INSERT INTO experiment_check_ins(id, experiment_id, slot_date, note, '
        "created_at, updated_at) VALUES (?, '$experimentId', '2026-10-05', "
        "?, '$stamp', '$stamp')",
        [id, note],
      );
      await expectLater(insertNote('c-empty', ''), rejected);
      await expectLater(insertNote('c-blank', '   '), rejected);
    });

    test('a second check-in for one slot is rejected', () async {
      await insertExperiment(db);
      Future<void> insertNote(String id) => db.customStatement(
        'INSERT INTO experiment_check_ins(id, experiment_id, slot_date, note, '
        "created_at, updated_at) VALUES (?, '$experimentId', '2026-10-05', "
        "'Note', '$stamp', '$stamp')",
        [id],
      );
      await insertNote('c1');
      await expectLater(insertNote('c2'), rejected);
    });
  });

  group('outbox payloads', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('an experiment and a check-in queue complete payloads', () async {
      await insertTag(db);
      await insertExperiment(db, overrides: {'purpose': 'Try it'});
      await db.customStatement(
        'INSERT INTO experiment_check_ins(id, experiment_id, slot_date, note, '
        "created_at, updated_at) VALUES ('c1', '$experimentId', "
        "'2026-10-05', 'Went fine', '$stamp', '$stamp')",
      );

      final log = await db.select(db.syncLog).get();
      expect(
        log
            .where((row) => row.entityTableName.startsWith('experiment'))
            .map((row) => (row.entityTableName, row.operation)),
        [('experiments', 'insert'), ('experiment_check_ins', 'insert')],
      );
      final experiment = await lastPayload(db, 'experiments');
      expect(
        experiment.keys,
        containsAll(<String>[
          'id',
          'tag_id',
          'purpose',
          'start_date',
          'end_date',
          'weekday_target_min',
          'weekend_target_min',
          'check_in_every_days',
          'status',
          'extensions_json',
          'outcome',
          'conclusion_note',
          'concluded_on',
          'created_at',
          'updated_at',
          'deleted_at',
          'server_version',
          '_planner_payload_version',
          '_planner_revision',
        ]),
      );
      expect(experiment['id'], experimentId);
      expect(experiment['tag_id'], tagId);
      expect(experiment['purpose'], 'Try it');
      expect(experiment['extensions_json'], '[]');
      expect(experiment['_planner_payload_version'], 2);
      final checkIn = await lastPayload(db, 'experiment_check_ins');
      expect(
        checkIn.keys,
        containsAll(<String>[
          'id',
          'experiment_id',
          'slot_date',
          'note',
          'created_at',
          'updated_at',
          'deleted_at',
          'server_version',
        ]),
      );
      expect(checkIn['experiment_id'], experimentId);
      expect(checkIn['note'], 'Went fine');
    });

    test('an experiment update queues an update operation', () async {
      await insertTag(db);
      await insertExperiment(db);
      await db.customStatement(
        "UPDATE experiments SET end_date = '2026-11-10' "
        "WHERE id = '$experimentId'",
      );
      final log = await db.select(db.syncLog).get();
      final operations = log
          .where((row) => row.entityTableName == 'experiments')
          .map((row) => row.operation);
      expect(operations, ['insert', 'update']);
      expect((await lastPayload(db, 'experiments'))['end_date'], '2026-11-10');
    });

    test('setting and clearing tasks.tag_id queues a tasks update', () async {
      await insertTag(db);
      await db.customStatement(
        'INSERT INTO tasks(id, title, created_at, updated_at) '
        "VALUES ('task-1', 'A block', '$stamp', '$stamp')",
      );
      expect((await lastPayload(db, 'tasks')).containsKey('tag_id'), isTrue);
      expect((await lastPayload(db, 'tasks'))['tag_id'], isNull);

      await db.customStatement(
        "UPDATE tasks SET tag_id = '$tagId' WHERE id = 'task-1'",
      );
      var tasks = (await db.select(db.syncLog).get())
          .where((row) => row.entityTableName == 'tasks')
          .toList();
      expect(tasks.last.operation, 'update');
      expect((await lastPayload(db, 'tasks'))['tag_id'], tagId);
      final afterSet = tasks.length;

      await db.customStatement(
        "UPDATE tasks SET tag_id = NULL WHERE id = 'task-1'",
      );
      tasks = (await db.select(db.syncLog).get())
          .where((row) => row.entityTableName == 'tasks')
          .toList();
      expect(tasks.length, afterSet + 1);
      final cleared = await lastPayload(db, 'tasks');
      expect(cleared.containsKey('tag_id'), isTrue);
      expect(cleared['tag_id'], isNull);
    });
  });
}
