import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/tag_dao.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/domain/experiment_form.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ExperimentRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExperimentRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Experiment> create({String name = 'Learn C'}) => repo.createExperiment(
    name: name,
    startDate: '2026-09-04',
    endDate: '2026-10-03',
    weekdayTargetMin: 60,
    weekendTargetMin: 90,
    checkInEveryDays: 7,
  );

  Future<Experiment> concluded(
    String name, {
    ExperimentOutcome outcome = ExperimentOutcome.keep,
  }) async {
    final e = await create(name: name);
    return repo.concludeExperiment(
      e.id,
      outcome: outcome,
      today: '2026-10-09',
      expectedRevision: e.revision,
    );
  }

  Future<List<SyncLogRow>> experimentLog() async =>
      (await db.select(db.syncLog).get())
          .where((r) => r.entityTableName == 'experiments')
          .toList();

  group('deleteExperiment / restoreExperiment', () {
    test('delete hides the experiment, restore brings it back', () async {
      final e = await create();
      final revision = await repo.deleteExperiment(
        e.id,
        expectedRevision: e.revision,
      );
      expect(revision, e.revision + 1);
      final row = (await db.experimentDao.getExperimentById(e.id))!;
      expect(row.deletedAt, isNotNull);
      expect(row.revision, revision);
      expect(await db.experimentDao.getExperiments(), isEmpty);

      final restored = await repo.restoreExperiment(
        e.id,
        expectedRevision: revision,
      );
      expect(restored.revision, revision + 1);
      expect(
        (await db.experimentDao.getExperimentById(e.id))!.deletedAt,
        isNull,
      );
      expect(await db.experimentDao.getExperiments(), hasLength(1));
    });

    test('restore with a changed revision fails and writes nothing', () async {
      final e = await create();
      final revision = await repo.deleteExperiment(
        e.id,
        expectedRevision: e.revision,
      );
      final logBefore = (await db.select(db.syncLog).get()).length;
      await expectLater(
        repo.restoreExperiment(e.id, expectedRevision: revision - 1),
        throwsStateError,
      );
      final row = (await db.experimentDao.getExperimentById(e.id))!;
      expect(row.deletedAt, isNotNull);
      expect(row.revision, revision);
      expect((await db.select(db.syncLog).get()).length, logBefore);
    });

    test('restore of a live experiment fails', () async {
      final e = await create();
      await expectLater(
        repo.restoreExperiment(e.id, expectedRevision: e.revision),
        throwsStateError,
      );
    });

    test('delete with a stale revision fails and writes nothing', () async {
      final e = await create();
      await expectLater(
        repo.deleteExperiment(e.id, expectedRevision: e.revision + 5),
        throwsStateError,
      );
      expect(
        (await db.experimentDao.getExperimentById(e.id))!.deletedAt,
        isNull,
      );
    });

    test('deleting a missing or already deleted experiment fails', () async {
      await expectLater(
        repo.deleteExperiment('nope', expectedRevision: 1),
        throwsStateError,
      );
      final e = await create();
      final revision = await repo.deleteExperiment(
        e.id,
        expectedRevision: e.revision,
      );
      await expectLater(
        repo.deleteExperiment(e.id, expectedRevision: revision),
        throwsStateError,
      );
    });

    test(
      'works for not started, running, concluded, kept and retired',
      () async {
        final notStarted = await repo.createExperiment(
          name: 'Future',
          startDate: '2026-12-01',
          endDate: '2026-12-30',
          weekdayTargetMin: 30,
          weekendTargetMin: 30,
          checkInEveryDays: 7,
        );
        final running = await create(name: 'Running');
        final dropped = await concluded(
          'Dropped',
          outcome: ExperimentOutcome.drop,
        );
        final kept = await concluded('Kept');
        final toRetire = await concluded('Retired');
        final retired = await repo.retireKeptExperiment(
          toRetire.id,
          expectedRevision: toRetire.revision,
        );
        for (final e in [notStarted, running, dropped, kept, retired]) {
          await repo.deleteExperiment(e.id, expectedRevision: e.revision);
          expect(
            (await db.experimentDao.getExperimentById(e.id))!.deletedAt,
            isNotNull,
            reason: e.tagName,
          );
        }
        expect(await db.experimentDao.getExperiments(), isEmpty);
      },
    );

    test('a deleted experiment refuses check-in, extend, conclude, retire '
        'and adjust', () async {
      final e = await create();
      await repo.deleteExperiment(e.id, expectedRevision: e.revision);
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-09-10',
          note: 'x',
          today: '2026-10-09',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.extendExperiment(
          e.id,
          days: 7,
          reason: 'x',
          today: '2026-10-09',
          expectedRevision: e.revision + 1,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.concludeExperiment(
          e.id,
          outcome: ExperimentOutcome.drop,
          today: '2026-10-09',
          expectedRevision: e.revision + 1,
        ),
        throwsStateError,
      );

      final k = await concluded('Kept');
      await repo.deleteExperiment(k.id, expectedRevision: k.revision);
      await expectLater(
        repo.retireKeptExperiment(k.id, expectedRevision: k.revision + 1),
        throwsStateError,
      );
      await expectLater(
        repo.adjustKeptTarget(
          k.id,
          weekdayTargetMin: 75,
          weekendTargetMin: 90,
          fromNextWeek: true,
          today: '2026-10-10',
          expectedRevision: k.revision + 1,
        ),
        throwsStateError,
      );
    });

    test('check-ins are left as they are', () async {
      final e = await create();
      await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-09-10',
        note: 'ok',
        today: '2026-10-09',
      );
      expect(await repo.countCheckIns(e.id), 1);
      await repo.deleteExperiment(e.id, expectedRevision: e.revision);
      final checkIns = await db.select(db.experimentCheckIns).get();
      expect(checkIns.single.deletedAt, isNull);
      expect(await repo.countCheckIns(e.id), 1);
    });
  });

  group('sync trigger', () {
    test(
      'delete queues a delete with the full row, restore an update',
      () async {
        final e = await create();
        final base = (await experimentLog()).length;
        final revision = await repo.deleteExperiment(
          e.id,
          expectedRevision: e.revision,
        );
        var log = await experimentLog();
        expect(log, hasLength(base + 1));
        expect(log.last.operation, 'delete');
        expect(log.last.recordId, e.id);
        final payload = jsonDecode(log.last.payload) as Map<String, dynamic>;
        expect(payload['id'], e.id);
        expect(payload['tag_id'], e.tagId);
        expect(payload['start_date'], '2026-09-04');
        expect(payload['status'], 'running');
        expect(payload['deleted_at'], isNotNull);
        expect(payload['_planner_revision'], revision);

        await repo.restoreExperiment(e.id, expectedRevision: revision);
        log = await experimentLog();
        expect(log, hasLength(base + 2));
        expect(log.last.operation, 'update');
        final restored = jsonDecode(log.last.payload) as Map<String, dynamic>;
        expect(restored['deleted_at'], isNull);
        expect(restored['_planner_revision'], revision + 1);
      },
    );

    test('queues nothing while sync.apply_mode is on', () async {
      final e = await create();
      final base = (await experimentLog()).length;
      await db.syncDao.runWithoutOutbound(() async {
        await repo.deleteExperiment(e.id, expectedRevision: e.revision);
      });
      expect(await experimentLog(), hasLength(base));
    });
  });

  group('tag flags and the deleted name', () {
    test('a deleted experiment is absent from the dashboard source and '
        'its tag loses the Experiment marker', () async {
      final e = await create();
      var options = await db.tagDao.watchTagOptions().first;
      expect(options.single.hasExperiment, isTrue);
      expect(options.single.hasDeletedExperiment, isFalse);

      await repo.deleteExperiment(e.id, expectedRevision: e.revision);
      expect(await db.experimentDao.getExperiments(), isEmpty);
      options = await db.tagDao.watchTagOptions().first;
      expect(options.single.hasExperiment, isFalse);
      expect(options.single.hasDeletedExperiment, isTrue);
      // Unfiltered on purpose: it finds the deleted experiment of the tag.
      expect((await db.experimentDao.getExperimentByTagId(e.tagId))?.id, e.id);
      // The tag guard still sees the row.
      expect(await db.tagDao.tagBelongsToExperiment(e.tagId), isTrue);
    });

    test('createExperiment on a deleted name is refused', () async {
      final e = await create();
      await repo.deleteExperiment(e.id, expectedRevision: e.revision);
      await expectLater(
        create(name: 'learn c'),
        throwsA(
          isA<ExperimentNameDeletedException>().having(
            (x) => x.toString(),
            'message',
            'An experiment called "Learn C" was deleted. '
                'Pick a different name.',
          ),
        ),
      );
      expect(await db.select(db.experiments).get(), hasLength(1));
    });

    test('the form says the name was deleted, not that it is in use', () {
      const state = ExperimentFormState(
        name: 'Learn C',
        startDate: '2026-10-01',
        endDate: '2026-10-30',
        weekdayTargetText: '60',
        weekendTargetText: '90',
      );
      final tag = TagOptionRowForTest.deleted('Learn C');
      final validation = state.validate(tags: [tag]);
      expect(
        validation.nameError,
        'An experiment called "Learn C" was deleted. Pick a different name.',
      );
      expect(validation.canSubmit, isFalse);
    });
  });
}

/// Builds the tag option of a tag that holds only a deleted experiment.
class TagOptionRowForTest {
  static TagOptionRow deleted(String name) => TagOptionRow(
    id: 'tag-$name',
    name: name,
    createdAt: '2026-10-01T00:00:00.000Z',
    hasExperiment: false,
    hasDeletedExperiment: true,
  );
}
