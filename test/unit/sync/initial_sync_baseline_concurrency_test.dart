import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/initial_sync_coordinator.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';

import '../../helpers/initial_sync_fakes.dart';
import '../../helpers/runtime_auth_fakes.dart';
import '../../helpers/sqlite_setup.dart';

/// Phase G correction pass: the initial-baseline protocol under real
/// multi-device concurrency.
///
/// One [FakeInitialSyncGateway] + [FakeSyncRemoteGateway] pair represents one
/// account on the server. Two "devices" are two account databases with their own
/// coordinators talking to that shared server state, so claim ownership, lease
/// expiry, takeover and fencing behave the way the RPCs do.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final scope = PlannerAccountScope.provisioned(
    projectRef: projectRefA,
    authUserId: authUserIdX,
  );

  late List<RemoteCall> calls;
  late FakeInitialSyncGateway server;
  late List<AppDatabase> databases;
  late List<AnonymousDatabaseFixture> anonymousFixtures;
  late int claimTokenCounter;
  late int seedCalls;

  setUp(() {
    calls = <RemoteCall>[];
    server = FakeInitialSyncGateway(calls: calls);
    databases = <AppDatabase>[];
    anonymousFixtures = <AnonymousDatabaseFixture>[];
    claimTokenCounter = 0;
    seedCalls = 0;
  });

  tearDown(() async {
    for (final database in databases) {
      await database.close();
    }
    for (final fixture in anonymousFixtures) {
      fixture.delete();
    }
  });

  /// One physical device: an account database, its own sync connection to the
  /// shared account and a coordinator on top of both.
  _Device device({bool emptyOfflineData = true}) {
    final database = AppDatabase(NativeDatabase.memory());
    databases.add(database);
    final anonymous = AnonymousDatabaseFixture.create();
    anonymousFixtures.add(anonymous);
    final remote = FakeSyncRemoteGateway(
      calls: calls,
      account: server,
      // The real server appends every accepted mutation to its change log, so a
      // second device can observe and restore it.
      echoApplied: true,
    );
    final coordinator = InitialSyncCoordinator(
      database: database,
      scope: scope,
      gateway: server,
      repositoryFactory: () => SyncRepository.withGateway(
        database,
        remote,
        scope.storageId,
        currentAccountId: () => scope.storageId,
      ),
      anonymousDatabaseFactory: anonymous.open,
      currentAccountId: () => scope.storageId,
      seedDefaultsIfEmpty: () async {
        seedCalls += 1;
        await CategoryRepository(database).seedDefaultsIfEmpty();
      },
      operationTimeout: const Duration(seconds: 5),
      claimTokenFactory: () => 'claim-${++claimTokenCounter}',
    );
    return _Device(
      database: database,
      remote: remote,
      coordinator: coordinator,
    );
  }

  Future<InitialSyncRecord> stateOf(_Device device) =>
      InitialSyncStateStore(device.database).read();

  test(
    'an empty account is established by a server claim and completion before the local state completes',
    () async {
      final a = device();
      var appliesWhenServerCompleted = -1;
      server.onComplete = () => appliesWhenServerCompleted = server.appliedCount;

      await a.coordinator.start();

      final state = await stateOf(a);
      expect(state.phase, InitialSyncPhase.complete);
      // Exactly one server-side establishment event, with nothing uploaded.
      expect(server.claimCalls, 1);
      expect(server.claims.single.token, 'claim-1');
      expect(server.claims.single.observed, 1);
      expect(server.completeCalls, 1);
      expect(server.claimCompleted, isTrue);
      expect(appliesWhenServerCompleted, 0);
      expect(server.appliedCount, 0);
      expect(a.remote.applyCalls, 0);
      // The built-in defaults may only follow the established baseline; they are
      // queued locally and are not part of the baseline establishment.
      expect(seedCalls, 1);
      expect(await a.database.syncDao.pendingCount(), 4);
      expect(server.appliedCount, 0);
      expect(
        calls.map((call) => call.name).toList(),
        <String>[
          'accountState',
          'claimBaseline',
          'completeBaseline',
        ],
      );
    },
  );

  test(
    'a completed empty baseline is permanent and a second device cannot reclaim it',
    () async {
      final a = device();
      await a.coordinator.start();
      expect(server.claimCompleted, isTrue);
      final claimsAfterA = server.claimCalls;

      final b = device();
      await b.coordinator.start();

      final bState = await stateOf(b);
      expect(bState.phase, InitialSyncPhase.complete);
      // Device B never claims: the account is already established.
      expect(server.claimCalls, claimsAfterA);
      expect(server.completeCalls, 1);
      expect(b.remote.applyCalls, 0);
      expect(server.appliedCount, 0);

      // The server itself refuses a fresh claim on the established account.
      final refused = await server.claimBaseline(
        claimToken: 'device-c-claim',
        observedNextChangeId: server.nextChangeId,
      );
      expect(
        RemoteBaselineClaimResult.fromJson(refused).status,
        RemoteBaselineClaimStatus.remoteInUse,
      );
      expect(server.claimToken, 'claim-1');
    },
  );

  test(
    'a foreign partial first baseline is never restored as completed cloud data',
    () async {
      // Device A claims and uploads part of its data, then stops without
      // completing the baseline.
      final a = device();
      await insertLocalCategory(a.database, id: 'a-cat', name: 'A work');
      await insertLocalTask(
        a.database,
        id: 'a-task',
        title: 'A task',
        categoryId: 'a-cat',
      );
      a.remote.onApply = () {
        // Fail every apply after the first one so the upload is genuinely
        // partial: the first mutation reaches the server, the second does not.
        if (a.remote.applyCalls >= 2) {
          a.remote.applyError = Exception('SocketException: connection reset');
        }
      };
      await a.coordinator.start();
      final aState = await stateOf(a);
      expect(aState.phase, InitialSyncPhase.retryable);
      expect(server.appliedCount, 1);
      expect(server.claimCompleted, isFalse);

      // Device B is fresh and discovers the same account.
      final b = device();
      final pullCallsBefore = b.remote.pullCalls;
      await b.coordinator.start();

      final bState = await stateOf(b);
      expect(
        bState.phase,
        InitialSyncPhase.retryable,
        reason: 'the live foreign claim keeps B waiting',
      );
      expect(b.remote.applyCalls, 0, reason: 'B must not upload');
      expect(
        b.remote.pullCalls,
        pullCallsBefore,
        reason: 'B must not pull partial rows as if they were complete data',
      );
      expect(server.claimCompleted, isFalse);

      // Once A's retry backoff has elapsed it finishes the upload and completes
      // its baseline; B then restores the complete dataset normally.
      a.remote
        ..applyError = null
        ..onApply = null;
      await a.database.customStatement(
        "UPDATE sync_log SET next_attempt_at = NULL WHERE state = 'error'",
      );
      await a.coordinator.start();
      expect((await stateOf(a)).phase, InitialSyncPhase.complete);
      expect(server.appliedCount, 2);
      expect((await stateOf(a)).phase, InitialSyncPhase.complete);
      expect(server.claimCompleted, isTrue);

      await b.coordinator.start();
      expect((await stateOf(b)).phase, InitialSyncPhase.complete);
      final restored = await b.database.categoryDao.getCategoryById('a-cat');
      expect(restored, isNotNull);
      expect(await b.database.taskDao.getTaskById('a-task'), isNotNull);
    },
  );

  test(
    'a claimant that loses ownership is fenced by the server and cannot mutate',
    () async {
      final a = device();
      await insertLocalCategory(a.database, id: 'a-cat', name: 'A work');
      await insertLocalTask(
        a.database,
        id: 'a-task',
        title: 'A task',
        categoryId: 'a-cat',
      );
      // Device B takes ownership while A's first upload is in flight: the lease
      // lapses server-side and the server grants B a replacement claim before
      // A's mutation reaches the mutation function.
      var tookOver = false;
      a.remote.onApplyAsync = () async {
        if (tookOver) return;
        tookOver = true;
        server.leaseExpired = true;
        final takenOver = await server.claimBaseline(
          claimToken: 'claim-2',
          observedNextChangeId: server.nextChangeId,
        );
        expect(
          RemoteBaselineClaimResult.fromJson(takenOver).status,
          RemoteBaselineClaimStatus.claimed,
        );
      };

      await a.coordinator.start();

      // A applied nothing after the takeover and the server rejected its
      // fenced mutation.
      expect(server.appliedCount, 0);
      expect(server.rejectedMutations, 1);
      final aState = await stateOf(a);
      expect(aState.phase, InitialSyncPhase.conflict);
      expect(aState.detail?['message'], baselineFencedMessage);
      expect(aState.baselineComplete, isFalse);
      expect(aState.claimToken, isNull);
      // A's local work is intact and stays queued for the established account.
      expect(await a.database.select(a.database.tasks).get(), hasLength(1));
      expect(await a.database.syncDao.pendingCount(), 2);
      expect(a.remote.applyCalls, 1);
      expect(server.claimToken, 'claim-2');
      expect(server.claimCompleted, isFalse);

      // The replacement claimant has its own durable claim and can mutate and
      // complete, exactly as the new owner would.
      final b = device();
      await insertLocalCategory(b.database, id: 'b-cat', name: 'B work');
      await InitialSyncStateStore(b.database).write(
        const InitialSyncRecord(
          phase: InitialSyncPhase.uploading,
          claimToken: 'claim-2',
          observedBaselineChangeId: 1,
        ),
      );
      await b.coordinator.start();

      expect(server.claimCompleted, isTrue);
      expect(server.rejectedMutations, 1, reason: 'only A was fenced');
      expect(server.appliedCount, 1);
      expect((await stateOf(b)).phase, InitialSyncPhase.complete);
      expect(server.claimToken, 'claim-2');
    },
  );

  test(
    'a verified claimant renews its lease and cannot be stolen',
    () async {
      final a = device();
      await insertLocalCategory(a.database, id: 'a-cat', name: 'A work');
      await insertLocalTask(
        a.database,
        id: 'a-task',
        title: 'A task',
        categoryId: 'a-cat',
      );
      // Simulate a long upload: the lease deadline passes before the first
      // mutation, and the claim/mutation must renew it.
      server.leaseExpired = true;
      var contenderStatus = '';
      a.remote.onApplyAsync = () async {
        // A contender that asks while the claim is live is refused; it never
        // steals ownership from a renewing claimant.
        if (contenderStatus.isEmpty) {
          contenderStatus = RemoteBaselineClaimResult.fromJson(
            await server.claimBaseline(
              claimToken: 'contender-claim',
              observedNextChangeId: server.nextChangeId,
            ),
          ).status.name;
          expect(server.leaseExpired, isFalse, reason: 'renewed before pushing');
          expect(server.claimToken, 'claim-1');
        }
      };

      await a.coordinator.start();

      expect(contenderStatus, RemoteBaselineClaimStatus.claimHeld.name);
      expect(server.claimCompleted, isTrue);
      expect(server.leaseExpired, isFalse);
      expect(server.rejectedMutations, 0);
      expect(server.appliedCount, 2);
      expect(server.claimToken, 'claim-1');
      expect((await stateOf(a)).phase, InitialSyncPhase.complete);

      // Afterwards the account is permanently established.
      final refused = await server.claimBaseline(
        claimToken: 'contender-claim',
        observedNextChangeId: 1,
      );
      expect(
        RemoteBaselineClaimResult.fromJson(refused).status,
        RemoteBaselineClaimStatus.remoteInUse,
      );
      expect(server.claimToken, 'claim-1');
    },
  );

  test(
    'a fresh device recovers an expired, empty foreign claim through the server',
    () async {
      // Device A claimed an empty account and died before uploading anything.
      final a = device();
      server.claimToken = 'claim-a';
      server.claimClaimedAt = DateTime.now().toUtc();
      server.leaseExpired = true;

      final b = device();
      await insertLocalCategory(b.database, id: 'b-cat', name: 'B work');
      await b.coordinator.start();

      expect(server.claimCalls, 1);
      expect(server.claimToken, 'claim-1');
      expect(server.claimCompleted, isTrue);
      expect(server.appliedCount, 1);
      expect((await stateOf(b)).phase, InitialSyncPhase.complete);
      expect(a.remote.applyCalls, 0);
    },
  );

  test(
    'an expired foreign claim with partial history requires explicit recovery',
    () async {
      // Device A uploaded 30% and its lease lapsed: the server must not hand the
      // account to a fresh device as if the remaining 70% still existed.
      server
        ..claimToken = 'claim-a'
        ..claimClaimedAt = DateTime.now().toUtc()
        ..hasHistory = true
        ..nextChangeId = 4
        ..changeCount = 3
        ..leaseExpired = true;

      final b = device();
      await insertLocalCategory(b.database, id: 'b-cat', name: 'B work');
      final pullsBefore = b.remote.pullCalls;
      await b.coordinator.start();

      final bState = await stateOf(b);
      expect(bState.phase, InitialSyncPhase.conflict);
      expect(bState.detail?['message'], baselineRecoveryRequiredMessage);
      expect(server.claimCalls, 1, reason: 'B asks the server, not its own clock');
      expect(server.claimToken, 'claim-a', reason: 'no silent takeover');
      expect(b.remote.applyCalls, 0);
      expect(b.remote.pullCalls, pullsBefore);
      expect(server.appliedCount, 0);
    },
  );

  test(
    'a local edit during the remote restore stops completion and preserves both sides',
    () async {
      server
        ..hasHistory = true
        ..claimCompleted = true
        ..nextChangeId = 3
        ..changeCount = 2;
      final seedGateway = FakeSyncRemoteGateway(calls: calls, account: server);
      final database = AppDatabase(NativeDatabase.memory());
      databases.add(database);
      seedGateway.seedChanges([
        remoteCategoryChange(
          id: 'cloud-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
        remoteTaskChange(
          id: 'cloud-task',
          title: 'Cloud task',
          changeId: 0,
          serverVersion: 0,
          categoryId: 'cloud-cat',
        ),
      ]);

      final anonymous = AnonymousDatabaseFixture.create();
      anonymousFixtures.add(anonymous);
      final remote = FakeSyncRemoteGateway(calls: calls, account: server);
      // The user writes Planner data while the restore request is in flight.
      remote.onPull = () async {
        await insertLocalTask(
          database,
          id: 'local-during-restore',
          title: 'Written during restore',
        );
      };
      final coordinator = InitialSyncCoordinator(
        database: database,
        scope: scope,
        gateway: server,
        repositoryFactory: () => SyncRepository.withGateway(
          database,
          remote,
          scope.storageId,
          currentAccountId: () => scope.storageId,
        ),
        anonymousDatabaseFactory: anonymous.open,
        currentAccountId: () => scope.storageId,
        operationTimeout: const Duration(seconds: 5),
        claimTokenFactory: () => 'claim-${++claimTokenCounter}',
      );

      await coordinator.start();

      final state = await InitialSyncStateStore(database).read();
      expect(state.phase, InitialSyncPhase.conflict);
      expect(state.detail?['message'], restoreLocalWorkConflictMessage);
      expect(state.baselineComplete, isFalse);
      // The uncommitted page was rolled back: no restored rows were applied
      // after the local edit appeared.
      expect(await database.taskDao.getTaskById('cloud-task'), isNull);
      // The user's own work is preserved and still queued.
      expect(
        await database.taskDao.getTaskById('local-during-restore'),
        isNotNull,
      );
      expect(await database.syncDao.pendingCount(), 1);
      expect(remote.applyCalls, 0);
      expect(server.appliedCount, 0);
    },
  );

  test(
    'a local edit after the last committed page still prevents completion',
    () async {
      server
        ..hasHistory = true
        ..claimCompleted = true
        // The durable cursor is already past the feed, so the restore pulls an
        // empty page and the per-page hook never runs.
        ..nextChangeId = 5
        ..changeCount = 0;
      final database = AppDatabase(NativeDatabase.memory());
      databases.add(database);
      final anonymous = AnonymousDatabaseFixture.create();
      anonymousFixtures.add(anonymous);
      final remote = FakeSyncRemoteGateway(calls: calls, account: server);
      remote.onPull = () async {
        await insertLocalCategory(database, id: 'late-cat', name: 'Late work');
      };
      final coordinator = InitialSyncCoordinator(
        database: database,
        scope: scope,
        gateway: server,
        repositoryFactory: () => SyncRepository.withGateway(
          database,
          remote,
          scope.storageId,
          currentAccountId: () => scope.storageId,
        ),
        anonymousDatabaseFactory: anonymous.open,
        currentAccountId: () => scope.storageId,
        operationTimeout: const Duration(seconds: 5),
      );

      await coordinator.start();

      final state = await InitialSyncStateStore(database).read();
      expect(state.phase, InitialSyncPhase.conflict);
      expect(state.detail?['message'], restoreLocalWorkConflictMessage);
      expect(state.baselineComplete, isFalse);
      expect(await database.categoryDao.getCategoryById('late-cat'), isNotNull);
      expect(await database.syncDao.pendingCount(), 1);
    },
  );

  test(
    'a remote restore with no concurrent local edit still completes',
    () async {
      server
        ..hasHistory = true
        ..claimCompleted = true
        ..nextChangeId = 3
        ..changeCount = 2;
      final seedGateway = FakeSyncRemoteGateway(calls: calls, account: server);
      final database = AppDatabase(NativeDatabase.memory());
      databases.add(database);
      seedGateway.seedChanges([
        remoteCategoryChange(
          id: 'cloud-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
        remoteTaskChange(
          id: 'cloud-task',
          title: 'Cloud task',
          changeId: 0,
          serverVersion: 0,
          categoryId: 'cloud-cat',
        ),
      ]);

      final anonymous = AnonymousDatabaseFixture.create();
      anonymousFixtures.add(anonymous);
      final remote = FakeSyncRemoteGateway(calls: calls, account: server);
      final coordinator = InitialSyncCoordinator(
        database: database,
        scope: scope,
        gateway: server,
        repositoryFactory: () => SyncRepository.withGateway(
          database,
          remote,
          scope.storageId,
          currentAccountId: () => scope.storageId,
        ),
        anonymousDatabaseFactory: anonymous.open,
        currentAccountId: () => scope.storageId,
        seedDefaultsIfEmpty: () async {
          seedCalls += 1;
          await CategoryRepository(database).seedDefaultsIfEmpty();
        },
        operationTimeout: const Duration(seconds: 5),
      );

      await coordinator.start();

      final state = await InitialSyncStateStore(database).read();
      expect(state.phase, InitialSyncPhase.complete);
      expect(await database.taskDao.getTaskById('cloud-task'), isNotNull);
      expect(await database.categoryDao.getCategoryById('cloud-cat'), isNotNull);
      expect(remote.applyCalls, 0);
      // The restored account is not empty, so no defaults were seeded.
      expect(seedCalls, 0);
    },
  );

  test(
    'a normal SyncEngine writer cannot mutate while a foreign baseline is in progress',
    () async {
      // An established-style writer (no fence token, like the post-baseline
      // engine) is refused by the server while another device owns the
      // in-progress first baseline.
      server
        ..claimToken = 'device-a-claim'
        ..claimClaimedAt = DateTime.now().toUtc();
      final writer = FakeSyncRemoteGateway(calls: calls, account: server);

      await expectLater(
        writer.applyOperation(
          operationId: 'operations-1',
          tableName: 'categories',
          recordId: 'cat',
          operation: 'insert',
          expectedServerVersion: null,
          payload: const <String, dynamic>{'id': 'cat', 'name': 'Work'},
          payloadVersion: 2,
        ),
        throwsA(isA<FakeFencedMutationException>()),
      );
      expect(server.rejectedMutations, 1);
      expect(server.appliedCount, 0);
      expect(server.claimToken, 'device-a-claim');
    },
  );

  test(
    'the historical v1 mutation RPC cannot bypass an active initial baseline',
    () async {
      // Device A owns an active, incomplete first baseline.
      server
        ..claimToken = 'token-a'
        ..claimClaimedAt = DateTime.now().toUtc();
      final writerA = FakeSyncRemoteGateway(calls: calls, account: server);
      final otherClient = FakeSyncRemoteGateway(calls: calls, account: server);

      // Another authenticated client calls the legacy, untokened v1 entry point.
      await expectLater(
        otherClient.applyLegacyV1Operation(
          operationId: 'legacy-1',
          tableName: 'categories',
          recordId: 'cat',
          operation: 'insert',
          expectedServerVersion: null,
          payload: const <String, dynamic>{'id': 'cat', 'name': 'Bypass'},
        ),
        throwsA(isA<FakeFencedMutationException>()),
      );

      // The rejection happens before any domain mutation.
      expect(server.appliedCount, 0);
      expect(server.rejectedMutations, 1);
      expect(server.remoteChanges, isEmpty);
      expect(server.claimToken, 'token-a');
      expect(server.claimCompleted, isFalse);
      expect(writerA.appliedOperations, isEmpty);
    },
  );

  test(
    'a stale token cannot mutate after a takeover, nor after the replacement completed',
    () async {
      // A owns the first baseline, then becomes safely take-overable.
      server
        ..claimToken = 'token-a'
        ..claimClaimedAt = DateTime.now().toUtc()
        ..leaseExpired = true;
      final writer = FakeSyncRemoteGateway(calls: calls, account: server);

      // B takes over and completes the baseline.
      final takeover = await server.claimBaseline(
        claimToken: 'token-b',
        observedNextChangeId: server.nextChangeId,
      );
      expect(
        RemoteBaselineClaimResult.fromJson(takeover).status,
        RemoteBaselineClaimStatus.claimed,
      );
      final completion = await server.completeBaseline(claimToken: 'token-b');
      expect(
        RemoteBaselineClaimResult.fromJson(completion).status,
        RemoteBaselineClaimStatus.completed,
      );
      expect(server.claimToken, 'token-b');
      expect(server.appliedCount, 0);

      Map<String, dynamic> payload(String name) =>
          <String, dynamic>{'id': 'cat', 'name': name};
      Future<Object?> applyWith(String? token, String name) =>
          writer.applyOperation(
            operationId: 'op-$name',
            tableName: 'categories',
            recordId: 'cat',
            operation: 'insert',
            expectedServerVersion: null,
            payload: payload(name),
            payloadVersion: 2,
            baselineToken: token,
          );

      // Stale A is rejected with zero mutation, even though the baseline it once
      // owned is now completed.
      await expectLater(
        applyWith('token-a', 'stale-a'),
        throwsA(isA<FakeFencedMutationException>()),
      );
      expect(server.appliedCount, 0, reason: 'stale A mutated nothing');
      // v3 stays strictly the in-progress entry point: even the completing
      // token cannot mutate through it once the baseline is completed.
      await expectLater(
        applyWith('token-b', 'stale-b'),
        throwsA(isA<FakeFencedMutationException>()),
      );
      expect(server.appliedCount, 0);
      expect(server.rejectedMutations, 2);

      // Ordinary post-baseline synchronization (v2, untokened) still works.
      final ack = await applyWith(null, 'normal');
      expect((ack! as Map)['status'], 'applied');
      expect(server.appliedCount, 1);
      expect(server.claimToken, 'token-b');
    },
  );

  test(
    'a local write at the exact completion boundary prevents the durable completion',
    () async {
      server
        ..hasHistory = true
        ..claimCompleted = true
        ..nextChangeId = 3
        ..changeCount = 2;
      final seedGateway = FakeSyncRemoteGateway(calls: calls, account: server);
      final database = AppDatabase(NativeDatabase.memory());
      databases.add(database);
      seedGateway.seedChanges([
        remoteCategoryChange(
          id: 'cloud-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
        remoteTaskChange(
          id: 'cloud-task',
          title: 'Cloud task',
          changeId: 0,
          serverVersion: 0,
          categoryId: 'cloud-cat',
        ),
      ]);
      final anonymous = AnonymousDatabaseFixture.create();
      anonymousFixtures.add(anonymous);
      final remote = FakeSyncRemoteGateway(calls: calls, account: server);
      var boundaryReached = false;
      final coordinator = InitialSyncCoordinator(
        database: database,
        scope: scope,
        gateway: server,
        repositoryFactory: () => SyncRepository.withGateway(
          database,
          remote,
          scope.storageId,
          currentAccountId: () => scope.storageId,
        ),
        anonymousDatabaseFactory: anonymous.open,
        currentAccountId: () => scope.storageId,
        operationTimeout: const Duration(seconds: 5),
        // Sol's race: the restore has already produced a clean local result and
        // a genuine Planner write now commits before the durable transition.
        onCompletionBoundary: () async {
          boundaryReached = true;
          await insertLocalTask(
            database,
            id: 'race-task',
            title: 'Written at the completion boundary',
          );
        },
      );

      await coordinator.start();

      expect(boundaryReached, isTrue, reason: 'the boundary must be exercised');
      final state = await InitialSyncStateStore(database).read();
      expect(state.phase, InitialSyncPhase.conflict);
      expect(state.baselineComplete, isFalse);
      expect(state.detail?['message'], restoreLocalWorkConflictMessage);
      // The user's work is durable and outboxed, and nothing was pushed.
      expect(await database.taskDao.getTaskById('race-task'), isNotNull);
      expect(await database.syncDao.pendingCount(), 1);
      expect(remote.applyCalls, 0);
      expect(server.appliedCount, 0);
      // The cloud copy is preserved untouched.
      expect(server.remoteChanges, hasLength(2));
      expect(server.claimCompleted, isTrue);
    },
  );

  test(
    'a local edit after the durable completion is ordinary post-baseline work',
    () async {
      server
        ..hasHistory = true
        ..claimCompleted = true
        ..nextChangeId = 2
        ..changeCount = 1;
      final seedGateway = FakeSyncRemoteGateway(calls: calls, account: server);
      final database = AppDatabase(NativeDatabase.memory());
      databases.add(database);
      seedGateway.seedChanges([
        remoteCategoryChange(
          id: 'cloud-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
      ]);
      final anonymous = AnonymousDatabaseFixture.create();
      anonymousFixtures.add(anonymous);
      final remote = FakeSyncRemoteGateway(calls: calls, account: server);
      final coordinator = InitialSyncCoordinator(
        database: database,
        scope: scope,
        gateway: server,
        repositoryFactory: () => SyncRepository.withGateway(
          database,
          remote,
          scope.storageId,
          currentAccountId: () => scope.storageId,
        ),
        anonymousDatabaseFactory: anonymous.open,
        currentAccountId: () => scope.storageId,
        operationTimeout: const Duration(seconds: 5),
      );

      await coordinator.start();
      expect(
        (await InitialSyncStateStore(database).read()).phase,
        InitialSyncPhase.complete,
      );

      // A genuine local edit after the durable completion is normal work...
      await insertLocalCategory(
        database,
        id: 'after-complete',
        name: 'After completion',
      );
      expect(
        (await InitialSyncStateStore(database).read()).phase,
        InitialSyncPhase.complete,
        reason: 'post-completion work never reopens the first-sync state',
      );
      expect(await database.syncDao.pendingCount(), 1);

      // ...and it synchronizes through the ordinary, untokened route.
      final repository = SyncRepository.withGateway(
        database,
        remote,
        scope.storageId,
        currentAccountId: () => scope.storageId,
      );
      expect(await repository.push(), isNull);
      expect(await database.syncDao.pendingCount(), 0);
      expect(server.appliedCount, 1);
      expect(
        remote.appliedOperations.single['record_id'],
        'after-complete',
        reason: 'the post-completion edit reached the server normally',
      );
    },
  );

  test('unknown remote state never claims, uploads or completes', () async {
    final a = device();
    await insertLocalCategory(a.database, id: 'a-cat', name: 'A work');
    server.stateError = Exception('SocketException: network is unreachable');

    await a.coordinator.start();

    final state = await stateOf(a);
    expect(state.phase, InitialSyncPhase.retryable);
    expect(server.claimCalls, 0);
    expect(server.completeCalls, 0);
    expect(server.appliedCount, 0);
    expect(a.remote.pullCalls, 0);
  });
}

class _Device {
  const _Device({
    required this.database,
    required this.remote,
    required this.coordinator,
  });

  final AppDatabase database;
  final FakeSyncRemoteGateway remote;
  final InitialSyncCoordinator coordinator;
}
