import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/sync_dao.dart';
import '../../../core/models/plan_title_change.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/json_map_utils.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../../core/utils/uuid.dart';
import '../../settings/data/backup_codec.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import '../../task_editor/domain/plan_title_history.dart';
import 'remote_apply.dart';
import '../domain/sync_models.dart';
import '../domain/sync_semantic_equality.dart';
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

  /// Most operations one push attempts. Held rows do not count.
  static const _pushBatchSize = 100;

  /// Retention window for acknowledged outbox rows.
  static const acknowledgedRetention = Duration(days: 30);

  /// Drained pull cycles a change may wait for a missing parent before it is
  /// quarantined.
  ///
  /// A parent that is anywhere in the feed arrives within the cycle that
  /// drains the feed, so most held changes resolve at the end of their first
  /// cycle. Later cycles cover parents that materialize out of band, such as
  /// a parent restored by the quarantine repair at the start of a later pull.
  /// Five cycles span several sync triggers (startup, resume, reconnect,
  /// periodic) before a child is given up as an orphan, yet a genuine orphan
  /// still surfaces within about half an hour of periodic sync. Only cycles
  /// that reach the end of the feed count; failed pulls do not.
  static const pendingParentCycleLimit = 5;
  static const _pendingParentPrefix = 'sync.pending_parent.';
  static const _legacyTitleHistoryTransitionDiagnostic =
      'Existing plan title events cannot be removed or changed';

  /// What the server's apply function raises (SQLSTATE 22023) for a table it
  /// does not know yet, and what an older app build records when it
  /// quarantines a pulled row of a table it does not know.
  static const _unsupportedSyncTableMessage = 'Unsupported sync table';
  static const _unsupportedRemoteTableDiagnostic =
      'Unsupported remote sync table';

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
    // A second entry point must not be able to fabricate a successful cycle:
    // nothing was sent or pulled, so the caller is told the attempt was
    // skipped instead of receiving an empty "success".
    if (_cycleRunning) return const SyncCycleResult.skipped();
    _cycleRunning = true;
    try {
      final pushFailure = await push();
      final pullFailure = await pull();
      if (pushFailure == null && pullFailure == null) {
        try {
          await _db.syncDao.pruneAcknowledgedOperations(
            olderThan: DateTime.now().toUtc().subtract(acknowledgedRetention),
          );
        } on Object {
          // Pruning is best-effort.
        }
        try {
          final last = DateTime.tryParse(
            await _db.syncDao.getSetting('sync.last_compaction_at') ?? '',
          );
          final now = DateTime.now().toUtc();
          if (last == null ||
              now.difference(last) >= const Duration(hours: 24)) {
            await _gateway.compactHistory();
            await _db.syncDao.setSetting(
              'sync.last_compaction_at',
              now.toIso8601String(),
            );
          }
        } on Object {
          // Compaction is best-effort server housekeeping.
        }
      }
      return SyncCycleResult(
        pushFailure: pushFailure,
        pullFailure: pullFailure,
      );
    } finally {
      _cycleRunning = false;
    }
  }

  Future<SyncFailure?> push({String? baselineToken}) async {
    try {
      _assertAccountScope();
      await _repairTitleHistoryPermanentOperations();
      await _requeueAuthenticationParkedOperations();
      await _requeueUpgradeParkedOperations();
    } catch (error) {
      return classifySyncFailure(error);
    }
    // One eligibility instant for every page, so rows that fail during this
    // push (and move to a later retry time) cannot shift the page offsets.
    final fetchedAt = DateTime.now().toUtc();
    SyncFailure? firstFailure;
    // Held rows stay eligible and keep their place at the front of the
    // outbox. They are paged past by offset instead of being allowed to fill
    // every batch, and only rows that are actually attempted use the budget.
    var budget = _pushBatchSize;
    var held = 0;
    // Set once the server answers "Unsupported sync table" for an experiment
    // table: its migration has not been applied yet, so every other operation
    // of those two tables waits for a later push (ED19).
    var experimentTablesHeld = false;
    while (budget > 0) {
      late final List<SyncLogRow> page;
      late final List<SyncLogRow> operations;
      try {
        page = await _db.syncDao.getRetryableOperations(
          fetchedAt,
          limit: _pushBatchSize,
          offset: held,
        );
        operations = _orderOperations(page);
      } catch (error) {
        return classifySyncFailure(error);
      }
      if (page.isEmpty) break;
      final heldBefore = held;
      final budgetBefore = budget;
      for (final queuedOperation in operations) {
        if (budget == 0) break;
        // The initial batch is only a scheduling snapshot. Acknowledging an
        // earlier operation rebases later rows in SQLite, so reload this
        // operation immediately before sending it instead of using a stale
        // expectedServerVersion captured at batch start.
        final operation = await _db.syncDao.getOperation(
          queuedOperation.operationId,
        );
        if (operation == null ||
            !const {
              'pending',
              'error',
              'in_flight',
            }.contains(operation.state)) {
          continue;
        }
        try {
          _assertAccountScope();
          // Leave the row exactly as queued (no attempt, no state change, same
          // operation ID) until what it depends on has been acknowledged.
          if (await _isHeldBehindPredecessor(operation)) {
            held++;
            continue;
          }
          if (experimentTablesHeld &&
              _isExperimentTable(operation.entityTableName)) {
            held++;
            continue;
          }
          budget--;
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
            baselineToken: baselineToken,
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
        } on _SyncUpgradeRequired catch (error) {
          // The backend, not this payload, is behind. The capability check runs
          // before the operation is marked in flight, so leave it queued as-is
          // and stop the batch; the next cycle checks capabilities again.
          return classifySyncFailure(error);
        } catch (error) {
          // A server without the experiments migration rejects the two new
          // tables with "Unsupported sync table". Nothing is wrong with the
          // payload, so the operation stays queued exactly as it was (no
          // attempt counted, not parked), the rest of those two tables waits
          // for the next push, and every other table keeps syncing. It is not
          // reported as a failure: the sync status shows pending work.
          if (_isExperimentTable(operation.entityTableName) &&
              '$error'.contains(_unsupportedSyncTableMessage)) {
            await _db.syncDao.releaseInFlight(
              operation.operationId,
              DateTime.now().toUtc(),
            );
            experimentTablesHeld = true;
            held++;
            continue;
          }
          final failure = classifySyncFailure(error);
          // An expired or revoked session says nothing about this payload, and
          // every later operation would be refused the same way. Return the
          // operation to the queue without counting an attempt and stop the
          // batch so a refresh or sign-in can resume it unchanged.
          if (failure.kind == SyncFailureKind.authentication) {
            await _db.syncDao.releaseInFlight(
              operation.operationId,
              DateTime.now().toUtc(),
            );
            return failure;
          }
          firstFailure ??= failure;
          final failureMessage = failure.message;
          if (failure.keepsOperationQueued) {
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
          // A fencing rejection is a protocol-level answer: this client no longer
          // owns the account's in-progress baseline, so no further operation from
          // this batch may be attempted.
          if (isInitialBaselineFencingFailure(failure)) return failure;
        }
      }
      if (page.length < _pushBatchSize) break;
      // Nothing on a full page was held or attempted, so every row left the
      // queue concurrently. Stop rather than risk spinning on such a page.
      if (held == heldBefore && budget == budgetBefore) break;
    }
    return firstFailure;
  }

  static bool _isExperimentTable(String table) =>
      table == 'experiments' || table == 'experiment_check_ins';

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

  /// Requeues operations that earlier builds parked for an authentication
  /// failure. Their payload was never judged invalid; a fresh failure is now
  /// released without parking.
  Future<void> _requeueAuthenticationParkedOperations() async {
    final parked = await _db.syncDao.getPermanentOperationsMatching(
      null,
      _authenticationExpiredMessage,
    );
    for (final operation in parked) {
      await _db.syncDao.retryPermanentOperation(
        operation.operationId,
        DateTime.now().toUtc(),
      );
    }
  }

  /// Requeues operations that earlier builds parked because the server lacked
  /// a Sync v2 capability, once the server verifies those capabilities.
  Future<void> _requeueUpgradeParkedOperations() async {
    final parked = [
      for (final diagnostic in const [
        _upgradeRequiredMessage,
        _capabilityUnavailableMessage,
      ])
        ...await _db.syncDao.getPermanentOperationsMatching(null, diagnostic),
    ];
    if (parked.isEmpty) return;
    try {
      await _ensureV2Capabilities();
    } on Object {
      // Still behind or unreachable: leave them parked until a later cycle.
      return;
    }
    for (final operation in parked) {
      await _db.syncDao.retryPermanentOperation(
        operation.operationId,
        DateTime.now().toUtc(),
      );
    }
  }

  /// Whether [operation] must wait for an earlier operation that has not been
  /// acknowledged. Durable outbox state is the only input, so the same rule
  /// covers a predecessor that failed earlier in this batch and one that was
  /// never fetched because it is backing off, parked, or past the batch limit.
  ///
  /// - An earlier operation for the same record that is still active (queued,
  ///   backing off, parked, in flight, or in conflict) holds it: sending it
  ///   first would compare against a server version that the earlier one has
  ///   not produced, which the server reports as a conflict.
  /// - For a non-delete, a parent whose insert has not reached the server holds
  ///   it: the server enforces the foreign key immediately. A child held
  ///   behind a parked parent insert waits until that parent is repaired, so it
  ///   is held-behind-parked rather than parked itself.
  Future<bool> _isHeldBehindPredecessor(SyncLogRow operation) async {
    final sameRecord = await _db.syncDao.getActiveOperationsForRecord(
      operation.entityTableName,
      operation.recordId,
    );
    if (sameRecord.any(
      (earlier) =>
          earlier.operationId != operation.operationId &&
          _operationChronology(earlier, operation) < 0,
    )) {
      return true;
    }
    if (operation.operation == 'delete') return false;
    for (final parent in _operationDependencies(
      operation,
      _clientPayload(operation.payload, operation.entityTableName),
    )) {
      if (await _db.syncDao.hasUnsentInsert(parent.table, parent.id)) {
        return true;
      }
    }
    return false;
  }

  /// Classifies the outstanding outbox with the same hold rules as push, for
  /// the first-sync completion check.
  ///
  /// Parked rows and conflicts wait for a user repair or decision rather than
  /// for the network. A row held behind one of them, directly or through a
  /// chain of held rows, waits for that same action: it is "held behind
  /// parked" (or "held behind conflict"), counted separately so it stays
  /// distinguishable from both the parked row and ordinary queued work.
  Future<SyncOutboxBacklog> outboxBacklog() async {
    final rows = (await _db.syncDao.getOutstandingOperations())
      ..sort(_operationChronology);
    String key(String table, String id) => '$table\u0000$id';
    final byRecord = <String, List<SyncLogRow>>{};
    final unsentInserts = <String, List<SyncLogRow>>{};
    final roots = <String, _BacklogRoot>{};
    for (final row in rows) {
      final recordKey = key(row.entityTableName, row.recordId);
      (byRecord[recordKey] ??= []).add(row);
      if (row.operation == 'insert' && row.state != 'conflict') {
        (unsentInserts[recordKey] ??= []).add(row);
      }
      if (row.state == 'conflict') {
        roots[row.operationId] = _BacklogRoot.conflict;
      } else if (_isParked(row)) {
        roots[row.operationId] = _BacklogRoot.parked;
      }
    }
    final parkedCount =
        roots.length - rows.where((row) => row.state == 'conflict').length;

    _BacklogRoot? blockedBy(SyncLogRow row) {
      for (final earlier in byRecord[key(row.entityTableName, row.recordId)]!) {
        if (_operationChronology(earlier, row) >= 0) break;
        final root = roots[earlier.operationId];
        if (root != null) return root;
      }
      if (row.operation == 'delete') return null;
      final Iterable<({String table, String id})> parents;
      try {
        parents = _operationDependencies(
          row,
          _clientPayload(row.payload, row.entityTableName),
        );
      } on Object {
        return null;
      }
      for (final parent in parents) {
        for (final insert
            in unsentInserts[key(parent.table, parent.id)] ??
                const <SyncLogRow>[]) {
          final root = roots[insert.operationId];
          if (root != null) return root;
        }
      }
      return null;
    }

    // Propagate until stable: a chain of held rows can be listed in any order
    // relative to the parked row or conflict it ultimately waits for.
    var changed = true;
    while (changed) {
      changed = false;
      for (final row in rows) {
        if (roots.containsKey(row.operationId)) continue;
        final root = blockedBy(row);
        if (root == null) continue;
        roots[row.operationId] = root == _BacklogRoot.conflict
            ? _BacklogRoot.heldBehindConflict
            : _BacklogRoot.heldBehindParked;
        changed = true;
      }
    }

    var queued = 0;
    var heldBehindParked = 0;
    var heldBehindConflict = 0;
    String? queuedError;
    for (final row in rows) {
      switch (roots[row.operationId]) {
        case null:
          queued++;
          queuedError ??= row.lastError;
        case _BacklogRoot.heldBehindParked:
          heldBehindParked++;
        case _BacklogRoot.heldBehindConflict:
          heldBehindConflict++;
        case _BacklogRoot.parked || _BacklogRoot.conflict:
          break;
      }
    }
    return SyncOutboxBacklog(
      queued: queued,
      parked: parkedCount,
      heldBehindParked: heldBehindParked,
      heldBehindConflict: heldBehindConflict,
      queuedError: queuedError,
    );
  }

  static bool _isParked(SyncLogRow row) =>
      row.state == 'error' &&
      (row.nextAttemptAt?.isAtSameMomentAs(SyncDao.permanentRetryAt) ??
          false) &&
      (row.lastError?.startsWith(SyncDao.permanentErrorPrefix) ?? false);

  /// Pulls remote changes from the durable cursor.
  ///
  /// [beforePageCommit] runs inside the transaction that applies one coalesced
  /// page, immediately before that page's rows and cursor advance are written.
  /// Throwing from it rolls the whole page back, which the Phase G remote-first
  /// restore uses to stop the moment meaningful local work appears.
  Future<SyncFailure?> pull({
    int limit = 200,
    Future<void> Function()? beforePageCommit,
  }) async {
    try {
      _assertAccountScope();
      await _repairTitleHistoryQuarantine();
      await _repairExperimentQuarantine();
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
      final endOfFeed = rawChanges.length < pageSize;
      if (received.isEmpty) {
        if (maxChangeId > cursor) {
          await _db.syncDao.advanceCursor(
            _accountId,
            maxChangeId,
            DateTime.now().toUtc(),
          );
        }
        if (endOfFeed && await _hasPendingParents()) {
          // The feed drained without a page to settle the held changes in,
          // so settle them on their own: retry, then count the cycle.
          final changedTables = <String>{};
          await _commitPage(
            const [],
            const [],
            nextCursor: maxChangeId,
            batchValidated: true,
            endOfCycle: true,
            beforePageCommit: beforePageCommit,
            changedTables: changedTables,
            onInvalid: (failure) => invalidFailure ??= failure,
          );
          _notifyDomainStreams(changedTables);
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
      await _commitPage(
        changes,
        received,
        nextCursor: nextCursor,
        batchValidated: batchValidated,
        // The last page of a drained feed also ends the pull cycle.
        endOfCycle: endOfFeed,
        beforePageCommit: beforePageCommit,
        changedTables: changedTables,
        onInvalid: (failure) => invalidFailure ??= failure,
      );
      _notifyDomainStreams(changedTables);
      cursor = nextCursor;
      if (endOfFeed) return invalidFailure;
    }
  }

  /// Runs [_applyPage] tolerantly, then once strictly if a tolerated
  /// reciprocal partner did not materialize.
  Future<void> _commitPage(
    List<SyncRemoteChange> changes,
    List<SyncRemoteChange> received, {
    required int nextCursor,
    required bool batchValidated,
    required bool endOfCycle,
    required Future<void> Function()? beforePageCommit,
    required Set<String> changedTables,
    required void Function(SyncFailure) onInvalid,
  }) async {
    final affectedActualTaskIds = <String>{};
    Future<void> applyPage({required bool strictLinks}) => _applyPage(
      changes,
      received,
      nextCursor: nextCursor,
      strictLinks: strictLinks,
      batchValidated: batchValidated,
      endOfCycle: endOfCycle,
      beforePageCommit: beforePageCommit,
      changedTables: changedTables,
      affectedActualTaskIds: affectedActualTaskIds,
      onInvalid: onInvalid,
    );
    try {
      await applyPage(strictLinks: false);
    } on _PageForeignKeyViolation {
      // A tolerated reciprocal partner did not materialize. The page rolled
      // back as a whole; re-run it once requiring every parent up front.
      changedTables.clear();
      affectedActualTaskIds.clear();
      await applyPage(strictLinks: true);
    }
  }

  /// Applies one coalesced pull page and advances the cursor atomically.
  /// Unless [strictLinks] is set, a task may reference its reciprocal
  /// reschedule partner from the same page before that partner exists; the
  /// page then fails with [_PageForeignKeyViolation] if the partner was
  /// quarantined, so the caller can re-run it strictly.
  ///
  /// A change whose parent has not arrived is held in the pending-parent
  /// queue instead of being quarantined, and the queue is retried against
  /// the page's result before the cursor advances. With [endOfCycle] the
  /// retry also counts a drained pull cycle for every change still held.
  Future<void> _applyPage(
    List<SyncRemoteChange> changes,
    List<SyncRemoteChange> received, {
    required int nextCursor,
    required bool strictLinks,
    required bool batchValidated,
    required bool endOfCycle,
    required Future<void> Function()? beforePageCommit,
    required Set<String> changedTables,
    required Set<String> affectedActualTaskIds,
    required void Function(SyncFailure) onInvalid,
  }) {
    return _db.syncDao.runWithoutOutbound(() async {
      var toleratedAny = false;
      // A valid reschedule pair stores reciprocal self-references. SQLite
      // must validate those foreign keys after both task snapshots exist.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      // Phase G: the restore may only continue while this local database is
      // still free of user-authored Planner work. The check runs inside this
      // page transaction, so a new local edit aborts the page atomically:
      // no remote rows and no cursor advance are committed after it.
      if (beforePageCommit != null) await beforePageCommit();
      // Loaded inside the page transaction, so a strict re-run starts again
      // from the committed queue.
      final pending = await _loadPendingParents();
      final rejected = await _quarantinedRecordKeys();
      // Coalescing is correct for the materialized row, but it must not
      // hide an acknowledgement that precedes a newer feed entry for the
      // same record. Retire/rebase every matching local operation first;
      // the newest coalesced change then decides the visible row state.
      for (final change in changes) {
        // A newer feed entry decides the record, exactly as coalescing does
        // within a page, so it supersedes an older held change.
        final superseded = pending.remove(_recordKey(change));
        if (superseded != null) {
          await _db.syncDao.deleteSetting(superseded.settingKey);
        }
        try {
          _assertAccountScope();
          // Keep a malformed relationship from aborting the whole page.
          // The savepoint rolls back any metadata/conflict work for this
          // one change, while valid siblings can still commit atomically
          // with the cursor advancement below.
          await _db.transaction(() async {
            _assertAccountScope();
            await _collectAffectedActualTaskIds(change, affectedActualTaskIds);
            for (final acknowledgement in received) {
              if (acknowledgement.tableName == change.tableName &&
                  acknowledgement.recordId == change.recordId) {
                await _acknowledgePulledOperation(acknowledgement);
              }
            }
            final materialized = await _applyPulledChange(
              change,
              skipHistoryValidation: batchValidated,
            );
            if (materialized) {
              // Deferred foreign keys are only checked at COMMIT, which a
              // savepoint cannot catch. Check parents here so an orphan is
              // quarantined alone instead of failing the whole page.
              final tolerated = strictLinks
                  ? const <String>{}
                  : {
                      for (final partner in changes)
                        if (_isReciprocalReschedulePair(change, partner))
                          '${partner.tableName}\u0000${partner.recordId}',
                    };
              await _assertParentsMaterialized(change, tolerated: tolerated);
              if (tolerated.isNotEmpty) toleratedAny = true;
            }
            changedTables.add(change.tableName);
          });
        } on _SyncAccountScopeChanged {
          rethrow;
        } catch (error) {
          if (error is _MissingSyncParent &&
              !_isRejectedParent(error.parentKey, pending, rejected)) {
            // The parent may still arrive in a later page or cycle.
            final entry = _PendingParent(
              settingKey: '$_pendingParentPrefix$_accountId.${change.changeId}',
              change: change,
              parentKey: error.parentKey,
              cycles: 0,
            );
            pending[_recordKey(change)] = entry;
            await _writePendingParent(entry);
            continue;
          }
          await _quarantinePulledChange(
            change,
            'Rejected remote ${change.tableName}/${change.recordId}: '
            '${safeSyncError(error)}',
            rejected: rejected,
            onInvalid: onInvalid,
          );
        }
      }
      if (await _retryPendingParents(
        pending,
        rejected,
        strictLinks: strictLinks,
        endOfCycle: endOfCycle,
        changedTables: changedTables,
        affectedActualTaskIds: affectedActualTaskIds,
        onInvalid: onInvalid,
      )) {
        toleratedAny = true;
      }
      if (affectedActualTaskIds.isNotEmpty) {
        final actualDuration = TaskActualDurationService(_db);
        for (final taskId in affectedActualTaskIds) {
          await actualDuration.recomputeTaskInTransaction(taskId);
        }
        changedTables.add('tasks');
      }
      if (toleratedAny) {
        final violations = await _db
            .customSelect('PRAGMA foreign_key_check(tasks)')
            .get();
        if (violations.isNotEmpty) throw const _PageForeignKeyViolation();
      }
      _assertAccountScope();
      await _db.syncDao.advanceCursor(
        _accountId,
        nextCursor,
        DateTime.now().toUtc(),
      );
    });
  }

  /// Throws [_MissingSyncParent] when a dependency of [change] other than one
  /// in [tolerated] has no local row, so the caller's savepoint rolls
  /// [change] back and the caller holds or quarantines it.
  Future<void> _assertParentsMaterialized(
    SyncRemoteChange change, {
    required Set<String> tolerated,
  }) async {
    for (final key in _changeDependencies(change)) {
      if (tolerated.contains(key)) continue;
      if (!await _parentExists(key)) {
        final split = key.indexOf('\u0000');
        throw _MissingSyncParent(
          key,
          'Remote ${change.tableName}/${change.recordId} references missing '
          '${key.substring(0, split)}/${key.substring(split + 1)}',
        );
      }
    }
  }

  /// [key] is a `table\u0000id` dependency key from [_changeDependencies].
  Future<bool> _parentExists(String key) async {
    final split = key.indexOf('\u0000');
    final row = await _db
        .customSelect(
          'SELECT 1 FROM ${key.substring(0, split)} WHERE id = ? LIMIT 1',
          variables: [Variable<String>(key.substring(split + 1))],
        )
        .getSingleOrNull();
    return row != null;
  }

  static String _recordKey(SyncRemoteChange change) =>
      '${change.tableName}\u0000${change.recordId}';

  /// A missing parent whose own feed change was quarantined (and is not
  /// itself waiting for a parent) was rejected, not delayed: its children
  /// are quarantined with it instead of waiting.
  static bool _isRejectedParent(
    String parentKey,
    Map<String, _PendingParent> pending,
    Set<String> rejected,
  ) => rejected.contains(parentKey) && !pending.containsKey(parentKey);

  Future<void> _quarantinePulledChange(
    SyncRemoteChange change,
    String diagnostic, {
    required Set<String> rejected,
    required void Function(SyncFailure) onInvalid,
  }) async {
    onInvalid(SyncFailure(SyncFailureKind.invalidData, diagnostic));
    rejected.add(_recordKey(change));
    await _db.syncDao.recordQuarantinedChange(
      _accountId,
      change.changeId,
      diagnostic,
      rawChange: _rawChangeJson(change),
    );
  }

  static Map<String, Object?> _rawChangeJson(SyncRemoteChange change) => {
    'change_id': change.changeId,
    'operation_id': change.operationId,
    'table_name': change.tableName,
    'record_id': change.recordId,
    'operation': change.operation,
    'server_version': change.serverVersion,
    'server_timestamp': change.serverTimestamp.toIso8601String(),
    'payload': change.payload,
  };

  Future<bool> _hasPendingParents() async =>
      (await _db.syncDao.readSettingsWithPrefix(
        '$_pendingParentPrefix$_accountId.',
      )).isNotEmpty;

  /// The durable pending-parent queue, one entry per record (newest wins).
  Future<Map<String, _PendingParent>> _loadPendingParents() async {
    final settings = await _db.syncDao.readSettingsWithPrefix(
      '$_pendingParentPrefix$_accountId.',
    );
    final pending = <String, _PendingParent>{};
    for (final MapEntry(:key, :value) in settings.entries) {
      final _PendingParent entry;
      try {
        final record = jsonDecode(value) as Map;
        final parent = record['missing_parent'] as Map;
        entry = _PendingParent(
          settingKey: key,
          change: SyncRemoteChange.fromJson(record['raw_change']),
          parentKey: '${parent['table']}\u0000${parent['id']}',
          cycles: (record['cycles'] as num).toInt(),
        );
      } on Object {
        // Unreadable entries stay reviewable as quarantine records.
        await _db.syncDao.deleteSetting(key);
        await _db.syncDao.recordQuarantinedChange(
          _accountId,
          int.tryParse(key.substring(key.lastIndexOf('.') + 1)) ?? 0,
          'Unreadable pending-parent record',
          rawChange: value,
        );
        continue;
      }
      final recordKey = _recordKey(entry.change);
      final existing = pending[recordKey];
      if (existing != null &&
          existing.change.changeId > entry.change.changeId) {
        await _db.syncDao.deleteSetting(entry.settingKey);
        continue;
      }
      if (existing != null) {
        await _db.syncDao.deleteSetting(existing.settingKey);
      }
      pending[recordKey] = entry;
    }
    return pending;
  }

  Future<void> _writePendingParent(_PendingParent entry) {
    final split = entry.parentKey.indexOf('\u0000');
    return _db.syncDao.setSetting(
      entry.settingKey,
      jsonEncode({
        'account_id': _accountId,
        'change_id': entry.change.changeId,
        'missing_parent': {
          'table': entry.parentKey.substring(0, split),
          'id': entry.parentKey.substring(split + 1),
        },
        'cycles': entry.cycles,
        'raw_change': _rawChangeJson(entry.change),
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  /// Record keys whose quarantined feed change named them.
  Future<Set<String>> _quarantinedRecordKeys() async {
    final settings = await _db.syncDao.readSettingsWithPrefix(
      'sync.quarantine.$_accountId.',
    );
    final keys = <String>{};
    for (final value in settings.values) {
      try {
        final record = jsonDecode(value);
        final raw = record is Map ? record['raw_change'] : null;
        if (raw is! Map) continue;
        final table = raw['table_name'];
        final id = raw['record_id'];
        if (table is String && id != null) keys.add('$table\u0000$id');
      } on Object {
        continue;
      }
    }
    return keys;
  }

  /// Retries held changes until a pass makes no progress, so a chain of
  /// held parents and children resolves in one call. With [endOfCycle],
  /// every change still held afterwards has one more drained cycle counted
  /// and is quarantined once it reaches [pendingParentCycleLimit]. Returns
  /// whether a reciprocal reschedule partner was tolerated, so the caller
  /// verifies task foreign keys before committing.
  Future<bool> _retryPendingParents(
    Map<String, _PendingParent> pending,
    Set<String> rejected, {
    required bool strictLinks,
    required bool endOfCycle,
    required Set<String> changedTables,
    required Set<String> affectedActualTaskIds,
    required void Function(SyncFailure) onInvalid,
  }) async {
    var toleratedAny = false;
    Future<void> settle(_PendingParent entry) async {
      pending.remove(_recordKey(entry.change));
      await _db.syncDao.deleteSetting(entry.settingKey);
    }

    String diagnostic(_PendingParent entry, Object error) =>
        'Rejected remote ${entry.change.tableName}/${entry.change.recordId}: '
        '${safeSyncError(error)}';

    var progressed = true;
    while (progressed && pending.isNotEmpty) {
      progressed = false;
      final ordered = pending.values.toList()
        ..sort((a, b) => a.change.changeId.compareTo(b.change.changeId));
      for (final entry in ordered) {
        _assertAccountScope();
        final change = entry.change;
        if (_isRejectedParent(entry.parentKey, pending, rejected)) {
          await settle(entry);
          await _quarantinePulledChange(
            change,
            diagnostic(
              entry,
              _MissingSyncParent(
                entry.parentKey,
                'Remote ${change.tableName}/${change.recordId} references '
                'rejected ${entry.parentKey.replaceFirst('\u0000', '/')}',
              ),
            ),
            rejected: rejected,
            onInvalid: onInvalid,
          );
          progressed = true;
          continue;
        }
        // A held reciprocal reschedule partner is tolerated exactly as a
        // partner in the same page is; the caller's foreign-key check and
        // strict re-run cover a partner that then fails to materialize.
        final tolerated = strictLinks
            ? const <String>{}
            : {
                for (final other in pending.values)
                  if (!identical(other, entry) &&
                      _isReciprocalReschedulePair(change, other.change))
                    _recordKey(other.change),
              };
        if (!tolerated.contains(entry.parentKey) &&
            !await _parentExists(entry.parentKey)) {
          continue;
        }
        try {
          await _db.transaction(() async {
            _assertAccountScope();
            // Never move a record back to an older server version than one
            // this device already holds.
            if (await _hasLocalVersionAtLeast(change)) return;
            await _collectAffectedActualTaskIds(change, affectedActualTaskIds);
            if (await _applyPulledChange(change)) {
              await _assertParentsMaterialized(change, tolerated: tolerated);
              if (tolerated.isNotEmpty) toleratedAny = true;
            }
            changedTables.add(change.tableName);
          });
          await settle(entry);
          progressed = true;
        } on _SyncAccountScopeChanged {
          rethrow;
        } catch (error) {
          if (error is _MissingSyncParent &&
              !_isRejectedParent(error.parentKey, pending, rejected)) {
            // Another parent of the same change is still missing.
            if (error.parentKey != entry.parentKey) {
              entry.parentKey = error.parentKey;
              await _writePendingParent(entry);
            }
            continue;
          }
          await settle(entry);
          await _quarantinePulledChange(
            change,
            diagnostic(entry, error),
            rejected: rejected,
            onInvalid: onInvalid,
          );
          progressed = true;
        }
      }
    }
    if (!endOfCycle) return toleratedAny;
    for (final entry in pending.values.toList()) {
      entry.cycles++;
      if (entry.cycles < pendingParentCycleLimit) {
        await _writePendingParent(entry);
        continue;
      }
      await settle(entry);
      final change = entry.change;
      await _quarantinePulledChange(
        change,
        diagnostic(
          entry,
          _MissingSyncParent(
            entry.parentKey,
            'Remote ${change.tableName}/${change.recordId} references missing '
            '${entry.parentKey.replaceFirst('\u0000', '/')}, which did not '
            'arrive within $pendingParentCycleLimit pull cycles',
          ),
        ),
        rejected: rejected,
        onInvalid: onInvalid,
      );
    }
    return toleratedAny;
  }

  Future<bool> _hasLocalVersionAtLeast(SyncRemoteChange change) async {
    if (!SyncPayloadValidator.tables.contains(change.tableName)) return false;
    final QueryRow? row;
    if (change.tableName == 'task_tags') {
      final pieces = change.recordId.split(':');
      if (pieces.length != 2) return false;
      row = await _db
          .customSelect(
            'SELECT server_version FROM task_tags '
            'WHERE task_id = ? AND tag_id = ?',
            variables: [
              Variable<String>(pieces[0]),
              Variable<String>(pieces[1]),
            ],
          )
          .getSingleOrNull();
    } else {
      row = await _db
          .customSelect(
            'SELECT server_version FROM ${change.tableName} WHERE id = ?',
            variables: [Variable<String>(change.recordId)],
          )
          .getSingleOrNull();
    }
    final version = row?.readNullable<int>('server_version');
    return version != null && version >= change.serverVersion;
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

  /// An older build quarantines pulled rows of the two experiment tables with
  /// "Unsupported remote sync table". Once this build knows the tables it
  /// re-applies those retained records (ED21), parents first and lower change
  /// ids first. A record is skipped while its parent row is missing, while a
  /// local operation is active for it, or when the local row is already at
  /// least as new. Errors leave the record in place; the cursor is untouched.
  Future<void> _repairExperimentQuarantine() async {
    final retained = await _db.syncDao.getQuarantinedChanges(_accountId);
    final candidates = <({String settingKey, SyncRemoteChange change})>[];
    for (final setting in retained) {
      try {
        final decoded = jsonDecode(setting.value);
        if (decoded is! Map) continue;
        final record = Map<String, dynamic>.from(decoded);
        if (record['account_id']?.toString() != _accountId ||
            !record['diagnostic'].toString().contains(
              _unsupportedRemoteTableDiagnostic,
            )) {
          continue;
        }
        final raw = record['raw_change'];
        if (raw is! Map) continue;
        final change = SyncRemoteChange.fromJson(raw);
        if (!_isExperimentTable(change.tableName)) continue;
        candidates.add((settingKey: setting.key, change: change));
      } on Object {
        // Unreadable records stay available for explicit review.
      }
    }
    if (candidates.isEmpty) return;
    candidates.sort((a, b) {
      final table = (a.change.tableName == 'experiments' ? 0 : 1).compareTo(
        b.change.tableName == 'experiments' ? 0 : 1,
      );
      return table != 0
          ? table
          : a.change.changeId.compareTo(b.change.changeId);
    });
    final changedTables = <String>{};
    for (final candidate in candidates) {
      _assertAccountScope();
      final change = candidate.change;
      try {
        final localVersion = await _localServerVersion(change);
        if (localVersion != null && localVersion >= change.serverVersion) {
          continue;
        }
        final active = await _db.syncDao.getActiveOperationsForRecord(
          change.tableName,
          change.recordId,
        );
        if (active.isNotEmpty) continue;
        var parentsPresent = true;
        for (final parent in _changeDependencies(change)) {
          if (!await _parentExists(parent)) parentsPresent = false;
        }
        if (!parentsPresent) continue;
        await _applier.validate(
          change,
          checkMaterializedState: false,
          checkHistoryLinks: false,
        );
        var repaired = false;
        await _db.syncDao.runWithoutOutbound(() async {
          _assertAccountScope();
          if (await _db.syncDao.getSetting(candidate.settingKey) == null) {
            return;
          }
          final stillActive = await _db.syncDao.getActiveOperationsForRecord(
            change.tableName,
            change.recordId,
          );
          if (stillActive.isNotEmpty) return;
          await _applyPulledChange(change);
          await _db.syncDao.deleteSetting(candidate.settingKey);
          repaired = true;
        });
        if (repaired) changedTables.add(change.tableName);
      } on _SyncAccountScopeChanged {
        rethrow;
      } on Object {
        // The retained record stays for a later pull or explicit review.
      }
    }
    _notifyDomainStreams(changedTables);
  }

  Future<int?> _localServerVersion(SyncRemoteChange change) async {
    final row = await _db
        .customSelect(
          'SELECT server_version FROM ${change.tableName} WHERE id = ?',
          variables: [Variable<String>(change.recordId)],
        )
        .getSingleOrNull();
    return row?.readNullable<int>('server_version');
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

  /// Returns true when [change] was materialized through the applier, false
  /// when only remote metadata or a conflict was recorded.
  Future<bool> _applyPulledChange(
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
        return true;
      }
      await _setRemoteMetadata(
        change.tableName,
        change.recordId,
        change.serverVersion,
        pending: newer.isNotEmpty,
        conflict: newer.any((operation) => operation.state == 'conflict'),
      );
      return false;
    }
    if (active.isNotEmpty &&
        active.every((op) => op.state == 'pending' || op.state == 'error') &&
        !active.any(_isParked) &&
        semanticallyEqualSnapshots(
          change.tableName,
          _clientPayload(active.last.payload, change.tableName),
          change.payload,
        )) {
      final now = DateTime.now().toUtc();
      for (final op in active) {
        await _db.syncDao.markAcknowledged(op.operationId, now);
      }
      await _applier.apply(change, checkHistoryLinks: !skipHistoryValidation);
      return true;
    }
    if (active.isNotEmpty) {
      await _savePulledConflict(active.last, change);
      return false;
    }
    await _applier.apply(change, checkHistoryLinks: !skipHistoryValidation);
    return true;
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
    final actualVersion = acknowledgement.actualServerVersion;
    final remoteSnapshot = acknowledgement.remoteSnapshot;
    if (actualVersion != null &&
        remoteSnapshot != null &&
        semanticallyEqualSnapshots(
          operation.entityTableName,
          _clientPayload(operation.payload, operation.entityTableName),
          remoteSnapshot,
        )) {
      await _acknowledgeEquivalent(operation, actualVersion);
      return;
    }
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

  /// The server already holds exactly this operation's intent (for example a
  /// deterministic occurrence materialized on two devices). Adopt the server
  /// version instead of asking the user to choose between identical states.
  Future<void> _acknowledgeEquivalent(
    SyncLogRow operation,
    int serverVersion,
  ) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.syncDao.markAcknowledged(operation.operationId, now);
      await _db.syncDao.rebasePendingOperations(
        operation.entityTableName,
        operation.recordId,
        serverVersion,
        now,
      );
      final remaining = await _db.syncDao.getActiveOperationsForRecord(
        operation.entityTableName,
        operation.recordId,
      );
      await _setRemoteMetadata(
        operation.entityTableName,
        operation.recordId,
        serverVersion,
        pending: remaining.isNotEmpty,
        conflict: remaining.any((entry) => entry.state == 'conflict'),
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

  /// The newest local intent is the last enqueued operation.
  static SyncLogRow _newestOperation(List<SyncLogRow> operations) {
    var newest = operations.first;
    for (final candidate in operations.skip(1)) {
      if (SyncDao.compareOutboxOrder(candidate, newest) > 0) {
        newest = candidate;
      }
    }
    return newest;
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
      if (conflict.entityTableName == 'recurring_rules') {
        final remote = Map<String, dynamic>.from(
          jsonDecode(conflict.remoteSnapshot) as Map,
        );
        local['exceptions_json'] = _unionExceptions(
          local['exceptions_json'],
          remote['exceptions_json'],
        );
        await _writeRuleExceptions(
          conflict.recordId,
          local['exceptions_json'] as String,
          now,
        );
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
      Map<String, dynamic>? localRuleSnapshot;
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
        if (_sameTitleHistory(historyPreservingPayload, remotePayload)) {
          historyPreservingPayload = null;
        }
      }
      if (conflict.entityTableName == 'recurring_rules' &&
          actualVersion != null) {
        final active = await _db.syncDao.getActiveOperationsForRecord(
          conflict.entityTableName,
          conflict.recordId,
        );
        final newerLocal = active
            .where((entry) => entry.state != 'conflict')
            .toList(growable: false);
        localRuleSnapshot = Map<String, dynamic>.from(
          jsonDecode(
            newerLocal.isEmpty
                ? conflict.localSnapshot
                : _newestOperation(newerLocal).payload,
          ) as Map,
        );
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
      final ruleSnapshot = localRuleSnapshot;
      if (ruleSnapshot != null &&
          remotePayload['deleted'] != true &&
          remotePayload['deleted_at'] == null) {
        final merged = _unionExceptions(
          remotePayload['exceptions_json'],
          ruleSnapshot['exceptions_json'],
        );
        if (merged !=
            _unionExceptions(remotePayload['exceptions_json'], null)) {
          await _writeRuleExceptions(conflict.recordId, merged, now);
          final followUp = Map<String, dynamic>.from(remotePayload)
            ..remove('server_version')
            ..remove('user_id')
            ..['exceptions_json'] = merged
            ..['updated_at'] = now.toIso8601String()
            ..['_planner_payload_version'] = 2;
          await _db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: generateUuidV7(),
              entityTableName: 'recurring_rules',
              recordId: conflict.recordId,
              operation: 'update',
              expectedServerVersion: Value(actualVersion),
              payload: jsonEncode(followUp),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
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

  /// True when the union added no locally unique title event and kept the
  /// remote display pointer, so applying the remote row is the whole answer.
  static bool _sameTitleHistory(
    Map<String, dynamic> merged,
    Map<String, dynamic> remote,
  ) {
    Set<String> events(Object? raw) => raw is String
        ? PlanTitleHistory.decodeJson(raw)
              .map((event) => jsonEncode(event.toJson()))
              .toSet()
        : <String>{};
    final mergedEvents = events(merged['plan_title_history_json']);
    final remoteEvents = events(remote['plan_title_history_json']);
    return mergedEvents.length == remoteEvents.length &&
        mergedEvents.containsAll(remoteEvents) &&
        merged['display_plan_change_id']?.toString() ==
            remote['display_plan_change_id']?.toString();
  }

  static String _unionExceptions(Object? a, Object? b) {
    final dates = <String>{
      ...JsonListUtils.decode(a is String ? a : null),
      ...JsonListUtils.decode(b is String ? b : null),
    }.toList()..sort();
    return JsonListUtils.encode(dates);
  }

  Future<void> _writeRuleExceptions(
    String ruleId,
    String exceptionsJson,
    DateTime now,
  ) => _db.customUpdate(
    'UPDATE recurring_rules SET exceptions_json = ?, updated_at = ?, '
    'sync_status = 1, revision = revision + 1 WHERE id = ?',
    variables: [
      Variable<String>(exceptionsJson),
      Variable<String>(now.toIso8601String()),
      Variable<String>(ruleId),
    ],
    updates: {_db.recurringRules},
  );

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

    void jsonMap(String backupKey, String syncKey) {
      final value = result.remove(backupKey);
      result[syncKey] = JsonMapUtils.encode(
        value is Map
            ? {
                for (final entry in value.entries)
                  '${entry.key}': '${entry.value}',
              }
            : const <String, String>{},
      );
    }

    switch (table) {
      case 'tasks':
        integerFlag('is_inbox');
        integerFlag('manual_actual_set');
        jsonList('plan_title_history', 'plan_title_history_json');
        jsonMap('plan_change_reasons', 'plan_change_reasons_json');
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
        jsonMap('task_reasons', 'task_reasons_json');
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
      'experiments': _db.experiments,
      'experiment_check_ins': _db.experimentCheckIns,
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
      'experiments',
      'experiment_check_ins',
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
        final taskTagId = value('tag_id');
        if (taskTagId != null && taskTagId.isNotEmpty) {
          yield key('tags', taskTagId);
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
      case 'experiments':
        final tagId = value('tag_id');
        if (tagId != null && tagId.isNotEmpty) {
          yield key('tags', tagId);
        }
      case 'experiment_check_ins':
        final experimentId = value('experiment_id');
        if (experimentId != null && experimentId.isNotEmpty) {
          yield key('experiments', experimentId);
        }
    }
  }

  static Map<String, dynamic> _clientPayload(String encoded, String table) {
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
    if (table == 'tasks') {
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
    final payload = _clientPayload(
      operation.payload,
      operation.entityTableName,
    );
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
      throw const _SyncUpgradeRequired(_capabilityUnavailableMessage);
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
      throw const _SyncUpgradeRequired(_upgradeRequiredMessage);
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
      final payload = _clientPayload(
        operation.payload,
        operation.entityTableName,
      );
      for (final dependency in _operationDependencies(operation, payload)) {
        final parent = inserts['${dependency.table}\u0000${dependency.id}'];
        if (parent != null) before(parent, operation);
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

  /// Parent records that [operation]'s payload references by foreign key. A
  /// reference to the operation's own record is not a dependency.
  static Iterable<({String table, String id})> _operationDependencies(
    SyncLogRow operation,
    Map<String, dynamic> payload,
  ) sync* {
    const fields = {
      'category_id': 'categories',
      'recurring_rule_id': 'recurring_rules',
      'task_id': 'tasks',
      'tag_id': 'tags',
      'experiment_id': 'experiments',
    };
    final references = <({String table, String? id})>[
      for (final entry in fields.entries)
        (table: entry.value, id: payload[entry.key]?.toString()),
      if (operation.entityTableName == 'tasks')
        for (final field in const ['rescheduled_from_id', 'rescheduled_to_id'])
          (table: 'tasks', id: payload[field]?.toString()),
    ];
    for (final reference in references) {
      final id = reference.id;
      if (id == null || id.isEmpty) continue;
      if (reference.table == operation.entityTableName &&
          id == operation.recordId) {
        continue;
      }
      yield (table: reference.table, id: id);
    }
  }

  static int _operationChronology(SyncLogRow a, SyncLogRow b) =>
      SyncDao.compareOutboxOrder(a, b);

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
    'experiments': 10,
    'experiment_check_ins': 11,
  };

  static const _deleteOrder = {
    'day_contexts': 0,
    'task_tags': 0,
    'experiment_check_ins': 0,
    'experiments': 1,
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

/// Outstanding outbox rows grouped by what they are waiting for.
class SyncOutboxBacklog {
  const SyncOutboxBacklog({
    required this.queued,
    required this.parked,
    required this.heldBehindParked,
    required this.heldBehindConflict,
    this.queuedError,
  });

  /// Not acknowledged and waiting only on push, retry backoff, or an earlier
  /// row that is itself still queued.
  final int queued;

  /// Parked for an explicit repair.
  final int parked;

  /// Queued but held behind a parked row until it is repaired.
  final int heldBehindParked;

  /// Queued but held behind a conflict until it is resolved.
  final int heldBehindConflict;

  /// Diagnostic of the oldest queued row that failed and is backing off.
  final String? queuedError;
}

enum _BacklogRoot { parked, conflict, heldBehindParked, heldBehindConflict }

class SyncRepairException implements Exception {
  final String message;

  const SyncRepairException(this.message);

  @override
  String toString() => message;
}

class _SyncAccountScopeChanged implements Exception {
  const _SyncAccountScopeChanged();
}

class _PageForeignKeyViolation implements Exception {
  const _PageForeignKeyViolation();
}

/// A pulled change references a parent with no local row. [parentKey] is the
/// `table\u0000id` dependency key.
class _MissingSyncParent extends SyncValidationException {
  const _MissingSyncParent(this.parentKey, super.message);

  final String parentKey;
}

/// One held change in the durable pending-parent queue.
class _PendingParent {
  _PendingParent({
    required this.settingKey,
    required this.change,
    required this.parentKey,
    required this.cycles,
  });

  final String settingKey;
  final SyncRemoteChange change;
  String parentKey;
  int cycles;
}

const _upgradeRequiredMessage =
    'Server upgrade required before Sync v2 changes can sync.';
const _capabilityUnavailableMessage =
    'Server capability response is unavailable; upgrade sync before retrying.';

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
    String? baselineToken,
  });

  Future<Object?> pullChanges({required int afterChangeId, required int limit});

  Future<Object?> compactHistory();
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
    String? baselineToken,
  }) => baselineToken == null
      ? _client.rpc(
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
        )
      // Phase G: during the initial baseline the server requires the fenced
      // entry point, which verifies (and renews) the caller's claim. Ordinary
      // synchronization after the baseline keeps using the v2 RPC unchanged.
      : _client.rpc(
          'apply_sync_operation_v3',
          params: {
            'p_operation_id': operationId,
            'p_table_name': tableName,
            'p_record_id': recordId,
            'p_operation': operation,
            'p_expected_server_version': expectedServerVersion,
            'p_payload': payload,
            'p_payload_version': payloadVersion,
            'p_baseline_token': baselineToken,
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

  @override
  Future<Object?> compactHistory() =>
      _client.rpc('planner_compact_sync_history');
}

/// Diagnostic for a mutation that the server refused because the caller no
/// longer owns the in-progress initial baseline claim.
///
/// The durable outbox operation stays queued: once the account is established
/// (by whichever device owns it) ordinary synchronization can deliver it.
const initialBaselineFencedMessage =
    'Cloud baseline ownership changed; the first synchronization was stopped '
    'safely.';

/// True when a classified failure is the server's baseline fencing rejection.
bool isInitialBaselineFencingFailure(SyncFailure failure) =>
    failure.message == initialBaselineFencedMessage;

/// True when push stopped because the server lacks a required Sync v2
/// capability. No operation was attempted or changed.
bool isSyncUpgradeRequiredFailure(SyncFailure failure) =>
    failure.message == _upgradeRequiredMessage ||
    failure.message == _capabilityUnavailableMessage;

String safeSyncError(Object error) {
  if (error is SyncValidationException) {
    return 'Invalid sync data: ${error.message}';
  }
  final message = error.toString().toLowerCase();
  // An expired/absent session is its own recoverable state and must never be
  // presented as a backend that disappeared.
  if (message.contains('401') ||
      message.contains('403') ||
      message.contains('jwt') ||
      message.contains('unauthorized') ||
      message.contains('invalid login') ||
      message.contains('session')) {
    return 'Authentication expired; sign in again.';
  }
  if (looksLikeUnavailableBackend(message)) {
    return cloudBackendUnreachableMessage;
  }
  if (message.contains('socket') ||
      message.contains('timeout') ||
      message.contains('network') ||
      message.contains('connection') ||
      message.contains('dns')) {
    return 'Network unavailable; retry scheduled.';
  }
  return 'Sync request failed; retry scheduled.';
}

/// Copy for a backend that is reachable in principle but is not answering as
/// *this* Supabase project. Deliberately never suggests deleting anything: the
/// local Planner data, the queued outbox and the stored connection all stay.
const cloudBackendUnreachableMessage =
    'Your cloud backend could not be reached. Local Planner data and pending '
    'changes are safe on this device.';

/// True when a failure is evidence that the Provisioned Supabase project
/// itself is gone, rather than a transient transport problem.
///
/// Deliberately narrow: only a project host that cannot be resolved, or an
/// explicit "this project does not exist" answer, qualify. Generic timeouts,
/// socket resets and HTTP 5xx responses stay retryable, so a flaky network can
/// never be presented as a deleted backend.
bool looksLikeUnavailableBackend(String message) {
  const hostGone = <String>[
    'failed host lookup',
    'name or service not known',
    'nodename nor servname',
    'no address associated with hostname',
    'temporary failure in name resolution',
  ];
  if (hostGone.any(message.contains)) return true;
  if (message.contains('project not found') ||
      message.contains('project does not exist') ||
      message.contains('project is not available') ||
      message.contains('unknown project')) {
    return true;
  }
  // A PostgREST 404 carries the project host as its authority. Bare "not found"
  // is deliberately not enough: a missing RPC is an un-migrated backend, which
  // is a different, explicit state.
  return message.contains('404') && message.contains('supabase');
}

const _authenticationExpiredMessage = 'Authentication expired; sign in again.';

/// SQLSTATE-first classification of a server rejection. Returns null when the
/// error carries no recognised code, so the message rules in
/// [classifySyncFailure] still apply.
SyncFailure? classifyBySqlState(Object error) {
  if (error is! PostgrestException) return null;
  final code = error.code ?? '';
  final message = error.message;
  if (message.toLowerCase().contains('initial baseline claim')) return null;
  if ((code == '42501' && message.contains('Authentication required')) ||
      const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(code)) {
    return const SyncFailure(
      SyncFailureKind.authentication,
      _authenticationExpiredMessage,
    );
  }
  if (code.startsWith('22') ||
      code.startsWith('23') ||
      code == '42501' ||
      code == '55000') {
    return SyncFailure(
      SyncFailureKind.permanent,
      'Sync action needs attention: $message',
    );
  }
  if (const {'40001', '40P01', '55P03', '57014', '53300'}.contains(code)) {
    return const SyncFailure(
      SyncFailureKind.retryable,
      'Sync request failed; retry scheduled.',
    );
  }
  return null;
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
  // Fencing is checked before the generic transport/auth classification: the
  // server refused this mutation because another device owns the in-progress
  // initial baseline, which is a deliberate, recoverable protocol answer.
  if (message.contains('initial baseline claim')) {
    return const SyncFailure(
      SyncFailureKind.retryable,
      initialBaselineFencedMessage,
    );
  }
  final bySqlState = classifyBySqlState(error);
  if (bySqlState != null) return bySqlState;
  // Authentication is checked before backend availability: an expired session
  // is recoverable by signing in again, and must never look like a backend that
  // disappeared. (Project-gone evidence never carries these markers.)
  if (message.contains('401') ||
      message.contains('403') ||
      message.contains('jwt') ||
      message.contains('auth') ||
      message.contains('unauthorized')) {
    return const SyncFailure(
      SyncFailureKind.authentication,
      _authenticationExpiredMessage,
    );
  }
  // Distinct from the generic retry below: an unreachable project is a
  // needs-attention state that keeps the outbox and stored connection intact,
  // rather than a transient transport failure the engine silently retries.
  if (looksLikeUnavailableBackend(message)) {
    return const SyncFailure(
      SyncFailureKind.backendUnavailable,
      cloudBackendUnreachableMessage,
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
