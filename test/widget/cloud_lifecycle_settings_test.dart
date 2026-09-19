import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/sync/data/anonymous_data_adoption.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/backend_project_probe.dart';
import 'package:personal_planner/features/sync/data/connection_profile_store.dart';
import 'package:personal_planner/features/sync/data/initial_sync_coordinator.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_capability_store.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/cloud_connection_lifecycle.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';
import 'package:personal_planner/features/sync/presentation/screens/sync_settings_screen.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';

import '../helpers/initial_sync_fakes.dart';
import '../helpers/provisioning_fakes.dart';
import '../helpers/runtime_auth_fakes.dart';
import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart' show settle;

/// Phase H lifecycle UX: Disable sync, Disconnect, Reconnect, recovery_required
/// and an unusable stored profile, all presented as clearly different actions
/// with non-destructive consequences.
void main() {
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late ConnectionProfileStore profileStore;
  late _RecordingCapabilityStore capabilities;
  late FakeProvisioningApi api;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('planner_lifecycle_ui_');
    profileStore = ConnectionProfileStore(directory: directory);
    capabilities = _RecordingCapabilityStore();
    api = FakeProvisioningApi();
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  testWidgets('Cloud Sync can be switched off before the baseline exists', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      backend: testProvisionedBackend(),
      profileStore: profileStore,
      capabilities: capabilities,
      api: api,
      signedIn: true,
      initialSyncPhase: InitialSyncPhase.retryable,
    );

    expect(find.byKey(const ValueKey('sync-enable-toggle')), findsOneWidget);
    final toggle = find.byType(Switch).first;
    expect(tester.widget<Switch>(toggle).value, isTrue);

    await tester.tap(toggle);
    await settle(tester);

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.textContaining('Cloud Sync is switched off'), findsOneWidget);
    // Retry is unreachable while automatic synchronization is off.
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('first-sync-retry')),
          )
          .onPressed,
      isNull,
    );
    // The preference is durable in the account database, not in memory.
    expect(await harness.database.syncDao.getSetting('sync.enabled'), 'false');
    // Once the baseline exists the same preference reads as an explicit
    // lifecycle state instead of a misleading "Not configured".
    await InitialSyncStateStore(harness.database).write(
      InitialSyncRecord(
        phase: InitialSyncPhase.complete,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await settle(tester);
    expect(find.text('Sync is off'), findsOneWidget);
    expect(
      find.text('Changes will stay on this device until you turn sync back on.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Sync now'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await _teardown(tester, harness);
  });

  testWidgets(
    'disconnect stops using the backend but keeps local data and the connection',
    (tester) async {
      final backend = testProvisionedBackend();
      final stored = _readyProfile();
      // Durable profile storage is real file I/O, so it runs in the real async
      // zone rather than under the widget test's fake clock.
      await tester.runAsync(() => profileStore.save(stored));
      final reloader = _RecordingReloader();
      final harness = await _pump(
        tester,
        backend: backend,
        profileStore: profileStore,
        capabilities: capabilities,
        api: api,
        signedIn: true,
        initialSyncPhase: InitialSyncPhase.complete,
        reloader: reloader,
      );
      final sessionKey = RuntimeAuthNamespaces.forProject(testProjectRef)
          .sessionKey;
      harness.store.values[sessionKey] = 'project-session';
      // Building the screen adopts the already-ready backend once; only the
      // reloads after that belong to the lifecycle action under test.
      reloader.calls = 0;

      await _openAdvancedAccess(tester);
      await tester.tap(
        find.byKey(const ValueKey('cloud-stop-using-cloud-action')),
      );
      await settle(tester);
      expect(find.text(cloudDisconnectConfirmation), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cloud-disconnect-confirm')));
      await _flushLifecycle(tester, () => reloader.calls >= 1);

      expect(reloader.calls, 1);
      final storedAfter = await tester.runAsync(profileStore.read);
      expect(storedAfter?.connectionDisabled, isTrue);
      expect(storedAfter?.projectRef, testProjectRef);
      expect(storedAfter?.generation, stored.generation + 1);
      // The project-scoped Auth session is gone; the account database is not.
      expect(
        harness.store.values.containsKey(
          RuntimeAuthNamespaces.forProject(testProjectRef).sessionKey,
        ),
        isFalse,
      );
      expect(harness.closeGuard.closed, isFalse);
      // Nothing was uploaded, pulled, or deleted.
      expect(harness.remote.applyCalls, 0);
      expect(harness.remote.pullCalls, 0);

      await _teardown(tester, harness);
    },
  );

  testWidgets('a disconnected backend offers a same-project reconnect', (
    tester,
  ) async {
    final stored = _readyProfile(disconnected: true);
    await tester.runAsync(() => profileStore.save(stored));
    api.attempt = ProvisioningAttempt(
      profile: stored,
      transactionId: testTransactionId,
      hasCapability: false,
    );
    final reloader = _RecordingReloader();
    final harness = await _pump(
      tester,
      backend: const LocalOnlyRuntimeBackend(),
      profileStore: profileStore,
      capabilities: capabilities,
      api: api,
      signedIn: false,
      reloader: reloader,
    );

    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text(cloudStorageDisconnectedStatus), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-reconnect-action')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('cloud-reconnect-action')));
    await _flushLifecycle(tester, () => reloader.calls == 1);

    final storedAfter = await tester.runAsync(profileStore.read);
    expect(storedAfter?.connectionDisabled, isFalse);
    expect(storedAfter?.projectRef, testProjectRef);
    // Adopting the backend is the bootstrap's job, exactly once.
    expect(reloader.calls, 1);

    await _teardown(tester, harness);
  });

  testWidgets(
    'disconnect tears down the runtime when the settings screen is disposed '
    'mid-flight',
    (tester) async {
      final backend = testProvisionedBackend();
      final stored = _readyProfile();
      // Durable profile storage is real file I/O; the lifecycle service writes
      // the connection_disabled flag through this exact store.
      final profileStore = _GatedProfileStore(directory: directory);
      await tester.runAsync(() => profileStore.save(stored));
      final containerRef = _ContainerRef();
      // Mirrors what the bootstrap does on reload: release the provisioned
      // runtime Auth stack and install the local-only one.
      final reloader = _TearingDownReloader(() async {
        final container = containerRef.container!;
        final stack = container.read(runtimeAuthStackProvider);
        await stack.controller?.dispose();
        await stack.repository?.dispose();
        container
            .read(runtimeAuthStackProvider.notifier)
            .replace(const RuntimeAuthStack.localOnly());
      });
      final harness = await _pump(
        tester,
        backend: backend,
        profileStore: profileStore,
        capabilities: capabilities,
        api: api,
        signedIn: true,
        initialSyncPhase: InitialSyncPhase.complete,
        reloader: reloader,
        containerRef: containerRef,
      );
      final container = containerRef.container!;
      final sessionKey = RuntimeAuthNamespaces.forProject(testProjectRef)
          .sessionKey;
      harness.store.values[sessionKey] = 'project-session';
      reloader.calls = 0;
      profileStore.armed = true;

      await _openAdvancedAccess(tester);
      await tester.tap(
        find.byKey(const ValueKey('cloud-stop-using-cloud-action')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('cloud-disconnect-confirm')));
      // The disconnect has already published a null session and is now stopped
      // inside the durable profile write.
      await _flushLifecycle(tester, () => profileStore.saveStarted);
      expect(profileStore.saveStarted, isTrue);

      // This is the race the fix removes: the sign-out above makes bootstrap
      // adopt another database, which disposes this screen's provider
      // container and unmounts this State while disconnect is still running.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      expect(reloader.calls, 0, reason: 'teardown must not have run yet');

      // Let the disconnect finish with the initiating widget already gone.
      profileStore.release();
      await _flushLifecycle(tester, () => reloader.calls >= 1);

      // The durable lifecycle transition completed *and* the provisioned
      // runtime was torn down although the screen disappeared.
      expect(reloader.calls, 1);
      final storedAfter = await tester.runAsync(profileStore.read);
      expect(storedAfter?.connectionDisabled, isTrue);
      expect(storedAfter?.projectRef, testProjectRef);
      expect(storedAfter?.generation, stored.generation + 1);

      // Runtime state: local-only, with no provisioned Auth client, repository
      // or controller left anywhere in the provider graph.
      expect(
        container.read(runtimeBackendProvider),
        isA<LocalOnlyRuntimeBackend>(),
      );
      final stack = container.read(runtimeAuthStackProvider);
      expect(stack.backend, isA<LocalOnlyRuntimeBackend>());
      expect(stack.repository, isNull);
      expect(stack.controller, isNull);
      expect(stack.hasRuntimeAuth, isFalse);
      expect(container.read(authRepositoryProvider), isNull);
      expect(container.read(syncAccountBindingProvider), isNull);
      // Project A's session is gone and signing in normally is impossible:
      // there is no Auth repository to sign into.
      expect(harness.store.values.containsKey(sessionKey), isFalse);

      // The rebuilt screen offers local use only; the Project A sign-in form is
      // not available without an explicit reconnect.
      api.attempt = null;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncSettingsScreen()),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('sync-email')), findsNothing);
      expect(find.text('Offline-only mode'), findsOneWidget);

      // Nothing was deleted or uploaded by the disconnect.
      expect(harness.closeGuard.closed, isFalse);
      expect(harness.remote.applyCalls, 0);
      expect(harness.remote.pullCalls, 0);

      await _teardown(tester, harness);
    },
  );

  testWidgets('recovery_required shows only non-destructive options', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      backend: testProvisionedBackend(),
      profileStore: profileStore,
      capabilities: capabilities,
      api: api,
      signedIn: true,
      initialSyncPhase: InitialSyncPhase.recoveryRequired,
      initialSyncMessage: baselineRecoveryRequiredMessage,
    );

    expect(find.text('This cloud account needs recovery'), findsOneWidget);
    expect(find.textContaining('will not merge or overwrite'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('first-sync-recovery-retry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('first-sync-recovery-disconnect')),
      findsOneWidget,
    );
    // Normal synchronization never appears for this state.
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Synced'), findsNothing);

    await _teardown(tester, harness);
  });

  testWidgets('an unusable stored profile surfaces a repair path', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      backend: const LocalOnlyRuntimeBackend(),
      profileStore: profileStore,
      capabilities: capabilities,
      api: api,
      signedIn: false,
      profileHealth: BackendProfileHealth.corrupt,
    );

    expect(find.text('Cloud connection needs attention'), findsOneWidget);
    expect(find.textContaining('Your Planner data is intact'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-profile-health-repair')),
      findsOneWidget,
    );
    expect(find.text('Offline-only mode'), findsOneWidget);

    await _teardown(tester, harness);
  });
}

