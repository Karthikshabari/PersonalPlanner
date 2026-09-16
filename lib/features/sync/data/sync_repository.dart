import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/plan_title_change.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../../core/utils/uuid.dart';
import '../../settings/data/backup_codec.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import '../../task_editor/domain/plan_title_history.dart';
import 'remote_apply.dart';
import '../domain/sync_models.dart';
import '../domain/sync_validation.dart';

/// The remote boundary for one authenticated account. The UI never calls the
/// Supabase client directly; this repository talks only to the two committed
/// RPCs and applies their results to SQLite.
class SyncRepository {
  SyncRepository(
    this._db,
    SupabaseClient client,
    this._accountId, {
    this._currentAccountId,
  }) : _gateway = SupabaseSyncRemoteGateway(client),
       _applier = SyncRemoteApplier(_db);

  SyncRepository.withGateway(
    this._db,
    this._gateway,
    this._accountId, {
    this._currentAccountId,
  }) : _applier = SyncRemoteApplier(_db);

  final AppDatabase _db;
  final SyncRemoteGateway _gateway;
  final String _accountId;
  final String? Function()? _currentAccountId;
  final SyncRemoteApplier _applier;
  bool _cycleRunning = false;
  bool _v2CapabilityVerified = false;
  static const _legacyTitleHistoryTransitionDiagnostic =
      'Existing plan title events cannot be removed or changed';

  void _assertAccountScope() {
    final current = _currentAccountId?.call();
    if (_currentAccountId != null && current != _accountId) {
      throw const _SyncAccountScopeChanged();
    }
  }

  static const _scopeFailure = SyncFailure(
    SyncFailureKind.authentication,
    'Account changed; synchronization was stopped safely.',
  );

  Future<SyncCycleResult> sync() async {
    if (_cycleRunning) return const SyncCycleResult();
    _cycleRunning = true;
    try {
      final pushFailure = await push();
      final pullFailure = await pull();
      return SyncCycleResult(
        pushFailure: pushFailure,
        pullFailure: pullFailure,
      );
    } finally {
      _cycleRunning = false;
    }
  }

  Future<SyncFailure?> push() async {
    late final List<SyncLogRow> operations;
    try {
      _assertAccountScope();
      await _repairTitleHistoryPermanentOperations();
      operations = _orderOperations(
        await _db.syncDao.getRetryableOperations(DateTime.now().toUtc()),
      );
    } catch (error) {
      return classifySyncFailure(error);
    }
    SyncFailure? firstFailure;
    for (final queuedOperation in operations) {
      // The initial batch is only a scheduling snapshot. Acknowledging an
      // earlier operation rebases later rows in SQLite, so reload this
      // operation immediately before sending it instead of using a stale
      // expectedServerVersion captured at batch start.
      final operation = await _db.syncDao.getOperation(
        queuedOperation.operationId,
      );
      if (operation == null ||
          !const {'pending', 'error', 'in_flight'}.contains(operation.state)) {
        continue;
      }
      try {
        _assertAccountScope();
        final now = DateTime.now().toUtc();
        final prepared = await _clientPayloadForOperation(operation);
        final payload = prepared.payload;
        if (prepared.version == 2) {
          await _ensureV2Capabilities();
        }
        await _db.syncDao.markInFlight(operation.operationId, now);
        SyncPayloadValidator.validate(
          SyncRemoteChange(
            changeId: 0,
            operationId: operation.operationId,
            tableName: operation.entityTableName,
            recordId: operation.recordId,
            operation: operation.operation,
            serverVersion: operation.expectedServerVersion ?? 0,
            serverTimestamp: now,
            payload: payload,
          ),
        );
        _assertAccountScope();
        final response = await _gateway.applyOperation(
          operationId: operation.operationId,
          tableName: operation.entityTableName,
          recordId: operation.recordId,
          operation: operation.operation,
          expectedServerVersion: operation.expectedServerVersion,
          payload: payload,
          payloadVersion: prepared.version,
        );
        _assertAccountScope();
        final acknowledgement = SyncRpcAcknowledgement.fromJson(response);
        if (acknowledgement.status == 'conflict') {
          await _saveConflict(operation, acknowledgement);
        } else if (acknowledgement.status == 'acknowledged' ||
            acknowledgement.status == 'applied') {
          await _acknowledge(operation, acknowledgement);
        } else {
          throw StateError('Unexpected sync acknowledgement');
        }
      } on _SyncAccountScopeChanged {
        await _db.syncDao.releaseInFlight(
          operation.operationId,
          DateTime.now().toUtc(),
        );
        return _scopeFailure;
      } catch (error) {
        final failure = classifySyncFailure(error);
        firstFailure ??= failure;
        final failureMessage = failure.message;
        if (failure.kind == SyncFailureKind.retryable) {
          final retryAt = DateTime.now().toUtc().add(
            _backoff(operation.attemptCount + 1),
          );
          await _db.syncDao.markRetryableError(
            operation.operationId,
            now: DateTime.now().toUtc(),
            nextAttemptAt: retryAt,
            error: failureMessage,
          );
        } else {
          await _db.syncDao.markPermanentError(
            operation.operationId,
            now: DateTime.now().toUtc(),
            error: failureMessage,
          );
        }
      }
    }
    return firstFailure;
  }

  /// Requeues only permanent task operations whose retained diagnostic is the
  /// former server-side F03 transition error. The original operation ID,
  /// expected version, payload, and ordering remain intact so the corrected
  /// server can return its normal idempotent acknowledgement or CAS conflict.
  Future<void> _repairTitleHistoryPermanentOperations() async {
    final failed = await _db.syncDao.getPermanentOperationsMatching(
      'tasks',
      _legacyTitleHistoryTransitionDiagnostic,
    );
    for (final operation in failed) {
      _assertAccountScope();
      try {
        final prepared = await _clientPayloadForOperation(operation);
        SyncPayloadValidator.validate(
          SyncRemoteChange(
            changeId: 0,
            operationId: operation.operationId,
            tableName: operation.entityTableName,
            recordId: operation.recordId,
            operation: operation.operation,
            serverVersion: operation.expectedServerVersion ?? 0,
            serverTimestamp: DateTime.now().toUtc(),
            payload: prepared.payload,
          ),
        );
        await _db.syncDao.retryPermanentOperation(
          operation.operationId,
          DateTime.now().toUtc(),
        );
      } on _SyncAccountScopeChanged {
        rethrow;
      } on Object {
        // Leave malformed or no-longer-decodable operations permanently
        // stopped for explicit repair.
      }
    }
  }

