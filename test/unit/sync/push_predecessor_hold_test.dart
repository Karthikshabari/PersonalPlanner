import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/sync_dao.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  final now = DateTime.utc(2026, 1, 1, 9);

  test(
    'a retryable insert failure holds a later update of the same record',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final server = _CasServer()
        ..failNext('held-category', StateError('network timeout'));
      try {
        final repository = CategoryRepository(db);
        await repository.insertCategory(_category('held-category', now));
        final created = (await repository.getCategoryById('held-category'))!;
        await _nextMillisecond();
        await repository.updateCategory(created.copyWith(name: 'Edited'));

        await _push(db, server);

        // Only the failed insert was attempted; the edit was not sent with a
        // version the server cannot have yet.
        expect(server.sent, ['categories/held-category/insert']);
        expect(await db.select(db.syncConflicts).get(), isEmpty);
        final update = await _operation(db, 'held-category', 'update');
        _expectUntouched(update);

        // Still backing off: the update stays held across cycles.
        await _push(db, server);
        expect(server.sent, hasLength(1));
        _expectUntouched(await _operation(db, 'held-category', 'update'));

        await _makeRetriesDue(db);
        await _push(db, server);

        expect(server.sent.skip(1), [
          'categories/held-category/insert',
          'categories/held-category/update',
        ]);
        expect(server.expectedVersions.skip(1), [null, 1]);
        expect(await db.select(db.syncConflicts).get(), isEmpty);
        expect(await db.syncDao.pendingCount(), 0);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'a retryable task insert failure holds its subtask instead of parking it',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final server = _CasServer()
        ..failNext('parent-task', StateError('network timeout'));
      try {
        await _insertTask(db, 'parent-task', now);
        await _insertSubtask(db, 'child-subtask', 'parent-task', now);

        await _push(db, server);

        expect(server.sent, ['tasks/parent-task/insert']);
        expect(await db.syncDao.firstPermanentOperation(), isNull);
        _expectUntouched(await _operation(db, 'child-subtask', 'insert'));

        await _makeRetriesDue(db);
        await _push(db, server);

        expect(server.sent.skip(1), [
          'tasks/parent-task/insert',
          'subtasks/child-subtask/insert',
        ]);
        expect(await db.syncDao.firstPermanentOperation(), isNull);
        expect(await db.syncDao.pendingCount(), 0);
      } finally {
        await db.close();
      }
    },
  );

  test('a child written while its parent backs off is held across cycles', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final server = _CasServer()
      ..failNext('backoff-task', StateError('network timeout'));
    try {
      await _insertTask(db, 'backoff-task', now);
      await _push(db, server);
      expect(server.sent, ['tasks/backoff-task/insert']);

      // The parent is not eligible yet, so it is not in the next batch at all.
      await _insertSubtask(db, 'late-subtask', 'backoff-task', now);
      await _push(db, server);

      expect(server.sent, hasLength(1));
      expect(await db.syncDao.firstPermanentOperation(), isNull);
      _expectUntouched(await _operation(db, 'late-subtask', 'insert'));

      await _makeRetriesDue(db);
      await _push(db, server);

      expect(server.sent.skip(1), [
        'tasks/backoff-task/insert',
        'subtasks/late-subtask/insert',
      ]);
      expect(await db.syncDao.pendingCount(), 0);
    } finally {
      await db.close();
    }
  });

  test(
    'a child split from its parent by the batch limit is held, not parked',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final server = _CasServer();
      try {
        for (var i = 0; i < 99; i++) {
          await CategoryRepository(db)
              .insertCategory(_category('fill-$i', now));
        }
        await _insertTask(db, 'split-task', now);
        await _insertSubtask(db, 'split-subtask', 'split-task', now);
        // Model a same-millisecond tie resolved against the parent: the child
        // sorts as operation 100 and the parent insert falls outside the batch.
        final later = DateTime.now().toUtc().add(const Duration(hours: 1));
        await _setCreatedAt(db, 'split-subtask', later);
        await _setCreatedAt(
          db,
          'split-task',
          later.add(const Duration(milliseconds: 1)),
        );

        await _push(db, server);

        // The held child does not use the batch budget, so the push pages on
        // and sends the parent; the child waits for the next push.
        expect(server.sent, hasLength(100));
        expect(server.sent.last, 'tasks/split-task/insert');
        expect(await db.syncDao.firstPermanentOperation(), isNull);
        _expectUntouched(await _operation(db, 'split-subtask', 'insert'));

        await _push(db, server);

        expect(server.sent.skip(100), ['subtasks/split-subtask/insert']);
        expect(await db.syncDao.pendingCount(), 0);
      } finally {
        await db.close();
      }
    },
  );

  test('a child behind a parked parent insert is held until the parent is repaired', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final server = _CasServer()
      ..failNext(
        'parked-task',
        Exception('PostgrestException(message: Invalid due date, code: 22023)'),
      );
    try {
      await _insertTask(db, 'parked-task', now);
      await _insertSubtask(db, 'held-subtask', 'parked-task', now);

      await _push(db, server);

      final parked = await db.syncDao.firstPermanentOperation();
      expect(parked?.recordId, 'parked-task');
      expect(server.sent, ['tasks/parked-task/insert']);
      _expectUntouched(await _operation(db, 'held-subtask', 'insert'));

      // Still parked: the child keeps waiting and is never parked itself.
      await _push(db, server);
      expect(server.sent, hasLength(1));
      _expectUntouched(await _operation(db, 'held-subtask', 'insert'));

      await db.customStatement(
        "UPDATE tasks SET title = 'Repaired' WHERE id = 'parked-task'",
      );
      await SyncRepository.withGateway(
        db,
        server,
        'account',
      ).repairPermanentOperation(parked!.operationId);
      await _push(db, server);

      expect(server.sent.skip(1), [
        'tasks/parked-task/insert',
        'subtasks/held-subtask/insert',
      ]);
      expect(await db.syncDao.firstPermanentOperation(), isNull);
      expect(await db.syncDao.pendingCount(), 0);
    } finally {
      await db.close();
    }
  });

  test(
    'an earlier conflict holds later operations on the same record',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final server = _CasServer()
        ..seed('categories', 'conflict-category', 6, {
          'id': 'conflict-category',
          'name': 'Remote',
          'color_hex': '#4285F4',
          'sort_order': 0,
          'is_focus': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'deleted_at': null,
        });
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: 'conflict-category',
                  name: 'Base',
                  colorHex: '#4285F4',
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
        });
        final repository = CategoryRepository(db);
        final base = (await repository.getCategoryById('conflict-category'))!;
        await repository.updateCategory(base.copyWith(name: 'Local 1'));
        final first = (await repository.getCategoryById(base.id))!;
        await _nextMillisecond();
        await repository.updateCategory(first.copyWith(name: 'Local 2'));

        await _push(db, server);

        expect(server.sent, ['categories/conflict-category/update']);
        final conflicts = await db.select(db.syncConflicts).get();
        expect(conflicts, hasLength(1));
        final active = await db.syncDao.getActiveOperationsForRecord(
          'categories',
          base.id,
        );
        expect(active.map((entry) => entry.state), ['conflict', 'pending']);
        _expectUntouched(active.last);

        // Resolving the conflict retires both and queues one rebased write.
        await SyncRepository.withGateway(
          db,
          server,
          'account',
        ).keepLocal(conflicts.single.id);
        await _push(db, server);

        expect(server.sent.skip(1), ['categories/conflict-category/update']);
        expect(server.expectedVersions.last, 6);
        expect(await db.select(db.syncConflicts).get(), isEmpty);
        expect(await db.syncDao.pendingCount(), 0);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'held rows filling the batch window do not stall unrelated records',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final server = _CasServer()
        ..failNext(
          'parked-category',
          Exception('PostgrestException(message: Invalid category, code: 22023)'),
        );
      try {
        await CategoryRepository(db).insertCategory(
          _category('parked-category', now),
        );
        for (var i = 0; i < 120; i++) {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: 'waiting-$i',
                  title: 'waiting-$i',
                  categoryId: const Value('parked-category'),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        await _nextMillisecond();
        await CategoryRepository(db).insertCategory(
          _category('unrelated-category', now),
        );

        await _push(db, server);

        // 120 held tasks sit ahead of the unrelated row, more than one batch.
        expect(server.sent, [
          'categories/parked-category/insert',
          'categories/unrelated-category/insert',
        ]);
        expect(
          (await _operation(db, 'unrelated-category', 'insert')).state,
          'acknowledged',
        );
        _expectUntouched(await _operation(db, 'waiting-119', 'insert'));

        // Only held rows remain: a push pages through them and sends nothing.
        await _push(db, server);
        expect(server.sent, hasLength(2));
      } finally {
        await db.close();
      }
    },
  );

  test('a failed record does not hold unrelated records', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final server = _CasServer()
      ..failNext('unrelated-b', StateError('network timeout'));
    try {
      for (final id in ['unrelated-a', 'unrelated-b', 'unrelated-c']) {
        await CategoryRepository(db).insertCategory(_category(id, now));
      }

      await _push(db, server);

      expect(server.sent, hasLength(3));
      for (final id in ['unrelated-a', 'unrelated-c']) {
        expect((await _operation(db, id, 'insert')).state, 'acknowledged');
      }
      expect((await _operation(db, 'unrelated-b', 'insert')).state, 'error');
    } finally {
      await db.close();
    }
  });
}