BackendConnectionProfile _readyProfile({bool disconnected = false}) =>
    BackendConnectionProfile(
      profileId: 'profile-1',
      generation: 2,
      state: ProvisioningState.ready,
      createdAt: testNow,
      updatedAt: testNow,
      projectRef: testProjectRef,
      projectUrl: 'https://$testProjectRef.supabase.co',
      publishableKey: testPublishableKey,
      provisioningTransactionId: testTransactionId,
      connectionDisabled: disconnected,
    );

class _RecordingCapabilityStore implements ProvisioningCapabilityStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({
    required String transactionId,
    required String capability,
  }) async => values[transactionId] = capability;

  @override
  Future<String?> read({required String transactionId}) async =>
      values[transactionId];

  @override
  Future<void> delete({required String transactionId}) async =>
      values.remove(transactionId);
}

class _RecordingReloader implements RuntimeBackendReloader {
  int calls = 0;

  @override
  Future<void> reload() async => calls += 1;
}

/// Late-bound access to the container [_pump] builds, so a test can supply a
/// reloader that performs a real teardown against it.
class _ContainerRef {
  ProviderContainer? container;
}

/// Real profile store whose post-seed writes can be paused, so a test can
/// destroy the initiating widget while a disconnect is still in flight.
class _GatedProfileStore extends ConnectionProfileStore {
  _GatedProfileStore({required super.directory});