  Future<SyncFailure?> pull({int limit = 200}) async {
    try {
      _assertAccountScope();
      await _repairTitleHistoryQuarantine();
    } on _SyncAccountScopeChanged {
      return _scopeFailure;
    }
    final pageSize = limit.clamp(1, 500);
    var cursor = await _db.syncDao.getCursor(_accountId);
    while (true) {
      late final Object? response;
      try {
        _assertAccountScope();
        response = await _gateway.pullChanges(
          afterChangeId: cursor,
          limit: pageSize,
        );
        _assertAccountScope();
      } on _SyncAccountScopeChanged {
        return _scopeFailure;
      } catch (error) {
        return classifySyncFailure(error);
      }
      final rawValue = response is Map ? response['changes'] : response;
      if (rawValue is! List) {
        return const SyncFailure(
          SyncFailureKind.invalidData,
          'Invalid sync feed response; no local data was changed.',
        );
      }
      final rawChanges = rawValue;
      final received = <SyncRemoteChange>[];
      SyncFailure? invalidFailure;
      var maxChangeId = cursor;
      for (final raw in rawChanges) {
        try {
          final change = SyncRemoteChange.fromJson(raw);
          if (change.changeId <= cursor) continue;
          maxChangeId = maxChangeId < change.changeId
              ? change.changeId
              : maxChangeId;
          // Structural validation can run before the page is staged. State
          // dependent checks (for example, the single active timer rule)
          // must run immediately before each apply so earlier siblings in
          // this page are visible.
          await _applier.validate(
            change,
            checkMaterializedState: false,
            checkHistoryLinks: false,
          );
          received.add(change);
        } catch (error) {
          final changeId = _rawChangeId(raw);
          final message = classifySyncFailure(error).message;
          invalidFailure ??= SyncFailure(SyncFailureKind.invalidData, message);
          if (changeId != null && changeId > cursor) {
            await _db.syncDao.recordQuarantinedChange(
              _accountId,
              changeId,
              message,
              rawChange: raw,
            );
            maxChangeId = maxChangeId < changeId ? changeId : maxChangeId;
          }
        }
      }
      if (received.isEmpty) {
        if (maxChangeId > cursor) {
          await _db.syncDao.advanceCursor(
            _accountId,
            maxChangeId,
            DateTime.now().toUtc(),
          );
        }
        return invalidFailure;
      }

      final latest = <String, SyncRemoteChange>{};
      for (final change in received) {
        latest['${change.tableName}\u0000${change.recordId}'] = change;
      }
      final changes = _orderPulledChanges(latest.values.toList());
      // Relationship validation is proportional to the coalesced page when
      // the final staged graph is valid. If it fails, retain the existing
      // per-change validation inside the savepoints below so invalid records
      // can still be quarantined individually.
      var batchValidated = true;
      try {
        await _applier.validateBatch(changes, checkMaterializedState: false);
      } on SyncValidationException {
        batchValidated = false;
      }
      final nextCursor = maxChangeId;
      final changedTables = <String>{};
      final affectedActualTaskIds = <String>{};
      await _db.syncDao.runWithoutOutbound(() async {
        // A valid reschedule pair stores reciprocal self-references. SQLite
        // must validate those foreign keys after both task snapshots exist.
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        // Coalescing is correct for the materialized row, but it must not
        // hide an acknowledgement that precedes a newer feed entry for the
        // same record. Retire/rebase every matching local operation first;
        // the newest coalesced change then decides the visible row state.
        for (final change in changes) {
          try {
            _assertAccountScope();
            // Keep a malformed relationship from aborting the whole page.
            // The savepoint rolls back any metadata/conflict work for this
            // one change, while valid siblings can still commit atomically
            // with the cursor advancement below.
            await _db.transaction(() async {
              _assertAccountScope();
              await _collectAffectedActualTaskIds(
                change,
                affectedActualTaskIds,
              );
              for (final acknowledgement in received) {
                if (acknowledgement.tableName == change.tableName &&
                    acknowledgement.recordId == change.recordId) {
                  await _acknowledgePulledOperation(acknowledgement);
                }
              }
              await _applyPulledChange(
                change,
                skipHistoryValidation: batchValidated,
              );
              changedTables.add(change.tableName);
            });
          } on _SyncAccountScopeChanged {
            rethrow;
          } catch (error) {
            final diagnostic =
                'Rejected remote ${change.tableName}/${change.recordId}: '
                '${safeSyncError(error)}';
            invalidFailure ??= SyncFailure(
              SyncFailureKind.invalidData,
              diagnostic,
            );
            await _db.syncDao.recordQuarantinedChange(
              _accountId,
              change.changeId,
              diagnostic,
              rawChange: {
                'change_id': change.changeId,
                'operation_id': change.operationId,
                'table_name': change.tableName,
                'record_id': change.recordId,
                'operation': change.operation,
                'server_version': change.serverVersion,
                'server_timestamp': change.serverTimestamp.toIso8601String(),
                'payload': change.payload,
              },
            );
          }
        }
        if (affectedActualTaskIds.isNotEmpty) {
          final actualDuration = TaskActualDurationService(_db);
          for (final taskId in affectedActualTaskIds) {
            await actualDuration.recomputeTaskInTransaction(taskId);
          }
          changedTables.add('tasks');
        }
        _assertAccountScope();
        await _db.syncDao.advanceCursor(
          _accountId,
          nextCursor,
          DateTime.now().toUtc(),
        );
      });
      _notifyDomainStreams(changedTables);
      cursor = nextCursor;
      if (rawChanges.length < pageSize) return invalidFailure;
    }
  }

  static int? _rawChangeId(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['change_id'] ?? raw['changeId'];
    return value is num ? value.toInt() : int.tryParse('$value');
  }

  /// Reconsiders only retained task rows that carry the exact diagnostic
  /// emitted by the former pre-conflict title-transition check. A current
  /// active local operation is required, so an old feed row can only enter
  /// acknowledgement/conflict handling and can never overwrite an unrelated
  /// newer materialized edit. Other quarantine records and the cursor remain
  /// untouched.
  Future<void> _repairTitleHistoryQuarantine() async {
    final retained = await _db.syncDao.getQuarantinedChanges(_accountId);
    final changedTables = <String>{};
    for (final setting in retained) {
      _assertAccountScope();
      try {
        final decoded = jsonDecode(setting.value);
        if (decoded is! Map) continue;
        final record = Map<String, dynamic>.from(decoded);
        if (record['account_id']?.toString() != _accountId ||
            !record['diagnostic'].toString().contains(
              _legacyTitleHistoryTransitionDiagnostic,
            )) {
          continue;
        }
        final raw = record['raw_change'];
        if (raw is! Map) continue;
        final change = SyncRemoteChange.fromJson(raw);
        if (change.tableName != 'tasks' || change.operation == 'delete') {
          continue;
        }
        final currentTask = await _db.taskDao.getTaskById(change.recordId);
        final currentVersion = currentTask?.serverVersion;
        if (currentTask == null ||
            (currentVersion != null &&
                change.serverVersion <= currentVersion)) {
          continue;
        }
        final active = await _db.syncDao.getActiveOperationsForRecord(
          change.tableName,
          change.recordId,
        );
        if (active.isEmpty) continue;
        await _applier.validate(
          change,
          checkMaterializedState: false,
          checkHistoryLinks: false,
        );

        var repaired = false;
        await _db.syncDao.runWithoutOutbound(() async {
          _assertAccountScope();
          if (await _db.syncDao.getSetting(setting.key) == null) return;
          final stillActive = await _db.syncDao.getActiveOperationsForRecord(
            change.tableName,
            change.recordId,
          );
          if (stillActive.isEmpty) return;
          await _applyPulledChange(change);
          await _db.syncDao.deleteSetting(setting.key);
          repaired = true;
        });
        if (repaired) changedTables.add(change.tableName);
      } on _SyncAccountScopeChanged {
        rethrow;
      } on Object {
        // The retained row remains available for explicit review if it is not
        // structurally valid under the corrected boundary or cannot be safely
        // classified against the current local operation set.
      }
    }
    _notifyDomainStreams(changedTables);
  }

