import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/sync_dao.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('authentication failure during push', () {
    test(
      'keeps the batch queued without parking or counting attempts',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final gateway = _ScriptedGateway()
          ..applyErrors.add(StateError('PostgrestException: JWT expired'));
        try {
          await _queueCategories(db, ['auth-a', 'auth-b', 'auth-c']);

          final failure = await SyncRepository.withGateway(
            db,
            gateway,
            'account',
          ).push();

          expect(failure?.kind, SyncFailureKind.authentication);
          // The first refusal stops the batch; no later operation is attempted.
          expect(gateway.appliedRecords, hasLength(1));
          expect(await db.syncDao.firstPermanentOperation(), isNull);
          final operations = await db.select(db.syncLog).get();
          expect(operations, hasLength(3));
          for (final operation in operations) {
            expect(operation.state, 'pending', reason: operation.recordId);
            expect(operation.nextAttemptAt, isNull, reason: operation.recordId);
            expect(operation.attemptCount, 0, reason: operation.recordId);
          }

          // After a refresh or sign-in the same operations sync unchanged.
          final retry = await SyncRepository.withGateway(
            db,
            gateway,
            'account',
          ).push();

          expect(retry, isNull);
          expect(
            gateway.appliedRecords.skip(1),
            unorderedEquals(const ['auth-a', 'auth-b', 'auth-c']),
          );
          expect(await db.syncDao.pendingCount(), 0);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'requeues operations an earlier build parked for authentication',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final gateway = _ScriptedGateway();
        try {
          await _queueCategories(db, ['parked-auth', 'parked-invalid']);
          final operations = {
            for (final row in await db.select(db.syncLog).get())
              row.recordId: row,
          };
          final now = DateTime.now().toUtc();
          await db.syncDao.markPermanentError(
            operations['parked-auth']!.operationId,
            now: now,
            error: 'Authentication expired; sign in again.',
          );
          await db.syncDao.markPermanentError(
            operations['parked-invalid']!.operationId,
            now: now,
            error: 'Sync action needs attention: invalid payload',
          );

          final failure = await SyncRepository.withGateway(
            db,
            gateway,
            'account',
          ).push();

          expect(failure, isNull);
          expect(gateway.appliedRecords, ['parked-auth']);
          final invalid = await db.syncDao.getOperation(
            operations['parked-invalid']!.operationId,
          );
          expect(invalid?.nextAttemptAt?.toUtc(), SyncDao.permanentRetryAt);
        } finally {
          await db.close();
        }
      },
    );
  });

  group('server upgrade required during push', () {
    test('keeps operations queued and syncs them once migrated', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _ScriptedGateway()
        ..capabilitiesResponse = () =>
            Map<String, dynamic>.from(_ScriptedGateway.fullCapabilities)
              ..remove('recurrence_removal_provenance');
      try {
        await _queueCategories(db, ['upgrade-a', 'upgrade-b', 'upgrade-c']);

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();

        expect(failure?.kind, SyncFailureKind.permanent);
        expect(failure?.message, contains('Server upgrade required'));
        expect(gateway.appliedRecords, isEmpty);
        // The batch stops at the first refusal instead of re-checking and
        // parking every remaining operation.
        expect(gateway.capabilityCalls, 1);
        expect(await db.syncDao.firstPermanentOperation(), isNull);
        for (final operation in await db.select(db.syncLog).get()) {
          expect(operation.state, 'pending', reason: operation.recordId);
          expect(operation.nextAttemptAt, isNull, reason: operation.recordId);
          expect(operation.attemptCount, 0, reason: operation.recordId);
        }

        // The backend is migrated; the untouched operations now sync.
        gateway.capabilitiesResponse = null;
        final retry = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();

        expect(retry, isNull);
        expect(
          gateway.appliedRecords,
          unorderedEquals(const ['upgrade-a', 'upgrade-b', 'upgrade-c']),
        );
        expect(await db.syncDao.pendingCount(), 0);
      } finally {
        await db.close();
      }
    });

    test(
      'requeues operations an earlier build parked once capabilities verify',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final gateway = _ScriptedGateway()
          ..capabilitiesResponse = () => const {'protocol_version': 1};
        try {
          await _queueCategories(db, ['parked-upgrade']);
          final operation = (await db.select(db.syncLog).get()).single;
          await db.syncDao.markPermanentError(
            operation.operationId,
            now: DateTime.now().toUtc(),
            error: 'Server upgrade required before Sync v2 changes can sync.',
          );

          // Still un-migrated: the parked operation stays parked.
          await SyncRepository.withGateway(db, gateway, 'account').push();
          expect(gateway.appliedRecords, isEmpty);
          expect(
            (await db.syncDao.getOperation(operation.operationId))
                ?.nextAttemptAt
                ?.toUtc(),
            SyncDao.permanentRetryAt,
          );

          gateway.capabilitiesResponse = null;
          final failure = await SyncRepository.withGateway(
            db,
            gateway,
            'account',
          ).push();

          expect(failure, isNull);
          expect(gateway.appliedRecords, ['parked-upgrade']);
          expect(await db.syncDao.pendingCount(), 0);
        } finally {
          await db.close();
        }
      },
    );
  });

  group('QA Phase 3: refused and repeatedly failing operations', () {
    const refusal = PostgrestException(
      message: 'permission denied for function apply_sync_operation_v2',
      code: '42501',
    );

    Future<void> makeEligible(AppDatabase db) => db.customStatement(
      "UPDATE sync_log SET next_attempt_at = NULL WHERE state = 'error' "
      "AND next_attempt_at <> '${SyncDao.permanentRetryAt.toIso8601String()}'",
    );

    test(
      'a refused record is skipped; other records sync in the same push',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final gateway = _ScriptedGateway()
          ..errorsByRecord['refused-a'] = refusal;
        try {
          await _queueCategories(db, ['refused-a']);
          await (db.update(db.categories)
                ..where((c) => c.id.equals('refused-a')))
              .write(const CategoriesCompanion(name: Value('renamed')));
          await _queueCategories(db, ['normal-b']);
          final before = await db.syncDao.getActiveOperationsForRecord(
            'categories',
            'refused-a',
          );
          expect(before, hasLength(2));

          final failure = await SyncRepository.withGateway(
            db,
            gateway,
            'account',
          ).push();

          expect(failure?.kind, SyncFailureKind.refused);
          // A's later update is held; B is sent and acknowledged.
          expect(gateway.appliedRecords, ['refused-a', 'normal-b']);
          expect(
            await db.syncDao.getActiveOperationsForRecord(
              'categories',
              'normal-b',
            ),
            isEmpty,
          );
          final after = await db.syncDao.getActiveOperationsForRecord(
            'categories',
            'refused-a',
          );
          expect(after, hasLength(2));
          expect(after.first.operationId, before.first.operationId);
          expect(after.first.payload, before.first.payload);
          expect(after.first.state, 'error');
          expect(after.first.attemptCount, 1);
          expect(
            after.first.nextAttemptAt!.isAfter(DateTime.now().toUtc()),
            isTrue,
          );
          expect(after.first.nextAttemptAt, isNot(SyncDao.permanentRetryAt));
          expect(after.last.state, 'pending');
          expect(await db.syncDao.firstPermanentOperation(), isNull);
          final local = await (db.select(
            db.categories,
          )..where((c) => c.id.equals('refused-a'))).getSingleOrNull();
          expect(local, isNotNull);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'a create refused 20 times keeps its payload and is listed from 5',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final gateway = _ScriptedGateway()
          ..errorsByRecord['refused-a'] = refusal;
        try {
          await _queueCategories(db, ['refused-a']);
          final original = (await db.select(db.syncLog).get()).single;
          final errorLengths = <int>{};
          for (var attempt = 1; attempt <= 20; attempt++) {
            await SyncRepository.withGateway(db, gateway, 'account').push();
            final row = (await db.syncDao.getOperation(original.operationId))!;
            errorLengths.add(row.lastError!.length);
            final listed = await db.syncDao.watchAttentionOperations().first;
            expect(
              listed.length,
              attempt >= 5 ? 1 : 0,
              reason: 'attempt $attempt',
            );
            await makeEligible(db);
          }
          final row = (await db.syncDao.getOperation(original.operationId))!;
          expect(row.operation, 'insert');
          expect(row.payload, original.payload);
          expect(row.attemptCount, 20);
          expect(row.state, 'error');
          expect(
            row.lastError,
            '$syncRefusedMessage [server - 42501] '
            'permission denied for function apply_sync_operation_v2',
          );
          expect(errorLengths, hasLength(1));
          expect(await db.syncDao.firstPermanentOperation(), isNull);
        } finally {
          await db.close();
        }
      },
    );

    test('20 network failures never list the row', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _ScriptedGateway()
        ..errorsByRecord['offline-a'] = Exception(
          'ClientException with SocketException: Connection reset by peer',
        );
      try {
        await _queueCategories(db, ['offline-a']);
        for (var attempt = 1; attempt <= 20; attempt++) {
          await SyncRepository.withGateway(db, gateway, 'account').push();
          await makeEligible(db);
        }
        final row = (await db.select(db.syncLog).get()).single;
        expect(row.attemptCount, 20);
        expect(await db.syncDao.watchAttentionOperations().first, isEmpty);
      } finally {
        await db.close();
      }
    });

    test('retryNow acts only on a listed row', () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _queueCategories(db, ['listed', 'parked', 'flying', 'pending']);
        final ids = {
          for (final row in await db.select(db.syncLog).get())
            row.recordId: row.operationId,
        };
        final now = DateTime.now().toUtc();
        final later = now.add(const Duration(hours: 1));
        for (var i = 0; i < 5; i++) {
          await db.syncDao.markRetryableError(
            ids['listed']!,
            now: now,
            nextAttemptAt: later,
            error: '$syncRefusedMessage [server 403 403] Forbidden',
          );
        }
        await db.syncDao.markPermanentError(
          ids['parked']!,
          now: now,
          error: 'Invalid sync data: bad [server - x] y',
        );
        await db.syncDao.markInFlight(ids['flying']!, now);
        final before = {
          for (final row in await db.select(db.syncLog).get())
            row.operationId: row,
        };

        expect(await db.syncDao.retryNow(ids['parked']!, now), isFalse);
        expect(await db.syncDao.retryNow(ids['flying']!, now), isFalse);
        expect(await db.syncDao.retryNow(ids['pending']!, now), isFalse);
        for (final key in ['parked', 'flying', 'pending']) {
          final row = await db.syncDao.getOperation(ids[key]!);
          expect(row, before[ids[key]!], reason: key);
        }

        expect(await db.syncDao.retryNow(ids['listed']!, now), isTrue);
        final listed = (await db.syncDao.getOperation(ids['listed']!))!;
        expect(listed.nextAttemptAt, isNull);
        expect(listed.attemptCount, 5);
        expect(listed.payload, before[ids['listed']!]!.payload);
      } finally {
        await db.close();
      }
    });
  });
}

