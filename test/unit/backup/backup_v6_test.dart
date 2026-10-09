import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/settings/data/backup_codec.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';
import 'package:personal_planner/features/task_editor/data/tag_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase database;
  late Experiment experiment;
  late Task taggedTask;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final tags = TagRepository(database);
    final repo = ExperimentRepository(database);
    experiment = await repo.createExperiment(
      name: 'Learn C',
      purpose: 'Does it stick?',
      startDate: '2026-10-01',
      endDate: '2026-10-14',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 7,
    );
    await repo.saveCheckIn(
      experimentId: experiment.id,
      slotDate: '2026-10-07',
      note: 'Going well 😀',
      today: '2026-10-08',
    );
    experiment = await repo.extendExperiment(
      experiment.id,
      days: 7,
      reason: 'Travelled',
      today: '2026-10-14',
      expectedRevision: experiment.revision,
    );
    taggedTask = await TaskRepository(database).insertTask(
      Task(
        id: '',
        title: 'Tagged block',
        startTime: DateTime.utc(2026, 10, 6, 9),
        endTime: DateTime.utc(2026, 10, 6, 10),
        tagId: (await tags.findByNameIgnoringCase('learn c'))!.id,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Map<String, dynamic> dataOf(Map<String, dynamic> document) =>
      (document['content'] as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

  /// Re-seals a document after a test changed its data.
  String reseal(Map<String, dynamic> document, {int? version}) {
    final content = document['content'] as Map<String, dynamic>;
    if (version != null) {
      document['schema_version'] = version;
      content['schema_version'] = version;
    }
    (document['validation'] as Map<String, dynamic>)['record_counts'] =
        BackupCodec.recordCounts(content['data'] as Map<String, dynamic>);
    document['content_checksum'] = BackupCodec.checksum(content);
    return jsonEncode(document);
  }

  Future<Map<String, dynamic>> exported() async =>
      jsonDecode(await BackupService(database).exportJson())
          as Map<String, dynamic>;

  test('the format version is 6', () {
    expect(plannerBackupSchemaVersion, 6);
  });

  test('export carries tag_id, experiments and check-ins', () async {
    final document = await exported();
    expect(document['schema_version'], 6);
    final data = dataOf(document);

    final task = (data['tasks'] as List).cast<Map>().singleWhere(
      (row) => row['id'] == taggedTask.id,
    );
    expect(task['tag_id'], experiment.tagId);

    final experiments = (data['experiments'] as List).cast<Map>();
    expect(experiments, hasLength(1));
    expect(experiments.single['id'], experiment.id);
    expect(experiments.single['tag_id'], experiment.tagId);
    expect(experiments.single['end_date'], '2026-10-21');
    expect(experiments.single['status'], 'running');
    final extensions =
        jsonDecode(experiments.single['extensions_json'] as String) as List;
    expect(extensions.single['reason'], 'Travelled');

    final checkIns = (data['experiment_check_ins'] as List).cast<Map>();
    expect(checkIns.single['experiment_id'], experiment.id);
    expect(checkIns.single['slot_date'], '2026-10-07');
    expect(checkIns.single['note'], 'Going well 😀');
  });

  test('v6 round trips through a merge import', () async {
    final source = await BackupService(database).exportJson();
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    final result = await BackupService(restored)
        .importJson(source, ownershipConfirmed: true);
    expect(result.conflicts, isEmpty);
    expect(result.inserted, greaterThan(0));

    final task = await restored.taskDao.getTaskById(taggedTask.id);
    expect(task!.tagId, experiment.tagId);
    final row = (await restored.select(restored.experiments).get()).single;
    expect(row.id, experiment.id);
    expect(row.tagId, experiment.tagId);
    expect(row.purpose, 'Does it stick?');
    expect(row.endDate, '2026-10-21');
    expect(row.weekendTargetMin, 90);
    expect(
      (jsonDecode(row.extensionsJson) as List).single['new_end_date'],
      '2026-10-21',
    );
    final checkIn =
        (await restored.select(restored.experimentCheckIns).get()).single;
    expect(checkIn.note, 'Going well 😀');
    expect(checkIn.experimentId, experiment.id);

    // The restored data exports to the same document content.
    expect(
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(restored))['experiments'],
      ),
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(database))['experiments'],
      ),
    );
  });

  test('importing the same file again changes nothing', () async {
    final source = await BackupService(database).exportJson();
    final before = await database.select(database.syncLog).get();
    final result = await BackupService(database)
        .importJson(source, ownershipConfirmed: true);
    expect(result.inserted, 0);
    expect(result.conflicts, isEmpty);
    expect(result.skipped, greaterThan(0));
    expect(
      (await database.select(database.syncLog).get()).length,
      before.length,
    );
  });

  test('replace removes the experiments of the old data first', () async {
    final source = await BackupService(database).exportJson();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await ExperimentRepository(other).createExperiment(
      name: 'Other',
      startDate: '2026-09-01',
      endDate: '2026-09-30',
      weekdayTargetMin: 30,
      weekendTargetMin: 30,
      checkInEveryDays: 1,
    );
    final preImport = await BackupService(other).exportJson();

    await BackupService(other).replaceFromJson(
      source,
      preImportBackup: preImport,
      confirmed: true,
      ownershipConfirmed: true,
    );

    final rows = await other.select(other.experiments).get();
    expect(rows.map((r) => r.id), [experiment.id]);
    expect(await other.select(other.experimentCheckIns).get(), hasLength(1));
    expect(
      (await other.taskDao.getTaskById(taggedTask.id))!.tagId,
      experiment.tagId,
    );
  });

  test(
    'a v5 backup imports with no tags on blocks and no experiments',
    () async {
      final document = await exported();
      final data = dataOf(document);
      data.remove('experiments');
      data.remove('experiment_check_ins');
      for (final raw in data['tasks'] as List) {
        (raw as Map<String, dynamic>).remove('tag_id');
      }
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);

      await BackupService(restored)
          .importJson(reseal(document, version: 5), ownershipConfirmed: true);

      expect(await restored.select(restored.experiments).get(), isEmpty);
      expect(await restored.select(restored.experimentCheckIns).get(), isEmpty);
      final tasks = await restored.select(restored.tasks).get();
      expect(tasks, isNotEmpty);
      expect(tasks.every((t) => t.tagId == null), isTrue);
      // The tag row itself is an ordinary v5 table and comes along.
      expect(await restored.select(restored.tags).get(), hasLength(1));
    },
  );

  group('invalid rows are rejected', () {
    Future<void> expectRejected(
      void Function(Map<String, dynamic> data) mutate,
    ) async {
      final document = await exported();
      mutate(dataOf(document));
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await expectLater(
        BackupService(target)
            .importJson(reseal(document), ownershipConfirmed: true),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await target.select(target.tasks).get(), isEmpty);
      expect(await target.select(target.experiments).get(), isEmpty);
    }

    Map<String, dynamic> experimentRow(Map<String, dynamic> data) =>
        (data['experiments'] as List).first as Map<String, dynamic>;
    Map<String, dynamic> checkInRow(Map<String, dynamic> data) =>
        (data['experiment_check_ins'] as List).first as Map<String, dynamic>;

    test('an experiment id that does not match its tag', () async {
      await expectRejected(
        (d) => experimentRow(d)['id'] = generateDeterministicUuid('other'),
      );
    });

    test('an unsupported frequency', () async {
      await expectRejected((d) => experimentRow(d)['check_in_every_days'] = 2);
    });

    test('an end date before the start date', () async {
      await expectRejected((d) => experimentRow(d)['end_date'] = '2026-09-01');
    });

    test('a target out of range', () async {
      await expectRejected((d) => experimentRow(d)['weekday_target_min'] = -1);
      await expectRejected(
        (d) => experimentRow(d)['weekend_target_min'] = 10000,
      );
    });

    test('a concluded experiment without an outcome', () async {
      await expectRejected((d) {
        experimentRow(d)['status'] = 'concluded';
        experimentRow(d)['concluded_on'] = '2026-10-21';
      });
    });

    test('a running experiment with an outcome', () async {
      await expectRejected((d) => experimentRow(d)['outcome'] = 'drop');
    });

    test('an extension entry with a missing key', () async {
      await expectRejected(
        (d) => experimentRow(d)['extensions_json'] = jsonEncode([
          {'reason': 'x', 'previous_end_date': '2026-10-14'},
        ]),
      );
    });

    test('an extension that does not move the end date later', () async {
      await expectRejected(
        (d) => experimentRow(d)['extensions_json'] = jsonEncode([
          {
            'reason': 'x',
            'previous_end_date': '2026-10-14',
            'new_end_date': '2026-10-14',
            'made_on': '2026-10-14',
          },
        ]),
      );
    });

    test('a purpose over 1000 characters', () async {
      await expectRejected((d) => experimentRow(d)['purpose'] = 'p' * 1001);
    });

    test('an experiment whose tag is missing from the document', () async {
      await expectRejected((d) {
        final tag = experiment.tagId;
        (d['tags'] as List).removeWhere((r) => (r as Map)['id'] == tag);
        for (final raw in d['tasks'] as List) {
          (raw as Map<String, dynamic>)['tag_id'] = null;
        }
      });
    });

    test('a task whose tag is missing from the document', () async {
      await expectRejected(
        (d) => ((d['tasks'] as List).first as Map<String, dynamic>)['tag_id'] =
            generateUuidV7(),
      );
    });

    test('a check-in id that does not match its experiment and date', () async {
      await expectRejected(
        (d) => checkInRow(d)['id'] = generateDeterministicUuid('nope'),
      );
    });

    test('a blank check-in note', () async {
      await expectRejected((d) => checkInRow(d)['note'] = '   ');
    });

    test('a check-in note over 4000 characters', () async {
      await expectRejected((d) => checkInRow(d)['note'] = '😀' * 4001);
    });

    test('a check-in of a missing experiment', () async {
      final missing = generateUuidV7();
      await expectRejected((d) {
        final row = checkInRow(d);
        row['experiment_id'] = missing;
        row['id'] = generateDeterministicUuid(
          'experiment-check-in:$missing:${row['slot_date']}',
        );
      });
    });

    test('an experiment row with an unknown field', () async {
      await expectRejected((d) => experimentRow(d)['feel'] = 3);
    });
  });

  test('a note of exactly 4000 emoji is accepted', () async {
    final document = await exported();
    final row =
        (dataOf(document)['experiment_check_ins'] as List).first
            as Map<String, dynamic>;
    row['note'] = '😀' * 4000;
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await BackupService(restored)
        .importJson(reseal(document), ownershipConfirmed: true);
    final stored =
        (await restored.select(restored.experimentCheckIns).get()).single;
    expect(stored.note.runes.length, 4000);
  });
}
