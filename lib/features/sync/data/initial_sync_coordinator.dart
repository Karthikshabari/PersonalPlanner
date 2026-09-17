import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/planner_account_scope.dart';
import '../../../core/utils/uuid.dart';
import '../../categories/data/category_repository.dart';
import '../domain/initial_sync_models.dart';
import '../domain/sync_models.dart';
import 'anonymous_data_adoption.dart';
import 'initial_sync_gateway.dart';
import 'initial_sync_state_store.dart';
import 'planner_data_probe.dart';
import 'sync_repository.dart';

typedef InitialSyncPersistPhase =
    Future<void> Function(
      InitialSyncPhase phase, {
      bool clearClaim,
      String? nextMessage,
    });

/// Thrown internally when the account scope changed (or the container was
/// disposed) while remote work was in flight. The stale result is dropped
/// without touching any local or remote state.
class _InitialSyncAbandoned implements Exception {
  const _InitialSyncAbandoned();
}

/// Thrown by the restore's page hook when meaningful local Planner work appears
/// while remote data is being restored. Rolling the page back keeps the restore
/// from committing remote rows after that point.
class _LocalWorkAppearedDuringRestore implements Exception {
  const _LocalWorkAppearedDuringRestore();
}

/// A device created Planner data while its cloud data was being restored.
const restoreLocalWorkConflictMessage =
    'You created Planner data on this device while its cloud Planner data was '
    'being restored. Nothing was uploaded or overwritten; both copies are '
    'preserved and are waiting for an explicit decision.';

/// The server refused to hand over an abandoned first baseline.
const baselineRecoveryRequiredMessage =
    'A previous device started the first cloud synchronization and never '
    'finished it, and the cloud already holds part of that data. Nothing was '
    'merged or overwritten; this account needs an explicit recovery decision.';

/// The server fenced this device because another device took ownership.
const baselineFencedMessage =
    'Another device took ownership of the first cloud synchronization. Your '
    'local Planner data was not uploaded and stays on this device.';

/// Phase G: safe initial synchronization and local adoption for a provisioned
/// user-owned backend.
///
/// Invariants enforced here:
///
/// * remote state is discovered *before* any local mutation may be pushed;
/// * "remote unknown" is never treated as "remote empty";
/// * local data is only adopted/uploaded after the remote is proven unused;
/// * local data plus non-empty remote data stops in an explicit conflict state
///   with both datasets preserved;
/// * a remote-empty observation is re-validated atomically (compare-and-set on
///   the account's monotonic change baseline) and serialized with a baseline
///   claim before the first local upload;
/// * every step is resumable after a crash and scoped to one canonical
///   `(projectRef, authUserId)` account database.
class InitialSyncCoordinator {
  InitialSyncCoordinator({
    required this.database,
    required this.scope,
    required this.gateway,
    required this.repositoryFactory,
    Future<AppDatabase> Function()? anonymousDatabaseFactory,
    this.currentAccountId,
    this.seedDefaultsIfEmpty,
    this.operationTimeout = const Duration(seconds: 30),
    String Function()? claimTokenFactory,
    this.onCompletionBoundary,
  }) : anonymousDatabaseFactory =
           anonymousDatabaseFactory ?? AppDatabase.open,
       claimTokenFactory = claimTokenFactory ?? generateUuidV7 {
    _adoption = AnonymousDataAdoptionService(
      database,
      anonymousDatabaseFactory: anonymousDatabaseFactory,
    );
    _stateStore = InitialSyncStateStore(database);
    _probe = PlannerDataProbe(database);
  }

  final AppDatabase database;

  /// Canonical identity of the account database this coordinator owns.
  final PlannerAccountScope scope;

  final InitialSyncRemoteGateway gateway;
  final SyncRepository Function() repositoryFactory;
  final Future<AppDatabase> Function() anonymousDatabaseFactory;

  /// Live canonical account id of the runtime Auth stack, or null when the
  /// caller cannot provide one (isolated tests).
  final String? Function()? currentAccountId;

  final Future<void> Function()? seedDefaultsIfEmpty;
  final Duration operationTimeout;
  final String Function() claimTokenFactory;

  /// Test-only seam: runs inside the atomic completion transaction of the
  /// remote-first restore, after the clean pre-check and before the conditional
  /// durable transition. Production never sets it.
  final Future<void> Function()? onCompletionBoundary;