  Future<void> _acknowledgePulledOperation(SyncRemoteChange change) async {
    final operation = await _db.syncDao.getOperation(change.operationId);
    if (operation == null || operation.state == 'acknowledged') return;
    final now = DateTime.now().toUtc();
    await _db.syncDao.markAcknowledged(operation.operationId, now);
    await _db.syncDao.rebasePendingOperations(
      change.tableName,
      change.recordId,
      change.serverVersion,
      now,
    );
  }

  Future<void> _applyPulledChange(
    SyncRemoteChange change, {
    bool skipHistoryValidation = false,
  }) async {
    final matching = await _db.syncDao.getOperation(change.operationId);
    final active = await _db.syncDao.getActiveOperationsForRecord(
      change.tableName,
      change.recordId,
    );
    if (matching != null) {
      if (matching.state != 'acknowledged') {
        await _db.syncDao.markAcknowledged(
          matching.operationId,
          DateTime.now().toUtc(),
        );
      }
      await _db.syncDao.rebasePendingOperations(
        change.tableName,
        change.recordId,
        change.serverVersion,
        DateTime.now().toUtc(),
      );
      final newer = await _db.syncDao.getActiveOperationsForRecord(
        change.tableName,
        change.recordId,
      );
      if (newer.isEmpty) {
        await _applier.apply(change, checkHistoryLinks: !skipHistoryValidation);
      } else {
        await _setRemoteMetadata(
          change.tableName,
          change.recordId,
          change.serverVersion,
          pending: newer.isNotEmpty,
          conflict: newer.any((operation) => operation.state == 'conflict'),
        );
      }
      return;
    }
    if (active.isNotEmpty) {
      await _savePulledConflict(active.last, change);
      return;
    }
    await _applier.apply(change, checkHistoryLinks: !skipHistoryValidation);
  }

  /// A coalesced page can contain a task source edit and several timer source
  /// mutations in any feed order. Record both the old and incoming timer
  /// parent, then recalculate only after the complete page has been applied.
  Future<void> _collectAffectedActualTaskIds(
    SyncRemoteChange change,
    Set<String> taskIds,
  ) async {
    if (change.tableName == 'tasks') {
      taskIds.add(change.recordId);
      return;
    }
    if (change.tableName != 'timer_sessions') return;
    final prior = await _db.timerDao.getSessionById(change.recordId);
    if (prior != null) taskIds.add(prior.taskId);
    final incoming = change.payload['task_id']?.toString();
    if (incoming != null && incoming.isNotEmpty) taskIds.add(incoming);
  }

