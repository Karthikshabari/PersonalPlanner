import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/domain/sync_engine.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_settings_provider.dart';

import '../../helpers/initial_sync_fakes.dart';
import '../../helpers/runtime_auth_fakes.dart';
import '../../helpers/sqlite_setup.dart';

/// Phase G activation gate: a signed-in provisioned account gets runtime Auth
/// immediately, but SyncRepository, SyncEngine, automatic push/pull and
/// "Sync now" exist only after the durable initial-synchronization baseline.
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
  late FakeRuntimeAuthClient client;
  late AuthRepository authRepository;
  late AuthSessionController controller;
  late List<RemoteCall> calls;
  late FakeInitialSyncGateway initial;
  late FakeSyncRemoteGateway remote;
  late ProviderContainer container;
  late List<ProviderSubscription<dynamic>> subscriptions;
  late _RecordingConnectivity connectivity;

  Future<void> buildContainer({
    RuntimeBackend? backend,
    PlannerAccountScope? scope,
    AppDatabase? database,
  }) async {
    final effectiveBackend = backend ?? testProvisionedBackend();
    client.emitSignedIn(
      testAuthSession(authUserId: authUserIdX, email: 'person@example.com'),
    );
    await controller.start();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database ?? accountDb),
        openAccountScopeProvider.overrideWithValue(
          scope ?? effectiveBackend.accountScopeFor(authUserIdX),
        ),
        runtimeAuthStackProvider.overrideWith(
          () => RuntimeAuthStackNotifier(
            RuntimeAuthStack(
              backend: effectiveBackend,
              repository: authRepository,
              controller: controller,
            ),
          ),
        ),
        syncRemoteFactoryProvider.overrideWithValue(
          FakeSyncRemoteFactory(
            initialSyncGateway: initial,
            syncGateway: remote,
          ),
        ),
        syncConnectivityMonitorProvider.overrideWithValue(connectivity),
        anonymousDatabaseFactoryProvider.overrideWithValue(anonymous.open),
      ],
    );
    subscriptions = <ProviderSubscription<dynamic>>[
      container.listen(initialSyncCoordinatorProvider, (previous, next) {}),
      container.listen(syncRepositoryProvider, (previous, next) {}),
      container.listen(syncEngineProvider, (previous, next) {}),
      container.listen(syncStatusProvider, (previous, next) {}),
    ];
  }

  setUp(() {
    accountDb = AppDatabase(NativeDatabase.memory());
    anonymous = AnonymousDatabaseFixture.create();
    client = FakeRuntimeAuthClient();
    authRepository = AuthRepository(client);
    controller = AuthSessionController(authRepository);
    calls = <RemoteCall>[];
    initial = FakeInitialSyncGateway(calls: calls);
    remote = FakeSyncRemoteGateway(calls: calls);
    connectivity = _RecordingConnectivity();
    subscriptions = <ProviderSubscription<dynamic>>[];
  });

  tearDown(() async {
    subscriptions.clear();
    container.dispose();
    await connectivity.close();
    await controller.dispose();
    await authRepository.dispose();
    await client.close();
    await accountDb.close();
    anonymous.delete();
  });

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await pumpEventQueue();
    }
  }

  test(
    'Test 12 - authentication alone leaves a provisioned account without any sync surface',
    () async {
      // The cloud is unreachable: remote state stays explicitly unknown.
      initial.stateError = Exception('SocketException: network is unreachable');

      await buildContainer();
      await settle();
      await container.read(initialSyncCoordinatorProvider)!.start();
      await settle();

      expect(container.read(authSessionControllerProvider), controller);
      expect(controller.session?.user.id, authUserIdX);
      expect(await container.read(syncEnabledProvider.future), isTrue);
      expect(container.read(openAccountScopeProvider), scopeA);
      expect(
        container.read(syncRepositoryProvider),
        isNull,
        reason: 'a provisioned account without a baseline has no repository',
      );
      expect(
        container.read(syncEngineProvider),
        isNull,
        reason: 'no SyncEngine may start before the baseline exists',
      );
      expect(container.read(syncStatusProvider).value?.state, SyncEngineState.initialSyncPending);
      expect(container.read(syncStatusProvider).value?.message, isNotNull);

      // Zero remote mutation while the remote state is unknown.
      expect(initial.claimCalls, 0);
      expect(remote.applyCalls, 0);
      expect(remote.pullCalls, 0);
      final record = await InitialSyncStateStore(accountDb).read();
      expect(record.phase, InitialSyncPhase.retryable);
      expect(record.baselineComplete, isFalse);
    },
  );

  test(
    'Test 13 - normal provisioned sync becomes available only after the baseline completes',
    () async {
      // First connection attempt is offline, so the account stays pre-baseline.
      initial.stateError = Exception('SocketException: network is unreachable');
      var appliesWhenServerCompleted = -1;
      initial.onComplete = () => appliesWhenServerCompleted = remote.applyCalls;
      await buildContainer();
      await settle();

      // Pre-baseline: no sync surface at all.
      expect(container.read(syncRepositoryProvider), isNull);
      expect(container.read(syncEngineProvider), isNull);
      expect(
        (await InitialSyncStateStore(accountDb).read()).phase,
        InitialSyncPhase.retryable,
      );

      // Connectivity returns and the account is proven unused on both sides.
      initial.stateError = null;
      await container.read(initialSyncCoordinatorProvider)!.retry();
      await settle();

      final record = await InitialSyncStateStore(accountDb).read();
      expect(record.phase, InitialSyncPhase.complete);
      expect(
        container.read(syncRepositoryProvider),
        isNotNull,
        reason: 'the baseline unlocks the normal provisioned repository',
      );
      expect(container.read(syncEngineProvider), isNotNull);
      // Post-baseline normal sync runs: the freshly seeded default categories
      // are uploaded through the durable outbox (nothing was pushed earlier).
      await settle();
      expect(await accountDb.syncDao.pendingCount(), 0);
      expect(remote.applyCalls, 4);
      await container.read(syncEngineProvider)?.stop();
      await settle();

      // The empty account is established by exactly one server-side baseline
      // claim and completion; no Planner rows had to be uploaded for that.
      expect(initial.claimCalls, 1);
      expect(initial.completeCalls, 1);
      expect(remote.applyCalls, 4, reason: 'only the seeded defaults upload');
      expect(
        appliesWhenServerCompleted,
        0,
        reason: 'no Planner mutation may precede server baseline completion',
      );
      expect(initial.claimCompleted, isTrue);
    },
  );

  test(
    'a foreign in-progress first baseline keeps every sync surface disabled',
    () async {
      // Another device owns the first baseline and has already uploaded part of
      // its data: those rows are explicitly not a completed remote dataset.
      initial
        ..claimToken = 'device-a-claim'
        ..claimClaimedAt = DateTime.now().toUtc()
        ..hasHistory = true
        ..nextChangeId = 3
        ..changeCount = 2;

      await buildContainer();
      await settle();
      await container.read(initialSyncCoordinatorProvider)!.start();
      await settle();

      final record = await InitialSyncStateStore(accountDb).read();
      expect(record.baselineComplete, isFalse);
      expect(record.phase, InitialSyncPhase.retryable);
      expect(
        container.read(syncRepositoryProvider),
        isNull,
        reason: 'a partial foreign baseline is not complete cloud data',
      );
      expect(container.read(syncEngineProvider), isNull);
      expect(container.read(syncStatusProvider).value?.state,
          SyncEngineState.initialSyncPending);
      // Zero remote mutation and zero restore of the partial rows.
      expect(remote.applyCalls, 0);
      expect(remote.pullCalls, 0);
      expect(initial.claimCalls, 0, reason: 'a live foreign claim is not contested');
      expect(initial.completeCalls, 0);
    },
  );

  test(
    'Test 7 - the same user in two projects has separate state, database and remote target',
    () async {
      final databaseA = accountDb;
      final databaseB = AppDatabase(NativeDatabase.memory());
      final anonymousB = AnonymousDatabaseFixture.create();
      final callsB = <RemoteCall>[];
      final initialB = FakeInitialSyncGateway(calls: callsB)
        ..stateError = Exception('SocketException: offline');
      final remoteB = FakeSyncRemoteGateway(calls: callsB);
      final containerB = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(databaseB),
          openAccountScopeProvider.overrideWithValue(scopeB),
          runtimeAuthStackProvider.overrideWith(
            () => RuntimeAuthStackNotifier(
              RuntimeAuthStack(
                backend: testProvisionedBackend(projectRef: projectRefB),
                repository: authRepository,
                controller: controller,
              ),
            ),
          ),
          syncRemoteFactoryProvider.overrideWithValue(
            FakeSyncRemoteFactory(
              initialSyncGateway: initialB,
              syncGateway: remoteB,
            ),
          ),
          anonymousDatabaseFactoryProvider.overrideWithValue(anonymousB.open),
        ],
      );
      final containerSubscriptions = <ProviderSubscription<dynamic>>[
        containerB.listen(initialSyncCoordinatorProvider, (previous, next) {}),
      ];
      try {
        await buildContainer();
        await settle();
        await container.read(initialSyncCoordinatorProvider)!.start();
        await settle();
        await containerB.read(initialSyncCoordinatorProvider)!.start();
        await settle();

        final recordA = await InitialSyncStateStore(databaseA).read();
        final recordB = await InitialSyncStateStore(databaseB).read();
        expect(recordA.phase, InitialSyncPhase.complete);
        expect(recordB.phase, InitialSyncPhase.retryable);

        // Separate remote targets: each account talks to its own project.
        final bindingA = container.read(syncAccountBindingProvider)!;
        final bindingB = containerB.read(syncAccountBindingProvider)!;
        expect(bindingA.endpoint.url, 'https://$projectRefA.supabase.co');
        expect(bindingB.endpoint.url, 'https://$projectRefB.supabase.co');
        expect(bindingA.accountId, 'project_${projectRefA}__user_$authUserIdX');
        expect(bindingB.accountId, 'project_${projectRefB}__user_$authUserIdX');
        expect(initialB.stateCalls, greaterThanOrEqualTo(1));
        expect(initial.stateCalls, greaterThanOrEqualTo(1));
      } finally {
        containerSubscriptions.clear();
        containerB.dispose();
        await databaseB.close();
        anonymousB.delete();
      }
    },
  );
}

/// Connectivity stand-in: no platform plugin is available under unit tests.
class _RecordingConnectivity implements SyncConnectivityMonitor {
  final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get changes => _changes.stream;

  @override
  Future<List<ConnectivityResult>> check() async =>
      <ConnectivityResult>[ConnectivityResult.ethernet];

  Future<void> close() => _changes.close();
}