Category _category(String id, DateTime now) => Category(
  id: id,
  name: id,
  colorHex: '#4285F4',
  createdAt: now,
  updatedAt: now,
);

Future<void> _insertTask(AppDatabase db, String id, DateTime now) => db
    .into(db.tasks)
    .insert(
      TasksCompanion.insert(id: id, title: id, createdAt: now, updatedAt: now),
    );

Future<void> _insertSubtask(
  AppDatabase db,
  String id,
  String taskId,
  DateTime now,
) => db
    .into(db.subtasks)
    .insert(
      SubtasksCompanion.insert(
        id: id,
        taskId: taskId,
        title: id,
        createdAt: now,
        updatedAt: now,
      ),
    );

Future<void> _push(AppDatabase db, _CasServer server) =>
    SyncRepository.withGateway(db, server, 'account').push();

Future<SyncLogRow> _operation(
  AppDatabase db,
  String recordId,
  String operation,
) async =>
    (await (db.select(db.syncLog)..where(
              (row) =>
                  row.recordId.equals(recordId) &
                  row.operation.equals(operation),
            ))
            .get())
        .single;

/// Outbox triggers stamp milliseconds; same-millisecond writes to one record
/// fall back to a random operation-ID tiebreak, which these tests avoid.
Future<void> _nextMillisecond() =>
    Future<void>.delayed(const Duration(milliseconds: 3));

