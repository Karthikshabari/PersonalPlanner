import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/inbox/domain/inbox_history.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_semantic_equality.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

const _ideaId = '01900000-0000-7000-8000-0000000000a1';
const _sessionId = '01900000-0000-7000-8000-0000000000b1';
const _stamp = '2026-10-12T09:00:00.000Z';

final _closedJson = InboxHistory.encodeJson([
  InboxClosure(
    kind: InboxCloseKind.closed,
    at: DateTime.utc(2026, 10, 12, 9, 30),
    reason: 'Bought it elsewhere',
  ),
]);

/// A complete tasks snapshot as the server sends it. [extra] overrides or adds
/// keys; [without] removes keys (an older client or an un-migrated server).
Map<String, dynamic> _taskPayload(
  String id, {
  Map<String, dynamic>? extra,
  Iterable<String> without = const [],
}) {
  final payload = <String, dynamic>{
    'id': id,
    'title': id,
    'description': null,
    'start_time': null,
    'end_time': null,
    'estimated_duration_min': null,
    'actual_duration_min': null,
    'manual_duration_adjustment_min': 0,
    'manual_actual_set': 0,
    'category_id': null,
    'priority': 0,
    'status': 'planned',
    'notes': null,
    'recurring_rule_id': null,
    'recurrence_removal_reason': null,
    'rescheduled_from_id': null,
    'rescheduled_to_id': null,
    'is_inbox': 0,
    'inbox_content_version': 0,
    'due_date': null,
    'missed_at': null,
    'plan_title_history_json': '[]',
    'display_plan_change_id': null,
    'plan_change_reasons_json': '{}',
    'tag_id': null,
    'inbox_item_id': null,
    'inbox_history_json': '[]',
    'created_at': _stamp,
    'updated_at': _stamp,
    'deleted_at': null,
    ...?extra,
  };
  for (final key in without) {
    payload.remove(key);
  }
  return payload;
}

Map<String, dynamic> _idea({
  String history = '[]',
  Iterable<String> without = const [],
}) => _taskPayload(
  _ideaId,
  extra: {
    'description': 'Learn C',
    'is_inbox': 1,
    'inbox_content_version': 1,
    'inbox_history_json': history,
  },
  without: without,
);

Map<String, dynamic> _session({
  String? itemId = _ideaId,
  Map<String, dynamic>? extra,
  Iterable<String> without = const [],
}) => _taskPayload(
  _sessionId,
  extra: {
    'start_time': '2026-10-14T09:00:00.000Z',
    'end_time': '2026-10-14T10:00:00.000Z',
    'estimated_duration_min': 60,
    'inbox_item_id': itemId,
    ...?extra,
  },
  without: without,
);

SyncRemoteChange _change(
  String recordId,
  Map<String, dynamic> payload, {
  int changeId = 1,
  int serverVersion = 5,
  String operation = 'update',
}) => SyncRemoteChange(
  changeId: changeId,
  operationId:
      '00000000-0000-4000-8000-${changeId.toString().padLeft(12, '0')}',
  tableName: 'tasks',
  recordId: recordId,
  operation: operation,
  serverVersion: serverVersion,
  serverTimestamp: DateTime.utc(2026, 10, 12, 10),
  payload: payload,
);

