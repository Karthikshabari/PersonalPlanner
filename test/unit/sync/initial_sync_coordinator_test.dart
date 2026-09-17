import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/anonymous_data_adoption.dart';
import 'package:personal_planner/features/sync/data/initial_sync_coordinator.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';

import '../../helpers/initial_sync_fakes.dart';
import '../../helpers/runtime_auth_fakes.dart';
import '../../helpers/sqlite_setup.dart';

/// Phase G mandatory matrix: safe initial synchronization and adoption for a
/// provisioned user-owned backend.
///
/// Every safety assertion measures the remote boundary directly (recording
/// gateways), so "zero remote mutation" is observed rather than inferred.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final scopeA = PlannerAccountScope.provisioned(
    projectRef: projectRefA,
    authUserId: authUserIdX,
  );
  final scopeB = PlannerAccountScope.provisioned(
    projectRef: projectRefB,
    authUserId: authUserIdX,
  );

  late AppDatabase accountDb;
  late AnonymousDatabaseFixture anonymous;
  late List<RemoteCall> calls;
  late FakeInitialSyncGateway initial;
  late FakeSyncRemoteGateway remote;
  late String currentAccountId;
  late int claimTokenCounter;
  late int seedCalls;

  setUp(() {
    accountDb = AppDatabase(NativeDatabase.memory());
    anonymous = AnonymousDatabaseFixture.create();
    calls = <RemoteCall>[];
    initial = FakeInitialSyncGateway(calls: calls);
    remote = FakeSyncRemoteGateway(calls: calls);
    currentAccountId = scopeA.storageId;
    claimTokenCounter = 0;
    seedCalls = 0;
  });

  tearDown(() async {
    await accountDb.close();
    anonymous.delete();
  });

  InitialSyncCoordinator coordinator({
    String? Function()? current,
    SyncRepository Function()? repository,
  }) => InitialSyncCoordinator(
    database: accountDb,
    scope: scopeA,
    gateway: initial,
    repositoryFactory:
        repository ??
        () => SyncRepository.withGateway(
          accountDb,
          remote,
          scopeA.storageId,
          currentAccountId: current ?? () => currentAccountId,
        ),
    anonymousDatabaseFactory: anonymous.open,
    currentAccountId: current ?? () => currentAccountId,
    seedDefaultsIfEmpty: () async {
      seedCalls += 1;
      await CategoryRepository(accountDb).seedDefaultsIfEmpty();
    },
    operationTimeout: const Duration(seconds: 5),
    claimTokenFactory: () => 'claim-token-${++claimTokenCounter}',
  );

  Future<InitialSyncRecord> durableState() =>
      InitialSyncStateStore(accountDb).read();

  Future<int> localTaskCount() async =>
      (await accountDb.select(accountDb.tasks).get()).length;

  Future<int> localCategoryCount() async =>
      (await accountDb.select(accountDb.categories).get()).length;

  test(
    'the client classifies every server fence message as a baseline fence',
    () {
      // These exact strings are asserted to exist in migration 6 by
      // sql_migration_contract_test.dart, so the server and the client cannot
      // drift apart silently.
      const messages = <String>[
        'No active initial baseline claim: this account is being established by a fenced first synchronization',
        'No active initial baseline claim for this account',
        'Initial baseline claim is no longer owned by this device',
        'Initial baseline claim is no longer active: the baseline is already completed; use ordinary synchronization',
      ];
      for (final message in messages) {
        final failure = classifySyncFailure(
          PostgrestException(message: message, code: 'P0001'),
        );
        expect(
          isInitialBaselineFencingFailure(failure),
          isTrue,
          reason: message,
        );
        expect(failure.kind, SyncFailureKind.retryable, reason: message);
        expect(failure.message, initialBaselineFencedMessage);
      }
      // An unrelated server failure is not treated as a fence.
      final other = classifySyncFailure(
        PostgrestException(message: 'unexpected server error', code: 'XX000'),
      );
      expect(isInitialBaselineFencingFailure(other), isFalse);
    },
  );

  test(
    'Test 1 - a fresh device restores existing cloud data and pushes nothing',
    () async {
      initial
        ..hasHistory = true
        ..nextChangeId = 3
        ..changeCount = 2
        ..liveRowTotal = 2;
      remote.seedChanges([
        remoteCategoryChange(
          id: 'remote-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
        remoteTaskChange(
          id: 'remote-task',
          title: 'Cloud task',
          changeId: 0,
          serverVersion: 0,
          categoryId: 'remote-cat',
        ),
      ]);

      await coordinator().start();

      // Discovery is the first remote boundary call, and no local mutation was
      // pushed: the remote-first restore owns the first data call.
      expect(calls.first.toString(), 'initial.accountState');
      expect(remote.applyCalls, 0);
      expect(initial.claimCalls, 0);
      expect(remote.pullCalls, greaterThanOrEqualTo(1));
      expect(calls[1].name, 'pull');

      final task = await accountDb.taskDao.getTaskById('remote-task');
      expect(task, isNotNull);
      expect(task!.title, 'Cloud task');
      expect(await accountDb.categoryDao.getCategoryById('remote-cat'), isNotNull);
      expect(await accountDb.syncDao.pendingCount(), 0);

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(record.claimToken, isNull);
      expect(initial.completeCalls, 0);

      // Bootstrap defaults did not appear locally and were never uploaded.
      expect(
        await accountDb.categoryDao.getCategoryById(
          CategoryRepository.defaultCategoryId('work'),
        ),
        isNull,
      );
      expect(seedCalls, 0);
    },
  );

  test(
    'Test 2 - local Planner data is uploaded only after the cloud is proven empty',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      await insertLocalTask(
        accountDb,
        id: 'local-task',
        title: 'Local task',
        categoryId: 'local-cat',
      );
      expect(await accountDb.syncDao.pendingCount(), 2);

      await coordinator().start();

      final names = calls.map((call) => call.name).toList();
      expect(calls.first.name, 'accountState');
      expect(names.indexOf('claimBaseline'), lessThan(names.indexOf('apply')));
      expect(names.indexOf('pull'), lessThan(names.indexOf('apply')));
      expect(initial.claims.single.observed, 1);
      expect(remote.applyCalls, 2);
      expect(
        remote.appliedOperations.map((entry) => entry['record_id']),
        containsAll(<String>['local-cat', 'local-task']),
      );
      expect(initial.completions, hasLength(1));
      expect(await accountDb.syncDao.pendingCount(), 0);
      expect(await localTaskCount(), 1);
      expect(await localCategoryCount(), 1);

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(record.claimToken, isNull);
    },
  );

  test(
    'Test 3 - local data plus a non-empty cloud stops without touching either side',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      await insertLocalTask(
        accountDb,
        id: 'local-task',
        title: 'Local task',
        categoryId: 'local-cat',
      );
      initial
        ..hasHistory = true
        ..nextChangeId = 4
        ..changeCount = 3
        ..liveRowTotal = 3;
      remote.seedChanges([
        remoteCategoryChange(
          id: 'remote-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
        remoteTaskChange(
          id: 'remote-task',
          title: 'Cloud task',
          changeId: 0,
          serverVersion: 0,
          categoryId: 'remote-cat',
        ),
      ]);

      await coordinator().start();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.conflict);
      expect(record.baselineComplete, isFalse);
      // Zero blind push, zero pull that could overwrite local data.
      expect(remote.applyCalls, 0);
      expect(remote.pullCalls, 0);
      expect(initial.claimCalls, 0);
      expect(initial.completeCalls, 0);
      // Both datasets are preserved exactly as they were.
      expect((await accountDb.taskDao.getTaskById('local-task')), isNotNull);
      expect(await accountDb.taskDao.getTaskById('remote-task'), isNull);
      expect(await localTaskCount(), 1);
      expect(await localCategoryCount(), 1);
      expect(await accountDb.syncDao.pendingCount(), 2);
    },
  );

  test(
    'Test 4 / 5 - discovery failure is retryable, never "empty", and the local Planner keeps working',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      await insertLocalTask(
        accountDb,
        id: 'local-task',
        title: 'Local task',
        categoryId: 'local-cat',
      );
      initial.stateError = Exception('SocketException: network is unreachable');

      await coordinator().start();

      var record = await durableState();
      expect(record.phase, InitialSyncPhase.retryable);
      expect(record.detail?['message'], isNotNull);
      expect(initial.claimCalls, 0);
      expect(remote.applyCalls, 0);
      expect(remote.pullCalls, 0);

      // The local Planner stays usable while the cloud state is unknown.
      await insertLocalTask(
        accountDb,
        id: 'offline-task',
        title: 'Written while offline',
      );
      expect(await localTaskCount(), 2);

      // Connectivity returns: discovery happens first, then the upload.
      initial.stateError = null;
      await coordinator().start();
      record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(remote.applyCalls, 3);
      expect(
        calls
            .where((call) => call.name == 'accountState')
            .length,
        2,
      );
    },
  );

  test('Test 5b - a discovery timeout is retryable and mutates nothing', () async {
    await insertLocalTask(accountDb, id: 'local-task', title: 'Local task');
    initial.stateGate = Completer<void>();

    await InitialSyncCoordinator(
      database: accountDb,
      scope: scopeA,
      gateway: initial,
      repositoryFactory: () => SyncRepository.withGateway(
        accountDb,
        remote,
        scopeA.storageId,
        currentAccountId: () => currentAccountId,
      ),
      anonymousDatabaseFactory: anonymous.open,
      currentAccountId: () => currentAccountId,
      operationTimeout: const Duration(milliseconds: 50),
      claimTokenFactory: () => 'claim-token-timeout',
    ).start();

    final record = await durableState();
    expect(record.phase, InitialSyncPhase.retryable);
    expect(initial.claimCalls, 0);
    expect(remote.applyCalls, 0);
    expect(remote.pullCalls, 0);
  });

  test(
    'Test 6 - seeded default categories cannot pollute a used cloud account',
    () async {
      // A database seeded by an earlier build: untouched defaults plus their
      // durable seed inserts, and no user content.
      await CategoryRepository(accountDb).seedDefaultsIfEmpty();
      expect(await accountDb.syncDao.pendingCount(), 4);

      initial
        ..hasHistory = true
        ..nextChangeId = 8
        ..changeCount = 4
        ..liveRowTotal = 2;
      remote.seedChanges([
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

      await coordinator().start();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(remote.applyCalls, 0);
      expect(await accountDb.syncDao.pendingCount(), 0);
      expect(
        await accountDb.categoryDao.getCategoryById(
          CategoryRepository.defaultCategoryId('work'),
        ),
        isNull,
      );
      expect(
        await accountDb.categoryDao.getCategoryById('cloud-cat'),
        isNotNull,
      );
      expect(await accountDb.taskDao.getTaskById('cloud-task'), isNotNull);
      expect(await localCategoryCount(), 1);
      expect(seedCalls, 0);
    },
  );

  test(
    'Test 8 - an account switch during discovery drops the stale result',
    () async {
      initial
        ..hasHistory = true
        ..nextChangeId = 4
        ..liveRowTotal = 1;
      initial.onState = () => currentAccountId = scopeB.storageId;

      await coordinator().start();

      final record = await durableState();
      // Only the pre-switch "discovering" marker exists; the Project A result
      // was never allowed to decide anything for the replacement account.
      expect(record.phase, InitialSyncPhase.discovering);
      expect(record.baselineComplete, isFalse);
      expect(initial.claimCalls, 0);
      expect(remote.applyCalls, 0);
      expect(remote.pullCalls, 0);
    },
  );

  test(
    'Test 9 - an account switch during the first upload never completes the baseline',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      await insertLocalTask(
        accountDb,
        id: 'local-task',
        title: 'Local task',
        categoryId: 'local-cat',
      );
      remote.onApply = () => currentAccountId = scopeB.storageId;

      await coordinator().start();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.uploading);
      expect(record.baselineComplete, isFalse);
      expect(initial.completeCalls, 0);
      // The in-flight operation was released back to the durable queue; the
      // replacement account saw no acknowledgement.
      expect(await accountDb.syncDao.pendingCount(), 2);
      expect(await localTaskCount(), 1);
    },
  );

  test(
    'Test 10a - restart resumes a remote-first restore from the durable cursor',
    () async {
      initial
        ..hasHistory = true
        ..nextChangeId = 5
        ..changeCount = 2
        ..liveRowTotal = 2;
      remote.seedChanges([
        remoteCategoryChange(
          id: 'remote-cat',
          name: 'Cloud category',
          changeId: 0,
          serverVersion: 0,
        ),
        remoteTaskChange(
          id: 'remote-task',
          title: 'Cloud task',
          changeId: 0,
          serverVersion: 0,
          categoryId: 'remote-cat',
        ),
      ]);
      remote.pullError = Exception('SocketException: connection reset');

      await coordinator().start();

      var record = await durableState();
      expect(record.phase, InitialSyncPhase.retryable);
      expect(record.baselineComplete, isFalse);
      expect(await localTaskCount(), 0);

      // Restart: a fresh coordinator over the same account database.
      remote.pullError = null;
      await coordinator().start();

      record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(await accountDb.taskDao.getTaskById('remote-task'), isNotNull);
      expect(remote.applyCalls, 0);
    },
  );

  test(
    'Test 10b - restart after a lost acknowledgement resumes without duplicating',
    () async {
      remote.echoApplied = true;
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      await insertLocalTask(
        accountDb,
        id: 'local-task',
        title: 'Local task',
        categoryId: 'local-cat',
      );
      remote
        ..applyError = Exception('SocketException: connection reset')
        ..applyErrorAfterRecord = true;

      await coordinator().start();

      var record = await durableState();
      expect(record.phase, InitialSyncPhase.retryable);
      expect(record.claimToken, isNotNull);
      // The first operation reached the server and the change log before the
      // response was lost; the same failure also hit the second operation.
      expect(remote.applyCalls, 2);
      expect(await accountDb.syncDao.pendingCount(), 2);

      // Restart with the server's acknowledgement still recorded.
      remote.applyError = null;
      await coordinator().start();

      record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      // The pulled self-acknowledgement retired the lost operation; no
      // duplicate upload happened.
      expect(remote.applyCalls, 2);
      expect(await localCategoryCount(), 1);
      expect(await localTaskCount(), 1);
      expect(await accountDb.syncDao.pendingCount(), 0);
      expect(initial.completions, hasLength(1));
    },
  );

  test(
    'Test 10c - a server-completed baseline survives a lost local marker',
    () async {
      await InitialSyncStateStore(accountDb).write(
        const InitialSyncRecord(
          phase: InitialSyncPhase.uploading,
          claimToken: 'claim-token-1',
          observedBaselineChangeId: 1,
        ),
      );
      initial
        ..hasHistory = true
        ..nextChangeId = 3
        ..claimToken = 'claim-token-1'
        ..claimCompleted = true;

      await coordinator().start();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(remote.applyCalls, 0);
      expect(initial.completeCalls, 0);
    },
  );

  test(
    'Test 11 - repeated adoption orchestration never duplicates local entities',
    () async {
      await anonymous.use((db) async {
        await insertLocalCategory(
          db,
          id: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
          name: 'Offline work',
        );
        await insertLocalTask(
          db,
          id: 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
          title: 'Offline task',
          categoryId: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
        );
      });

      final service = coordinator();
      await service.start();

      var record = await durableState();
      if (record.phase != InitialSyncPhase.adoptionRequired) {
        fail('Expected an explicit adoption decision, got ${record.phase}');
      }
      expect(remote.applyCalls, 0);

      await service.adoptOfflineData();
      record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(await localCategoryCount(), 1);
      expect(await localTaskCount(), 1);
      final appliesAfterAdoption = remote.applyCalls;
      expect(appliesAfterAdoption, 2);

      // Orchestrating the same import again must not duplicate anything.
      await service.adoptOfflineData();
      expect(await localCategoryCount(), 1);
      expect(await localTaskCount(), 1);
      expect(remote.applyCalls, appliesAfterAdoption);
      expect((await durableState()).phase, InitialSyncPhase.complete);
    },
  );

  test(
    'Test 11b - keeping offline data separate completes an empty baseline',
    () async {
      await anonymous.use((db) async {
        await insertLocalCategory(
          db,
          id: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
          name: 'Offline work',
        );
      });

      final service = coordinator();
      await service.start();
      expect((await durableState()).phase, InitialSyncPhase.adoptionRequired);

      await service.keepOfflineDataSeparate();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.complete);
      expect(await localCategoryCount(), 4);
      expect(remote.applyCalls, 0);
      expect(seedCalls, greaterThanOrEqualTo(1));
      final decision = await accountDb.syncDao.getSetting(
        anonymousAdoptionDecisionKey,
      );
      expect(decision, 'separate');
    },
  );

  test(
    'Test 14 - a baseline that moved between discovery and claim aborts the upload',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      await insertLocalTask(
        accountDb,
        id: 'local-task',
        title: 'Local task',
        categoryId: 'local-cat',
      );
      initial.onClaim = () {
        // Another device wrote after discovery.
        initial.hasHistory = true;
        initial.nextChangeId = 2;
      };

      await coordinator().start();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.conflict);
      expect(remote.applyCalls, 0);
      expect(remote.pullCalls, 0);
      expect(initial.completeCalls, 0);
      expect(await accountDb.syncDao.pendingCount(), 2);
      expect(await localTaskCount(), 1);
    },
  );

  test(
    'Test 14b - a changed baseline token is reported as a conflict, not an upload',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      initial.onClaim = () {
        initial.nextChangeId = 2;
        initial.claimStatusOverride = 'baseline_changed';
      };

      await coordinator().start();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.conflict);
      expect(record.detail?['message'], contains('changed'));
      expect(remote.applyCalls, 0);
    },
  );

  test(
    'a baseline claim held by another device never uploads local data',
    () async {
      await insertLocalCategory(accountDb, id: 'local-cat', name: 'Local work');
      initial
        ..claimToken = 'other-device-claim'
        ..claimClaimedAt = DateTime.now().toUtc();

      await coordinator().start();

      var record = await durableState();
      expect(record.phase, InitialSyncPhase.conflict);
      expect(remote.applyCalls, 0);
      expect(initial.claims, isEmpty);

      // With no local content the same situation is a retry, not a conflict.
      final cleanDb = AppDatabase(NativeDatabase.memory());
      try {
        await InitialSyncCoordinator(
          database: cleanDb,
          scope: scopeA,
          gateway: initial,
          repositoryFactory: () => SyncRepository.withGateway(
            cleanDb,
            remote,
            scopeA.storageId,
            currentAccountId: () => currentAccountId,
          ),
          anonymousDatabaseFactory: anonymous.open,
          currentAccountId: () => currentAccountId,
          operationTimeout: const Duration(seconds: 5),
        ).start();
        record = await InitialSyncStateStore(cleanDb).read();
        expect(record.phase, InitialSyncPhase.retryable);
      } finally {
        await cleanDb.close();
      }
    },
  );
}
