import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/sync_dao.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';

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
  /// Errors thrown by successive [applyOperation] calls; once empty, calls
  /// are acknowledged.
  final applyErrors = <Object>[];
  final appliedRecords = <String>[];
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