Map<String, dynamic> _rawChange(
  String recordId,
  Map<String, dynamic> payload, {
  required int changeId,
  String operation = 'insert',
}) => {
  'change_id': changeId,
  'operation_id':
      '00000000-0000-4000-8000-${changeId.toString().padLeft(12, '0')}',
  'table_name': 'tasks',
  'record_id': recordId,
  'operation': operation,
  'server_version': changeId,
  'server_timestamp': '2026-10-12T10:00:00.000Z',
  'payload': payload,
};

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });
  tearDown(() => db.close());

  Future<Task> insertIdea({List<InboxClosure> history = const []}) =>
      tasks.insertTask(
        Task(
          id: _ideaId,
          title: 'Learn C',
          description: 'Learn C',
          isInbox: true,
          inboxContentVersion: 1,
          inboxHistory: history,
          createdAt: DateTime.utc(2026, 10, 12),
          updatedAt: DateTime.utc(2026, 10, 12),
        ),
      );

  Future<Task> insertSession({String id = _sessionId}) => tasks.insertTask(
    Task(
      id: id,
      title: 'Learn C',
      startTime: DateTime.utc(2026, 10, 14, 9),
      endTime: DateTime.utc(2026, 10, 14, 10),
      inboxItemId: _ideaId,
      createdAt: DateTime.utc(2026, 10, 12),
      updatedAt: DateTime.utc(2026, 10, 12),
    ),
  );

  Future<Task> insertPlainTask(String id) => tasks.insertTask(
    Task(
      id: id,
      title: id,
      startTime: DateTime.utc(2026, 10, 15, 9),
      endTime: DateTime.utc(2026, 10, 15, 10),
      createdAt: DateTime.utc(2026, 10, 12),
      updatedAt: DateTime.utc(2026, 10, 12),
    ),
  );

  Future<void> applyRemote(SyncRemoteChange change) =>
      db.syncDao.runWithoutOutbound(() => SyncRemoteApplier(db).apply(change));

  Future<List<Map<String, dynamic>>> outboxPayloads(String recordId) async {
    final rows = await db.select(db.syncLog).get();
    return [
      for (final row in rows.where((row) => row.recordId == recordId))
        jsonDecode(row.payload) as Map<String, dynamic>,
    ];
  }

  group('sync trigger', () {
    test('the trigger version is 7 and there are still 40 triggers', () async {
      expect(AppDatabase.syncTriggerVersion, 7);
      final count = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'trigger' "
            r"AND name LIKE 'sync\_%' ESCAPE '\'",
          )
          .getSingle();
      expect(count.read<int>('c'), 40);
      expect(
        await db.syncDao.getSetting('schema.sync_trigger_version'),
        '${AppDatabase.syncTriggerVersion}',
      );
    });

    test('a local session write emits both keys in the outbox JSON', () async {
      await insertIdea();
      await insertSession();

      final idea = (await outboxPayloads(_ideaId)).single;
      expect(idea.containsKey('inbox_item_id'), isTrue);
      expect(idea['inbox_item_id'], isNull);
      expect(idea['inbox_history_json'], '[]');

      final session = (await outboxPayloads(_sessionId)).single;
      expect(session['inbox_item_id'], _ideaId);
      expect(session['inbox_history_json'], '[]');
      expect(session.containsKey('inbox_history'), isFalse);
    });

    test('closing an idea queues an update that carries the history', () async {
      final idea = await insertIdea();
      await tasks.updateTask(
        idea.copyWith(
          inboxHistory: InboxHistory.close(
            const [],
            kind: InboxCloseKind.closed,
            at: DateTime.utc(2026, 10, 12, 9, 30),
            reason: 'Bought it elsewhere',
          ),
        ),
      );

      final payloads = await outboxPayloads(_ideaId);
      expect(payloads, hasLength(2));
      expect(payloads.last['inbox_history_json'], _closedJson);
    });

    test('changing only the link queues an update', () async {
      await insertIdea();
      final session = await insertSession();
      await tasks.updateTask(session.copyWith(inboxItemId: null));

      final payloads = await outboxPayloads(_sessionId);
      expect(payloads, hasLength(2));
      expect(payloads.last['inbox_item_id'], isNull);
    });
  });

  group('remote apply', () {
    test('a snapshot without the keys keeps the local values', () async {
      await insertIdea(history: InboxHistory.decodeJson(_closedJson));
      await insertSession();

      await applyRemote(
        _change(
          _ideaId,
          _idea(without: ['inbox_item_id', 'inbox_history_json'])
            ..['title'] = 'Remote title',
        ),
      );
      await applyRemote(
        _change(
          _sessionId,
          _session(without: ['inbox_item_id', 'inbox_history_json'])
            ..['title'] = 'Remote session title',
        ),
      );

      final idea = (await db.taskDao.getTaskById(_ideaId))!;
      expect(idea.title, 'Remote title');
      expect(idea.inboxHistoryJson, _closedJson);
      final session = (await db.taskDao.getTaskById(_sessionId))!;
      expect(session.title, 'Remote session title');
      expect(session.inboxItemId, _ideaId);
    });

    test('an explicit null clears the link', () async {
      await insertIdea();
      await insertSession();

      await applyRemote(_change(_sessionId, _session(itemId: null)));

      expect((await db.taskDao.getTaskById(_sessionId))!.inboxItemId, isNull);
    });

    test('an explicit value sets the link and the history', () async {
      await insertIdea();
      await insertPlainTask(_sessionId);

      await applyRemote(_change(_sessionId, _session()));
      await applyRemote(_change(_ideaId, _idea(history: _closedJson)));

      expect((await db.taskDao.getTaskById(_sessionId))!.inboxItemId, _ideaId);
      final idea = (await db.taskDao.getTaskById(_ideaId))!;
      expect(idea.inboxHistoryJson, _closedJson);
      expect(
        TaskRepository.fromRow(idea).inboxHistory.single.reason,
        'Bought it elsewhere',
      );
    });

    test('a first snapshot without the keys applies the defaults', () async {
      await applyRemote(
        _change(
          _ideaId,
          _idea(without: ['inbox_item_id', 'inbox_history_json']),
          operation: 'insert',
        ),
      );

      final idea = (await db.taskDao.getTaskById(_ideaId))!;
      expect(idea.inboxItemId, isNull);
      expect(idea.inboxHistoryJson, '[]');
    });

    test('applying a remote change does not echo into the outbox', () async {
      await insertIdea();
      await insertSession();
      final before = (await db.select(db.syncLog).get()).length;

      await applyRemote(_change(_sessionId, _session(itemId: null)));

      expect((await db.select(db.syncLog).get()).length, before);
    });
  });

  group('validation', () {
    void accepts(Map<String, dynamic> payload, [String id = _sessionId]) =>
        expect(
          () => SyncPayloadValidator.validate(_change(id, payload)),
          returnsNormally,
        );

    void rejects(
      Map<String, dynamic> payload, [
      String id = _sessionId,
      Pattern? message,
    ]) => expect(
      () => SyncPayloadValidator.validate(_change(id, payload)),
      throwsA(
        isA<SyncValidationException>().having(
          (error) => error.message,
          'message',
          message ?? isNotEmpty,
        ),
      ),
    );

    test('accepts the keys, an explicit null, and no keys at all', () {
      accepts(_session());
      accepts(_session(itemId: null));
      accepts(_session(without: ['inbox_item_id', 'inbox_history_json']));
      accepts(_idea(history: _closedJson), _ideaId);
    });

    test('is shape only: the Inbox pairing is a write-time rule', () {
      accepts(_idea()..['inbox_item_id'] = _sessionId, _ideaId);
      accepts(_session(extra: {'inbox_history_json': _closedJson}));
    });

    test('rejects a link that points at the row itself', () {
      rejects(_session(itemId: _sessionId));
    });

    test('rejects a link that is not an id', () {
      rejects(_session(extra: {'inbox_item_id': 7}));
      rejects(_session(extra: {'inbox_item_id': ''}));
    });

    test('rejects a history that is not valid history text', () {
      rejects(_session(extra: {'inbox_history_json': <String>[]}));
      rejects(_session(extra: {'inbox_history_json': null}));
      rejects(_session(extra: {'inbox_history_json': 'nope'}));
      rejects(_session(extra: {'inbox_history_json': '{}'}));
      // A closed event needs a reason.
      rejects(
        _session(
          extra: {
            'inbox_history_json':
                '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z",'
                '"reason":null,"experiment_id":null,"reopened_at":null}]',
          },
        ),
      );
    });
  });

  group('push ordering', () {
    test('a session operation is sent after its idea', () async {
      await insertIdea();
      await insertSession();
      // Reverse the outbox so the dependency, not insertion order, has to put
      // the idea first.
      await db.customStatement('UPDATE sync_log SET seq = 1000 - seq');

      final gateway = _Gateway();
      final failure = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).push();

      expect(failure, isNull);
      expect(gateway.sent.map((entry) => entry.recordId).toList(), [
        _ideaId,
        _sessionId,
      ]);
      expect(gateway.sent.last.payload['inbox_item_id'], _ideaId);
      expect(await db.syncDao.pendingCount(), 0);
    });
  });

  group('pull', () {
    test('a session and its idea in one page both apply', () async {
      final gateway = _Gateway()
        ..pullPages.add([
          _rawChange(_sessionId, _session(), changeId: 1),
          _rawChange(_ideaId, _idea(), changeId: 2),
        ]);

      final failure = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).pull();

      expect(failure, isNull);
      expect((await db.taskDao.getTaskById(_ideaId)), isNotNull);
      expect((await db.taskDao.getTaskById(_sessionId))!.inboxItemId, _ideaId);
      expect(await db.syncDao.getCursor('account'), 2);
      expect(await db.syncDao.getQuarantinedChanges('account'), isEmpty);
    });

    test('a session whose idea arrives in a later page is held, not applied or '
        'quarantined, and applies once the idea is there', () async {
      final gateway = _Gateway()
        ..pullPages.add([_rawChange(_sessionId, _session(), changeId: 1)]);
      final repository = SyncRepository.withGateway(db, gateway, 'account');

      expect(await repository.pull(), isNull);

      // Held in the pending-parent queue: the cursor moved past it.
      expect(await db.taskDao.getTaskById(_sessionId), isNull);
      expect(await db.syncDao.getQuarantinedChanges('account'), isEmpty);
      expect(await db.syncDao.getCursor('account'), 1);
      expect(
        await db.syncDao.readSettingsWithPrefix('sync.pending_parent.account.'),
        hasLength(1),
      );

      gateway.pullPages.add([_rawChange(_ideaId, _idea(), changeId: 2)]);
      expect(await repository.pull(), isNull);

      expect((await db.taskDao.getTaskById(_sessionId))!.inboxItemId, _ideaId);
      expect(await db.taskDao.getTaskById(_ideaId), isNotNull);
      expect(await db.syncDao.getQuarantinedChanges('account'), isEmpty);
      expect(
        await db.syncDao.readSettingsWithPrefix('sync.pending_parent.account.'),
        isEmpty,
      );
      expect(await db.syncDao.getCursor('account'), 2);
    });

    test(
      'an invalid history is quarantined and does not block the rest',
      () async {
        final gateway = _Gateway()
          ..pullPages.add([
            _rawChange(_ideaId, _idea(), changeId: 1),
            _rawChange(
              _sessionId,
              _session(extra: {'inbox_history_json': '{}'}),
              changeId: 2,
            ),
            _rawChange('plain-task', _taskPayload('plain-task'), changeId: 3),
          ]);

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(failure?.kind, SyncFailureKind.invalidData);
        expect(await db.taskDao.getTaskById(_ideaId), isNotNull);
        expect(await db.taskDao.getTaskById('plain-task'), isNotNull);
        expect(await db.taskDao.getTaskById(_sessionId), isNull);
        expect(await db.syncDao.getQuarantinedChanges('account'), hasLength(1));
        expect(await db.syncDao.getCursor('account'), 3);
      },
    );

    test(
      'a pulled snapshot from an un-migrated server keeps local values',
      () async {
        await insertIdea(history: InboxHistory.decodeJson(_closedJson));
        await db.customStatement('DELETE FROM sync_log');
        final gateway = _Gateway()
          ..pullPages.add([
            _rawChange(
              _ideaId,
              _idea(without: ['inbox_item_id', 'inbox_history_json'])
                ..['title'] = 'Edited elsewhere',
              changeId: 1,
              operation: 'update',
            ),
          ]);

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(failure, isNull);
        final idea = (await db.taskDao.getTaskById(_ideaId))!;
        expect(idea.title, 'Edited elsewhere');
        expect(idea.inboxHistoryJson, _closedJson);
      },
    );
  });

  group('capability hold (C15)', () {
    Future<List<SyncLogRow>> log() => db.select(db.syncLog).get();

    SyncLogRow forRecord(List<SyncLogRow> rows, String id) =>
        rows.singleWhere((row) => row.recordId == id);

    test('holds Inbox operations on a server without inbox_sessions while a '
        'plain task and a default idea are sent', () async {
      await insertIdea();
      await insertSession();
      await insertPlainTask('plain-task');

      final gateway = _Gateway(inboxSessions: false);
      final failure = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).push();

      // Pending work, not an error.
      expect(failure, isNull);
      expect(gateway.sent.map((entry) => entry.recordId).toSet(), {
        _ideaId,
        'plain-task',
      });
      final rows = await log();
      final held = forRecord(rows, _sessionId);
      expect(held.state, 'pending');
      expect(held.attemptCount, 0);
      expect(held.nextAttemptAt, isNull);
      expect(held.lastError, isNull);
      expect(forRecord(rows, _ideaId).state, 'acknowledged');
      expect(forRecord(rows, 'plain-task').state, 'acknowledged');
      expect(await db.syncDao.firstPermanentOperation(), isNull);
      expect(await db.syncDao.pendingCount(), 1);
    });

    test('holds a closed idea but not a default one', () async {
      final idea = await insertIdea();
      final gateway = _Gateway(inboxSessions: false);
      final repository = SyncRepository.withGateway(db, gateway, 'account');
      expect(await repository.push(), isNull);
      expect(forRecord(await log(), _ideaId).state, 'acknowledged');

      await tasks.updateTask(
        idea.copyWith(inboxHistory: InboxHistory.decodeJson(_closedJson)),
      );
      gateway.sent.clear();
      expect(await repository.push(), isNull);

      expect(gateway.sent, isEmpty);
      final pending = (await log()).where((row) => row.state == 'pending');
      expect(pending, hasLength(1));
      expect(pending.single.attemptCount, 0);
    });

    test('the next cycle sends held operations once the capability appears, '
        'without a new repository', () async {
      await insertIdea();
      await insertSession();
      final gateway = _Gateway(inboxSessions: false);
      final repository = SyncRepository.withGateway(db, gateway, 'account');

      expect(await repository.push(), isNull);
      expect(gateway.sent.map((entry) => entry.recordId), [_ideaId]);
      expect(await db.syncDao.pendingCount(), 1);
      // One v2 capability check and one probe for the Inbox keys, however
      // many operations were held.
      expect(gateway.capabilityReads, 2);

      gateway.inboxSessions = true;
      expect(await repository.push(), isNull);

      expect(gateway.sent.map((entry) => entry.recordId), [
        _ideaId,
        _sessionId,
      ]);
      expect(gateway.sent.last.payload['inbox_item_id'], _ideaId);
      expect(await db.syncDao.pendingCount(), 0);
      expect(gateway.capabilityReads, 3);

      // Once seen, the capability is not read again.
      await tasks.updateTask(
        (await tasks.getTaskById(_sessionId))!.copyWith(title: 'Renamed'),
      );
      expect(await repository.push(), isNull);
      expect(gateway.capabilityReads, 3);
    });

    test('a held operation keeps its operation id', () async {
      await insertIdea();
      await insertSession();
      final before = forRecord(await log(), _sessionId).operationId;
      final gateway = _Gateway(inboxSessions: false);
      final repository = SyncRepository.withGateway(db, gateway, 'account');
      await repository.push();
      gateway.inboxSessions = true;
      await repository.push();

      final sentSession = gateway.sent.singleWhere(
        (entry) => entry.recordId == _sessionId,
      );
      expect(sentSession.operationId, before);
    });

    test('an unreadable capability response holds without counting an '
        'attempt', () async {
      await insertIdea();
      final session = await insertSession();
      await db.customStatement(
        "DELETE FROM sync_log WHERE record_id = '$_ideaId'",
      );
      final gateway = _Gateway(inboxSessions: false)
        ..capabilitiesError = StateError('network down');

      final failure = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).push();

      expect(failure, isNull);
      expect(gateway.sent, isEmpty);
      final row = forRecord(await log(), session.id);
      expect(row.state, 'pending');
      expect(row.attemptCount, 0);
    });

    test('a server that advertises inbox_sessions never holds', () async {
      await insertIdea();
      await insertSession();
      final gateway = _Gateway();

      expect(
        await SyncRepository.withGateway(db, gateway, 'account').push(),
        isNull,
      );

      expect(gateway.sent, hasLength(2));
      expect(await db.syncDao.pendingCount(), 0);
    });
  });

  group('semantic equality', () {
    test('re-encoded identical history is equal', () {
      final reordered = jsonEncode([
        {
          'reopened_at': null,
          'experiment_id': null,
          'reason': 'Bought it elsewhere',
          'at': '2026-10-12T09:30:00.000Z',
          'kind': 'closed',
        },
      ]);
      expect(
        semanticallyEqualSnapshots(
          'tasks',
          {'id': 't', 'inbox_history_json': _closedJson},
          {'id': 't', 'inbox_history_json': reordered},
        ),
        isTrue,
      );
    });

    test('different history is not equal', () {
      expect(
        semanticallyEqualSnapshots(
          'tasks',
          {'id': 't', 'inbox_history_json': _closedJson},
          {'id': 't', 'inbox_history_json': '[]'},
        ),
        isFalse,
      );
    });

    test('a snapshot from an un-migrated server (no key) equals the default '
        'history', () {
      expect(
        semanticallyEqualSnapshots(
          'tasks',
          {'id': 't', 'inbox_item_id': null, 'inbox_history_json': '[]'},
          {'id': 't'},
        ),
        isTrue,
      );
    });

    test('a link and no link are not equal', () {
      expect(
        semanticallyEqualSnapshots(
          'tasks',
          {'id': 't', 'inbox_item_id': _ideaId},
          {'id': 't', 'inbox_item_id': null},
        ),
        isFalse,
      );
      expect(
        semanticallyEqualSnapshots(
          'tasks',
          {'id': 't', 'inbox_item_id': _ideaId},
          {'id': 't', 'inbox_item_id': _ideaId},
        ),
        isTrue,
      );
    });
  });

  group('permanent repair', () {
    test(
      'a repaired idea is requeued with the history in sync shape',
      () async {
        await insertIdea(history: InboxHistory.decodeJson(_closedJson));
        final failed = (await db.syncDao.getRetryableOperations(
          DateTime.utc(2027),
        )).single;
        await db.syncDao.markPermanentError(
          failed.operationId,
          now: DateTime.utc(2026, 10, 12),
          error: 'invalid payload',
        );
        await db.syncDao.runWithoutOutbound(() async {
          await db.customStatement(
            "UPDATE tasks SET title = 'Repaired', revision = 2 "
            "WHERE id = '$_ideaId'",
          );
        });

        await SyncRepository.withGateway(
          db,
          _Gateway(),
          'account',
        ).repairPermanentOperation(failed.operationId);

        final active = await db.syncDao.getActiveOperationsForRecord(
          'tasks',
          _ideaId,
        );
        expect(active, hasLength(1));
        final payload =
            jsonDecode(active.single.payload) as Map<String, dynamic>;
        expect(payload['title'], 'Repaired');
        expect(payload['inbox_history_json'], _closedJson);
        expect(payload.containsKey('inbox_item_id'), isTrue);
        expect(payload.containsKey('inbox_history'), isFalse);
      },
    );
  });
}