Future<void> _queueCategories(AppDatabase db, List<String> ids) async {
  for (final id in ids) {
    await CategoryRepository(db).insertCategory(
      Category(
        id: id,
        name: id,
        colorHex: '#4285F4',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  }
}

class _ScriptedGateway implements SyncRemoteGateway {
  @override
  Future<Object?> compactHistory() async => null;

  /// Errors thrown by successive [applyOperation] calls; once empty, calls
  /// are acknowledged.
  final applyErrors = <Object>[];
  final appliedRecords = <String>[];

  /// Thrown by every [applyOperation] call for that record while present.
  final errorsByRecord = <String, Object>{};
  Object? Function()? capabilitiesResponse;
  var capabilityCalls = 0;
  var _version = 0;

  static const fullCapabilities = {
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
  Future<Object?> getCapabilities() async {
    capabilityCalls++;
    return capabilitiesResponse?.call() ?? fullCapabilities;
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
    appliedRecords.add(recordId);
    if (applyErrors.isNotEmpty) throw applyErrors.removeAt(0);
    final recordError = errorsByRecord[recordId];
    if (recordError != null) throw recordError;
    _version++;
    return {
      'status': 'applied',
      'server_version': _version,
      'change_id': _version,
      'server_timestamp': '2026-01-02T00:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => const <Object>[];
}