  late final AnonymousDataAdoptionService _adoption;
  late final InitialSyncStateStore _stateStore;
  late final PlannerDataProbe _probe;

  final StreamController<InitialSyncStatus> _status =
      StreamController<InitialSyncStatus>.broadcast();
  InitialSyncStatus _last = InitialSyncStatus.unresolved;
  Future<void>? _activeRun;
  bool _disposed = false;

  Stream<InitialSyncStatus> get status => _status.stream;

  InitialSyncStatus get current => _last;

  bool get _alive {
    if (_disposed) return false;
    final current = currentAccountId?.call();
    if (currentAccountId != null && current != scope.storageId) return false;
    return true;
  }

  /// Runs one initial-synchronization pass.
  ///
  /// Idempotent: concurrent calls share one run, and a run that already
  /// completed can be started again (that is what the user-facing Retry does).
  Future<void> start() {
    if (_disposed) return Future<void>.value();
    final previous = _activeRun ?? Future<void>.value();
    final run = previous.then(
      (_) => _run(),
      onError: (Object _, StackTrace _) => _run(),
    );
    _activeRun = run;
    return run.whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
  }

  /// Explicit user confirmation to copy offline-only Planner data into this
  /// account. Delegates to the existing adoption service (atomic, idempotent
  /// and conflict-aborting) and then re-runs the safe first sync.
  Future<void> adoptOfflineData() async {
    if (!_alive) return;
    await _adoption.adopt();
    await start();
  }

  /// Explicit user choice to keep offline-only data out of this account.
  Future<void> keepOfflineDataSeparate() async {
    if (!_alive) return;
    await _adoption.keepSeparate();
    await start();
  }

  /// Rebuilds a locally parked (permanent) outbox operation from the current
  /// local row. This never touches the remote: the repaired operation is only
  /// re-queued, and the next pass uploads it after the baseline rules allow it.
  Future<void> repairPendingOperation(String operationId) async {
    if (!_alive) return;
    await repositoryFactory().repairPermanentOperation(operationId);
  }

  Future<void> retry() => start();

  Future<void> dispose() async {
    _disposed = true;
    await _status.close();
  }