  Future<void> _acknowledge(
    SyncLogRow operation,
    SyncRpcAcknowledgement acknowledgement,
  ) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.syncDao.markAcknowledged(operation.operationId, now);
      await _db.syncDao.rebasePendingOperations(
        operation.entityTableName,
        operation.recordId,
        acknowledgement.serverVersion,
        now,
      );
      final remaining = await _db.syncDao.getActiveOperationsForRecord(
        operation.entityTableName,
        operation.recordId,
      );
      await _setRemoteMetadata(
        operation.entityTableName,
        operation.recordId,
        acknowledgement.serverVersion,
        pending: remaining.isNotEmpty,
        conflict: remaining.any((entry) => entry.state == 'conflict'),
      );
    });
    _notifyDomainStreams({operation.entityTableName});
  }

  Future<void> _saveConflict(
    SyncLogRow operation,
    SyncRpcAcknowledgement acknowledgement,
  ) async {
    final remote = acknowledgement.remoteSnapshot ?? <String, dynamic>{};
    await _db.transaction(() async {
      await _db.syncDao.markConflict(
        operation.operationId,
        DateTime.now().toUtc(),
      );
      final active = await _db.syncDao.getActiveOperationsForRecord(
        operation.entityTableName,
        operation.recordId,
      );
      // A newer local write may have been created while this request was in
      // flight. The conflict must retain that newest complete snapshot, not
      // the stale payload that happened to lose the compare-and-swap race.
      final outstanding = active
          .where((entry) => entry.state != 'conflict')
          .toList(growable: false);
      final local = _newestOperation([operation, ...outstanding]);
      await _setRemoteMetadata(
        operation.entityTableName,
        operation.recordId,
        acknowledgement.actualServerVersion,
        pending: active.any(
          (entry) =>
              entry.state == 'pending' ||
              entry.state == 'error' ||
              entry.state == 'in_flight',
        ),
        conflict: true,
      );
      await _db.syncDao.insertConflict(
        SyncConflictsCompanion.insert(
          id: generateUuidV7(),
          operationId: local.operationId,
          entityTableName: local.entityTableName,
          recordId: local.recordId,
          expectedServerVersion: Value(local.expectedServerVersion),
          actualServerVersion: Value(acknowledgement.actualServerVersion),
          localSnapshot: local.payload,
          remoteSnapshot: jsonEncode(remote),
          createdAt: DateTime.now().toUtc(),
        ),
      );
    });
    _notifyDomainStreams({operation.entityTableName});
  }

  Future<void> _savePulledConflict(
    SyncLogRow operation,
    SyncRemoteChange change,
  ) async {
    final snapshot = jsonEncode(change.payload);
    final existing = await _db.syncDao.getConflictForRecord(
      change.tableName,
      change.recordId,
    );
    await _db.syncDao.markConflict(
      operation.operationId,
      DateTime.now().toUtc(),
    );
    await _setRemoteMetadata(
      change.tableName,
      change.recordId,
      change.serverVersion,
      pending: false,
      conflict: true,
    );
    if (existing != null) {
      await _db.syncDao.updateConflictRemote(
        existing.id,
        operationId: operation.operationId,
        entityTableName: operation.entityTableName,
        recordId: operation.recordId,
        expectedServerVersion: operation.expectedServerVersion,
        actualServerVersion: change.serverVersion,
        localSnapshot: operation.payload,
        remoteSnapshot: snapshot,
      );
      return;
    }
    await _db.syncDao.insertConflict(
      SyncConflictsCompanion.insert(
        id: generateUuidV7(),
        operationId: operation.operationId,
        entityTableName: change.tableName,
        recordId: change.recordId,
        expectedServerVersion: Value(operation.expectedServerVersion),
        actualServerVersion: Value(change.serverVersion),
        localSnapshot: operation.payload,
        remoteSnapshot: snapshot,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  static SyncLogRow _newestOperation(List<SyncLogRow> operations) {
    var newest = operations.first;
    for (final candidate in operations.skip(1)) {
      final newestRevision = _snapshotRevision(newest.payload);
      final candidateRevision = _snapshotRevision(candidate.payload);
      if (newestRevision != null &&
          candidateRevision != null &&
          candidateRevision != newestRevision) {
        if (candidateRevision > newestRevision) newest = candidate;
        continue;
      }
      final newestAt = _snapshotUpdatedAt(newest.payload) ?? newest.createdAt;
      final candidateAt =
          _snapshotUpdatedAt(candidate.payload) ?? candidate.createdAt;
      final isLater = candidateAt.isAfter(newestAt);
      final isSameTime = candidateAt.isAtSameMomentAs(newestAt);
      final isLaterCreated = candidate.createdAt.isAfter(newest.createdAt);
      final isSameCreated = candidate.createdAt.isAtSameMomentAs(
        newest.createdAt,
      );
      if (isLater ||
          (isSameTime &&
              (isLaterCreated ||
                  (isSameCreated &&
                      candidate.operationId.compareTo(newest.operationId) >
                          0)))) {
        newest = candidate;
      }
    }
    return newest;
  }

  static int? _snapshotRevision(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final value = decoded['_planner_revision'];
        if (value is num && value == value.toInt()) return value.toInt();
        return int.tryParse('$value');
      }
    } on FormatException {
      // Payload validation happens at the sync boundary.
    }
    return null;
  }

  static DateTime? _snapshotUpdatedAt(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return DateTime.tryParse('${decoded['updated_at'] ?? ''}')?.toUtc();
      }
    } on FormatException {
      // Payload validation happens at the sync boundary. Keep snapshot
      // selection defensive if a legacy row contains malformed JSON.
    }
    return null;
  }

  Future<void> keepLocal(String conflictId) async {
    String? changedTable;
    await _db.syncDao.runWithoutOutbound(() async {
      // Resolve against the current durable operation set, not only the
      // snapshot captured when the conflict was first recorded. A user may
      // have edited the same task/category while the conflict card remained
      // open; that newer pending operation is the local choice to keep.
      final conflict = await _db.syncDao.getConflict(conflictId);
      if (conflict == null) return;
      changedTable = conflict.entityTableName;
      final operation = await _db.syncDao.getOperation(conflict.operationId);
      if (operation == null) return;
      final active = await _db.syncDao.getActiveOperationsForRecord(
        conflict.entityTableName,
        conflict.recordId,
      );
      final localOperations = active
          .where((entry) => entry.state != 'conflict')
          .toList(growable: false);
      final currentLocal = localOperations.isEmpty
          ? operation
          : _newestOperation(localOperations);
      final now = DateTime.now().toUtc();
      final newOperationId = generateUuidV7();
      var local = Map<String, dynamic>.from(
        jsonDecode(currentLocal.payload) as Map,
      );
      if (conflict.entityTableName == 'tasks') {
        final remote = Map<String, dynamic>.from(
          jsonDecode(conflict.remoteSnapshot) as Map,
        );
        local = _mergeTaskHistoryPayload(chosen: local, other: remote);
        local['_planner_payload_version'] = 2;
        await _writeMergedTaskHistory(conflict.recordId, local, now);
      }
      final localDeleted =
          local['deleted'] == true || local['deleted_at'] != null;
      final actualVersion = conflict.actualServerVersion;
      await _db.syncDao.retirePendingOperations(
        conflict.entityTableName,
        conflict.recordId,
      );
      if (actualVersion == null && localDeleted) {
        await _setRemoteMetadata(
          conflict.entityTableName,
          conflict.recordId,
          null,
          pending: false,
        );
        await _db.syncDao.deleteConflict(conflictId);
        return;
      }
      await _setRemoteMetadata(
        conflict.entityTableName,
        conflict.recordId,
        actualVersion,
        pending: true,
      );
      await _db.syncDao.enqueueOperation(
        SyncLogCompanion.insert(
          operationId: newOperationId,
          entityTableName: conflict.entityTableName,
          recordId: conflict.recordId,
          operation: actualVersion == null
              ? 'insert'
              : (localDeleted ? 'delete' : 'update'),
          expectedServerVersion: Value(actualVersion),
          payload: jsonEncode(local),
          state: const Value('pending'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _db.syncDao.deleteConflict(conflictId);
    });
    if (changedTable != null) _notifyDomainStreams({changedTable!});
  }

  Future<void> keepRemote(String conflictId) async {
    final conflict = await _db.syncDao.getConflict(conflictId);
    if (conflict == null) return;
    final actualVersion = conflict.actualServerVersion;
    final remotePayload = Map<String, dynamic>.from(
      jsonDecode(conflict.remoteSnapshot) as Map,
    );
    final affectedActualTaskIds = <String>{};
    await _db.syncDao.runWithoutOutbound(() async {
      final now = DateTime.now().toUtc();
      Map<String, dynamic>? historyPreservingPayload;
      if (conflict.entityTableName == 'tasks' &&
          actualVersion != null &&
          remotePayload['title'] != null) {
        final active = await _db.syncDao.getActiveOperationsForRecord(
          conflict.entityTableName,
          conflict.recordId,
        );
        final newerLocal = active
            .where((entry) => entry.state != 'conflict')
            .toList(growable: false);
        final localSnapshot = newerLocal.isEmpty
            ? conflict.localSnapshot
            : _newestOperation(newerLocal).payload;
        final localPayload = Map<String, dynamic>.from(
          jsonDecode(localSnapshot) as Map,
        );
        // The remote side deliberately controls the live title/pointer, but
        // locally unique intentional events remain durable history.
        historyPreservingPayload =
            _mergeTaskHistoryPayload(chosen: remotePayload, other: localPayload)
              ..['_planner_payload_version'] = 2
              ..['updated_at'] = now.toIso8601String();
      }
      await _collectAffectedActualTaskIds(
        SyncRemoteChange(
          changeId: 0,
          operationId: conflict.operationId,
          tableName: conflict.entityTableName,
          recordId: conflict.recordId,
          operation: 'update',
          serverVersion: actualVersion ?? 0,
          serverTimestamp: DateTime.now().toUtc(),
          payload: remotePayload,
        ),
        affectedActualTaskIds,
      );
      if (actualVersion == null) {
        await _applyRemoteAbsence(conflict.entityTableName, conflict.recordId);
      } else {
        final payloadForApply = historyPreservingPayload ?? remotePayload;
        await _applier.apply(
          SyncRemoteChange(
            changeId: 0,
            operationId: conflict.operationId,
            tableName: conflict.entityTableName,
            recordId: conflict.recordId,
            operation:
                remotePayload['deleted'] == true ||
                    remotePayload['deleted_at'] != null
                ? 'delete'
                : 'update',
            serverVersion: actualVersion,
            serverTimestamp: DateTime.now().toUtc(),
            payload: payloadForApply,
          ),
        );
      }
      await _db.syncDao.retirePendingOperations(
        conflict.entityTableName,
        conflict.recordId,
      );
      if (historyPreservingPayload != null) {
        await _writeMergedTaskHistory(
          conflict.recordId,
          historyPreservingPayload,
          now,
        );
        await _db.syncDao.enqueueOperation(
          SyncLogCompanion.insert(
            operationId: generateUuidV7(),
            entityTableName: 'tasks',
            recordId: conflict.recordId,
            operation: 'update',
            expectedServerVersion: Value(actualVersion),
            payload: jsonEncode(historyPreservingPayload),
            state: const Value('pending'),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _db.syncDao.deleteConflict(conflictId);
      if (affectedActualTaskIds.isNotEmpty) {
        final actualDuration = TaskActualDurationService(_db);
        for (final taskId in affectedActualTaskIds) {
          await actualDuration.recomputeTaskInTransaction(taskId);
        }
      }
    });
    _notifyDomainStreams({
      conflict.entityTableName,
      if (affectedActualTaskIds.isNotEmpty) 'tasks',
    });
  }

  /// Rebuilds one permanent outbox operation from the current local row.
  /// Retrying the old payload is deliberately refused: the user must have
  /// changed the row (or otherwise repaired it) before it can be validated
  /// and requeued with a fresh operation identity.
  Future<void> repairPermanentOperation(String operationId) async {
    final failed = await _db.syncDao.firstPermanentOperation();
    if (failed == null || failed.operationId != operationId) {
      throw const SyncRepairException('That sync failure is no longer active.');
    }

    final data = await BackupCodec.exportData(_db);
    final currentRecord = _portableRecord(
      data,
      failed.entityTableName,
      failed.recordId,
    );
    if (currentRecord == null) {
      throw const SyncRepairException(
        'The local record no longer exists. Restore or recreate it before retrying.',
      );
    }
    final current = _toSyncPayload(failed.entityTableName, currentRecord);

    final oldPayload = _decodePayload(failed.payload);
    if (BackupCodec.canonicalJson(_withoutServerVersion(current)) ==
        BackupCodec.canonicalJson(_withoutServerVersion(oldPayload))) {
      throw const SyncRepairException(
        'Edit or repair this record before retrying the invalid payload.',
      );
    }

    final now = DateTime.now().toUtc();
    final payload = _withoutServerVersion(current);
    SyncPayloadValidator.validate(
      SyncRemoteChange(
        changeId: 0,
        operationId: operationId,
        tableName: failed.entityTableName,
        recordId: failed.recordId,
        operation: failed.operation,
        serverVersion: failed.expectedServerVersion ?? 0,
        serverTimestamp: now,
        payload: payload,
      ),
    );

    await _db.transaction(() async {
      final stillFailed = await _db.syncDao.firstPermanentOperation();
      if (stillFailed == null || stillFailed.operationId != operationId) {
        throw const SyncRepairException(
          'That sync failure changed while it was being repaired.',
        );
      }
      final active = await _db.syncDao.getActiveOperationsForRecord(
        failed.entityTableName,
        failed.recordId,
      );
      if (active.any((operation) => operation.state == 'conflict')) {
        throw const SyncRepairException(
          'Resolve the existing conflict before repairing this record.',
        );
      }
      // The current local row is the authoritative repaired snapshot. Retire
      // older queued payloads for the same record so the server receives one
      // validated final state rather than a duplicate edit chain.
      await _db.syncDao.retirePendingOperations(
        failed.entityTableName,
        failed.recordId,
      );
      await _db.syncDao.enqueueOperation(
        SyncLogCompanion.insert(
          operationId: generateUuidV7(),
          entityTableName: failed.entityTableName,
          recordId: failed.recordId,
          operation: failed.operation,
          expectedServerVersion: Value(failed.expectedServerVersion),
          payload: jsonEncode(
            Map<String, dynamic>.from(payload)
              ..['_planner_payload_version'] = 2,
          ),
          state: const Value('pending'),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  static Map<String, dynamic>? _portableRecord(
    Map<String, dynamic> data,
    String table,
    String recordId,
  ) {
    final rows = data[table];
    if (rows is! List) return null;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final identity = table == 'task_tags'
          ? '${row['task_id']}:${row['tag_id']}'
          : row['id']?.toString();
      if (identity == recordId) return row;
    }
    return null;
  }

  static Map<String, dynamic> _decodePayload(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const SyncRepairException('The failed payload is not an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> _mergeTaskHistoryPayload({
    required Map<String, dynamic> chosen,
    required Map<String, dynamic> other,
  }) {
    List<PlanTitleChange> historyFrom(Map<String, dynamic> payload) {
      final raw = payload['plan_title_history_json'];
      if (raw == null) return const <PlanTitleChange>[];
      if (raw is! String) {
        throw const SyncValidationException(
          'plan_title_history_json must be JSON text',
        );
      }
      try {
        return PlanTitleHistory.decodeJson(raw);
      } on FormatException catch (error) {
        throw SyncValidationException(error.message);
      }
    }

    final merged = Map<String, dynamic>.from(chosen);
    final history = PlanTitleHistory.union(
      chosen: historyFrom(chosen),
      other: historyFrom(other),
    );
    final pointer = merged['display_plan_change_id']?.toString();
    try {
      PlanTitleHistory.validate(
        history,
        displayPlanChangeId: pointer,
        currentTitle: merged['title']?.toString() ?? '',
      );
    } on FormatException catch (error) {
      throw SyncValidationException(error.message);
    }
    merged['plan_title_history_json'] = PlanTitleHistory.encodeJson(history);
    merged['display_plan_change_id'] = pointer;
    return merged;
  }

  Future<void> _writeMergedTaskHistory(
    String taskId,
    Map<String, dynamic> payload,
    DateTime now,
  ) async {
    final row = await _db.taskDao.getTaskById(taskId);
    if (row == null) return;
    await _db.customUpdate(
      'UPDATE tasks SET plan_title_history_json = ?, '
      'display_plan_change_id = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE id = ?',
      variables: [
        Variable<String>(payload['plan_title_history_json'] as String),
        Variable<String>(payload['display_plan_change_id']?.toString()),
        Variable<String>(now.toIso8601String()),
        Variable<String>(taskId),
      ],
      updates: {_db.tasks},
    );
  }

  static Map<String, dynamic> _withoutServerVersion(
    Map<String, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(source);
    result.remove('server_version');
    result.remove('_planner_payload_version');
    result.remove('_planner_revision');
    return result;
  }

  static Map<String, dynamic> _toSyncPayload(
    String table,
    Map<String, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(source);
    void integerFlag(String key) {
      final value = result[key];
      if (value is bool) result[key] = value ? 1 : 0;
    }

    void jsonList(String backupKey, String syncKey) {
      final value = result.remove(backupKey);
      result[syncKey] = jsonEncode(value is List ? value : const <dynamic>[]);
    }

    switch (table) {
      case 'tasks':
        integerFlag('is_inbox');
        integerFlag('manual_actual_set');
        jsonList('plan_title_history', 'plan_title_history_json');
      case 'categories':
        integerFlag('is_focus');
      case 'subtasks':
        integerFlag('is_completed');
      case 'recurring_rules':
        jsonList('tags', 'tags_json');
        jsonList('exceptions', 'exceptions_json');
        integerFlag('is_active');
      case 'task_templates':
        jsonList('tags', 'tags_json');
      case 'daily_reviews':
        jsonList('wins', 'wins_json');
        jsonList('improvements', 'improvements_json');
      case 'weekly_reviews':
        jsonList('goals_met', 'goals_met_json');
        jsonList('goals_missed', 'goals_missed_json');
        jsonList('next_week_focus', 'next_week_focus_json');
      case 'timer_sessions':
        jsonList('work_intervals', 'work_intervals_json');
    }
    return result;
  }

  /// Raw SQL is used at the sync boundary so payload columns can be applied
  /// uniformly. Tell Drift which materialized tables changed only after the
  /// surrounding transaction has committed; this refreshes existing streams
  /// without causing trigger-generated outbox echoes.
  void _notifyDomainStreams(Iterable<String> tableNames) {
    final tables = <String, TableInfo>{
      'tasks': _db.tasks,
      'categories': _db.categories,
      'subtasks': _db.subtasks,
      'tags': _db.tags,
      'task_tags': _db.taskTags,
      'recurring_rules': _db.recurringRules,
      'task_templates': _db.taskTemplates,
      'daily_reviews': _db.dailyReviews,
      'weekly_reviews': _db.weeklyReviews,
      'timer_sessions': _db.timerSessions,
      'day_contexts': _db.dayContexts,
    };
    final changed = <TableInfo>[
      for (final name in tableNames)
        if (tables[name] != null) tables[name]!,
    ];
    if (changed.isNotEmpty) _db.markTablesUpdated(changed);
  }

  Future<void> _setRemoteMetadata(
    String table,
    String recordId,
    int? serverVersion, {
    required bool pending,
    bool conflict = false,
  }) async {
    final status = conflict ? 2 : (pending ? 1 : 0);
    if (table == 'task_tags') {
      final pieces = recordId.split(':');
      if (pieces.length != 2) throw StateError('Invalid task_tags record ID');
      await _db.customStatement(
        'UPDATE task_tags SET server_version = ?, sync_status = ? '
        'WHERE task_id = ? AND tag_id = ?',
        [serverVersion, status, pieces[0], pieces[1]],
      );
      return;
    }
    const tables = {
      'tasks',
      'subtasks',
      'categories',
      'tags',
      'recurring_rules',
      'task_templates',
      'daily_reviews',
      'weekly_reviews',
      'timer_sessions',
      'day_contexts',
    };
    if (!tables.contains(table)) throw StateError('Unsupported sync table');
    await _db.customStatement(
      'UPDATE $table SET server_version = ?, sync_status = ? WHERE id = ?',
      [serverVersion, status, recordId],
    );
  }

  Future<void> _applyRemoteAbsence(String table, String recordId) async {
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    if (table == 'task_tags') {
      final pieces = recordId.split(':');
      if (pieces.length != 2) throw StateError('Invalid task_tags record ID');
      await _db.customStatement(
        'UPDATE task_tags SET deleted_at = ?, server_version = NULL, '
        'sync_status = 0 WHERE task_id = ? AND tag_id = ?',
        [deletedAt, pieces[0], pieces[1]],
      );
      return;
    }
    if (!_upsertOrder.containsKey(table)) {
      throw StateError('Unsupported sync table');
    }
    final clearRecurrenceReason = table == 'tasks'
        ? 'recurrence_removal_reason = NULL, '
        : '';
    await _db.customStatement(
      'UPDATE $table SET deleted_at = ?, $clearRecurrenceReason'
      'server_version = NULL, sync_status = 0 WHERE id = ?',
      [deletedAt, recordId],
    );
  }

  static Duration _backoff(int attempt) {
    final seconds = 1 << (attempt - 1).clamp(0, 5);
    return Duration(seconds: seconds.clamp(1, 60));
  }

  static int _changeOrder(SyncRemoteChange a, SyncRemoteChange b) {
    final aDelete = a.operation == 'delete';
    final bDelete = b.operation == 'delete';
    if (aDelete != bDelete) return aDelete ? 1 : -1;
    final order = aDelete ? _deleteOrder : _upsertOrder;
    final table = (order[a.tableName] ?? 100).compareTo(
      order[b.tableName] ?? 100,
    );
    return table == 0 ? a.changeId.compareTo(b.changeId) : table;
  }

  /// Orders one coalesced pull page as a dependency graph. Table ranks cover
  /// the normal aggregate order; these edges additionally handle a task's
  /// self-references and any parent/child rows that share the page.
  static List<SyncRemoteChange> _orderPulledChanges(
    List<SyncRemoteChange> source,
  ) {
    final changes = List<SyncRemoteChange>.of(source);
    final byKey = {
      for (final change in changes)
        '${change.tableName}\u0000${change.recordId}': change,
    };
    final outgoing = <String, Set<String>>{
      for (final change in changes) change.operationId: <String>{},
    };
    final indegree = <String, int>{
      for (final change in changes) change.operationId: 0,
    };
    void before(SyncRemoteChange first, SyncRemoteChange second) {
      if (first.operationId == second.operationId) return;
      if (outgoing[first.operationId]!.add(second.operationId)) {
        indegree[second.operationId] = indegree[second.operationId]! + 1;
      }
    }

    for (var i = 0; i < changes.length; i++) {
      for (var j = i + 1; j < changes.length; j++) {
        final a = changes[i];
        final b = changes[j];
        // Every supported remote delete is a soft tombstone UPDATE. Treating
        // it as a physical delete here makes a tombstoned parent and its
        // historical child require opposite orders and creates a false cycle.
        final aDelete = _isHardDelete(a);
        final bDelete = _isHardDelete(b);
        if (aDelete != bDelete) {
          if (aDelete) {
            before(b, a);
          } else {
            before(a, b);
          }
          continue;
        }
        final rank = aDelete ? _deleteOrder : _upsertOrder;
        final comparison = (rank[a.tableName] ?? 100).compareTo(
          rank[b.tableName] ?? 100,
        );
        if (a.tableName == 'timer_sessions' &&
            b.tableName == 'timer_sessions') {
          final sameOwnedTask =
              a.payload['owner_device_id'] != null &&
              a.payload['owner_device_id'] == b.payload['owner_device_id'] &&
              a.payload['task_id'] == b.payload['task_id'];
          final aUnfinished =
              a.operation != 'delete' &&
              const {'running', 'paused'}.contains(a.payload['state']) &&
              a.payload['deleted_at'] == null;
          final bUnfinished =
              b.operation != 'delete' &&
              const {'running', 'paused'}.contains(b.payload['state']) &&
              b.payload['deleted_at'] == null;
          if (sameOwnedTask && aUnfinished != bUnfinished) {
            before(aUnfinished ? b : a, aUnfinished ? a : b);
            continue;
          }
        }
        if (comparison < 0) before(a, b);
        if (comparison > 0) before(b, a);
      }
    }

    for (final change in changes) {
      final isDelete = _isHardDelete(change);
      for (final dependency in _changeDependencies(change)) {
        final parent = byKey[dependency];
        if (parent == null) continue;
        if (_isReciprocalReschedulePair(change, parent)) continue;
        if (isDelete) {
          before(change, parent);
        } else {
          before(parent, change);
        }
      }
    }

    final byOperationId = {
      for (final change in changes) change.operationId: change,
    };
    final ready =
        changes.where((change) => indegree[change.operationId] == 0).toList()
          ..sort(_changeOrder);
    final ordered = <SyncRemoteChange>[];
    while (ready.isNotEmpty) {
      final next = ready.removeAt(0);
      ordered.add(next);
      for (final childId in outgoing[next.operationId]!) {
        indegree[childId] = indegree[childId]! - 1;
        if (indegree[childId] == 0) {
          ready.add(byOperationId[childId]!);
          ready.sort(_changeOrder);
        }
      }
    }
    if (ordered.length != changes.length) {
      throw StateError('Remote sync dependency cycle detected');
    }
    return ordered;
  }

  static bool _isReciprocalReschedulePair(
    SyncRemoteChange change,
    SyncRemoteChange parent,
  ) {
    if (change.tableName != 'tasks' || parent.tableName != 'tasks') {
      return false;
    }
    final changeTo = change.payload['rescheduled_to_id']?.toString();
    final changeFrom = change.payload['rescheduled_from_id']?.toString();
    final parentTo = parent.payload['rescheduled_to_id']?.toString();
    final parentFrom = parent.payload['rescheduled_from_id']?.toString();
    return (changeTo == parent.recordId && parentFrom == change.recordId) ||
        (changeFrom == parent.recordId && parentTo == change.recordId);
  }

  static bool _isHardDelete(SyncRemoteChange change) => false;

  static Iterable<String> _changeDependencies(SyncRemoteChange change) sync* {
    String? value(String key) => change.payload[key]?.toString();
    String key(String table, String? id) => '$table\u0000$id';

    switch (change.tableName) {
      case 'recurring_rules':
      case 'task_templates':
        final categoryId = value('category_id');
        if (categoryId != null && categoryId.isNotEmpty) {
          yield key('categories', categoryId);
        }
      case 'tasks':
        final categoryId = value('category_id');
        if (categoryId != null && categoryId.isNotEmpty) {
          yield key('categories', categoryId);
        }
        final ruleId = value('recurring_rule_id');
        if (ruleId != null && ruleId.isNotEmpty) {
          yield key('recurring_rules', ruleId);
        }
        for (final field in const [
          'rescheduled_from_id',
          'rescheduled_to_id',
        ]) {
          final taskId = value(field);
          if (taskId != null && taskId.isNotEmpty) {
            yield key('tasks', taskId);
          }
        }
      case 'subtasks':
      case 'timer_sessions':
        final taskId = value('task_id');
        if (taskId != null && taskId.isNotEmpty) {
          yield key('tasks', taskId);
        }
      case 'task_tags':
        final taskId = value('task_id');
        final tagId = value('tag_id');
        if (taskId != null && taskId.isNotEmpty) {
          yield key('tasks', taskId);
        }
        if (tagId != null && tagId.isNotEmpty) {
          yield key('tags', tagId);
        }
    }
  }

  static Map<String, dynamic> _clientPayload(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const SyncValidationException(
        'Local sync payload is not an object',
      );
    }
    final payload = Map<String, dynamic>.from(decoded);
    for (final field in const {
      '_planner_payload_version',
      '_planner_revision',
      'user_id',
      'server_version',
      'change_id',
      'server_timestamp',
    }) {
      payload.remove(field);
    }
    if (payload['is_inbox'] == true ||
        payload['is_inbox'] == 1 ||
        payload['is_inbox'] == '1') {
      payload['start_time'] = null;
      payload['end_time'] = null;
      payload['estimated_duration_min'] = null;
    } else {
      payload['estimated_duration_min'] = TaskTimeMetrics.plannedMinutes(
        DateTime.tryParse(payload['start_time']?.toString() ?? ''),
        DateTime.tryParse(payload['end_time']?.toString() ?? ''),
      );
    }
    return payload;
  }

  Future<({Map<String, dynamic> payload, int version})>
  _clientPayloadForOperation(SyncLogRow operation) async {
    final decoded = jsonDecode(operation.payload);
    if (decoded is! Map) {
      throw const SyncValidationException(
        'Local sync payload is not an object',
      );
    }
    final rawVersion = decoded['_planner_payload_version'];
    final payloadVersion = rawVersion == null
        ? 1
        : rawVersion is num && rawVersion == rawVersion.toInt()
        ? rawVersion.toInt()
        : -1;
    if (payloadVersion != 1 && payloadVersion != 2) {
      throw SyncValidationException(
        'Unsupported local sync payload version: $rawVersion',
      );
    }
    final payload = _clientPayload(operation.payload);
    if (payloadVersion == 2 || operation.entityTableName != 'tasks') {
      return (payload: payload, version: payloadVersion);
    }

    final hasInboxMarker = decoded.containsKey('inbox_content_version');
    final needsLegacyInboxAdaptation = !hasInboxMarker;
    final needsDueDatePreservation = !decoded.containsKey('due_date');
    if (!needsLegacyInboxAdaptation && !needsDueDatePreservation) {
      return (payload: payload, version: payloadVersion);
    }

    final current = await _db.taskDao.getTaskById(operation.recordId);
    if (needsLegacyInboxAdaptation) {
      final isInbox =
          payload['is_inbox'] == true ||
          payload['is_inbox'] == 1 ||
          payload['is_inbox'] == '1';
      if (isInbox) {
        final currentContent = current?.inboxContentVersion == 1
            ? current?.description
            : null;
        final rawDescription = payload['description'];
        if ((rawDescription == null || rawDescription == '') &&
            currentContent != null) {
          payload['description'] = currentContent;
        } else if (rawDescription == null || rawDescription == '') {
          payload['description'] = payload['title']?.toString() ?? '';
        } else if (rawDescription != payload['title']) {
          payload['description'] =
              '${payload['title'] ?? ''}\n\n$rawDescription';
        }
        payload['inbox_content_version'] = 1;
      } else {
        payload['inbox_content_version'] = 0;
      }
    }
    if (needsDueDatePreservation) payload['due_date'] = current?.dueDate;
    return (payload: payload, version: payloadVersion);
  }

  Future<void> _ensureV2Capabilities() async {
    if (_v2CapabilityVerified) return;
    final raw = await _gateway.getCapabilities();
    if (raw is! Map) {
      throw const _SyncUpgradeRequired(
        'Server capability response is unavailable; upgrade sync before retrying.',
      );
    }
    final capabilities = Map<String, dynamic>.from(raw);
    final protocol = capabilities['protocol_version'];
    final payloadVersions = capabilities['payload_versions'];
    final supportsPayloadV2 =
        payloadVersions is List && payloadVersions.contains(2);
    if (protocol != 2 ||
        !supportsPayloadV2 ||
        capabilities['schedule_duration_projection'] != true ||
        capabilities['inbox_content_version'] != true ||
        capabilities['due_date'] != true ||
        capabilities['plan_title_history'] != true ||
        capabilities['manual_actual_source'] != true ||
        capabilities['timer_state_machine'] != true ||
        capabilities['day_contexts'] != true ||
        capabilities['recurrence_removal_provenance'] != true) {
      throw const _SyncUpgradeRequired(
        'Server upgrade required before Sync v2 changes can sync.',
      );
    }
    _v2CapabilityVerified = true;
  }

  static List<SyncLogRow> _orderOperations(List<SyncLogRow> source) {
    final operations = List<SyncLogRow>.of(source);
    final outgoing = <String, Set<String>>{
      for (final operation in operations) operation.operationId: <String>{},
    };
    final indegree = <String, int>{
      for (final operation in operations) operation.operationId: 0,
    };
    void before(SyncLogRow first, SyncLogRow second) {
      if (first.operationId == second.operationId) return;
      if (outgoing[first.operationId]!.add(second.operationId)) {
        indegree[second.operationId] = indegree[second.operationId]! + 1;
      }
    }

    for (var i = 0; i < operations.length; i++) {
      for (var j = i + 1; j < operations.length; j++) {
        final a = operations[i];
        final b = operations[j];
        if (a.entityTableName == b.entityTableName &&
            a.recordId == b.recordId) {
          final chronological = _operationChronology(a, b);
          before(chronological <= 0 ? a : b, chronological <= 0 ? b : a);
          continue;
        }
        final aDelete = a.operation == 'delete';
        final bDelete = b.operation == 'delete';
        if (aDelete != bDelete) continue;
        final rank = aDelete ? _deleteOrder : _upsertOrder;
        final comparison = (rank[a.entityTableName] ?? 100).compareTo(
          rank[b.entityTableName] ?? 100,
        );
        if (comparison < 0) before(a, b);
        if (comparison > 0) before(b, a);
      }
    }

    final inserts = <String, SyncLogRow>{
      for (final operation in operations)
        if (operation.operation == 'insert')
          '${operation.entityTableName}\u0000${operation.recordId}': operation,
    };
    for (final operation in operations.where(
      (item) => item.operation != 'delete',
    )) {
      final payload = _clientPayload(operation.payload);
      final dependencies = <String, String?>{
        'categories': payload['category_id']?.toString(),
        'recurring_rules': payload['recurring_rule_id']?.toString(),
        'tasks': payload['task_id']?.toString(),
        'tags': payload['tag_id']?.toString(),
      };
      for (final entry in dependencies.entries) {
        final id = entry.value;
        if (id == null || id.isEmpty) continue;
        final parent = inserts['${entry.key}\u0000$id'];
        if (parent != null) before(parent, operation);
      }
      if (operation.entityTableName == 'tasks') {
        for (final field in const [
          'rescheduled_from_id',
          'rescheduled_to_id',
        ]) {
          final id = payload[field]?.toString();
          final parent = id == null ? null : inserts['tasks\u0000$id'];
          if (parent != null) before(parent, operation);
        }
      }
    }

    final byId = {
      for (final operation in operations) operation.operationId: operation,
    };
    final ready =
        operations
            .where((operation) => indegree[operation.operationId] == 0)
            .toList()
          ..sort(_operationChronology);
    final ordered = <SyncLogRow>[];
    while (ready.isNotEmpty) {
      final next = ready.removeAt(0);
      ordered.add(next);
      for (final childId in outgoing[next.operationId]!) {
        indegree[childId] = indegree[childId]! - 1;
        if (indegree[childId] == 0) {
          ready.add(byId[childId]!);
          ready.sort(_operationChronology);
        }
      }
    }
    if (ordered.length != operations.length) {
      throw StateError(
        'Sync dependency cycle detected; operations remain durable.',
      );
    }
    return ordered;
  }

  static int _operationChronology(SyncLogRow a, SyncLogRow b) {
    final time = a.createdAt.compareTo(b.createdAt);
    return time == 0 ? a.operationId.compareTo(b.operationId) : time;
  }

  static const _upsertOrder = {
    'day_contexts': 0,
    'categories': 0,
    'tags': 1,
    'recurring_rules': 2,
    'tasks': 3,
    'task_templates': 4,
    'daily_reviews': 5,
    'weekly_reviews': 6,
    'subtasks': 7,
    'task_tags': 8,
    'timer_sessions': 9,
  };

  static const _deleteOrder = {
    'day_contexts': 0,
    'task_tags': 0,
    'timer_sessions': 1,
    'subtasks': 2,
    'daily_reviews': 3,
    'weekly_reviews': 4,
    'task_templates': 5,
    'tasks': 6,
    'recurring_rules': 7,
    'tags': 8,
    'categories': 9,
  };
}

class SyncRepairException implements Exception {
  final String message;

  const SyncRepairException(this.message);

  @override
  String toString() => message;
}

class _SyncAccountScopeChanged implements Exception {
  const _SyncAccountScopeChanged();
}

class _SyncUpgradeRequired implements Exception {
  final String message;

  const _SyncUpgradeRequired(this.message);
}

abstract interface class SyncRemoteGateway {
  Future<Object?> getCapabilities();

  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
  });

  Future<Object?> pullChanges({required int afterChangeId, required int limit});
}

class SupabaseSyncRemoteGateway implements SyncRemoteGateway {
  SupabaseSyncRemoteGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> getCapabilities() => _client.rpc('planner_sync_capabilities');

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
  }) => _client.rpc(
    'apply_sync_operation_v2',
    params: {
      'p_operation_id': operationId,
      'p_table_name': tableName,
      'p_record_id': recordId,
      'p_operation': operation,
      'p_expected_server_version': expectedServerVersion,
      'p_payload': payload,
      'p_payload_version': payloadVersion,
    },
  );

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) => _client.rpc(
    'pull_sync_changes',
    params: {'p_after_change_id': afterChangeId, 'p_limit': limit},
  );
}

String safeSyncError(Object error) {
  if (error is SyncValidationException) {
    return 'Invalid sync data: ${error.message}';
  }
  final message = error.toString().toLowerCase();
  if (message.contains('socket') ||
      message.contains('timeout') ||
      message.contains('network') ||
      message.contains('connection') ||
      message.contains('dns')) {
    return 'Network unavailable; retry scheduled.';
  }
  if (message.contains('401') ||
      message.contains('jwt') ||
      message.contains('auth')) {
    return 'Authentication expired; sign in again.';
  }
  return 'Sync request failed; retry scheduled.';
}

SyncFailure classifySyncFailure(Object error) {
  if (error is _SyncUpgradeRequired) {
    return SyncFailure(SyncFailureKind.permanent, error.message);
  }
  if (error is SyncValidationException) {
    return SyncFailure(SyncFailureKind.invalidData, safeSyncError(error));
  }
  if (error is FormatException || error is TypeError) {
    return SyncFailure(
      SyncFailureKind.invalidData,
      'Invalid sync data: ${error.toString().split(':').last.trim()}',
    );
  }
  final message = error.toString().toLowerCase();
  if (message.contains('401') ||
      message.contains('403') ||
      message.contains('jwt') ||
      message.contains('auth') ||
      message.contains('unauthorized')) {
    return const SyncFailure(
      SyncFailureKind.authentication,
      'Authentication expired; sign in again.',
    );
  }
  if (message.contains('invalid') ||
      message.contains('constraint') ||
      message.contains('identity') ||
      message.contains('foreign key') ||
      message.contains('permission denied') ||
      message.contains('unsupported')) {
    return SyncFailure(
      SyncFailureKind.permanent,
      'Sync action needs attention: ${safeSyncError(error)}',
    );
  }
  return SyncFailure(SyncFailureKind.retryable, safeSyncError(error));
}
