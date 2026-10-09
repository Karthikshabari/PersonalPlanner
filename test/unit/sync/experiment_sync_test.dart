import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_semantic_equality.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../helpers/sqlite_setup.dart';

const _tagId = '11111111-1111-4111-8111-111111111111';
const _experimentId = '6a921905-9a5c-51c0-b898-e0c6985d8a72';
const _checkInId = '52ddb265-2dac-5d4c-9d51-657bc6f99153';
const _stamp = '2026-10-09T10:00:00.000Z';

Map<String, dynamic> _experimentPayload({
  String tagId = _tagId,
  Map<String, dynamic>? extra,
}) => {
  'id': generateDeterministicUuid('experiment:$tagId'),
  'tag_id': tagId,
  'purpose': null,
  'start_date': '2026-10-05',
  'end_date': '2026-11-03',
  'weekday_target_min': 60,
  'weekend_target_min': 90,
  'check_in_every_days': 1,
  'status': 'running',
  'extensions_json': '[]',
  'outcome': null,
  'conclusion_note': null,
  'concluded_on': null,
  'created_at': _stamp,
  'updated_at': _stamp,
  'deleted_at': null,
  ...?extra,
};

Map<String, dynamic> _checkInPayload({
  String experimentId = _experimentId,
  String slotDate = '2026-10-05',
  String note = 'Going well',
  Map<String, dynamic>? extra,
}) => {
  'id': generateDeterministicUuid(
    'experiment-check-in:$experimentId:$slotDate',
  ),
  'experiment_id': experimentId,
  'slot_date': slotDate,
  'note': note,
  'created_at': _stamp,
  'updated_at': _stamp,
  'deleted_at': null,
  ...?extra,
};

Map<String, dynamic> _taskPayload(String id, {Map<String, dynamic>? extra}) => {
  'id': id,
  'title': id,
  'description': null,
  'start_time': null,
  'end_time': null,
  'estimated_duration_min': null,
  'actual_duration_min': null,
  'manual_duration_adjustment_min': 0,
  'category_id': null,
  'priority': 0,
  'status': 'planned',
  'notes': null,
  'recurring_rule_id': null,
  'rescheduled_from_id': null,
  'rescheduled_to_id': null,
  'is_inbox': 0,
  'missed_at': null,
  'created_at': _stamp,
  'updated_at': _stamp,
  'deleted_at': null,
  ...?extra,
};

SyncRemoteChange _change(
  String table,
  String recordId,
  Map<String, dynamic> payload, {
  int changeId = 1,
  int serverVersion = 5,
  String operation = 'update',
}) => SyncRemoteChange(
  changeId: changeId,
  operationId:
      '00000000-0000-4000-8000-${changeId.toString().padLeft(12, '0')}',
  tableName: table,
  recordId: recordId,
  operation: operation,
  serverVersion: serverVersion,
  serverTimestamp: DateTime.utc(2026, 10, 9, 10),
  payload: payload,
);

SyncRemoteChange _experimentChange(Map<String, dynamic> payload) =>
    _change('experiments', payload['id'] as String, payload);

SyncRemoteChange _checkInChange(Map<String, dynamic> payload) =>
    _change('experiment_check_ins', payload['id'] as String, payload);

Object? _rawChange(SyncRemoteChange change) => {
  'change_id': change.changeId,
  'operation_id': change.operationId,
  'table_name': change.tableName,
  'record_id': change.recordId,
  'operation': change.operation,
  'server_version': change.serverVersion,
  'server_timestamp': change.serverTimestamp.toIso8601String(),
  'payload': change.payload,
};