  Future<void> _run() async {
    if (!_alive) return;
    var record = await _stateStore.read();
    if (!_alive) return;
    if (record.baselineComplete) {
      _publish(record);
      return;
    }

    var claimToken = record.claimToken;
    var claimBaselineChangeId = record.observedBaselineChangeId;
    Map<String, dynamic>? remoteDetail = _asMap(record.detail?['remote']);
    Map<String, dynamic>? localDetail = _asMap(record.detail?['local']);
    Map<String, dynamic>? anonymousDetail = _asMap(record.detail?['anonymous']);
    String? phaseMessage = record.phase.isTransient
        ? null
        : record.detail?['message']?.toString();

    InitialSyncRecord buildRecord(
      InitialSyncPhase phase, {
      bool clearClaim = false,
      String? nextMessage,
    }) {
      if (nextMessage != null) phaseMessage = nextMessage;
      if (clearClaim) {
        claimToken = null;
        claimBaselineChangeId = null;
      }
      final detail = <String, dynamic>{
        'message': ?phaseMessage,
        'remote': ?remoteDetail,
        'local': ?localDetail,
        'anonymous': ?anonymousDetail,
      };
      return InitialSyncRecord(
        phase: phase,
        claimToken: claimToken,
        observedBaselineChangeId: claimBaselineChangeId,
        detail: detail.isEmpty ? null : detail,
        updatedAt: DateTime.now().toUtc(),
      );
    }

    Future<void> persist(
      InitialSyncPhase phase, {
      bool clearClaim = false,
      String? nextMessage,
    }) async {
      if (!_alive) throw const _InitialSyncAbandoned();
      final next = buildRecord(
        phase,
        clearClaim: clearClaim,
        nextMessage: nextMessage,
      );
      await _stateStore.write(next);
      _publish(next);
    }

    try {
      // Discovery is always the first authoritative step, whatever phase a
      // previous run stopped in. Transient phases therefore recover by
      // re-determining the remote state rather than by assuming what it was.
      phaseMessage = null;
      await persist(InitialSyncPhase.discovering);
      final snapshot = await _discover();
      remoteDetail = snapshot.toDetailJson();

      final ownClaim =
          claimToken != null && snapshot.claim?.token == claimToken;
      if (ownClaim && snapshot.claim!.completed) {
        // The server already recorded this device's baseline; only the local
        // completion marker was lost to a crash.
        await persist(
          InitialSyncPhase.complete,
          clearClaim: true,
          nextMessage:
              'The cloud baseline was already established. Normal sync resumes.',
        );
        await _seedDefaultsWhenEmpty();
        return;
      }
      if (ownClaim) {
        // Resume this device's own claimed baseline. The server renews and
        // re-validates the claim first, and every mutation then carries the
        // fence token, so this device is fenced the moment it loses ownership.
        await persist(
          InitialSyncPhase.uploading,
          nextMessage:
              'Resuming the first synchronization with your cloud account...',
        );
        final granted = await _claim(
          token: claimToken!,
          observedBaselineChangeId:
              claimBaselineChangeId ?? snapshot.nextChangeId,
          localDataPresent: true,
          persist: persist,
        );
        if (!granted) return;
        await _upload(
          claimToken: claimToken!,
          persist: persist,
        );
        return;
      }

      final accountPresence = await _probe.inspect();
      localDetail = _localDetail(accountPresence);
      final anonymous = await _anonymousPresence();
      anonymousDetail = anonymous.detail;
      final localMeaningful =
          accountPresence.hasMeaningfulData || anonymous.hasMeaningfulData;

      // Established accounts: a completed baseline (even with zero Planner
      // rows) or durable pre-Phase-G Planner history. Only here may the local
      // database be initialized from the cloud.
      if (snapshot.established) {
        if (localMeaningful) {
          await persist(
            InitialSyncPhase.conflict,
            clearClaim: true,
            nextMessage:
                'Local Planner data and cloud Planner data both exist. Nothing '
                'was uploaded or overwritten; both copies are preserved.',
          );
          return;
        }
        await _restoreFromCloud(persist: persist, buildRecord: buildRecord);
        return;
      }

      // A first baseline is already in progress on this account. Its partial
      // rows are explicitly not a completed remote dataset, so the ordinary
      // restore-and-complete path must not run.
      if (snapshot.baselineState == RemoteBaselineState.inProgress) {
        final foreignClaim = snapshot.claim;
        if (foreignClaim != null && foreignClaim.expired) {
          // The server owns time and safety. Ask it whether a takeover is
          // allowed; never decide expiry from the local clock.
          final token = claimTokenFactory();
          claimToken = token;
          claimBaselineChangeId = snapshot.nextChangeId;
          await persist(InitialSyncPhase.uploading);
          final granted = await _claim(
            token: token,
            observedBaselineChangeId: snapshot.nextChangeId,
            localDataPresent: localMeaningful,
            persist: persist,
          );
          if (!granted) return;
          await _upload(claimToken: token, persist: persist);
          return;
        }
        await persist(
          localMeaningful
              ? InitialSyncPhase.conflict
              : InitialSyncPhase.retryable,
          clearClaim: true,
          nextMessage: localMeaningful
              ? 'Another device is establishing the cloud baseline for this '
                    'account. Your local Planner data was not uploaded.'
              : 'Cloud setup is already in progress on another device. The '
                    'cloud copy is not treated as complete data yet.',
        );
        return;
      }

      if (accountPresence.hasMeaningfulData) {
        // Local account data may only be uploaded now that the remote account
        // is proven unused, and only through an atomic, fenced baseline claim.
        final freshClaimToken = claimTokenFactory();
        claimToken = freshClaimToken;
        claimBaselineChangeId = snapshot.nextChangeId;
        await persist(
          InitialSyncPhase.uploading,
          nextMessage: 'Uploading your local Planner data...',
        );
        final granted = await _claim(
          token: freshClaimToken,
          observedBaselineChangeId: snapshot.nextChangeId,
          localDataPresent: true,
          persist: persist,
        );
        if (!granted) return;
        await _upload(
          claimToken: freshClaimToken,
          persist: persist,
        );
        return;
      }

      if (anonymous.hasMeaningfulData) {
        await persist(
          InitialSyncPhase.adoptionRequired,
          clearClaim: true,
          nextMessage:
              'Offline-only Planner data exists. Confirm whether to import it '
              'into this cloud account.',
        );
        return;
      }

      // Empty local + empty remote still has to produce ONE durable
      // server-side establishment event. No Planner rows need to be uploaded:
      // server baseline completion itself establishes the account, and only
      // then may the local state become complete (and defaults be seeded).
      final emptyBaselineToken = claimTokenFactory();
      claimToken = emptyBaselineToken;
      claimBaselineChangeId = snapshot.nextChangeId;
      await persist(
        InitialSyncPhase.uploading,
        nextMessage: 'Establishing your cloud account...',
      );
      final granted = await _claim(
        token: emptyBaselineToken,
        observedBaselineChangeId: snapshot.nextChangeId,
        localDataPresent: false,
        persist: persist,
      );
      if (!granted) return;
      await _completeBaseline(
        claimToken: emptyBaselineToken,
        persist: persist,
        message:
            'Your cloud account was established with no Planner data. Normal '
            'sync is ready.',
      );
    } on _InitialSyncAbandoned {
      // The account scope changed while this run was in flight. Drop the
      // result without touching the replacement account.
      return;
    } catch (error) {
      // Unknown remote state is a distinct state: it is never treated as empty
      // and no local mutation is pushed. An existing baseline claim is kept so
      // a retry continues this device's own claim instead of looking like a
      // second device.
      final reason = describeInitialSyncError(error);
      try {
        await persist(
          InitialSyncPhase.retryable,
          clearClaim: false,
          nextMessage: reason,
        );
      } on _InitialSyncAbandoned {
        return;
      }
    }
  }