  /// When true, the next [save] blocks until [release] is called.
  bool armed = false;
  bool saveStarted = false;
  Completer<void>? _gate;

  @override
  Future<BackendConnectionProfile> save(
    BackendConnectionProfile profile, {
    int? expectedGeneration,
  }) async {
    if (armed) {
      saveStarted = true;
      _gate = Completer<void>();
      await _gate!.future;
    }
    return super.save(profile, expectedGeneration: expectedGeneration);
  }

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

/// Reloader that performs the same runtime teardown the bootstrap does.
class _TearingDownReloader implements RuntimeBackendReloader {
  _TearingDownReloader(this._tearDown);

  final Future<void> Function() _tearDown;
  int calls = 0;

  @override
  Future<void> reload() async {
    calls += 1;
    await _tearDown();
  }
}

class _Harness {
  const _Harness({
    required this.container,
    required this.database,
    required this.client,
    required this.store,
    required this.remote,
    required this.closeGuard,
  });

  final ProviderContainer container;
  final AppDatabase database;
  final FakeRuntimeAuthClient client;
  final FakeSecureKeyValueStore store;
  final FakeSyncRemoteGateway remote;
  final _CloseGuard closeGuard;
}

class _CloseGuard {
  bool closed = false;
}

/// Alternates fake-clock frames with real-async turns until [condition] holds.
///
/// A lifecycle action touches durable storage (a real file), which can only
/// complete while the real event loop runs; the widget tree still needs frames
/// to rebuild. Bounded, so a regression fails the test instead of hanging it.
Future<void> _flushLifecycle(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 60,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required RuntimeBackend backend,
  required ConnectionProfileStore profileStore,
  required _RecordingCapabilityStore capabilities,
  required FakeProvisioningApi api,
  required bool signedIn,
  RuntimeBackendReloader? reloader,
  _ContainerRef? containerRef,
  BackendProfileHealth profileHealth = BackendProfileHealth.ok,
  InitialSyncPhase initialSyncPhase = InitialSyncPhase.retryable,
  String? initialSyncMessage,
}) async {
  // The lifecycle surfaces stack several cards; a default test surface would
  // leave the lower ones unbuilt (a ListView builds lazily).
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = FakeSecureKeyValueStore();
  final client = FakeRuntimeAuthClient();
  final anonymous = AnonymousDatabaseFixture.create();
  final calls = <RemoteCall>[];
  final initialSync = FakeInitialSyncGateway(calls: calls);
  final remote = FakeSyncRemoteGateway(calls: calls);
  final namespaces =
      backend.authNamespaces ?? const RuntimeAuthNamespaces.legacyStatic();
  final storage = SecureSupabaseLocalStorage(
    storage: store,
    sessionKey: namespaces.sessionKey,
  );
  final repository = AuthRepository(client, sessionStorage: storage);
  final controller = AuthSessionController(repository);

  if (signedIn) {
    client.emitSignedIn(
      testAuthSession(authUserId: authUserIdX, email: 'person@example.com'),
    );
  }
  await controller.start();

  final database = AppDatabase(NativeDatabase.memory());
  final closeGuard = _CloseGuard();
  addTearDown(() {
    if (!closeGuard.closed) {
      closeGuard.closed = true;
      unawaited(database.close());
    }
    anonymous.delete();
  });
  if (signedIn) {
    await InitialSyncStateStore(database).write(
      InitialSyncRecord(
        phase: initialSyncPhase,
        detail: <String, dynamic>{'message': ?initialSyncMessage},
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      openAccountScopeProvider.overrideWithValue(
        backend.accountScopeFor(authUserIdX),
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
      backendProfileHealthProvider.overrideWith(
        () => BackendProfileHealthNotifier(profileHealth),
      ),
      provisioningApiProvider.overrideWithValue(api),
      provisioningPollIntervalProvider.overrideWith(
        (ref) => const Duration(hours: 1),
      ),
      // The cloud-storage card probes the project host while it is open; a real
      // HttpClient cannot run under the widget test's fake clock.
      backendProjectProbeProvider.overrideWithValue(
        FakeProjectProbe()..result = BackendProjectProbeResult.exists,
      ),
      browserLauncherProvider.overrideWithValue(FakeBrowserLauncher()),
      connectionProfileStoreProvider.overrideWithValue(profileStore),
      provisioningCapabilityStoreProvider.overrideWithValue(capabilities),
      if (reloader != null)
        runtimeBackendReloaderProvider.overrideWithValue(reloader),
      syncRemoteFactoryProvider.overrideWithValue(
        FakeSyncRemoteFactory(
          initialSyncGateway: initialSync,
          syncGateway: remote,
        ),
      ),
      anonymousDatabaseFactoryProvider.overrideWithValue(anonymous.open),
      // The provisioned data path needs a real SupabaseClient, whose refresh
      // ticker cannot be cancelled under a widget test's fake clock. The
      // lifecycle actions under test never need that client.
      syncRepositoryProvider.overrideWith((ref) => null),
      anonymousDataSummaryProvider.overrideWith(
        (ref) async => const AnonymousDataSummary(
          anonymousRecords: 0,
          accountRecords: 0,
          decision: null,
        ),
      ),
    ],
  );
  containerRef?.container = container;
  await tester.runAsync(() async {
    await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SyncSettingsScreen()),
    ),
  );
  await settle(tester);
  return _Harness(
    container: container,
    database: database,
    client: client,
    store: store,
    remote: remote,
    closeGuard: closeGuard,
  );
}

Future<void> _teardown(WidgetTester tester, _Harness harness) async {
  final controller = harness.container.read(authSessionControllerProvider);
  final repository = harness.container.read(authRepositoryProvider);
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
  await tester.runAsync(() async {
    harness.container.dispose();
    await controller?.dispose();
    await repository?.dispose();
    await harness.client.close();
    harness.closeGuard.closed = true;
    await harness.database.close();
  });
}

/// Opens the collapsed "Supabase connection" disclosure that now holds
/// the cloud-lifecycle action.
Future<void> _openAdvancedAccess(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey('cloud-advanced-access'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}
