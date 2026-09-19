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
import 'package:personal_planner/features/sync/data/app_link_source.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/domain/sync_engine.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/timer/platform/android_foreground_timer.dart';
import 'package:personal_planner/main.dart';

import '../helpers/runtime_auth_fakes.dart';
import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart' show settle;

/// Drives the real `_PlannerBootstrap` lifecycle: the runtime Auth stack, the
/// account database/provider container, and local-service scope.
///
/// Only the platform boundaries are substituted (in-memory databases, no-op
/// local services, scripted runtime Auth installation). The drain, staleness and
/// identity logic under test is the production code path.
void main() {
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() async {
    await resetRuntimeAuthBootstrapForTesting();
    AndroidForegroundTimer.setAccountScope(null);
  });

  testWidgets(
    'adopting a ready backend with a restored authenticated session opens that '
    'project database',
    (tester) async {
      final harness = _BootstrapHarness();

      // Local-only start: no runtime Auth stack at all.
      await harness.pump(tester);
      expect(harness.openedAccountIds, [null]);
      final anonymousContainer = harness.activeContainer(tester);
      expect(anonymousContainer.read(openAccountScopeProvider), isNull);
      expect(AndroidForegroundTimer.accountScope, isNull);

      // Cloud setup finished: the app adopts the stored READY profile, whose
      // scoped session restores an authenticated user.
      await harness.adopt(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );

      final accountId = _accountId(projectRefA, authUserIdX);
      expect(harness.openedAccountIds, [null, accountId]);

      final accountContainer = harness.activeContainer(tester);
      expect(
        accountContainer.read(openAccountScopeProvider)?.storageId,
        accountId,
      );
      // The anonymous container is no longer the active account container.
      expect(identical(accountContainer, anonymousContainer), isFalse);
      // Timer/background identity follows the same canonical account scope.
      expect(AndroidForegroundTimer.accountScope, accountId);
      // Local services were initialized for the account database only, after it
      // became the requested target.
      expect(harness.initializedScopes, [null, accountId]);

      await harness.finish(tester);
    },
  );

  testWidgets(
    'project A to project B with the same auth user id switches the database',
    (tester) async {
      final harness = _BootstrapHarness();
      final projectA = await harness.startSignedIn(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final accountA = _accountId(projectRefA, authUserIdX);
      expect(harness.openedAccountIds, [accountA]);
      final containerA = harness.activeContainer(tester);

      // The same Supabase auth user id now arrives in a different project.
      await harness.adopt(
        tester,
        projectRef: projectRefB,
        authUserId: authUserIdX,
      );

      final accountB = _accountId(projectRefB, authUserIdX);
      expect(accountA == accountB, isFalse);
      expect(harness.openedAccountIds, [accountA, accountB]);
      // Project A's container and local services were shut down.
      expect(harness.shutdownAccountIds, contains(accountA));

      final containerB = harness.activeContainer(tester);
      expect(containerB.read(openAccountScopeProvider)?.storageId, accountB);
      expect(identical(containerB, containerA), isFalse);
      // The active container is built for project B's runtime Auth stack.
      final projectB = harness.installedStacks.last;
      expect(containerB.read(authRepositoryProvider), projectB.repository);
      expect(
        identical(
          containerB.read(authSessionControllerProvider),
          projectA.controller,
        ),
        isFalse,
      );
      expect(AndroidForegroundTimer.accountScope, accountB);

      await harness.finish(tester);
    },
  );

  testWidgets('a stale event from the replaced project A client cannot change the active '
      'project', (tester) async {
    final harness = _BootstrapHarness();
    final projectA = await harness.startSignedIn(
      tester,
      projectRef: projectRefA,
      authUserId: authUserIdX,
    );
    final accountA = _accountId(projectRefA, authUserIdX);
    final accountB = _accountId(projectRefB, authUserIdX);
    final wrongProjectUser = _accountId(projectRefB, authUserIdY);

    // While the replacement is being installed, the replaced project A client
    // still holds queued events. Interpreting them with project B's identity
    // would request project B plus a different user, or tear the account down.
    final hold = Completer<void>();
    harness.installHold = hold;
    harness.duringInstall = () {
      projectA.client.emitSignedIn(testAuthSession(authUserId: authUserIdY));
      unawaited(projectA.client.signOut());
    };

    await harness.startAdoption(
      tester,
      projectRef: projectRefB,
      authUserId: authUserIdX,
    );
    // Pump while the replacement is mid-install, so the stale events are really
    // delivered during the replacement window rather than after it.
    await harness.pumpFrames(tester, 5);
    hold.complete();
    await harness.waitForScope(
      tester,
      accountB,
      reason: 'expected project B user X to become the active account',
    );

    expect(harness.openedAccountIds, [accountA, accountB]);
    expect(harness.openedAccountIds, isNot(contains(wrongProjectUser)));
    // The stale signed-out event did not send the active project B account back
    // to the local database, and the stale project A event did not open a
    // database for project B plus project A's other user.
    expect(harness.openedAccountIds.where((id) => id == null), isEmpty);
    // No local service was initialized for a target that never became active.
    expect(harness.initializedScopes, [accountA, accountB]);

    final container = harness.activeContainer(tester);
    expect(container.read(openAccountScopeProvider)?.storageId, accountB);
    expect(AndroidForegroundTimer.accountScope, accountB);

    await harness.finish(tester);
  });

  testWidgets(
    'events from the current project B stack still drive the account scope',
    (tester) async {
      final harness = _BootstrapHarness();
      await harness.startSignedIn(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      await harness.adopt(
        tester,
        projectRef: projectRefB,
        authUserId: authUserIdX,
      );
      final accountB = _accountId(projectRefB, authUserIdX);
      expect(
        harness
            .activeContainer(tester)
            .read(openAccountScopeProvider)
            ?.storageId,
        accountB,
      );

      // A current event on project B for another user must switch normally.
      final projectB = harness.installedStacks.last;
      projectB.client.emitSignedIn(testAuthSession(authUserId: authUserIdY));
      final secondUser = _accountId(projectRefB, authUserIdY);
      await harness.pumpUntil(
        tester,
        () => harness.activeScopeOrNull(tester) == secondUser,
        reason: 'expected project B user Y to become the active account',
      );
      expect(harness.openedAccountIds, contains(secondUser));
      expect(
        harness
            .activeContainer(tester)
            .read(openAccountScopeProvider)
            ?.storageId,
        secondUser,
      );
      expect(AndroidForegroundTimer.accountScope, secondUser);

      // Signing out of the current project returns to the local scope.
      await projectB.client.signOut();
      await harness.pumpUntil(
        tester,
        () =>
            harness.appMounted(tester) &&
            harness.activeScopeOrNull(tester) == null,
        reason: 'expected sign-out to return to the local account scope',
      );

      expect(
        harness.activeContainer(tester).read(openAccountScopeProvider),
        isNull,
      );
      expect(AndroidForegroundTimer.accountScope, isNull);

      await harness.finish(tester);
    },
  );

  testWidgets(
    'a target superseded while its database opens initializes nothing',
    (tester) async {
      final harness = _BootstrapHarness();
      await harness.startSignedIn(
        tester,
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final accountA = _accountId(projectRefA, authUserIdX);
      final staleTarget = _accountId(projectRefB, authUserIdX);
      final supersedingTarget = _accountId(projectRefB, authUserIdY);

      // Hold project B/user X's database open until a newer session has already
      // replaced it as the requested target.
      final hold = Completer<void>();
      harness.beforeReturningDatabase = (accountId) async {
        if (accountId == staleTarget) await hold.future;
      };

      await harness.startAdoption(
        tester,
        projectRef: projectRefB,
        authUserId: authUserIdX,
      );
      await harness.pumpUntil(
        tester,
        () => harness.openedAccountIds.contains(staleTarget),
        reason: 'expected project B/user X to start opening its database',
      );

      harness.installedStacks.last.client.emitSignedIn(
        testAuthSession(authUserId: authUserIdY),
      );
      // Let the current project B stack publish the newer session before the
      // already-superseded database open completes.
      await harness.pumpFrames(tester, 3);
      hold.complete();
      await harness.waitForScope(
        tester,
        supersedingTarget,
        reason: 'expected the superseding target to become the active account',
      );

      expect(harness.openedAccountIds, contains(staleTarget));
      expect(harness.openedAccountIds, contains(supersedingTarget));
      // The superseded target never reached local services.
      expect(harness.initializedScopes, [accountA, supersedingTarget]);
      final container = harness.activeContainer(tester);
      expect(
        container.read(openAccountScopeProvider)?.storageId,
        supersedingTarget,
      );
      expect(AndroidForegroundTimer.accountScope, supersedingTarget);

      await harness.finish(tester);
    },
  );
}

String _accountId(String projectRef, String authUserId) =>
    PlannerAccountScope.provisioned(
      projectRef: projectRef,
      authUserId: authUserId,
    ).storageId;

/// One prepared runtime Auth stack: a fake project client plus its Auth
/// boundary and controller.
class _PreparedAuthStack {
  _PreparedAuthStack({
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

class _BootstrapHarness {
  _BootstrapHarness() {
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
  final List<_PreparedAuthStack> installedStacks = <_PreparedAuthStack>[];
  final List<AppDatabase> openedDatabases = <AppDatabase>[];

  ProvisionedRuntimeBackend? _profileBackend;
  _PreparedAuthStack? _pendingInstall;

  /// Runs inside the runtime Auth installation step, so a test can deliver
  /// events from the replaced client while the replacement is being installed.
  void Function()? duringInstall;

  /// When set, holds the runtime Auth installation step open so a test can pump
  /// frames while the replacement is mid-flight.
  Completer<void>? installHold;

  /// Runs after a database was opened but before local services are created.
  Future<void> Function(String? accountId)? beforeReturningDatabase;

  /// Prepares (but does not install) a ready project whose runtime Auth session
  /// belongs to [authUserId].
  ///
  /// The controller is started here, in the test body, because production
  /// bootstrap also starts it before installing the stack.
  Future<_PreparedAuthStack> prepare({
    required String projectRef,
    required String authUserId,
  }) async {
    final client = FakeRuntimeAuthClient()
      ..emitSignedIn(testAuthSession(authUserId: authUserId));
    final repository = AuthRepository(client);
    final backend = testProvisionedBackend(projectRef: projectRef);
    final stack = _PreparedAuthStack(
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

  /// Installs [stack] as the active runtime Auth stack, the way the production
  /// bootstrap does once its client and session are ready.
  void install(_PreparedAuthStack stack) {
    installRuntimeAuthBootstrapForTesting(
      backend: stack.backend,
      repository: stack.repository,
      controller: stack.controller,
    );
    installedStacks.add(stack);
  }

  /// Starts the app with a signed-in provisioned backend already installed.
  Future<_PreparedAuthStack> startSignedIn(
    WidgetTester tester, {
    required String projectRef,
    required String authUserId,
  }) async {
    final stack = await prepare(projectRef: projectRef, authUserId: authUserId);
    install(stack);
    await pump(tester);
    return stack;
  }

  /// Starts local-only and then adopts [projectRef] exactly as the cloud-setup
  /// card does when provisioning finishes.
  Future<void> adopt(
    WidgetTester tester, {
    required String projectRef,
    required String authUserId,
  }) async {
    await startAdoption(tester, projectRef: projectRef, authUserId: authUserId);
    await waitForScope(
      tester,
      _accountId(projectRef, authUserId),
      reason: 'expected the active account to become $projectRef/$authUserId',
    );
  }

  /// Fires adoption of [projectRef] without waiting for the switch to finish.
  Future<void> startAdoption(
    WidgetTester tester, {
    required String projectRef,
    required String authUserId,
  }) async {
    await prepare(projectRef: projectRef, authUserId: authUserId);
    final container = activeContainer(tester);
    // Production fires this without awaiting (the cloud-setup card), so the
    // flow progresses on frames exactly like the running app.
    unawaited(container.read(runtimeBackendReloaderProvider)!.reload());
  }

  /// Waits until [accountId] is the active account scope.
  Future<void> waitForScope(
    WidgetTester tester,
    String accountId, {
    String? reason,
  }) => pumpUntil(
    tester,
    () => activeScopeOrNull(tester) == accountId,
    reason: reason,
  );

  /// Pumps [frames] frames without requiring a particular outcome.
  Future<void> pumpFrames(WidgetTester tester, int frames) async {
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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

  /// Active account scope, or null while the bootstrap still shows its loading
  /// or error screen instead of the app.
  String? activeScopeOrNull(WidgetTester tester) => appMounted(tester)
      ? activeContainer(tester).read(openAccountScopeProvider)?.storageId
      : null;

  /// Pumps frames until [condition] holds, so a test never depends on how many
  /// microtask flushes a switch needs. Fails loudly instead of hanging.
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
      '\n  installed stacks: ${installedStacks.length}'
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
    final database = AppDatabase(NativeDatabase.memory());
    openedDatabases.add(database);
    // Keep the app tree on the planner shell instead of onboarding.
    await database.syncDao.setSetting(onboardingCompletedKey, 'true');
    final hook = beforeReturningDatabase;
    if (hook != null) await hook(accountId);
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
    // The database stays open here: an account database whose provider graph
    // has live Drift streams has to be closed in the real async zone, which the
    // widget test cannot do from inside the production switch path. [finish]
    // closes every database it handed out.
  }

  Future<void> _install(
    ProvisionedRuntimeBackend backend,
    AppLinkSource links,
  ) async {
    final pending = _pendingInstall;
    if (pending == null || pending.backend != backend) {
      throw StateError('No prepared runtime Auth stack for $backend');
    }
    install(pending);
    final hook = duringInstall;
    duringInstall = null;
    hook?.call();
    final hold = installHold;
    installHold = null;
    if (hold != null) await hold.future;
  }

  /// Unmounts the app tree (cancelling its timers) and releases every resource.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(() async {
      for (final stack in installedStacks) {
        await stack.controller.dispose();
        await stack.repository.dispose();
        await stack.client.close();
      }
      for (final database in openedDatabases) {
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