  /// Acquires (or resumes) the server-authoritative first-baseline claim.
  ///
  /// The server decides: it renews this device's own claim, refuses a live
  /// foreign claim, refuses an abandoned foreign claim whose partial rows may
  /// already be in the cloud (recovery required), and never lets an established
  /// account be claimed again.
  Future<bool> _claim({
    required String token,
    required int observedBaselineChangeId,
    required bool localDataPresent,
    required InitialSyncPersistPhase persist,
  }) async {
    final claim = RemoteBaselineClaimResult.fromJson(
      await _guard(
        () => gateway.claimBaseline(
          claimToken: token,
          observedNextChangeId: observedBaselineChangeId,
        ),
      ),
    );
    switch (claim.status) {
      case RemoteBaselineClaimStatus.claimed:
        return true;
      case RemoteBaselineClaimStatus.claimHeld:
        await persist(
          localDataPresent
              ? InitialSyncPhase.conflict
              : InitialSyncPhase.retryable,
          clearClaim: true,
          nextMessage: localDataPresent
              ? 'Another device is establishing the cloud baseline for this '
                    'account. Your local Planner data was not uploaded.'
              : 'Cloud setup is already in progress on another device. The '
                    'cloud copy is not treated as complete data yet.',
        );
        return false;
      case RemoteBaselineClaimStatus.recoveryRequired:
        await persist(
          InitialSyncPhase.conflict,
          clearClaim: true,
          nextMessage: baselineRecoveryRequiredMessage,
        );
        return false;
      case RemoteBaselineClaimStatus.remoteInUse:
      case RemoteBaselineClaimStatus.baselineChanged:
        // The account moved (or was established by another device) between
        // discovery and the claim. With local Planner content this is the
        // explicit both-sides-exist conflict; without it the next pass simply
        // re-discovers and restores.
        await persist(
          localDataPresent
              ? InitialSyncPhase.conflict
              : InitialSyncPhase.retryable,
          clearClaim: true,
          nextMessage: localDataPresent
              ? 'The cloud account changed before the first upload started. '
                    'Local and cloud Planner data both exist; nothing was '
                    'uploaded or overwritten.'
              : 'The cloud account changed before the first upload started. '
                    'Nothing was uploaded; the cloud copy was left untouched.',
        );
        return false;
      case RemoteBaselineClaimStatus.completed:
        // An unexpected answer for a claim request: never continue blindly.
        await persist(
          InitialSyncPhase.retryable,
          clearClaim: true,
          nextMessage:
              'The cloud reported an unexpected baseline state. Retry the '
              'first synchronization.',
        );
        return false;
      case RemoteBaselineClaimStatus.unknownClaim:
        await persist(
          InitialSyncPhase.retryable,
          clearClaim: true,
          nextMessage:
              'The cloud did not confirm the baseline claim. Retry the first '
              'synchronization.',
        );
        return false;
    }
  }