class _Sent {
  _Sent(this.operationId, this.recordId, this.payload);

  final String operationId;
  final String recordId;
  final Map<String, dynamic> payload;
}

/// Acknowledges every operation. [inboxSessions] decides whether the
/// capability response advertises migration 13.
class _Gateway implements SyncRemoteGateway {
  _Gateway({this.inboxSessions = true});

  bool inboxSessions;
  Object? capabilitiesError;
  int capabilityReads = 0;
  final sent = <_Sent>[];
  final pullPages = <List<Object?>>[];
  var _version = 0;

  @override
  Future<Object?> compactHistory() async => null;

  @override
  Future<Object?> getCapabilities() async {
    capabilityReads++;
    final error = capabilitiesError;
    if (error != null) throw error;
    return {
      'protocol_version': 2,
      'payload_versions': const [1, 2],
      'schedule_duration_projection': true,
      'inbox_content_version': true,
      'due_date': true,
      'plan_title_history': true,
      'manual_actual_source': true,
      'timer_state_machine': true,
      'day_contexts': true,
      'recurrence_removal_provenance': true,
      if (inboxSessions) 'inbox_sessions': true,
    };
  }

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
    sent.add(_Sent(operationId, recordId, payload));
    _version++;
    return {
      'status': 'applied',
      'server_version': _version,
      'change_id': _version,
      'server_timestamp': '2026-10-12T10:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => pullPages.isEmpty ? const <Object>[] : pullPages.removeAt(0);
}
