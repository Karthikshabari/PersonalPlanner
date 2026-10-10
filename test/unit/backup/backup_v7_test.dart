import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/settings/data/backup_codec.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  const keptKeys = ['retired_at', 'retire_note', 'target_changes_json'];
  final retiredAt = DateTime.utc(2026, 10, 10, 8, 30);

  late AppDatabase database;
  late Experiment experiment;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final repo = ExperimentRepository(database, clock: () => retiredAt);
    var e = await repo.createExperiment(
      name: 'Morning pages',
      startDate: '2026-09-04',
      endDate: '2026-10-03',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 7,
    );
    e = await repo.concludeExperiment(
      e.id,
      outcome: ExperimentOutcome.keep,
      note: 'Mornings beat evenings.',
      today: '2026-10-09',
      expectedRevision: e.revision,
    );
    e = await repo.adjustKeptTarget(
      e.id,
      weekdayTargetMin: 75,
      weekendTargetMin: 90,
      fromNextWeek: true,
      today: '2026-10-10',
      expectedRevision: e.revision,
    );
    experiment = await repo.retireKeptExperiment(
      e.id,
      note: 'Learned enough',
      expectedRevision: e.revision,
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

  Map<String, dynamic> experimentRow(Map<String, dynamic> data) =>
      (data['experiments'] as List).first as Map<String, dynamic>;

  test('the format version is 7', () {
    expect(plannerBackupSchemaVersion, 7);
  });

  test('export carries the three kept keys on every experiments row', () async {
    final document = await exported();
    expect(document['schema_version'], 7);
    final rows = (dataOf(document)['experiments'] as List).cast<Map>();
    expect(rows, hasLength(1));
    for (final key in keptKeys) {
      expect(rows.single.containsKey(key), isTrue, reason: key);
    }
    expect(rows.single['retired_at'], '2026-10-10T08:30:00.000Z');
    expect(rows.single['retire_note'], 'Learned enough');
    final changes =
        jsonDecode(rows.single['target_changes_json'] as String) as List;
    expect(changes.single['effective_week_start'], '2026-10-12');
    expect(changes.single['weekday_target_min'], 75);
  });

  test('a round trip keeps retired_at, retire_note and the history', () async {
    final source = await BackupService(database).exportJson();
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    final result = await BackupService(restored)
        .importJson(source, ownershipConfirmed: true);
    expect(result.conflicts, isEmpty);

    final row = (await restored.select(restored.experiments).get()).single;
    expect(row.id, experiment.id);
    expect(row.retiredAt!.isAtSameMomentAs(retiredAt), isTrue);
    expect(row.retireNote, 'Learned enough');
    expect(row.targetChangesJson, contains('"2026-10-12"'));
    expect(
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(restored))['experiments'],
      ),
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(database))['experiments'],
      ),
    );
  });

  test('a v6 document imports with the kept defaults', () async {
    final document = await exported();
    for (final raw in dataOf(document)['experiments'] as List) {
      final row = raw as Map<String, dynamic>;
      for (final key in keptKeys) {
        row.remove(key);
      }
    }
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    await BackupService(restored)
        .importJson(reseal(document, version: 6), ownershipConfirmed: true);

    final row = (await restored.select(restored.experiments).get()).single;
    expect(row.outcome, 'continue_habit');
    expect(row.retiredAt, isNull);
    expect(row.retireNote, isNull);
    expect(row.targetChangesJson, '[]');
  });

  group('invalid kept rows are rejected', () {
    Future<void> expectRejected(
      void Function(Map<String, dynamic> row) mutate,
    ) async {
      final document = await exported();
      mutate(experimentRow(dataOf(document)));
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await expectLater(
        BackupService(target)
            .importJson(reseal(document), ownershipConfirmed: true),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await target.select(target.experiments).get(), isEmpty);
    }

    String changes(List<Map<String, Object?>> items) => jsonEncode(items);
    Map<String, Object?> change({
      String week = '2026-10-12',
      int weekday = 75,
      int weekend = 90,
    }) => {
      'effective_week_start': week,
      'weekday_target_min': weekday,
      'weekend_target_min': weekend,
      'made_on': '2026-10-10',
    };

    test('retired_at on a dropped experiment', () async {
      await expectRejected((row) => row['outcome'] = 'drop');
    });

    test('retired_at on a running experiment', () async {
      await expectRejected((row) {
        row['status'] = 'running';
        row['outcome'] = null;
        row['conclusion_note'] = null;
        row['concluded_on'] = null;
        row['target_changes_json'] = '[]';
      });
    });

    test('a retire note without a retirement', () async {
      await expectRejected((row) => row['retired_at'] = null);
    });

    test('a retire note over 4000 characters', () async {
      await expectRejected((row) => row['retire_note'] = '😀' * 4001);
    });

    test('a bad retired_at', () async {
      await expectRejected((row) => row['retired_at'] = 'yesterday');
    });

    test('a history on a running experiment', () async {
      await expectRejected((row) {
        row['status'] = 'running';
        row['outcome'] = null;
        row['conclusion_note'] = null;
        row['concluded_on'] = null;
        row['retired_at'] = null;
        row['retire_note'] = null;
        row['target_changes_json'] = changes([change()]);
      });
    });

    test('a history week that is not a Monday', () async {
      await expectRejected(
        (row) =>
            row['target_changes_json'] = changes([change(week: '2026-10-13')]),
      );
    });

    test('a history target outside 15..240', () async {
      await expectRejected(
        (row) => row['target_changes_json'] = changes([change(weekday: 10)]),
      );
      await expectRejected(
        (row) => row['target_changes_json'] = changes([change(weekend: 241)]),
      );
    });

    test('duplicate history weeks', () async {
      await expectRejected(
        (row) => row['target_changes_json'] = changes([change(), change()]),
      );
    });

    test('history that is not a JSON array', () async {
      await expectRejected((row) => row['target_changes_json'] = '{}');
      await expectRejected((row) => row['target_changes_json'] = 'nope');
      await expectRejected((row) => row['target_changes_json'] = 7);
    });
  });
}