void main() {
  setupSqliteForTests();

  group('deterministic ids', () {
    test('match the values the server migration is tested with', () {
      expect(generateDeterministicUuid('experiment:$_tagId'), _experimentId);
      expect(
        generateDeterministicUuid(
          'experiment-check-in:$_experimentId:2026-10-05',
        ),
        _checkInId,
      );
    });
  });

  group('validator', () {
    void accepts(SyncRemoteChange change) =>
        expect(() => SyncPayloadValidator.validate(change), returnsNormally);

    void rejects(SyncRemoteChange change, [Pattern? message]) => expect(
      () => SyncPayloadValidator.validate(change),
      throwsA(
        isA<SyncValidationException>().having(
          (error) => error.message,
          'message',
          message ?? isNotEmpty,
        ),
      ),
    );

    test('accepts valid rows of both tables', () {
      accepts(_experimentChange(_experimentPayload()));
      accepts(_checkInChange(_checkInPayload()));
      accepts(
        _experimentChange(
          _experimentPayload(
            extra: {
              'purpose': 'Find out',
              'status': 'concluded',
              'outcome': 'continue_habit',
              'conclusion_note': 'Liked it',
              'concluded_on': '2026-11-10',
              'end_date': '2026-11-10',
              'extensions_json': jsonEncode([
                {
                  'reason': 'Travelled',
                  'previous_end_date': '2026-11-03',
                  'new_end_date': '2026-11-10',
                  'made_on': '2026-11-03',
                },
              ]),
            },
          ),
        ),
      );
    });

    test('accepts a tombstone of either table by identity only', () {
      accepts(
        _change('experiments', _experimentId, {
          'id': _experimentId,
          'deleted_at': _stamp,
        }, operation: 'delete'),
      );
    });

    test('accepts a tasks row with a tag, an explicit null, or no key', () {
      accepts(
        _change('tasks', 't1', _taskPayload('t1', extra: {'tag_id': _tagId})),
      );
      accepts(
        _change('tasks', 't1', _taskPayload('t1', extra: {'tag_id': null})),
      );
      accepts(_change('tasks', 't1', _taskPayload('t1')));
      rejects(_change('tasks', 't1', _taskPayload('t1', extra: {'tag_id': 7})));
    });

    test('rejects a wrong deterministic id', () {
      rejects(
        _change(
          'experiments',
          '00000000-0000-4000-8000-000000000001',
          _experimentPayload(
            extra: {'id': '00000000-0000-4000-8000-000000000001'},
          ),
        ),
        'Experiment ID does not match its tag',
      );
      rejects(
        _change(
          'experiment_check_ins',
          '00000000-0000-4000-8000-000000000002',
          _checkInPayload(
            extra: {'id': '00000000-0000-4000-8000-000000000002'},
          ),
        ),
      );
      // A check-in id built for another slot date does not match.
      rejects(
        _checkInChange(
          _checkInPayload(
            extra: {'id': _checkInPayload(slotDate: '2026-10-06')['id']},
          ),
        ),
      );
    });

    test('rejects a bad frequency, target, date order or status', () {
      rejects(
        _experimentChange(
          _experimentPayload(extra: {'check_in_every_days': 2}),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(extra: {'weekday_target_min': 10000}),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(extra: {'weekend_target_min': -1}),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(
            extra: {'start_date': '2026-10-05', 'end_date': '2026-10-04'},
          ),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(extra: {'start_date': '2026-02-30'}),
        ),
      );
      rejects(
        _experimentChange(_experimentPayload(extra: {'status': 'paused'})),
      );
    });

    test('rejects an incoherent outcome, note or conclusion date', () {
      rejects(
        _experimentChange(_experimentPayload(extra: {'outcome': 'drop'})),
      );
      rejects(
        _experimentChange(
          _experimentPayload(extra: {'conclusion_note': 'Too early'}),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(
            extra: {'status': 'concluded', 'concluded_on': '2026-11-03'},
          ),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(extra: {'status': 'concluded', 'outcome': 'drop'}),
        ),
      );
      rejects(
        _experimentChange(
          _experimentPayload(
            extra: {
              'status': 'concluded',
              'outcome': 'maybe',
              'concluded_on': '2026-11-03',
            },
          ),
        ),
      );
    });

    test('rejects a bad extensions entry', () {
      String extensions(List<Object?> items) => jsonEncode(items);
      final good = {
        'reason': 'Travelled',
        'previous_end_date': '2026-11-03',
        'new_end_date': '2026-11-10',
        'made_on': '2026-11-03',
      };
      void expectRejected(Object? value) => rejects(
        _experimentChange(
          _experimentPayload(extra: {'extensions_json': value}),
        ),
      );
      expectRejected('not json');
      expectRejected('{}');
      expectRejected(5);
      expectRejected(extensions(['text']));
      expectRejected(
        extensions([
          {...good}..remove('made_on'),
        ]),
      );
      expectRejected(
        extensions([
          {...good, 'extra': 'key'},
        ]),
      );
      expectRejected(
        extensions([
          {...good, 'reason': '   '},
        ]),
      );
      expectRejected(
        extensions([
          {...good, 'reason': 'x' * 501},
        ]),
      );
      expectRejected(
        extensions([
          {...good, 'new_end_date': '2026-11-03'},
        ]),
      );
      expectRejected(
        extensions([
          {...good, 'made_on': '2026-13-01'},
        ]),
      );
      accepts(
        _experimentChange(
          _experimentPayload(
            extra: {
              'extensions_json': extensions([
                {...good, 'reason': 'x' * 500},
              ]),
            },
          ),
        ),
      );
    });

    test('bounds purpose and conclusion note in code points', () {
      accepts(
        _experimentChange(_experimentPayload(extra: {'purpose': '🙂' * 1000})),
      );
      rejects(
        _experimentChange(_experimentPayload(extra: {'purpose': '🙂' * 1001})),
      );
      rejects(
        _experimentChange(
          _experimentPayload(
            extra: {
              'status': 'concluded',
              'outcome': 'drop',
              'concluded_on': '2026-11-03',
              'conclusion_note': 'x' * 4001,
            },
          ),
        ),
      );
    });

    test('rejects an empty or blank note and a missing timestamp', () {
      rejects(_checkInChange(_checkInPayload(note: '')));
      rejects(_checkInChange(_checkInPayload(note: '   \n')));
      rejects(_checkInChange(_checkInPayload(extra: {'created_at': null})));
      rejects(
        _experimentChange(_experimentPayload(extra: {'updated_at': null})),
      );
    });

    test('a note of 4000 emoji code points passes and 4001 does not', () {
      final ok = '🙂' * 4000;
      expect(ok.length, 8000, reason: 'UTF-16 code units');
      expect(ok.runes.length, 4000);
      accepts(_checkInChange(_checkInPayload(note: ok)));
      rejects(_checkInChange(_checkInPayload(note: '🙂' * 4001)));
    });
  });

  group('database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> insertLocalTag([
      String id = _tagId,
      String name = 'Learn C',
    ]) => db.tagDao.insertTag(
      TagsCompanion.insert(
        id: id,
        name: name,
        createdAt: DateTime.utc(2026, 10, 9),
        updatedAt: DateTime.utc(2026, 10, 9),
        syncStatus: const Value(1),
      ),
    );

    Future<void> applyRemote(SyncRemoteChange change) => db.syncDao
        .runWithoutOutbound(() => SyncRemoteApplier(db).apply(change));

    Future<Task> insertLocalTask(String id, {String? tagId}) =>
        TaskRepository(db).insertTask(
          Task(
            id: id,
            title: id,
            tagId: tagId,
            createdAt: DateTime.utc(2026, 10, 9),
            updatedAt: DateTime.utc(2026, 10, 9),
          ),
        );

    group('task repository', () {
      test('stores and reads the tag', () async {
        await insertLocalTag();
        await insertLocalTask('t1', tagId: _tagId);

        expect((await db.taskDao.getTaskById('t1'))!.tagId, _tagId);
        final repository = TaskRepository(db);
        final loaded = TaskRepository.fromRow(
          (await db.taskDao.getTaskById('t1'))!,
        );
        expect(loaded.tagId, _tagId);
        await repository.updateTask(loaded.copyWith(tagId: null));
        expect((await db.taskDao.getTaskById('t1'))!.tagId, isNull);
      });

      test('refuses a tag that does not exist', () async {
        await expectLater(
          insertLocalTask('t1', tagId: 'missing-tag'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Tag missing-tag not found',
            ),
          ),
        );
        expect(await db.taskDao.getTaskById('t1'), isNull);

        final task = await insertLocalTask('t2');
        await expectLater(
          TaskRepository(db).updateTask(task.copyWith(tagId: 'missing-tag')),
          throwsA(isA<StateError>()),
        );
        expect((await db.taskDao.getTaskById('t2'))!.tagId, isNull);
      });
    });

    group('remote apply', () {
      test('inserts an experiment and a check-in', () async {
        await insertLocalTag();
        await applyRemote(_experimentChange(_experimentPayload()));
        await applyRemote(_checkInChange(_checkInPayload()));

        final experiment = await db.experimentDao.getExperimentById(
          _experimentId,
        );
        expect(experiment, isNotNull);
        expect(experiment!.tagId, _tagId);
        expect(experiment.startDate, '2026-10-05');
        expect(experiment.endDate, '2026-11-03');
        expect(experiment.weekdayTargetMin, 60);
        expect(experiment.weekendTargetMin, 90);
        expect(experiment.checkInEveryDays, 1);
        expect(experiment.status, 'running');
        expect(experiment.extensionsJson, '[]');
        expect(experiment.serverVersion, 5);
        expect(experiment.syncStatus, 0);
        final checkIns = await db.experimentDao.getCheckInsForExperiment(
          _experimentId,
        );
        expect(checkIns.single.id, _checkInId);
        expect(checkIns.single.note, 'Going well');
        expect(checkIns.single.slotDate, '2026-10-05');
        // Remote apply must not echo into the outbox.
        expect(
          (await db.select(db.syncLog).get()).where(
            (row) => _experimentTables.contains(row.entityTableName),
          ),
          isEmpty,
        );
      });

      test('a later experiment snapshot updates the row in place', () async {
        await insertLocalTag();
        await applyRemote(_experimentChange(_experimentPayload()));
        await applyRemote(
          _change(
            'experiments',
            _experimentId,
            _experimentPayload(
              extra: {
                'end_date': '2026-11-10',
                'extensions_json': jsonEncode([
                  {
                    'reason': 'Travelled',
                    'previous_end_date': '2026-11-03',
                    'new_end_date': '2026-11-10',
                    'made_on': '2026-11-03',
                  },
                ]),
              },
            ),
            serverVersion: 6,
          ),
        );

        final experiment = (await db.experimentDao.getExperimentById(
          _experimentId,
        ))!;
        expect(experiment.endDate, '2026-11-10');
        expect(experiment.serverVersion, 6);
        expect(jsonDecode(experiment.extensionsJson), hasLength(1));
      });

      test('a tasks payload without tag_id keeps the local tag', () async {
        await insertLocalTag();
        await insertLocalTask('t1', tagId: _tagId);

        await applyRemote(
          _change(
            'tasks',
            't1',
            _taskPayload('t1', extra: {'title': 'Remote title'}),
          ),
        );

        final row = (await db.taskDao.getTaskById('t1'))!;
        expect(row.title, 'Remote title');
        expect(row.tagId, _tagId);
      });

      test('a tasks payload with an explicit null clears the tag', () async {
        await insertLocalTag();
        await insertLocalTask('t1', tagId: _tagId);

        await applyRemote(
          _change(
            'tasks',
            't1',
            _taskPayload('t1', extra: {'title': 'Cleared', 'tag_id': null}),
          ),
        );

        final row = (await db.taskDao.getTaskById('t1'))!;
        expect(row.title, 'Cleared');
        expect(row.tagId, isNull);
      });

      test('a tasks payload with a tag sets it', () async {
        await insertLocalTag();
        await insertLocalTask('t1');

        await applyRemote(
          _change('tasks', 't1', _taskPayload('t1', extra: {'tag_id': _tagId})),
        );

        expect((await db.taskDao.getTaskById('t1'))!.tagId, _tagId);
      });

      test('a complete delete snapshot without tag_id keeps the tag', () async {
        await insertLocalTag();
        await insertLocalTask('t1', tagId: _tagId);

        await applyRemote(
          _change(
            'tasks',
            't1',
            _taskPayload('t1', extra: {'deleted_at': _stamp}),
            operation: 'delete',
          ),
        );

        final row = (await db.taskDao.getTaskById('t1'))!;
        expect(row.deletedAt, isNotNull);
        expect(row.tagId, _tagId);
      });
    });

    test('semantic equality compares extensions_json structurally', () {
      final local = _experimentPayload(
        extra: {'extensions_json': '[{"a":1,"b":2}]'},
      );
      final remote = _experimentPayload(
        extra: {'extensions_json': '[ {"b":2, "a":1} ]'},
      );
      expect(semanticallyEqualSnapshots('experiments', local, remote), isTrue);
      expect(
        semanticallyEqualSnapshots('experiments', local, {
          ...remote,
          'extensions_json': '[{"a":1,"b":3}]',
        }),
        isFalse,
      );
    });

    test('a missing tag_id is not treated as equal to a set one', () {
      final local = _taskPayload('t1', extra: {'tag_id': _tagId});
      final remote = _taskPayload('t1');
      expect(semanticallyEqualSnapshots('tasks', local, remote), isFalse);
      expect(
        semanticallyEqualSnapshots('tasks', {...local, 'tag_id': null}, remote),
        isTrue,
      );
    });

    group('push', () {
      Future<void> insertLocalExperiment(String tagId) async {
        final now = DateTime.utc(2026, 10, 9);
        await db.experimentDao.insertExperiment(
          ExperimentsCompanion.insert(
            id: generateDeterministicUuid('experiment:$tagId'),
            tagId: tagId,
            startDate: '2026-10-05',
            endDate: '2026-11-03',
            weekdayTargetMin: 60,
            weekendTargetMin: 90,
            checkInEveryDays: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      Future<void> insertLocalCheckIn(String experimentId) async {
        final now = DateTime.utc(2026, 10, 9);
        await db.experimentDao.insertCheckIn(
          ExperimentCheckInsCompanion.insert(
            id: generateDeterministicUuid(
              'experiment-check-in:$experimentId:2026-10-05',
            ),
            experimentId: experimentId,
            slotDate: '2026-10-05',
            note: 'Going well',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      test(
        'sends a tag before its experiment, check-in and tagged task',
        () async {
          await insertLocalTag();
          await insertLocalExperiment(_tagId);
          await insertLocalCheckIn(_experimentId);
          await insertLocalTask('t1', tagId: _tagId);
          // Reverse the outbox so the dependency order, not insertion order,
          // has to put the parents first.
          await db.customStatement('UPDATE sync_log SET seq = 1000 - seq');

          final gateway = _Gateway();
          final failure = await SyncRepository.withGateway(
            db,
            gateway,
            'account',
          ).push();

          expect(failure, isNull);
          final sent = gateway.sent
              .map((entry) => '${entry.table}/${entry.operation}')
              .toList();
          int at(String entry) => sent.indexOf(entry);
          expect(sent, hasLength(4), reason: '$sent');
          expect(at('tags/insert'), lessThan(at('experiments/insert')));
          expect(
            at('experiments/insert'),
            lessThan(at('experiment_check_ins/insert')),
          );
          expect(at('tags/insert'), lessThan(at('tasks/insert')));
          expect(await db.syncDao.pendingCount(), 0);
          // The tasks payload carries the tag.
          final taskCall = gateway.sent.firstWhere(
            (entry) => entry.table == 'tasks',
          );
          expect(taskCall.payload['tag_id'], _tagId);
        },
      );

      test('an unmigrated server leaves experiment operations queued while '
          'other tables sync', () async {
        const otherTagId = '22222222-2222-4222-8222-222222222222';
        await insertLocalTag();
        await insertLocalTag(otherTagId, 'Run');
        await insertLocalExperiment(_tagId);
        await insertLocalExperiment(otherTagId);
        await insertLocalCheckIn(_experimentId);
        await CategoryRepository(db).insertCategory(
          Category(
            id: 'cat-1',
            name: 'Work',
            colorHex: '#4285F4',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        final gateway = _Gateway()..unsupportedTables.addAll(_experimentTables);
        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();

        // Pending work, not an error.
        expect(failure, isNull);
        final sent = gateway.sent.map((entry) => entry.table).toList();
        expect(sent, containsAll(<String>['categories', 'tags']));
        expect(
          sent.where(_experimentTables.contains),
          hasLength(1),
          reason: 'only the first experiment operation reaches the server',
        );
        expect(sent, isNot(contains('experiment_check_ins')));

        final log = await db.select(db.syncLog).get();
        final experimentOps = log
            .where((row) => _experimentTables.contains(row.entityTableName))
            .toList();
        expect(experimentOps, hasLength(3));
        for (final operation in experimentOps) {
          expect(operation.state, 'pending', reason: operation.recordId);
          expect(operation.attemptCount, 0, reason: operation.recordId);
          expect(operation.nextAttemptAt, isNull, reason: operation.recordId);
          expect(operation.lastError, isNull, reason: operation.recordId);
        }
        for (final operation in log.where(
          (row) => !_experimentTables.contains(row.entityTableName),
        )) {
          expect(operation.state, 'acknowledged', reason: operation.recordId);
        }
        expect(await db.syncDao.firstPermanentOperation(), isNull);

        // Once the server knows the tables the same operations go through.
        gateway.unsupportedTables.clear();
        final retry = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();
        expect(retry, isNull);
        expect(await db.syncDao.pendingCount(), 0);
      });
    });

    group('quarantine repair', () {
      Future<void> quarantine(SyncRemoteChange change) =>
          db.syncDao.recordQuarantinedChange(
            'account',
            change.changeId,
            'Rejected remote ${change.tableName}/${change.recordId}: '
                'Unsupported remote sync table: ${change.tableName}',
            rawChange: _rawChange(change),
          );

      test('re-applies retained experiment rows on the next pull', () async {
        await insertLocalTag();
        final experiment = _change(
          'experiments',
          _experimentId,
          _experimentPayload(),
          changeId: 4,
          serverVersion: 4,
          operation: 'insert',
        );
        final checkIn = _change(
          'experiment_check_ins',
          _checkInId,
          _checkInPayload(),
          changeId: 3,
          serverVersion: 3,
          operation: 'insert',
        );
        // The check-in has the lower change id but needs its parent first.
        await quarantine(checkIn);
        await quarantine(experiment);

        final failure = await SyncRepository.withGateway(
          db,
          _Gateway(),
          'account',
        ).pull();

        expect(failure, isNull);
        expect(
          (await db.experimentDao.getExperimentById(_experimentId))!
              .serverVersion,
          4,
        );
        expect(
          (await db.experimentDao.getCheckInById(_checkInId))!.serverVersion,
          3,
        );
        expect(await db.syncDao.getQuarantinedChanges('account'), isEmpty);
        expect(
          (await db.select(db.syncLog).get()).where(
            (row) => _experimentTables.contains(row.entityTableName),
          ),
          isEmpty,
        );
      });

      test(
        'leaves a record whose parent is missing, and others alone',
        () async {
          // No tag row exists, so the experiment cannot be applied.
          final experiment = _change(
            'experiments',
            _experimentId,
            _experimentPayload(),
            changeId: 4,
            serverVersion: 4,
            operation: 'insert',
          );
          await quarantine(experiment);
          // Another quarantine reason is not this repair's business.
          await db.syncDao.recordQuarantinedChange(
            'account',
            9,
            'Rejected remote categories/x: something else',
            rawChange: _rawChange(
              _change('categories', 'x', {'id': 'x'}, changeId: 9),
            ),
          );

          final failure = await SyncRepository.withGateway(
            db,
            _Gateway(),
            'account',
          ).pull();

          expect(failure, isNull);
          expect(
            await db.experimentDao.getExperimentById(_experimentId),
            isNull,
          );
          expect(
            await db.syncDao.getQuarantinedChanges('account'),
            hasLength(2),
          );
        },
      );

      test('skips a record when the local row is already newer', () async {
        await insertLocalTag();
        await applyRemoteDirect(
          db,
          _change(
            'experiments',
            _experimentId,
            _experimentPayload(extra: {'purpose': 'Newer'}),
            changeId: 8,
            serverVersion: 8,
          ),
        );
        await quarantine(
          _change(
            'experiments',
            _experimentId,
            _experimentPayload(extra: {'purpose': 'Older'}),
            changeId: 4,
            serverVersion: 4,
            operation: 'insert',
          ),
        );

        await SyncRepository.withGateway(db, _Gateway(), 'account').pull();

        expect(
          (await db.experimentDao.getExperimentById(_experimentId))!.purpose,
          'Newer',
        );
      });
    });
  });
}

Future<void> applyRemoteDirect(AppDatabase db, SyncRemoteChange change) =>
    db.syncDao.runWithoutOutbound(() => SyncRemoteApplier(db).apply(change));

const _experimentTables = {'experiments', 'experiment_check_ins'};

class _Sent {
  _Sent(this.table, this.operation, this.recordId, this.payload);

  final String table;
  final String operation;
  final String recordId;
  final Map<String, dynamic> payload;
}

/// Acknowledges every operation, except for the tables listed in
/// [unsupportedTables], which it rejects the way a server that lacks the
/// experiments migration does (SQLSTATE 22023, "Unsupported sync table").
class _Gateway implements SyncRemoteGateway {
  final sent = <_Sent>[];
  final unsupportedTables = <String>{};
  var _version = 0;

  @override
  Future<Object?> compactHistory() async => null;

  @override
  Future<Object?> getCapabilities() async => const {
    'protocol_version': 2,
    'payload_versions': [1, 2],
    'schedule_duration_projection': true,
    'inbox_content_version': true,
    'due_date': true,
    'plan_title_history': true,
    'manual_actual_source': true,
    'timer_state_machine': true,
    'day_contexts': true,
    'recurrence_removal_provenance': true,
  };

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
    String? baselineToken,
  }) async {
    sent.add(_Sent(tableName, operation, recordId, payload));
    if (unsupportedTables.contains(tableName)) {
      throw const PostgrestException(
        message: 'Unsupported sync table',
        code: '22023',
      );
    }
    _version++;
    return {
      'status': 'applied',
      'server_version': _version,
      'change_id': _version,
      'server_timestamp': '2026-10-09T10:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => const <Object>[];
}
