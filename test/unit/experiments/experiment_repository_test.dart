import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/task_editor/data/tag_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ExperimentRepository repo;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExperimentRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Experiment> create({
    String name = 'Learn C',
    String? purpose,
    String start = '2026-10-01',
    String end = '2026-10-30',
    int weekday = 60,
    int weekend = 90,
    int every = 7,
  }) => repo.createExperiment(
    name: name,
    purpose: purpose,
    startDate: start,
    endDate: end,
    weekdayTargetMin: weekday,
    weekendTargetMin: weekend,
    checkInEveryDays: every,
  );

  group('createExperiment', () {
    test(
      'creates the tag and the experiment with a deterministic id',
      () async {
        final experiment = await create(purpose: '  Find out if I like it  ');
        expect(experiment.tagName, 'Learn C');
        expect(experiment.tagId, generateDeterministicUuid('tag:Learn C'));
        expect(
          experiment.id,
          generateDeterministicUuid('experiment:${experiment.tagId}'),
        );
        expect(experiment.status, ExperimentStatus.running);
        expect(experiment.extensions, isEmpty);
        expect(experiment.purpose, 'Find out if I like it');
        expect(experiment.revision, 1);
        expect(experiment.outcome, isNull);
        expect(
          (await tags.findByNameIgnoringCase('learn c'))!.id,
          experiment.tagId,
        );
      },
    );

    test('an empty purpose is stored as null', () async {
      expect((await create(purpose: '   ')).purpose, isNull);
    });

    test(
      'uses an existing tag that has no experiment, matching case',
      () async {
        final existing = await tags.getOrCreateByName('Learn C');
        final experiment = await create(name: '  learn  c ');
        expect(experiment.tagId, existing.id);
        expect(experiment.tagName, 'Learn C');
        expect((await tags.watchAllTags().first), hasLength(1));
      },
    );

    test('is refused when an experiment already uses the tag', () async {
      await create();
      await expectLater(
        create(name: 'LEARN C'),
        throwsA(
          isA<ExperimentTagInUseException>().having(
            (e) => e.tagName,
            'tagName',
            'Learn C',
          ),
        ),
      );
      expect(await db.select(db.experiments).get(), hasLength(1));
    });

    test('refused for invalid values, and nothing is written', () async {
      final bad = <Future<Experiment> Function()>[
        () => create(name: '   '),
        () => create(name: 'x' * 101),
        () => create(start: '2026-02-30'),
        () => create(end: '2026-09-30'),
        () => create(weekday: -1),
        () => create(weekend: 10000),
        () => create(every: 2),
        () => create(purpose: 'p' * 1001),
      ];
      for (final attempt in bad) {
        await expectLater(attempt(), throwsArgumentError);
      }
      expect(await db.select(db.experiments).get(), isEmpty);
      expect(await db.select(db.tags).get(), isEmpty);
    });

    test('accepts the limits exactly', () async {
      final experiment = await create(
        name: 'n' * 100,
        purpose: '😀' * 1000,
        weekday: 0,
        weekend: 9999,
        every: 15,
        end: '2026-10-01',
      );
      expect(experiment.purpose!.runes.length, 1000);
      expect(experiment.weekendTargetMin, 9999);
    });

    test('queues sync operations for the tag and the experiment', () async {
      final experiment = await create();
      final log = await db.select(db.syncLog).get();
      expect(
        log
            .where((r) => r.entityTableName == 'experiments')
            .map((r) => (r.recordId, r.operation)),
        [(experiment.id, 'insert')],
      );
      expect(
        log.where((r) => r.entityTableName == 'tags').map((r) => r.recordId),
        [experiment.tagId],
      );
    });

    test('watchExperiments streams the tag name', () async {
      await create();
      final list = await repo.watchExperiments().first;
      expect(list.single.tagName, 'Learn C');
    });
  });

  group('extendExperiment', () {
    test('only on or after the end date', () async {
      final e = await create();
      await expectLater(
        repo.extendExperiment(
          e.id,
          days: 7,
          reason: 'Travel',
          today: '2026-10-29',
          expectedRevision: e.revision,
        ),
        throwsStateError,
      );
      final extended = await repo.extendExperiment(
        e.id,
        days: 7,
        reason: 'Travel',
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
      expect(extended.endDate, '2026-11-06');
    });

    test('7, 14 and 30 only', () async {
      final e = await create();
      for (final days in [0, 1, 8, 15, 31]) {
        await expectLater(
          repo.extendExperiment(
            e.id,
            days: days,
            reason: 'x',
            today: '2026-10-30',
            expectedRevision: e.revision,
          ),
          throwsArgumentError,
        );
      }
      final extended = await repo.extendExperiment(
        e.id,
        days: 30,
        reason: 'x',
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
      expect(extended.endDate, '2026-11-29');
    });

    test('a reason is required and limited to 500 characters', () async {
      final e = await create();
      for (final reason in ['', '   ', 'r' * 501]) {
        await expectLater(
          repo.extendExperiment(
            e.id,
            days: 7,
            reason: reason,
            today: '2026-10-30',
            expectedRevision: e.revision,
          ),
          throwsArgumentError,
        );
      }
      await repo.extendExperiment(
        e.id,
        days: 7,
        reason: '😀' * 500,
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
    });

    test('records the history entry and bumps the revision', () async {
      final e = await create();
      final extended = await repo.extendExperiment(
        e.id,
        days: 14,
        reason: '  Missed a week  ',
        today: '2026-11-02',
        expectedRevision: e.revision,
      );
      expect(extended.revision, e.revision + 1);
      expect(extended.endDate, '2026-11-13');
      expect(extended.extensions, hasLength(1));
      final entry = extended.extensions.single;
      expect(entry.reason, 'Missed a week');
      expect(entry.previousEndDate, '2026-10-30');
      expect(entry.newEndDate, '2026-11-13');
      expect(entry.madeOn, '2026-11-02');
      final log = await db.select(db.syncLog).get();
      expect(
        log.where(
          (r) => r.entityTableName == 'experiments' && r.operation == 'update',
        ),
        isNotEmpty,
      );
    });

    test('repeated extends append entries', () async {
      var e = await create();
      e = await repo.extendExperiment(
        e.id,
        days: 7,
        reason: 'one',
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
      e = await repo.extendExperiment(
        e.id,
        days: 14,
        reason: 'two',
        today: '2026-11-06',
        expectedRevision: e.revision,
      );
      expect(e.extensions.map((x) => x.reason), ['one', 'two']);
      expect(e.extensions.last.previousEndDate, '2026-11-06');
      expect(e.endDate, '2026-11-20');
    });

    test('refuses a stale revision and a concluded experiment', () async {
      final e = await create();
      await expectLater(
        repo.extendExperiment(
          e.id,
          days: 7,
          reason: 'x',
          today: '2026-10-30',
          expectedRevision: e.revision + 5,
        ),
        throwsStateError,
      );
      final done = await repo.concludeExperiment(
        e.id,
        outcome: ExperimentOutcome.drop,
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
      await expectLater(
        repo.extendExperiment(
          e.id,
          days: 7,
          reason: 'x',
          today: '2026-10-31',
          expectedRevision: done.revision,
        ),
        throwsStateError,
      );
    });

    test('adds days by calendar across the fall-back day', () async {
      PlannerTimeZone.initialize(identifier: 'America/New_York');
      addTearDown(() => PlannerTimeZone.initialize(identifier: 'Asia/Kolkata'));
      final e = await create(start: '2026-10-25', end: '2026-10-31');
      final extended = await repo.extendExperiment(
        e.id,
        days: 7,
        reason: 'x',
        today: '2026-10-31',
        expectedRevision: e.revision,
      );
      expect(extended.endDate, '2026-11-07');
    });
  });

  group('concludeExperiment', () {
    test('both outcomes, with a trimmed note', () async {
      final a = await create(name: 'A');
      final b = await create(name: 'B');
      final doneA = await repo.concludeExperiment(
        a.id,
        outcome: ExperimentOutcome.keep,
        note: '  Like it  ',
        today: '2026-10-30',
        expectedRevision: a.revision,
      );
      final doneB = await repo.concludeExperiment(
        b.id,
        outcome: ExperimentOutcome.drop,
        today: '2026-11-01',
        expectedRevision: b.revision,
      );
      expect(doneA.status, ExperimentStatus.concluded);
      expect(doneA.outcome, ExperimentOutcome.keep);
      expect(doneA.conclusionNote, 'Like it');
      expect(doneA.concludedOn, '2026-10-30');
      expect(doneA.revision, a.revision + 1);
      expect(doneB.outcome, ExperimentOutcome.drop);
      expect(doneB.conclusionNote, isNull);
      expect(doneB.concludedOn, '2026-11-01');
    });

    test(
      'refused before the end date, for a long note and a stale revision',
      () async {
        final e = await create();
        await expectLater(
          repo.concludeExperiment(
            e.id,
            outcome: ExperimentOutcome.drop,
            today: '2026-10-29',
            expectedRevision: e.revision,
          ),
          throwsStateError,
        );
        await expectLater(
          repo.concludeExperiment(
            e.id,
            outcome: ExperimentOutcome.drop,
            note: 'n' * 4001,
            today: '2026-10-30',
            expectedRevision: e.revision,
          ),
          throwsArgumentError,
        );
        await expectLater(
          repo.concludeExperiment(
            e.id,
            outcome: ExperimentOutcome.drop,
            today: '2026-10-30',
            expectedRevision: e.revision + 1,
          ),
          throwsStateError,
        );
      },
    );

    test('cannot conclude twice', () async {
      final e = await create();
      final done = await repo.concludeExperiment(
        e.id,
        outcome: ExperimentOutcome.drop,
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
      await expectLater(
        repo.concludeExperiment(
          e.id,
          outcome: ExperimentOutcome.keep,
          today: '2026-10-30',
          expectedRevision: done.revision,
        ),
        throwsStateError,
      );
    });
  });

  group('saveCheckIn', () {
    test('saves a valid slot with the deterministic id', () async {
      final e = await create();
      final saved = await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-07',
        note: '  Going well  ',
        today: '2026-10-08',
      );
      expect(saved.note, 'Going well');
      expect(saved.slotDate, '2026-10-07');
      expect(
        saved.id,
        generateDeterministicUuid('experiment-check-in:${e.id}:2026-10-07'),
      );
      expect(await repo.watchCheckIns(e.id).first, hasLength(1));
      final log = await db.select(db.syncLog).get();
      expect(
        log
            .where((r) => r.entityTableName == 'experiment_check_ins')
            .map((r) => r.recordId),
        [saved.id],
      );
    });

    test('a slot dated today is allowed', () async {
      final e = await create();
      await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-07',
        note: 'ok',
        today: '2026-10-07',
      );
    });

    test('refused for a date that is not a slot', () async {
      final e = await create();
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-10-08',
          note: 'ok',
          today: '2026-10-09',
        ),
        throwsArgumentError,
      );
    });

    test('refused for a future slot', () async {
      final e = await create();
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-10-14',
          note: 'ok',
          today: '2026-10-13',
        ),
        throwsArgumentError,
      );
    });

    test('a second check-in for the same slot is refused', () async {
      final e = await create();
      await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-07',
        note: 'first',
        today: '2026-10-08',
      );
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-10-07',
          note: 'second',
          today: '2026-10-08',
        ),
        throwsStateError,
      );
      expect((await repo.watchCheckIns(e.id).first).single.note, 'first');
    });

    test('refused for a concluded experiment', () async {
      final e = await create();
      await repo.concludeExperiment(
        e.id,
        outcome: ExperimentOutcome.drop,
        today: '2026-10-30',
        expectedRevision: e.revision,
      );
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-10-07',
          note: 'late',
          today: '2026-10-31',
        ),
        throwsStateError,
      );
    });

    test('slots follow an extended end date', () async {
      final e = await create(end: '2026-10-14');
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-10-21',
          note: 'x',
          today: '2026-10-22',
        ),
        throwsArgumentError,
      );
      await repo.extendExperiment(
        e.id,
        days: 14,
        reason: 'x',
        today: '2026-10-14',
        expectedRevision: e.revision,
      );
      await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-21',
        note: 'x',
        today: '2026-10-22',
      );
    });

    test('a missing experiment is refused', () async {
      await expectLater(
        repo.saveCheckIn(
          experimentId: generateUuidV7(),
          slotDate: '2026-10-07',
          note: 'x',
          today: '2026-10-08',
        ),
        throwsStateError,
      );
    });

    test('note limits count code points (ED9)', () async {
      final e = await create(every: 1);
      // 4000 emoji are 8000 UTF-16 code units and must be accepted.
      final saved = await repo.saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-01',
        note: '😀' * 4000,
        today: '2026-10-05',
      );
      expect(saved.note.runes.length, 4000);
      expect(saved.note.length, 8000);
      await expectLater(
        repo.saveCheckIn(
          experimentId: e.id,
          slotDate: '2026-10-02',
          note: '😀' * 4001,
          today: '2026-10-05',
        ),
        throwsArgumentError,
      );
      for (final blank in ['', '  \n ']) {
        await expectLater(
          repo.saveCheckIn(
            experimentId: e.id,
            slotDate: '2026-10-03',
            note: blank,
            today: '2026-10-05',
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('kept writes', () {
    const today = '2026-10-10';
    final retireTime = DateTime.utc(2026, 10, 10, 8, 30);

    Future<Experiment> concluded(String name, ExperimentOutcome outcome) async {
      final e = await create(
        name: name,
        start: '2026-09-04',
        end: '2026-10-03',
      );
      return repo.concludeExperiment(
        e.id,
        outcome: outcome,
        today: '2026-10-09',
        expectedRevision: e.revision,
      );
    }

    Future<Experiment> kept() =>
        concluded('Morning pages', ExperimentOutcome.keep);

    Future<List<String>> experimentOperations() async =>
        (await db.select(db.syncLog).get())
            .where((r) => r.entityTableName == 'experiments')
            .map((r) => r.operation)
            .toList();

    test('adjust from next week creates a pending entry', () async {
      final e = await kept();
      final adjusted = await repo.adjustKeptTarget(
        e.id,
        weekdayTargetMin: 75,
        weekendTargetMin: 90,
        fromNextWeek: true,
        today: today,
        expectedRevision: e.revision,
      );
      expect(adjusted.revision, e.revision + 1);
      expect(adjusted.weekdayTargetMin, 60);
      expect(adjusted.targetChanges, hasLength(1));
      final change = adjusted.targetChanges.single;
      expect(change.effectiveWeekStart, '2026-10-12');
      expect(change.weekdayTargetMin, 75);
      expect(change.weekendTargetMin, 90);
      expect(change.madeOn, today);
    });

    test('adjust from this week creates a current entry', () async {
      final e = await kept();
      final adjusted = await repo.adjustKeptTarget(
        e.id,
        weekdayTargetMin: 75,
        weekendTargetMin: 105,
        fromNextWeek: false,
        today: today,
        expectedRevision: e.revision,
      );
      expect(adjusted.targetChanges.single.effectiveWeekStart, '2026-10-05');
      expect(adjusted.targetChanges.single.weekendTargetMin, 105);
    });

    test('an equal adjust is a no-op and adds no sync_log row', () async {
      final e = await kept();
      final before = (await experimentOperations()).length;
      final same = await repo.adjustKeptTarget(
        e.id,
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        fromNextWeek: true,
        today: today,
        expectedRevision: e.revision,
      );
      expect(same.revision, e.revision);
      expect(same.targetChanges, isEmpty);
      expect((await experimentOperations()).length, before);
    });

    test('adjust is refused when the experiment is not kept', () async {
      Future<void> adjust(Experiment e, {int weekday = 75}) =>
          repo.adjustKeptTarget(
            e.id,
            weekdayTargetMin: weekday,
            weekendTargetMin: 90,
            fromNextWeek: true,
            today: today,
            expectedRevision: e.revision,
          );
      final running = await create(name: 'Running one');
      await expectLater(adjust(running), throwsStateError);
      final dropped = await concluded('Dropped one', ExperimentOutcome.drop);
      await expectLater(adjust(dropped), throwsStateError);
      final k = await kept();
      final retired = await repo.retireKeptExperiment(
        k.id,
        expectedRevision: k.revision,
      );
      await expectLater(adjust(retired), throwsStateError);
    });

    test('adjust is refused for 14, 241 and a stale revision', () async {
      final e = await kept();
      for (final bad in [14, 241]) {
        await expectLater(
          repo.adjustKeptTarget(
            e.id,
            weekdayTargetMin: bad,
            weekendTargetMin: 90,
            fromNextWeek: true,
            today: today,
            expectedRevision: e.revision,
          ),
          throwsArgumentError,
        );
        await expectLater(
          repo.adjustKeptTarget(
            e.id,
            weekdayTargetMin: 60,
            weekendTargetMin: bad,
            fromNextWeek: true,
            today: today,
            expectedRevision: e.revision,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        repo.adjustKeptTarget(
          e.id,
          weekdayTargetMin: 75,
          weekendTargetMin: 90,
          fromNextWeek: true,
          today: today,
          expectedRevision: e.revision + 1,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.adjustKeptTarget(
          e.id,
          weekdayTargetMin: 75,
          weekendTargetMin: 90,
          fromNextWeek: true,
          today: 'not-a-date',
          expectedRevision: e.revision,
        ),
        throwsArgumentError,
      );
    });

    test('retire stores the clock time and a trimmed note', () async {
      final clocked = ExperimentRepository(db, clock: () => retireTime);
      final e = await kept();
      final retired = await clocked.retireKeptExperiment(
        e.id,
        note: '  Mornings beat evenings.  ',
        expectedRevision: e.revision,
      );
      expect(retired.retiredAt!.isAtSameMomentAs(retireTime), isTrue);
      expect(retired.retireNote, 'Mornings beat evenings.');
      expect(retired.isRetired, isTrue);
      expect(retired.isKept, isFalse);
      expect(retired.revision, e.revision + 1);
    });

    test('retire stores null for a blank note', () async {
      final e = await kept();
      final retired = await repo.retireKeptExperiment(
        e.id,
        note: '   ',
        expectedRevision: e.revision,
      );
      expect(retired.retiredAt, isNotNull);
      expect(retired.retireNote, isNull);
    });

    test(
      'retire refuses 4001 emoji, a stale revision and a non-kept one',
      () async {
        final e = await kept();
        await expectLater(
          repo.retireKeptExperiment(
            e.id,
            note: '😀' * 4001,
            expectedRevision: e.revision,
          ),
          throwsArgumentError,
        );
        final ok = await repo.retireKeptExperiment(
          e.id,
          note: '😀' * 4000,
          expectedRevision: e.revision,
        );
        expect(ok.retireNote!.runes.length, 4000);
        await expectLater(
          repo.retireKeptExperiment(e.id, expectedRevision: ok.revision),
          throwsStateError,
          reason: 'already retired',
        );
        final fresh = await concluded('Other', ExperimentOutcome.keep);
        await expectLater(
          repo.retireKeptExperiment(
            fresh.id,
            expectedRevision: fresh.revision + 1,
          ),
          throwsStateError,
        );
        final running = await create(name: 'Running one');
        await expectLater(
          repo.retireKeptExperiment(
            running.id,
            expectedRevision: running.revision,
          ),
          throwsStateError,
        );
        final dropped = await concluded('Dropped one', ExperimentOutcome.drop);
        await expectLater(
          repo.retireKeptExperiment(
            dropped.id,
            expectedRevision: dropped.revision,
          ),
          throwsStateError,
        );
      },
    );

    test('undo clears both fields and refuses when not retired', () async {
      final e = await kept();
      await expectLater(
        repo.undoRetireExperiment(e.id, expectedRevision: e.revision),
        throwsStateError,
      );
      final retired = await repo.retireKeptExperiment(
        e.id,
        note: 'Done with it',
        expectedRevision: e.revision,
      );
      final undone = await repo.undoRetireExperiment(
        e.id,
        expectedRevision: retired.revision,
      );
      expect(undone.retiredAt, isNull);
      expect(undone.retireNote, isNull);
      expect(undone.isKept, isTrue);
      expect(undone.revision, retired.revision + 1);
      await expectLater(
        repo.undoRetireExperiment(e.id, expectedRevision: undone.revision),
        throwsStateError,
      );
    });

    test(
      'each successful write queues exactly one experiments update',
      () async {
        final e = await kept();
        Future<int> updates() async =>
            (await experimentOperations()).where((o) => o == 'update').length;
        final base = await updates();

        final adjusted = await repo.adjustKeptTarget(
          e.id,
          weekdayTargetMin: 75,
          weekendTargetMin: 90,
          fromNextWeek: false,
          today: today,
          expectedRevision: e.revision,
        );
        expect(await updates(), base + 1);
        final retired = await repo.retireKeptExperiment(
          e.id,
          note: 'x',
          expectedRevision: adjusted.revision,
        );
        expect(await updates(), base + 2);
        await repo.undoRetireExperiment(
          e.id,
          expectedRevision: retired.revision,
        );
        expect(await updates(), base + 3);
      },
    );
  });
}