  /// Marks the claimed baseline complete on the server, and only then makes the
  /// local first-sync state complete.
  ///
  /// No Planner rows need to have been uploaded: an established empty account is
  /// a valid, permanent outcome.
  Future<void> _completeBaseline({
    required String claimToken,
    required InitialSyncPersistPhase persist,
    required String message,
  }) async {
    final completion = RemoteBaselineClaimResult.fromJson(
      await _guard(() => gateway.completeBaseline(claimToken: claimToken)),
    );
    if (completion.status != RemoteBaselineClaimStatus.completed) {
      // Keep the claim: a retry resumes this device's own baseline.
      await persist(
        InitialSyncPhase.retryable,
        nextMessage:
            'The cloud did not confirm the completed baseline. Retry the first '
            'synchronization.',
      );
      return;
    }
    await persist(
      InitialSyncPhase.complete,
      clearClaim: true,
      nextMessage: message,
    );
    await _seedDefaultsWhenEmpty();
  }

  /// Remote-first restore of an already established account.
  ///
  /// The server state is authoritative before this runs. Local work that appears
  /// *during* the restore switches the outcome to an explicit conflict instead
  /// of completing a silent merge: the durable outbox is the provenance-safe
  /// signal, because local domain writes enqueue operations while restored
  /// remote rows never do.
  Future<void> _restoreFromCloud({
    required InitialSyncPersistPhase persist,
    required InitialSyncRecord Function(
      InitialSyncPhase phase, {
      bool clearClaim,
      String? nextMessage,
    })
    buildRecord,
  }) async {
    await persist(
      InitialSyncPhase.remoteExisting,
      clearClaim: true,
      nextMessage:
          'Cloud Planner data found. It is restored before anything is '
          'uploaded.',
    );
    await persist(
      InitialSyncPhase.restoring,
      clearClaim: true,
      nextMessage: 'Restoring Planner data from your cloud account...',
    );
    var localWorkAppeared = false;
    SyncFailure? failure;
    try {
      failure = await repositoryFactory().pull(
        beforePageCommit: () async {
          if (await _probe.hasActiveOutboxOperations()) {
            throw const _LocalWorkAppearedDuringRestore();
          }
        },
      );
    } on _LocalWorkAppearedDuringRestore {
      localWorkAppeared = true;
    }
    if (!_alive) return;
    if (localWorkAppeared) {
      await persist(
        InitialSyncPhase.conflict,
        clearClaim: true,
        nextMessage: restoreLocalWorkConflictMessage,
      );
      return;
    }
    if (failure != null) {
      await persist(
        InitialSyncPhase.retryable,
        clearClaim: true,
        nextMessage: failure.message,
      );
      return;
    }
    // Completion boundary: a local edit may have landed after the last
    // committed page. Restored remote rows never enqueue an outbox operation,
    // so this cannot mistake them for local work.
    if (await _probe.hasActiveOutboxOperations()) {
      await persist(
        InitialSyncPhase.conflict,
        clearClaim: true,
        nextMessage: restoreLocalWorkConflictMessage,
      );
      return;
    }
    // A database seeded by an earlier build can still hold untouched built-in
    // categories with pending seed inserts. The remote account never referenced
    // them (they would have arrived with the restore), so discard them instead
    // of letting them become remote mutations on the first normal sync. This
    // runs before the completion gate and can only *remove* application-created
    // seed inserts, so it cannot reopen the completion window.
    await _discardUntouchedBootstrapDefaults();
    // The clean decision and the durable `complete` transition are one SQLite
    // transaction whose first statement takes the write lock, so a local Planner
    // mutation can only be ordered before the predicate (-> no completion) or
    // after the durable completion (-> ordinary post-baseline synchronization).
    final completedRecord = buildRecord(
      InitialSyncPhase.complete,
      clearClaim: true,
      nextMessage: 'Cloud Planner data restored. Normal sync is ready.',
    );
    final completed = await _stateStore.writeCompleteIfLocalWorkClean(
      completedRecord,
      onBoundary: onCompletionBoundary,
    );
    if (!_alive) return;
    if (!completed) {
      await persist(
        InitialSyncPhase.conflict,
        clearClaim: true,
        nextMessage: restoreLocalWorkConflictMessage,
      );
      return;
    }
    _publish(completedRecord);
    await _seedDefaultsWhenEmpty();
  }

