import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/sync/data/anonymous_data_adoption.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:personal_planner/features/sync/presentation/screens/sync_settings_screen.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_settings_provider.dart';

import '../helpers/provisioning_fakes.dart';
import '../helpers/initial_sync_fakes.dart';
import '../helpers/runtime_auth_fakes.dart';
import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart' show settle;

void main() {
  setupSqliteForTests();
  // Each case opens its own in-memory account database.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeProvisioningApi api;

  setUp(() {
    api = FakeProvisioningApi();
  });

  testWidgets('ready backend with no session offers account connection', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    final reloader = _RecordingReloader();
    final harness = await _pumpSyncSettings(
      tester,
      backend: testProvisionedBackend(),
      api: api,
      reloader: reloader,
    );

    expect(find.text('Cloud backend ready'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-password')), findsOneWidget);
    // No sync surface exists for the provisioned path.
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Enable sync'), findsNothing);
    // The newly ready backend is handed to the bootstrap exactly once.
    expect(reloader.calls, 1);

    await _teardown(tester, harness);
  });

  testWidgets(
    'an authenticated provisioned account claims no synchronization',
    (tester) async {
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
      final harness = await _pumpSyncSettings(
        tester,
        backend: testProvisionedBackend(),
        api: api,
        signedIn: true,
      );

      // The Phase G coordinator itself is covered by test/unit/sync; here the
      // durable state of an account whose cloud state could not be resolved is
      // written directly so the widget tree renders that state.
      await tester.runAsync(() async {
        await InitialSyncStateStore(harness.database).write(
          InitialSyncRecord(
            phase: InitialSyncPhase.retryable,
            detail: const <String, dynamic>{
              'message':
                  'Network unavailable; cloud setup will retry. Local planning '
                  'keeps working.',
            },
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      });
      await settle(tester);

      expect(find.text('Cloud account connected'), findsOneWidget);
      expect(find.textContaining('person@example.com'), findsOneWidget);
      expect(
        find.textContaining(
          'Cloud synchronization for Planner data starts only after the first '
          'synchronization is complete.',
        ),
        findsOneWidget,
      );
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Sync now'), findsNothing);
      expect(find.text('Enable sync'), findsNothing);
      expect(find.text('Synced'), findsNothing);
      // The Phase G first-sync state is described honestly: the account is
      // connected, but cloud synchronization is not claimed to be active.
      expect(find.byKey(const ValueKey('provisioned-first-sync')), findsOneWidget);
      expect(find.text('Cloud setup needs a retry'), findsOneWidget);
      expect(find.text('Retry cloud setup'), findsOneWidget);
      expect(find.byTooltip('Cloud setup pending'), findsOneWidget);

      await _teardown(tester, harness);
    },
  );

  testWidgets(
    'a completed first synchronization shows the normal sync controls',
    (tester) async {
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
      final harness = await _pumpSyncSettings(
        tester,
        backend: testProvisionedBackend(),
        api: api,
        signedIn: true,
      );

      await tester.runAsync(() async {
        await InitialSyncStateStore(harness.database).write(
          InitialSyncRecord(
            phase: InitialSyncPhase.complete,
            detail: const <String, dynamic>{
              'message': 'Cloud Planner data restored.',
            },
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      });
      await settle(tester);

      expect(find.byKey(const ValueKey('provisioned-first-sync')), findsNothing);
      expect(find.text('Enable sync'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);

      // Switching sync off keeps the controls visible so they can be switched
      // back on; it never claims a synced state.
      await tester.tap(find.text('Enable sync'));
      await settle(tester);
      expect(find.text('Enable sync'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => harness.container.read(syncEnabledProvider.future),
        ),
        isFalse,
      );

      await _teardown(tester, harness);
    },
  );

  testWidgets('signing out returns to backend-ready without restarting setup', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    final harness = await _pumpSyncSettings(
      tester,
      backend: testProvisionedBackend(),
      api: api,
      signedIn: true,
      // Another project's session must survive this sign-out.
      foreignSessionKeys: {'personal_planner.supabase.$projectRefB.session'},
    );

    await tester.tap(find.text('Log out'));
    await settle(tester);

    expect(find.text('Cloud account connected'), findsNothing);
    expect(find.byKey(const ValueKey('sync-email')), findsOneWidget);
    expect(find.text('Cloud backend ready'), findsOneWidget);
    // Signing out is not a provisioning restart and not a disconnect.
    expect(api.startAttemptCount, 0);
    expect(api.attempt, isNotNull);
    expect(harness.client.signOutCalls, 1);
    // Only this project's scoped session is cleared.
    expect(
      harness.store.values['personal_planner.supabase.$projectRefA.session'],
      isNull,
    );
    expect(
      harness.store.values['personal_planner.supabase.$projectRefB.session'],
      isNotNull,
    );
    // The account database is still open and untouched.
    expect(
      await tester.runAsync(
        () => harness.database.customSelect('SELECT 1').get(),
      ),
      isNotEmpty,
    );

    await _teardown(tester, harness);
  });

  testWidgets('the compile-time developer path keeps its account UI', (
    tester,
  ) async {
    final harness = await _pumpSyncSettings(
      tester,
      backend: const LegacyStaticRuntimeBackend(
        url: 'https://developer.supabase.co',
        publishableKey: publishableKeyA,
      ),
      api: api,
    );

    expect(find.byKey(const ValueKey('sync-email')), findsOneWidget);
    // No user-owned cloud setup card on the legacy path.
    expect(find.text('Cloud sync'), findsNothing);

    await _teardown(tester, harness);
  });

  testWidgets('the compile-time developer path keeps its sync controls', (
    tester,
  ) async {
    final harness = await _pumpSyncSettings(
      tester,
      backend: const LegacyStaticRuntimeBackend(
        url: 'https://developer.supabase.co',
        publishableKey: publishableKeyA,
      ),
      api: api,
      signedIn: true,
    );

    expect(
      find.textContaining('uses its own local SQLite database'),
      findsOneWidget,
    );
    expect(find.text('Enable sync'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);

    await _teardown(tester, harness);
  });

  testWidgets('a non-ready profile keeps provisioning authoritative', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.authorizationPending,
      projectRef: testProjectRef,
    );
    // The setup card advances one authoritative step when it opens, so script
    // that step to stay in "waiting for authorization".
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    final reloader = _RecordingReloader();
    final harness = await _pumpSyncSettings(
      tester,
      backend: const LocalOnlyRuntimeBackend(),
      api: api,
      reloader: reloader,
    );

    expect(find.text('Authorize Supabase'), findsOneWidget);
    expect(find.text('Cloud backend ready'), findsNothing);
    expect(find.byKey(const ValueKey('sync-email')), findsNothing);
    expect(reloader.calls, 0);

    await _teardown(tester, harness);
  });

  testWidgets('a local-only installation shows no account connection', (
    tester,
  ) async {
    final harness = await _pumpSyncSettings(
      tester,
      backend: const LocalOnlyRuntimeBackend(),
      api: api,
    );

    expect(find.text('Cloud sync'), findsOneWidget);
    expect(find.text('Enable Cloud Sync'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-email')), findsNothing);
    expect(find.text('Sync now'), findsNothing);

    await _teardown(tester, harness);
  });
}

class _RecordingReloader implements RuntimeBackendReloader {
  int calls = 0;

  @override
  Future<void> reload() async {
    calls += 1;
  }
}

class _Harness {
  const _Harness({
    required this.container,
    required this.database,
    required this.client,
    required this.store,
    required this.anonymous,
  });

  final ProviderContainer container;
  final AppDatabase database;
  final FakeRuntimeAuthClient client;
  final FakeSecureKeyValueStore store;
  final AnonymousDatabaseFixture anonymous;
}

Future<_Harness> _pumpSyncSettings(
  WidgetTester tester, {
  required RuntimeBackend backend,
  required FakeProvisioningApi api,
  bool signedIn = false,
  RuntimeBackendReloader? reloader,
  Set<String> foreignSessionKeys = const <String>{},
}) async {
  final store = FakeSecureKeyValueStore();
  final client = FakeRuntimeAuthClient();
  final anonymous = AnonymousDatabaseFixture.create();
  final calls = <RemoteCall>[];
  // The Phase G first synchronization is scripted to fail discovery, so a
  // signed-in account is shown in its honest pre-baseline state.
  final initialSync = FakeInitialSyncGateway(calls: calls)
    ..stateError = Exception('SocketException: network is unreachable');
  final syncRemote = FakeSyncRemoteGateway(calls: calls);
  final namespaces =
      backend.authNamespaces ?? const RuntimeAuthNamespaces.legacyStatic();
  final storage = SecureSupabaseLocalStorage(
    storage: store,
    sessionKey: namespaces.sessionKey,
  );
  final repository = AuthRepository(client, sessionStorage: storage);
  final controller = AuthSessionController(repository);
  for (final key in foreignSessionKeys) {
    store.values[key] = 'foreign-project-session';
  }

  // The Auth objects live in the test's own zone so controller events are
  // delivered by ordinary pumps instead of the real-async zone.
  if (signedIn) {
    client.emitSignedIn(
      testAuthSession(authUserId: authUserIdX, email: 'person@example.com'),
    );
  }
  await controller.start();

  final database = AppDatabase(NativeDatabase.memory());
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
      provisioningApiProvider.overrideWithValue(api),
      provisioningPollIntervalProvider.overrideWith(
        (ref) => const Duration(hours: 1),
      ),
      browserLauncherProvider.overrideWithValue(FakeBrowserLauncher()),
      runtimeBackendReloaderProvider.overrideWithValue(reloader),
      syncRemoteFactoryProvider.overrideWithValue(
        FakeSyncRemoteFactory(
          initialSyncGateway: initialSync,
          syncGateway: syncRemote,
        ),
      ),
      anonymousDatabaseFactoryProvider.overrideWithValue(anonymous.open),
      // The compile-time developer path builds a real SupabaseClient for normal
      // sync, whose auto-refresh ticker cannot be cancelled under a widget
      // test's fake clock. The sync DATA path stays covered by
      // test/unit/sync (see provisioned_sync_boundary_test.dart); this suite
      // only verifies which UI each backend shows.
      syncRepositoryProvider.overrideWith((ref) => null),
      // The legacy path inspects the anonymous database; keep this test free of
      // the platform path provider.
      anonymousDataSummaryProvider.overrideWith(
        (ref) async => const AnonymousDataSummary(
          anonymousRecords: 0,
          accountRecords: 0,
          decision: null,
        ),
      ),
    ],
  );
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
    anonymous: anonymous,
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
    await harness.database.close();
    harness.anonymous.delete();
  });
}
