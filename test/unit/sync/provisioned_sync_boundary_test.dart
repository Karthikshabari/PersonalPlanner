import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_settings_provider.dart';

import '../../helpers/runtime_auth_fakes.dart';
import '../../helpers/initial_sync_fakes.dart';
import '../../helpers/sqlite_setup.dart';

/// Phase G keeps the Phase EF barrier for the first synchronization: a
/// signed-in provisioned account whose cloud state is still unresolved gains no
/// sync repository, no sync engine and no "Sync now", and the sync-enabled flag
/// is untouched. The legacy developer backend keeps its historical behaviour.
void main() {
  setupSqliteForTests();

  test(
    'a signed-in provisioned account stays out of normal Planner sync until the baseline exists',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = FakeRuntimeAuthClient();
      final repository = AuthRepository(client);
      final controller = AuthSessionController(repository);
      final backend = testProvisionedBackend();
      final scope = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final calls = <RemoteCall>[];
      final anonymous = AnonymousDatabaseFixture.create();
      final initial = FakeInitialSyncGateway(calls: calls)
        // Discovery is unavailable, so the remote state stays unresolvable.
        ..stateError = Exception('SocketException: network is unreachable');
      final remote = FakeSyncRemoteGateway(calls: calls);

      // The user is genuinely signed in to the provisioned project.
      client.emitSignedIn(
        testAuthSession(authUserId: authUserIdX, email: 'person@example.com'),
      );
      await controller.start();

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
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
              initialSyncGateway: initial,
              syncGateway: remote,
            ),
          ),
          anonymousDatabaseFactoryProvider.overrideWithValue(
            anonymous.open,
          ),
        ],
      );

      try {
        expect(container.read(authRepositoryProvider), repository);
        expect(container.read(authSessionControllerProvider), controller);
        expect(controller.session?.user.id, authUserIdX);
        expect(controller.hasUsableAccessToken(), isTrue);

        final coordinatorSubscription = container.listen(
          initialSyncCoordinatorProvider,
          (previous, next) {},
        );
        final statusSubscription = container.listen(
          syncStatusProvider,
          (previous, next) {},
        );
        // Let the session stream publish its first value.
        await Future<void>.delayed(Duration.zero);
        await container.read(initialSyncCoordinatorProvider)!.start();

        // Sync is enabled by default, and the provisioned backend still gets no
        // sync surface at all.
        expect(await container.read(syncEnabledProvider.future), isTrue);
        expect(
          container.read(syncRepositoryProvider),
          isNull,
          reason: 'a provisioned backend must not expose a sync repository',
        );
        expect(
          container.read(syncEngineProvider),
          isNull,
          reason: 'SyncEngine must never start for a provisioned backend',
        );
        expect(
          statusSubscription.read().value?.state,
          SyncEngineState.initialSyncPending,
        );

        // Turning sync off, then seeing another Auth event, changes nothing.
        await container.read(syncEnabledProvider.notifier).setEnabled(false);
        client.emitTokenRefreshed(testAuthSession(authUserId: authUserIdX));
        await Future<void>.delayed(Duration.zero);
        expect(await container.read(syncEnabledProvider.future), isFalse);
        expect(container.read(syncRepositoryProvider), isNull);
        expect(container.read(syncEngineProvider), isNull);
        // Zero remote mutation while the remote state is unknown.
        expect(initial.claimCalls, 0);
        expect(remote.applyCalls, 0);
        expect(remote.pullCalls, 0);
        coordinatorSubscription.close();
        statusSubscription.close();
      } finally {
        container.dispose();
        await controller.dispose();
        await repository.dispose();
        await client.close();
        await db.close();
        anonymous.delete();
      }
    },
  );

  test(
    'the compile-time developer backend keeps its sync repository',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = FakeRuntimeAuthClient();
      final repository = AuthRepository(client);
      final controller = AuthSessionController(repository);
      final backend = LegacyStaticRuntimeBackend(
        url: 'https://developer.supabase.co',
        publishableKey: publishableKeyA,
      );

      client.emitSignedIn(testAuthSession(authUserId: authUserIdX));
      await controller.start();

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          openAccountScopeProvider.overrideWithValue(
            PlannerAccountScope.legacyStatic(authUserIdX),
          ),
          runtimeAuthStackProvider.overrideWith(
            () => RuntimeAuthStackNotifier(
              RuntimeAuthStack(
                backend: backend,
                repository: repository,
                controller: controller,
              ),
            ),
          ),
        ],
      );

      try {
        await container.read(syncEnabledProvider.future);
        // The session stream has to publish before the repository can exist.
        final sessionSubscription = container.listen(
          authSessionStateProvider,
          (previous, next) {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(sessionSubscription.read().value?.session, isNotNull);
        expect(container.read(syncRepositoryProvider), isNotNull);
        sessionSubscription.close();
      } finally {
        container.dispose();
        await controller.dispose();
        await repository.dispose();
        await client.close();
        await db.close();
      }
    },
  );
}