  Future<void> _upload({
    required String claimToken,
    required InitialSyncPersistPhase persist,
  }) async {
    final repository = repositoryFactory();

    // 1. Materialize whatever the remote holds right now (usually nothing, but
    //    a concurrent writer must never be silently overwritten).
    final beforePush = await repository.pull();
    if (!_alive) return;
    if (beforePush != null) {
      await _failUpload(persist, beforePush.message, retryable: true);
      return;
    }

    // 2. Upload the local Planner data through the normal durable outbox, using
    //    the fenced entry point: the server verifies this device's claim for
    //    every mutation and renews its lease, so a claimant that lost ownership
    //    (lease takeover) is fenced by the server and cannot mutate at all. Per
    //    record compare-and-set turns any collision into an explicit conflict
    //    instead of an overwrite.
    final pushFailure = await repository.push(baselineToken: claimToken);
    if (!_alive) return;
    if (pushFailure != null && isInitialBaselineFencingFailure(pushFailure)) {
      // Another device now owns the first baseline. Stop immediately, keep the
      // local data and keep every operation queued for the established account.
      await persist(
        InitialSyncPhase.conflict,
        clearClaim: true,
        nextMessage: baselineFencedMessage,
      );
      return;
    }
    final parked = pushFailure != null &&
        (pushFailure.kind == SyncFailureKind.permanent ||
            pushFailure.kind == SyncFailureKind.invalidData);
    if (pushFailure != null && !parked) {
      await _failUpload(persist, pushFailure.message, retryable: true);
      return;
    }

    // 3. Pick up the server's view of everything that was just uploaded and
    //    acknowledge any operation the server applied before a crash.
    final afterPush = await repository.pull();
    if (!_alive) return;
    if (afterPush != null) {
      await _failUpload(persist, afterPush.message, retryable: true);
      return;
    }

    final outstanding = await database.syncDao.pendingCount();
    final conflicts = await database.select(database.syncConflicts).get();
    final parkedOperation = await database.syncDao.firstPermanentOperation();
    // A retryable operation that is merely waiting out its backoff means the
    // first upload is not finished yet: the baseline must not be completed on a
    // partially uploaded dataset. Operations that are parked for explicit
    // repair are terminal (the user must repair them) and do not block the
    // established account.
    if (outstanding > 0 && parkedOperation == null) {
      await _failUpload(
        persist,
        '$outstanding local operation(s) still need to be uploaded. Retry the '
        'first synchronization to finish it.',
        retryable: true,
      );
      return;
    }
    final notes = <String>[
      'Your local Planner data was uploaded and cloud sync is ready.',
      if (conflicts.isNotEmpty)
        '${conflicts.length} record(s) need a keep-local/keep-remote decision.',
      if (parkedOperation != null)
        'One record still needs a repair before it can sync.',
      if (outstanding > 0 && conflicts.isEmpty && parkedOperation == null)
        '$outstanding operation(s) remain queued.',
    ];
    // 4. Only after the server's authoritative completion is the local state
    //    complete and normal synchronization allowed to exist.
    await _completeBaseline(
      claimToken: claimToken,
      persist: persist,
      message: notes.join(' '),
    );
  }

  Future<void> _failUpload(
    InitialSyncPersistPhase persist,
    String reason, {
    bool retryable = false,
  }) async {
    if (!_alive) return;
    await persist(
      retryable ? InitialSyncPhase.retryable : InitialSyncPhase.conflict,
      clearClaim: !retryable,
      nextMessage: reason,
    );
  }

  Future<RemoteAccountSnapshot> _discover() async {
    final raw = await _guard(() => gateway.accountState());
    return RemoteAccountSnapshot.fromJson(raw);
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (!_alive) throw const _InitialSyncAbandoned();
    final result = await action().timeout(operationTimeout);
    if (!_alive) throw const _InitialSyncAbandoned();
    return result;
  }

