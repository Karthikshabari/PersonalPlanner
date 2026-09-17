import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/initial_sync_coordinator.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_settings_provider.dart';

import '../../helpers/initial_sync_fakes.dart';
import '../../helpers/runtime_auth_fakes.dart';
import '../../helpers/sqlite_setup.dart';

/// Phase H treatment of the Phase G `recovery_required` state.
///
/// The protocol decision is untouched: the server still refuses to hand over an
/// abandoned first baseline that may already own partial cloud rows, and the
/// client still refuses to merge or overwrite. What Phase H adds is a durable,
/// distinguishable lifecycle state plus the guarantee that it survives a
/// restart, keeps normal synchronization switched off, and only ever offers
/// non-destructive actions.
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
  late AppDatabase database;
  late AnonymousDatabaseFixture anonymous;
  late int claimTokenCounter;

  setUp(() {
    calls = <RemoteCall>[];
    claimTokenCounter = 0;
    // A previous device uploaded 30% of its first baseline and its lease
    // lapsed: exactly the state Phase G deliberately refuses to auto-resolve.
    server = FakeInitialSyncGateway(calls: calls)
      ..claimToken = 'abandoned-claim'
      ..claimClaimedAt = DateTime.now().toUtc()
      ..hasHistory = true
      ..nextChangeId = 4
      ..changeCount = 3
      ..leaseExpired = true;
    database = AppDatabase(NativeDatabase.memory());
    anonymous = AnonymousDatabaseFixture.create();
  });

  tearDown(() async {
    await database.close();
    anonymous.delete();
  });

  InitialSyncCoordinator coordinator() => InitialSyncCoordinator(
    database: database,
    scope: scope,
    gateway: server,
    repositoryFactory: () => SyncRepository.withGateway(
      database,
      FakeSyncRemoteGateway(calls: calls, account: server),
      scope.storageId,
      currentAccountId: () => scope.storageId,
    ),
    anonymousDatabaseFactory: anonymous.open,
    currentAccountId: () => scope.storageId,
    operationTimeout: const Duration(seconds: 5),
    claimTokenFactory: () => 'claim-${++claimTokenCounter}',
  );

  Future<InitialSyncRecord> durableState() =>
      InitialSyncStateStore(database).read();

  test(
    'recovery_required is its own durable state, not a plain conflict',
    () async {
      await insertLocalCategory(database, id: 'local-cat', name: 'Local work');

      final first = coordinator();
      await first.start();
      await first.dispose();

      final record = await durableState();
      expect(record.phase, InitialSyncPhase.recoveryRequired);
      expect(record.phase.needsRecoveryDecision, isTrue);
      expect(record.baselineComplete, isFalse);
      expect(record.detail?['message'], baselineRecoveryRequiredMessage);
      expect(record.claimToken, isNull);

      // Nothing was merged, uploaded, restored or completed.
      expect(server.claimToken, 'abandoned-claim');
      expect(server.claimCompleted, isFalse);
      expect(server.appliedCount, 0);
      expect(
        calls.where((call) => call.boundary == 'data'),
        isEmpty,
        reason: 'no Planner data RPC may run for this account',
      );
      expect(await database.taskDao.getTaskById('local-cat'), isNull);
      expect(await database.syncDao.pendingCount(), greaterThan(0));
    },
  );

  test('the state survives a restart and a retry stays non-destructive', () async {
    await insertLocalCategory(database, id: 'local-cat', name: 'Local work');

    final first = coordinator();
    await first.start();
    await first.dispose();
    final claimsAfterFirstRun = server.claimCalls;

    // Restart: a brand new coordinator over the same durable database.
    final second = coordinator();
    await second.start();
    await second.dispose();

    final record = await durableState();
    expect(record.phase, InitialSyncPhase.recoveryRequired);
    expect(record.detail?['message'], baselineRecoveryRequiredMessage);
    // The client asked the server again instead of deciding on its own.
    expect(server.claimCalls, claimsAfterFirstRun + 1);
    expect(server.claimToken, 'abandoned-claim');
    expect(server.claimCompleted, isFalse);
    expect(server.appliedCount, 0);
    expect(await database.syncDao.pendingCount(), greaterThan(0));
  });

  test('normal provisioned synchronization stays switched off', () async {
    await insertLocalCategory(database, id: 'local-cat', name: 'Local work');
    final first = coordinator();
    await first.start();
    await first.dispose();

    final client = FakeRuntimeAuthClient()
      ..emitSignedIn(
        testAuthSession(authUserId: authUserIdX, email: 'person@example.com'),
      );
    final repository = AuthRepository(client);
    final controller = AuthSessionController(repository);
    await controller.start();
    final backend = testProvisionedBackend();
    final remotely = FakeSyncRemoteGateway(calls: calls);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        openAccountScopeProvider.overrideWithValue(scope),
        runtimeAuthStackProvider.overrideWith(
          () => RuntimeAuthStackNotifier(
            RuntimeAuthStack(
              backend: backend,
              repository: repository,
              controller: controller,
            ),
          ),
        ),
        syncRemoteFactoryProvider.overrideWithValue(
          FakeSyncRemoteFactory(
            initialSyncGateway: server,
            syncGateway: remotely,
          ),
        ),
        anonymousDatabaseFactoryProvider.overrideWithValue(anonymous.open),
      ],
    );
    try {
      final status = container.listen(syncStatusProvider, (previous, next) {});
      final initialSync = container.listen(
        syncInitialSyncProvider,
        (previous, next) {},
      );
      for (var attempt = 0;
          attempt < 100 &&
              initialSync.read().value?.phase !=
                  InitialSyncPhase.recoveryRequired;
          attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(Duration.zero);
      await container.read(syncEnabledProvider.future);

      expect(
        initialSync.read().value?.phase,
        InitialSyncPhase.recoveryRequired,
        reason: 'the durable account state must reach the provider graph',
      );
      expect(container.read(syncRepositoryProvider), isNull);
      expect(container.read(syncEngineProvider), isNull);
      final snapshot = status.read().value;
      expect(snapshot?.state, SyncEngineState.initialSyncPending);
      expect(snapshot?.message, baselineRecoveryRequiredMessage);
      expect(remotely.applyCalls, 0);
      expect(remotely.pullCalls, 0);
      initialSync.close();
      status.close();
    } finally {
      container.dispose();
      await controller.dispose();
      await repository.dispose();
      await client.close();
    }
  });
}
