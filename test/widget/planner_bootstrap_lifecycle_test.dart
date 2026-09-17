import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/features/onboarding/providers/onboarding_provider.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:personal_planner/features/sync/domain/sync_engine.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_settings_provider.dart';
import 'package:personal_planner/features/timer/platform/android_foreground_timer.dart';
import 'package:personal_planner/main.dart';

import '../helpers/initial_sync_fakes.dart';
import '../helpers/runtime_auth_fakes.dart';
import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart' show settle;

/// Phase H lifecycle behaviour of the real bootstrap.
///
/// Only the platform boundaries are substituted. The account-scope drain,
/// runtime-Auth stack identity, database selection and shutdown ordering under
/// test are the production code paths.
void main() {
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() async {
    await resetRuntimeAuthBootstrapForTesting();
    AndroidForegroundTimer.setAccountScope(null);
  });

  testWidgets('sign out returns to local use and keeps the account database', (
    tester,
  ) async {
    final harness = _Harness();
    final stackA = await harness.startSignedIn(
      tester,
      projectRef: projectRefA,
      authUserId: authUserIdX,
    );
    final accountA = _accountId(projectRefA, authUserIdX);
    final databaseA = harness.databaseFor(accountA)!;
    // Durable local work of this account, plus another project's session.
    await databaseA.syncDao.enqueueOperation(
      SyncLogCompanion.insert(
        operationId: 'op-1',
        entityTableName: 'tasks',
        recordId: 'task-1',
        operation: 'update',
        payload: '{}',
        createdAt: DateTime.utc(2026, 9, 17),
        updatedAt: DateTime.utc(2026, 9, 17),
      ),
    );
    final foreignKey = RuntimeAuthNamespaces.forProject(
      projectRefB,
    ).sessionKey;
    harness.secureStore.values[foreignKey] = 'project-b-session';

    await stackA.client.signOut();
    await harness.pumpUntil(
      tester,
      () => harness.activeScopeOrNull(tester) == null,
      reason: 'expected sign-out to return to the local account scope',
    );

    expect(harness.openedAccountIds, [accountA, null]);
    expect(harness.shutdownAccountIds, [accountA]);
    // The account database is preserved exactly: same file, same pending work.
    expect(harness.databaseFor(accountA), same(databaseA));
    expect(await databaseA.syncDao.pendingCount(), 1);
    // Only this project's session was cleared.
    expect(
      harness.secureStore.values.containsKey(
        RuntimeAuthNamespaces.forProject(projectRefA).sessionKey,
      ),
      isFalse,
    );
    expect(harness.secureStore.values[foreignKey], 'project-b-session');
    expect(AndroidForegroundTimer.accountScope, isNull);

    await harness.finish(tester);
  });

  testWidgets('signing back in returns to the same account database', (
    tester,
  ) async {
    final harness = _Harness();
    final stack = await harness.startSignedIn(
      tester,
      projectRef: projectRefA,
      authUserId: authUserIdX,
    );
    final accountA = _accountId(projectRefA, authUserIdX);
    final databaseA = harness.databaseFor(accountA);
    await stack.client.signOut();
    await harness.pumpUntil(
      tester,
      () => harness.activeScopeOrNull(tester) == null,
    );

    stack.client.emitSignedIn(testAuthSession(authUserId: authUserIdX));
    await harness.pumpUntil(
      tester,
      () => harness.activeScopeOrNull(tester) == accountA,
      reason: 'expected the same project/user to reopen its own database',
    );

    expect(harness.openedAccountIds, [accountA, null, accountA]);
    expect(harness.databaseFor(accountA), same(databaseA));

    await harness.finish(tester);
  });

  testWidgets('disabled sync and durable first-sync state survive a restart', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.startSignedIn(
      tester,
      projectRef: projectRefA,
      authUserId: authUserIdX,
    );
    final accountA = _accountId(projectRefA, authUserIdX);
    final databaseA = harness.databaseFor(accountA)!;
    await databaseA.syncDao.setSetting(syncEnabledKey, 'false');
    await InitialSyncStateStore(databaseA).write(
      InitialSyncRecord(
        phase: InitialSyncPhase.recoveryRequired,
        detail: const <String, dynamic>{'message': 'needs a decision'},
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Restart: a brand new bootstrap and provider container over the same
    // durable state (the harness reopens the same database per account id).
    await harness.restart(tester, signedIn: true);

    expect(harness.activeScopeOrNull(tester), accountA);
    final restarted = harness.activeContainer(tester);
    expect(await restarted.read(syncEnabledProvider.future), isFalse);
    expect(harness.databaseFor(accountA), same(databaseA));
    final state = await InitialSyncStateStore(databaseA).read();
    expect(state.phase, InitialSyncPhase.recoveryRequired);
    expect(state.baselineComplete, isFalse);

    await harness.finish(tester);
  });

  testWidgets('a completed baseline is still complete after a restart', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.startSignedIn(
      tester,
      projectRef: projectRefA,
      authUserId: authUserIdX,
    );
    final databaseA = harness.databaseFor(_accountId(projectRefA, authUserIdX))!;
    await InitialSyncStateStore(databaseA).write(
      InitialSyncRecord(
        phase: InitialSyncPhase.complete,
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    await harness.restart(tester, signedIn: true);

    final state = await InitialSyncStateStore(databaseA).read();
    expect(state.phase, InitialSyncPhase.complete);
    expect(state.claimToken, isNull);
    // Reopening the account did not run the Phase G state machine again: no
    // remote discovery, claim or upload is triggered by a restart.
    expect(harness.remoteCalls, isEmpty);

    await harness.finish(tester);
  });

  testWidgets(
    'switching to another project/user opens its own database and drops the '
    'old account',
    (tester) async {
      final harness = _Harness();
      await harness.startSignedIn(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final accountA = _accountId(projectRefA, authUserIdX);
      final accountB = _accountId(projectRefB, authUserIdY);

      // The same device now adopts another user-owned project.
      await harness.adopt(
        tester,
        projectRef: projectRefB,
        authUserId: authUserIdY,
      );

      expect(accountA == accountB, isFalse);
      expect(harness.openedAccountIds, [accountA, accountB]);
      expect(harness.shutdownAccountIds, contains(accountA));
      expect(harness.activeScopeOrNull(tester), accountB);
      expect(AndroidForegroundTimer.accountScope, accountB);

      // A stale event from the replaced project A client cannot move the
      // active scope, open another database, or reach any remote boundary.
      // The replaced project A stack is no longer able to drive anything: it
      // was shut down before project B became active, and the open-target
      // publish only happens after a switch succeeds.
      expect(harness.initializedScopes, [accountA, accountB]);
      expect(harness.remoteCalls, isEmpty);

      await harness.finish(tester);
    },
  );

  testWidgets(
    'a stored backend that no longer resolves tears down the provisioned '
    'runtime',
    (tester) async {
      final harness = _Harness();
      final stackA = await harness.startSignedIn(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final accountA = _accountId(projectRefA, authUserIdX);
      final databaseA = harness.databaseFor(accountA)!;
      // Durable local work and a completed Phase G baseline, so the sync
      // providers can only be absent because the runtime was torn down.
      await databaseA.syncDao.enqueueOperation(
        SyncLogCompanion.insert(
          operationId: 'op-1',
          entityTableName: 'tasks',
          recordId: 'task-1',
          operation: 'update',
          payload: '{}',
          createdAt: DateTime.utc(2026, 9, 17),
          updatedAt: DateTime.utc(2026, 9, 17),
        ),
      );
      await InitialSyncStateStore(databaseA).write(
        InitialSyncRecord(
          phase: InitialSyncPhase.complete,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final provisioned = harness.activeContainer(tester);
      // Precondition: the provisioned runtime really is installed for A/X.
      expect(provisioned.read(runtimeBackendProvider), stackA.backend);
      expect(
        provisioned.read(runtimeAuthStackProvider).hasRuntimeAuth,
        isTrue,
      );
      expect(provisioned.read(authRepositoryProvider), same(stackA.repository));

      // The durable profile no longer resolves (connection_disabled).
      harness.makeBackendUnresolvable();
      await harness.reloadRuntime(tester);
      expect(harness.activeScopeOrNull(tester), isNull);

      // Direct assertions on the resulting runtime graph.
      final local = harness.activeContainer(tester);
      expect(local.read(runtimeBackendProvider), isA<LocalOnlyRuntimeBackend>());
      final stack = local.read(runtimeAuthStackProvider);
      expect(stack.backend, isA<LocalOnlyRuntimeBackend>());
      expect(stack.repository, isNull);
      expect(stack.controller, isNull);
      expect(stack.hasRuntimeAuth, isFalse);
      expect(local.read(authRepositoryProvider), isNull);
      expect(local.read(authSessionControllerProvider), isNull);
      expect(local.read(syncAccountBindingProvider), isNull);
      expect(local.read(syncRepositoryProvider), isNull);
      expect(local.read(syncEngineProvider), isNull);
      // No stale first-sync coordinator is left driving the disconnected
      // project either.
      expect(local.read(initialSyncCoordinatorProvider), isNull);

      // Preserved local state and scope bookkeeping.
      expect(harness.databaseFor(accountA), same(databaseA));
      expect(await databaseA.syncDao.pendingCount(), 1);
      expect(AndroidForegroundTimer.accountScope, isNull);
      expect(harness.openedAccountIds, [accountA, null]);

      // The disconnected project cannot be resumed by an ordinary sign-in: the
      // old Auth client is no longer reachable, so even a late signed-in event
      // from it cannot re-open A/X or restart sync.
      stackA.client.emitSignedIn(
        testAuthSession(authUserId: authUserIdX, email: 'person@example.com'),
      );
      await harness.pumpFrames(tester, 5);
      expect(harness.activeScopeOrNull(tester), isNull);
      expect(harness.remoteCalls, isEmpty);

      await harness.finish(tester);
    },
  );

  testWidgets(
    'an explicit reconnect reuses the same account database and completed '
    'baseline',
    (tester) async {
      final harness = _Harness();
      await harness.startSignedIn(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final accountA = _accountId(projectRefA, authUserIdX);
      final databaseA = harness.databaseFor(accountA)!;
      await InitialSyncStateStore(databaseA).write(
        InitialSyncRecord(
          phase: InitialSyncPhase.complete,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      // Cloud Sync is switched off for this account, so the reconnect below
      // exercises the lifecycle (same database, same remembered backend, same
      // durable baseline) without starting normal synchronization.
      await databaseA.syncDao.setSetting(syncEnabledKey, 'false');

      // Disconnect: durable flag + runtime teardown.
      harness.makeBackendUnresolvable();
      await harness.reloadRuntime(tester);
      expect(harness.activeScopeOrNull(tester), isNull);
      expect(
        harness.activeContainer(tester).read(runtimeBackendProvider),
        isA<LocalOnlyRuntimeBackend>(),
      );

      // Explicit reconnect of the *same remembered* backend: no provisioning,
      // no new database, no new baseline.
      final reconnected = await harness.prepare(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      await harness.reloadRuntime(tester);
      expect(harness.activeScopeOrNull(tester), accountA);

      expect(harness.databaseFor(accountA), same(databaseA));
      final state = await InitialSyncStateStore(databaseA).read();
      expect(state.phase, InitialSyncPhase.complete);
      expect(state.claimToken, isNull);
      // Two stacks were installed over the test's lifetime (original +
      // reconnect); the reconnect reused the remembered backend verbatim and
      // provisioned nothing new.
      expect(harness.installedStacks.length, 2);
      expect(harness.installedStacks.last.backend, reconnected.backend);
      expect(harness.remoteCalls, isEmpty);
      expect(
        await harness.activeContainer(tester).read(syncEnabledProvider.future),
        isFalse,
      );

      await harness.finish(tester);
    },
  );
}

String _accountId(String projectRef, String authUserId) =>
    PlannerAccountScope.provisioned(
      projectRef: projectRef,
      authUserId: authUserId,
    ).storageId;

class _PreparedStack {
  _PreparedStack({
    required this.backend,
    required this.client,
    required this.repository,
    required this.controller,
  });

  final ProvisionedRuntimeBackend backend;
  final FakeRuntimeAuthClient client;
  final AuthRepository repository;
  final AuthSessionController controller;
}

class _Harness {
  _Harness() {
    seams = PlannerBootstrapSeams(
      readProvisionedBackend: () async =>
          ProvisionedBackendRead(backend: _profileBackend),
      installProvisionedRuntimeAuth: _install,
      openDatabase: _openDatabase,
      initializeLocalServices: _initializeLocalServices,
      shutdownLocalServices: _shutdownLocalServices,
    );
  }

  late final PlannerBootstrapSeams seams;

  final List<String?> openedAccountIds = <String?>[];
  final List<String?> initializedScopes = <String?>[];
  final List<String?> shutdownAccountIds = <String?>[];
  final List<_PreparedStack> installedStacks = <_PreparedStack>[];
  final List<RemoteCall> remoteCalls = <RemoteCall>[];
  final Map<String?, AppDatabase> databases = <String?, AppDatabase>{};
  final FakeSecureKeyValueStore secureStore = FakeSecureKeyValueStore();

  ProvisionedRuntimeBackend? _profileBackend;
  _PreparedStack? _pendingInstall;

  AppDatabase? databaseFor(String accountId) => databases[accountId];

  /// Simulates the durable backend profile becoming explicitly disconnected
  /// (or otherwise no longer resolving) without changing anything else.
  void makeBackendUnresolvable() => _profileBackend = null;

  Future<_PreparedStack> prepare({
    required String projectRef,
    required String authUserId,
    bool signedIn = true,
  }) async {
    final client = FakeRuntimeAuthClient();
    if (signedIn) {
      client.emitSignedIn(testAuthSession(authUserId: authUserId));
    }
    final namespaces = RuntimeAuthNamespaces.forProject(projectRef);
    final repository = AuthRepository(
      client,
      sessionStorage: SecureSupabaseLocalStorage(
        storage: secureStore,
        sessionKey: namespaces.sessionKey,
      ),
    );
    final backend = testProvisionedBackend(projectRef: projectRef);
    final stack = _PreparedStack(
      backend: backend,
      client: client,
      repository: repository,
      controller: AuthSessionController(repository),
    );
    await stack.controller.start();
    _profileBackend = backend;
    _pendingInstall = stack;
    return stack;
  }

  void install(_PreparedStack stack) {
    installRuntimeAuthBootstrapForTesting(
      backend: stack.backend,
      repository: stack.repository,
      controller: stack.controller,
    );
    installedStacks.add(stack);
  }

  Future<_PreparedStack> startSignedIn(
    WidgetTester tester, {
    required String projectRef,
    required String authUserId,
  }) async {
    final stack = await prepare(
      projectRef: projectRef,
      authUserId: authUserId,
    );
    install(stack);
    await pump(tester);
    return stack;
  }

  Future<void> adopt(
    WidgetTester tester, {
    required String projectRef,
    required String authUserId,
  }) async {
    await prepare(projectRef: projectRef, authUserId: authUserId);
    unawaited(
      activeContainer(tester).read(runtimeBackendReloaderProvider)!.reload(),
    );
    await pumpUntil(
      tester,
      () => activeScopeOrNull(tester) == _accountId(projectRef, authUserId),
      reason: 'expected $projectRef/$authUserId to become the active account',
    );
  }

  /// Simulates an app restart: the widget tree, provider container and runtime
  /// Auth stack are all rebuilt from the same durable state.
  Future<void> restart(WidgetTester tester, {required bool signedIn}) async {
    final backend = _profileBackend!;
    final previous = installedStacks.last;
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(() async {
      await previous.controller.dispose();
      await previous.repository.dispose();
      await previous.client.close();
    });
    await resetRuntimeAuthBootstrapForTesting();
    final next = await prepare(
      projectRef: backend.projectRef,
      authUserId: authUserIdX,
      signedIn: signedIn,
    );
    install(next);
    await pump(tester);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(plannerBootstrap(seams: seams));
    await pumpUntil(
      tester,
      () => appMounted(tester) && initializedScopes.isNotEmpty,
      reason: 'expected the app tree to appear for the opened account database',
    );
  }

  bool appMounted(WidgetTester tester) =>
      find.byType(PersonalPlannerApp).evaluate().isNotEmpty;

  String? activeScopeOrNull(WidgetTester tester) => appMounted(tester)
      ? activeContainer(tester).read(openAccountScopeProvider)?.storageId
      : null;

  Future<void> pumpFrames(WidgetTester tester, int frames) async {
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Asks the bootstrap to re-read durable connection state and drives the
  /// resulting account-scope switch.
  ///
  /// Runtime disposal and the database switch complete on futures the widget
  /// test's fake clock never advances, so the transition is driven on the real
  /// event loop — watching only the seam recordings, never the widget tree —
  /// before frames publish the replacement provider container.
  Future<void> reloadRuntime(WidgetTester tester) async {
    final previous = activeContainer(tester);
    final reloader = previous.read(runtimeBackendReloaderProvider)!;
    final openedBefore = openedAccountIds.length;
    await tester.runAsync(() async {
      unawaited(reloader.reload());
      for (var attempt = 0; attempt < 200; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (openedAccountIds.length > openedBefore) break;
      }
      // Let the switch open, initialize and publish its container.
      for (var attempt = 0; attempt < 100; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await pumpFrames(tester, 10);
    if (!appMounted(tester) ||
        identical(activeContainer(tester), previous)) {
      fail(
        'Runtime reload did not publish a new provider container'
        '\n  opened: $openedAccountIds'
        '\n  initialized: $initializedScopes'
        '\n  shutdown: $shutdownAccountIds',
      );
    }
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxFrames = 120,
    String? reason,
  }) async {
    for (var frame = 0; frame < maxFrames; frame += 1) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail(
      'Bootstrap did not reach the expected state after $maxFrames frames'
      '${reason == null ? '' : ': $reason'}'
      '\n  opened: $openedAccountIds'
      '\n  initialized: $initializedScopes'
      '\n  shutdown: $shutdownAccountIds'
      '\n  active: ${appMounted(tester) ? activeScopeOrNull(tester) : '<no app tree>'}',
    );
  }

  ProviderContainer activeContainer(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PersonalPlannerApp)),
        listen: false,
      );

  Future<AppDatabase> _openDatabase({String? accountId}) async {
    openedAccountIds.add(accountId);
    final existing = databases[accountId];
    if (existing != null) return existing;
    final database = AppDatabase(NativeDatabase.memory());
    databases[accountId] = database;
    await database.syncDao.setSetting(onboardingCompletedKey, 'true');
    return database;
  }

  Future<SyncEngine?> _initializeLocalServices(
    ProviderContainer container, {
    required Future<void> Function() beforeWindowClose,
  }) async {
    initializedScopes.add(container.read(openAccountScopeProvider)?.storageId);
    return null;
  }

  Future<void> _shutdownLocalServices(
    ProviderContainer container,
    AppDatabase database,
    SyncEngine? engine,
    bool persistWindow,
  ) async {
    shutdownAccountIds.add(container.read(openAccountScopeProvider)?.storageId);
    container.dispose();
  }

  Future<void> _install(ProvisionedRuntimeBackend backend) async {
    final pending = _pendingInstall;
    if (pending == null || pending.backend != backend) {
      throw StateError('No prepared runtime Auth stack for $backend');
    }
    install(pending);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(() async {
      for (final stack in installedStacks) {
        await stack.controller.dispose();
        await stack.repository.dispose();
        await stack.client.close();
      }
      for (final database in databases.values) {
        try {
          await database.close();
        } catch (_) {
          // Already closed by the bootstrap shutdown path.
        }
      }
    });
    await resetRuntimeAuthBootstrapForTesting();
  }
}