  /// A local probe of the anonymous database used by the first-sync decision.
  ///
  /// Untouched built-in categories are not user content, so a freshly seeded
  /// offline database reads as empty. Deletion history does count.
  Future<({LocalDataSummary presence, bool hasMeaningfulData, Map<String, dynamic> detail})>
  _anonymousPresence() async {
    final decision = await database.syncDao.getSetting(
      anonymousAdoptionDecisionKey,
    );
    final anonymous = await anonymousDatabaseFactory();
    try {
      final presence = await PlannerDataProbe(anonymous).inspect();
      final excluded = decision == 'separate';
      final meaningful = !excluded && presence.hasMeaningfulData;
      return (
        presence: presence,
        hasMeaningfulData: meaningful,
        detail: {
          'decision': decision,
          'excluded': excluded,
          'live_records': presence.liveRecords,
          'tombstoned_records': presence.tombstonedRecords,
        },
      );
    } finally {
      await anonymous.close();
    }
  }

  Future<void> _seedDefaultsWhenEmpty() async {
    final seed = seedDefaultsIfEmpty;
    if (seed == null || !_alive) return;
    final presence = await _probe.inspect();
    if (presence.hasMeaningfulData) return;
    await seed();
  }

  /// Removes built-in default categories that are still exactly untouched,
  /// were never accepted by the server and are referenced by nothing.
  ///
  /// Only a row that matches the built-in definition field by field, has
  /// `server_version IS NULL`, has no task/rule/template reference and whose
  /// only outbox history is an unacknowledged seed insert is eligible. A
  /// renamed, re-colored, re-ordered, re-used or synced category is always
  /// kept.
  Future<int> _discardUntouchedBootstrapDefaults() async {
    if (!_alive) return 0;
    var discarded = 0;
    await database.syncDao.runWithoutOutbound(() async {
      for (final definition in CategoryRepository.defaultCategoryDefinitions) {
        if (!_alive) return;
        final id = CategoryRepository.defaultCategoryId(definition.key);
        final eligible = await database.customSelect(
          '''
SELECT COUNT(*) AS count FROM categories c WHERE
  c.id = ? AND c.name = ? AND c.color_hex = ? AND c.sort_order = ?
  AND c.is_focus = ? AND c.deleted_at IS NULL AND c.server_version IS NULL
  AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.category_id = c.id)
  AND NOT EXISTS (
    SELECT 1 FROM recurring_rules r WHERE r.category_id = c.id
  )
  AND NOT EXISTS (
    SELECT 1 FROM task_templates k WHERE k.category_id = c.id
  )
  AND EXISTS (
    SELECT 1 FROM sync_log l WHERE l.table_name = 'categories'
      AND l.record_id = c.id AND l.operation = 'insert'
      AND l.state IN ('pending', 'error', 'in_flight')
  )
  AND NOT EXISTS (
    SELECT 1 FROM sync_log l WHERE l.table_name = 'categories'
      AND l.record_id = c.id
      AND (l.operation <> 'insert' OR l.state = 'acknowledged')
  )
''',
          variables: [
            Variable<String>(id),
            Variable<String>(definition.name),
            Variable<String>(definition.colorHex),
            Variable<int>(definition.sortOrder),
            Variable<int>(definition.isFocus ? 1 : 0),
          ],
        ).getSingle();
        if (eligible.read<int>('count') == 0) continue;
        await database.customStatement(
          "DELETE FROM sync_log WHERE table_name = 'categories' "
          'AND record_id = ?',
          [id],
        );
        await database.customStatement('DELETE FROM categories WHERE id = ?', [
          id,
        ]);
        discarded += 1;
      }
    });
    return discarded;
  }

  Map<String, dynamic> _localDetail(LocalDataSummary presence) =>
      <String, dynamic>{
        'live_records': presence.liveRecords,
        'tombstoned_records': presence.tombstonedRecords,
        'pending_operations': presence.pendingOperations,
      };

  void _publish(InitialSyncRecord record) {
    _last = InitialSyncStatus.fromRecord(record);
    if (!_status.isClosed) _status.add(_last);
  }

  static Map<String, dynamic>? _asMap(Object? raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : null;
}

/// User-facing reason for a failed initial-synchronization step.
///
/// A provisioned project whose backend does not yet carry the Phase G RPCs is
/// reported explicitly, because retrying can never succeed until the canonical
/// migrations are applied there.
String describeInitialSyncError(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('planner_sync_account_state') ||
      lower.contains('planner_claim_initial_baseline') ||
      lower.contains('planner_complete_initial_baseline') ||
      lower.contains('could not find the function') ||
      lower.contains('schema cache')) {
    return 'This cloud backend does not support safe initial synchronization '
        'yet. Apply the latest Planner migrations to the project, then retry.';
  }
  return safeSyncError(error);
}