/// A held row is exactly as the trigger queued it.
void _expectUntouched(SyncLogRow operation) {
  expect(operation.state, 'pending', reason: operation.recordId);
  expect(operation.attemptCount, 0, reason: operation.recordId);
  expect(operation.nextAttemptAt, isNull, reason: operation.recordId);
  expect(operation.lastError, isNull, reason: operation.recordId);
}

/// Ends every ordinary backoff without touching parked rows.
Future<void> _makeRetriesDue(AppDatabase db) => db.customStatement(
  "UPDATE sync_log SET next_attempt_at = ? "
  "WHERE state = 'error' AND next_attempt_at <> ?",
  [
    DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 1))
        .toIso8601String(),
    SyncDao.permanentRetryAt.toIso8601String(),
  ],
);

Future<void> _setCreatedAt(AppDatabase db, String recordId, DateTime at) =>
    db.customStatement(
      'UPDATE sync_log SET created_at = ? WHERE record_id = ?',
      [at.toUtc().toIso8601String(), recordId],
    );

/// Applies the server's compare-and-swap and immediate foreign-key rules, so
/// sending an operation ahead of its predecessor produces the same conflict or
/// rejection the real RPC would.
class _CasServer implements SyncRemoteGateway {
  final sent = <String>[];
  final expectedVersions = <int?>[];
  final _failures = <String, List<Object>>{};
  final _versions = <String, int>{};
  final _snapshots = <String, Map<String, dynamic>>{};
  final _acknowledged = <String, Map<String, dynamic>>{};
  var _nextVersion = 1;

  static const _capabilities = {
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

  void failNext(String recordId, Object error) =>
      (_failures[recordId] ??= []).add(error);

  void seed(
    String table,
    String recordId,
    int version,
    Map<String, dynamic> snapshot,
  ) {
    _versions['$table/$recordId'] = version;
    _snapshots['$table/$recordId'] = snapshot;
    if (version >= _nextVersion) _nextVersion = version + 1;
  }

  @override
  Future<Object?> getCapabilities() async => _capabilities;

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
    sent.add('$tableName/$recordId/$operation');
    expectedVersions.add(expectedServerVersion);
    final failures = _failures[recordId];
    if (failures != null && failures.isNotEmpty) throw failures.removeAt(0);
    final replay = _acknowledged[operationId];
    if (replay != null) return {...replay, 'status': 'acknowledged'};

    final key = '$tableName/$recordId';
    final current = _versions[key];
    if (operation != 'delete' &&
        const {'subtasks', 'timer_sessions', 'task_tags'}.contains(tableName) &&
        _versions['tasks/${payload['task_id']}'] == null) {
      throw Exception(
        'PostgrestException(message: insert or update on table "$tableName" '
        'violates foreign key constraint, code: 23503)',
      );
    }
    if ((operation == 'insert' && current != null) ||
        (operation != 'insert' && current == null) ||
        expectedServerVersion != current) {
      return {
        'status': 'conflict',
        'server_version': 0,
        'change_id': 0,
        'actual_server_version': current,
        'remote_snapshot': _snapshots[key] ?? {'deleted': true},
      };
    }
    final version = _nextVersion++;
    _versions[key] = version;
    _snapshots[key] = payload;
    final response = {
      'status': 'applied',
      'server_version': version,
      'change_id': version,
      'server_timestamp': '2026-01-02T00:00:00.000Z',
    };
    _acknowledged[operationId] = response;
    return response;
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => const <Object>[];
}
