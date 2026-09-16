import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/app_settings_table.dart';
import '../tables/sync_tables.dart';

part 'sync_dao.g.dart';

/// Local-only persistence boundary for the sync outbox, conflicts, and cursor.
@DriftAccessor(tables: [SyncLog, SyncConflicts, SyncState, AppSettings])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  static const permanentErrorPrefix = 'Permanent sync error: ';
  static final permanentRetryAt = DateTime.utc(9999, 12, 31, 23, 59, 59);

  Future<List<SyncLogRow>> getRetryableOperations(
    DateTime now, {
    int limit = 100,
  }) {
    return (select(syncLog)
          ..where(
            (row) =>
                row.state.isIn(['pending', 'error', 'in_flight']) &
                (row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerOrEqualValue(
                      now.toIso8601String(),
                    )),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.createdAt),
            (row) => OrderingTerm.asc(row.operationId),
          ])
          ..limit(limit))
        .get();
  }

  Future<SyncLogRow?> getOperation(String operationId) => (select(
    syncLog,
  )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();

  Future<List<SyncLogRow>> getActiveOperationsForRecord(
    String tableName,
    String recordId,
  ) =>
      (select(syncLog)
            ..where(
              (row) =>
                  row.entityTableName.equals(tableName) &
                  row.recordId.equals(recordId) &
                  row.state.isIn(['pending', 'error', 'in_flight', 'conflict']),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.operationId),
            ]))
          .get();

  Future<SyncConflictRow?> getConflictForRecord(
    String tableName,
    String recordId,
  ) =>
      (select(syncConflicts)
            ..where(
              (row) =>
                  row.entityTableName.equals(tableName) &
                  row.recordId.equals(recordId),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> markInFlight(String operationId, DateTime now) async {
    await (update(
      syncLog,
    )..where((row) => row.operationId.equals(operationId))).write(
      SyncLogCompanion(
        state: const Value('in_flight'),
        attemptCount: const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markAcknowledged(String operationId, DateTime now) async {
    await (update(
      syncLog,
    )..where((row) => row.operationId.equals(operationId))).write(
      SyncLogCompanion(
        state: const Value('acknowledged'),
        nextAttemptAt: const Value(null),
        lastError: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Returns an operation to the durable queue when its account scope is
  /// closed before the network request can be acknowledged. This is distinct
  /// from a transport failure: no retry count or error should be recorded for
  /// a request that was deliberately abandoned during account switching.
  Future<void> releaseInFlight(String operationId, DateTime now) async {
    await (update(syncLog)..where(
          (row) =>
              row.operationId.equals(operationId) &
              row.state.equals('in_flight'),
        ))
        .write(
          SyncLogCompanion(
            state: const Value('pending'),
            nextAttemptAt: const Value(null),
            lastError: const Value(null),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> markRetryableError(
    String operationId, {
    required DateTime now,
    required DateTime nextAttemptAt,
    required String error,
  }) async {
    final row = await getOperation(operationId);
    if (row == null) return;
    await (update(
      syncLog,
    )..where((entry) => entry.operationId.equals(operationId))).write(
      SyncLogCompanion(
        state: const Value('error'),
        attemptCount: Value(row.attemptCount + 1),
        nextAttemptAt: Value(nextAttemptAt),
        lastError: Value(error),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markConflict(String operationId, DateTime now) async {
    await (update(
      syncLog,
    )..where((row) => row.operationId.equals(operationId))).write(
      SyncLogCompanion(
        state: const Value('conflict'),
        nextAttemptAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markPermanentError(
    String operationId, {
    required DateTime now,
    required String error,
  }) async {
    await (update(
      syncLog,
    )..where((row) => row.operationId.equals(operationId))).write(
      SyncLogCompanion(
        // Schema v7 has no separate terminal state. Keep the existing error
        // state but move it beyond any practical retry window and prefix the
        // diagnostic so the engine can expose an actionable permanent state.
        state: const Value('error'),
        nextAttemptAt: Value(permanentRetryAt),
        lastError: Value('$permanentErrorPrefix$error'),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> rebasePendingOperations(
    String tableName,
    String recordId,
    int serverVersion,
    DateTime now,
  ) async {
    await (update(syncLog)..where(
          (row) =>
              row.entityTableName.equals(tableName) &
              row.recordId.equals(recordId) &
              row.state.isIn(['pending', 'error']),
        ))
        .write(
          SyncLogCompanion(
            expectedServerVersion: Value(serverVersion),
            updatedAt: Value(now),
          ),
        );
  }

  Future<int> pendingCount() async {
    final count = syncLog.operationId.count();
    final row =
        await (selectOnly(syncLog)
              ..addColumns([count])
              ..where(syncLog.state.isIn(['pending', 'error', 'in_flight'])))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<SyncLogRow?> firstPermanentOperation() =>
      (select(syncLog)
            ..where(
              (row) =>
                  row.state.equals('error') &
                  row.nextAttemptAt.equals(permanentRetryAt.toIso8601String()) &
                  row.lastError.like('$permanentErrorPrefix%'),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.operationId),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<List<SyncLogRow>> getPermanentOperationsMatching(
    String tableName,
    String diagnostic, {
    int limit = 50,
  }) =>
      (select(syncLog)
            ..where(
              (row) =>
                  row.entityTableName.equals(tableName) &
                  row.state.equals('error') &
                  row.nextAttemptAt.equals(permanentRetryAt.toIso8601String()) &
                  row.lastError.like('%$diagnostic%'),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.operationId),
            ])
            ..limit(limit))
          .get();

  Future<void> retryPermanentOperation(String operationId, DateTime now) async {
    await (update(syncLog)..where(
          (row) =>
              row.operationId.equals(operationId) &
              row.state.equals('error') &
              row.nextAttemptAt.equals(permanentRetryAt.toIso8601String()),
        ))
        .write(
          SyncLogCompanion(
            state: const Value('pending'),
            nextAttemptAt: const Value(null),
            lastError: const Value(null),
            updatedAt: Value(now),
          ),
        );
  }

  Stream<List<SyncLogRow>> watchPermanentOperations() =>
      (select(syncLog)
            ..where(
              (row) =>
                  row.state.equals('error') &
                  row.nextAttemptAt.equals(permanentRetryAt.toIso8601String()) &
                  row.lastError.like('$permanentErrorPrefix%'),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.operationId),
            ]))
          .watch();

  Stream<List<SyncLogRow>> watchPendingOperations() =>
      (select(syncLog)
            ..where(
              (row) =>
                  row.state.isIn(['pending', 'error', 'in_flight', 'conflict']),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .watch();

  /// Quarantined pull payloads remain in app settings until a repair tool
  /// explicitly handles them. The DAO exposes their durable metadata to UI.
  Stream<List<AppSetting>> watchQuarantinedChanges() =>
      (select(appSettings)
            ..where((row) => row.key.like('sync.quarantine.%'))
            ..orderBy([(row) => OrderingTerm.asc(row.key)]))
          .watch();

  Future<List<AppSetting>> getQuarantinedChanges(
    String accountId, {
    int limit = 50,
  }) =>
      (select(appSettings)
            ..where((row) => row.key.like('sync.quarantine.$accountId.%'))
            ..orderBy([(row) => OrderingTerm.asc(row.key)])
            ..limit(limit))
          .get();

  Stream<List<SyncConflictRow>> watchConflicts() => (select(
    syncConflicts,
  )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).watch();

  Future<void> insertConflict(SyncConflictsCompanion conflict) =>
      into(syncConflicts).insert(conflict);

  Future<void> updateConflictRemote(
    String conflictId, {
    required String operationId,
    required String entityTableName,
    required String recordId,
    required int? expectedServerVersion,
    required int? actualServerVersion,
    required String localSnapshot,
    required String remoteSnapshot,
  }) =>
      (update(syncConflicts)..where((row) => row.id.equals(conflictId))).write(
        SyncConflictsCompanion(
          operationId: Value(operationId),
          entityTableName: Value(entityTableName),
          recordId: Value(recordId),
          expectedServerVersion: Value(expectedServerVersion),
          actualServerVersion: Value(actualServerVersion),
          localSnapshot: Value(localSnapshot),
          remoteSnapshot: Value(remoteSnapshot),
        ),
      );

  Future<SyncConflictRow?> getConflict(String conflictId) => (select(
    syncConflicts,
  )..where((row) => row.id.equals(conflictId))).getSingleOrNull();

  Future<void> enqueueOperation(SyncLogCompanion operation) =>
      into(syncLog).insert(operation);

  Future<void> deleteConflict(String conflictId) async {
    await (delete(
      syncConflicts,
    )..where((row) => row.id.equals(conflictId))).go();
  }

  Future<int> getCursor(String accountId) async {
    final row = await (select(
      syncState,
    )..where((entry) => entry.accountId.equals(accountId))).getSingleOrNull();
    return row?.lastChangeId ?? 0;
  }

  Future<void> advanceCursor(
    String accountId,
    int changeId,
    DateTime now,
  ) async {
    await into(syncState).insertOnConflictUpdate(
      SyncStateCompanion.insert(
        accountId: accountId,
        lastChangeId: Value(changeId),
        updatedAt: now,
      ),
    );
  }

  /// Runs a remote apply while the SQLite transaction suppresses the local
  /// outbox triggers. The marker is itself local-only and is removed in the
  /// same transaction, including when [action] throws.
  Future<T> runWithoutOutbound<T>(Future<T> Function() action) {
    return transaction(() async {
      await into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: 'sync.apply_mode', value: '1'),
      );
      try {
        return await action();
      } finally {
        await (delete(
          appSettings,
        )..where((setting) => setting.key.equals('sync.apply_mode'))).go();
      }
    });
  }

  Future<bool> isRemoteApplyMode() async {
    final row =
        await (select(appSettings)
              ..where((setting) => setting.key.equals('sync.apply_mode')))
            .getSingleOrNull();
    return row?.value == '1';
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) {
    return into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<void> deleteSetting(String key) async {
    await (delete(
      appSettings,
    )..where((setting) => setting.key.equals(key))).go();
  }

  Future<void> recordQuarantinedChange(
    String accountId,
    int changeId,
    String diagnostic, {
    Object? rawChange,
  }) => setSetting(
    'sync.quarantine.$accountId.$changeId',
    jsonEncode({
      'account_id': accountId,
      'change_id': changeId,
      'diagnostic': diagnostic,
      'raw_change': rawChange,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  Future<int> retirePendingOperations(String tableName, String recordId) =>
      (update(syncLog)..where(
            (row) =>
                row.entityTableName.equals(tableName) &
                row.recordId.equals(recordId) &
                row.state.isIn(['pending', 'error', 'in_flight', 'conflict']),
          ))
          .write(
            const SyncLogCompanion(
              state: Value('acknowledged'),
              nextAttemptAt: Value(null),
              lastError: Value(null),
            ),
          );

  Future<void> retireOperation(String operationId) =>
      (update(
        syncLog,
      )..where((row) => row.operationId.equals(operationId))).write(
        const SyncLogCompanion(
          state: Value('acknowledged'),
          nextAttemptAt: Value(null),
          lastError: Value(null),
        ),
      );
}
