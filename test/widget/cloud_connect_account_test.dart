import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/sync/data/anonymous_data_adoption.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/backend_project_probe.dart';
import 'package:personal_planner/features/sync/data/initial_sync_state_store.dart';
import 'package:personal_planner/features/sync/domain/initial_sync_models.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/password_policy.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';
import 'package:personal_planner/features/sync/presentation/screens/sync_settings_screen.dart';
import 'package:personal_planner/features/sync/presentation/widgets/password_requirements.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_settings_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text(cloudStorageConnectedStatus), findsOneWidget);
    expect(find.text(cloudSetupReadyBody), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-password')), findsOneWidget);
    // No sync surface exists for the provisioned path.
    expect(find.text('Sync now'), findsNothing);
    expect(find.byKey(const ValueKey('sync-enable-toggle')), findsNothing);
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

      // The Planner account is presented as its own concept, separate from the
      // Supabase project and from Supabase management access.
      expect(find.text('Planner account'), findsOneWidget);
      expect(find.textContaining('person@example.com'), findsOneWidget);
      expect(
        find.textContaining(
          'Signed in. Cloud sync starts after the first synchronization '
          'finishes.',
        ),
        findsOneWidget,
      );
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Sync now'), findsNothing);
      // Phase H: the Cloud Sync preference is reachable before the baseline
      // exists, so automatic synchronization can always be switched off.
      expect(find.byKey(const ValueKey('sync-enable-toggle')), findsOneWidget);
      expect(find.text('Synced'), findsNothing);
      // The Phase G first-sync state is described honestly: the account is
      // connected, but cloud synchronization is not claimed to be active.
      expect(
        find.byKey(const ValueKey('provisioned-first-sync')),
        findsOneWidget,
      );
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

      expect(
        find.byKey(const ValueKey('provisioned-first-sync')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('sync-enable-toggle')), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      // Normal users never see the durable outbox or cursor terminology.
      expect(
        find.text('Keep your Planner data up to date across your devices.'),
        findsOneWidget,
      );
      expect(find.textContaining('outbox'), findsNothing);
      expect(find.textContaining('cursor'), findsNothing);

      // Switching sync off keeps the controls visible so they can be switched
      // back on; it never claims a synced state.
      await tester.tap(find.byKey(const ValueKey('sync-enable-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sync-enable-toggle')), findsOneWidget);
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
    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text(cloudStorageConnectedStatus), findsOneWidget);
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
    expect(find.text(cloudStorageTitle), findsNothing);

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
    expect(find.byKey(const ValueKey('sync-enable-toggle')), findsOneWidget);
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

    expect(find.text(cloudStorageWaitingStatus), findsOneWidget);
    expect(find.text(cloudStorageConnectedStatus), findsNothing);
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

    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text('Set up cloud storage'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-email')), findsNothing);
    expect(find.text('Sync now'), findsNothing);

    await _teardown(tester, harness);
  });

  group('registration password experience', () {
    Future<_Harness> pumpRegistrationForm(WidgetTester tester) async {
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
      final harness = await _pumpSyncSettings(
        tester,
        backend: testProvisionedBackend(),
        api: api,
      );
      await tester.tap(find.byKey(const ValueKey('sync-register-toggle')));
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('shows the real requirements and updates them live', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = await pumpRegistrationForm(tester);

      expect(find.byType(PasswordRequirementsIndicator), findsOneWidget);
      expect(
        find.text('At least ${PlannerPasswordPolicy.minimumLength} characters'),
        findsOneWidget,
      );
      expect(_requirementMet(tester, 'length'), isFalse);
      // Nothing is styled as an error before the user has interacted.
      expect(tester.takeException(), isNull);

      final passwordField = find.byKey(const ValueKey('sync-password'));
      await tester.enterText(passwordField, 'short');
      await tester.pump();
      expect(_requirementMet(tester, 'length'), isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sync-submit-action')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(passwordField, 'long enough');
      await tester.pump();
      expect(_requirementMet(tester, 'length'), isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sync-submit-action')),
            )
            .onPressed,
        isNotNull,
      );
      // The requirement is also exposed to assistive technology, not by colour
      // alone.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('password-rule-length')))
            .label,
        contains(
          'At least ${PlannerPasswordPolicy.minimumLength} characters: met',
        ),
      );
      semantics.dispose();

      await _teardown(tester, harness);
    });

    testWidgets('never submits a locally invalid password to Supabase', (
      tester,
    ) async {
      final harness = await pumpRegistrationForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('sync-email')),
        'person@example.com',
      );
      await tester.enterText(find.byKey(const ValueKey('sync-password')), 'pw');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sync-submit-action')));
      await tester.pumpAndSettle();

      expect(harness.client.signUpCalls, isEmpty);
      // The locally invalid value is not turned into a red server error.
      expect(find.text('Authentication failed. Check your details and try again.'), findsNothing);

      await _teardown(tester, harness);
    });

    testWidgets('reports a Supabase password rejection on the password field', (
      tester,
    ) async {
      final harness = await pumpRegistrationForm(tester);
      harness.client.signUpError = AuthWeakPasswordException(
        message:
            'Password should contain at least one character of each: '
            'abcdefghijklmnopqrstuvwxyz, 0123456789',
        statusCode: '422',
        reasons: <String>['characters'],
      );

      await tester.enterText(
        find.byKey(const ValueKey('sync-email')),
        'person@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sync-password')),
        'admin 123',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sync-submit-action')));
      await tester.pumpAndSettle();

      expect(harness.client.signUpCalls, hasLength(1));
      expect(find.text(passwordPolicyErrorMessage()), findsOneWidget);
      // The failure is never misreported as a generic or network problem.
      expect(
        find.text('Network unavailable. Your local data is still safe.'),
        findsNothing,
      );
      expect(
        find.text('Authentication failed. Check your details and try again.'),
        findsNothing,
      );

      await _teardown(tester, harness);
    });

    testWidgets('keeps non-password failures out of the password field', (
      tester,
    ) async {
      final harness = await pumpRegistrationForm(tester);
      harness.client.signUpError = const AuthException(
        'User already registered',
      );

      await tester.enterText(
        find.byKey(const ValueKey('sync-email')),
        'person@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sync-password')),
        'admin1234',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sync-submit-action')));
      await tester.pumpAndSettle();

      expect(find.text('That email is already registered.'), findsOneWidget);
      expect(find.text(passwordPolicyErrorMessage()), findsNothing);

      await _teardown(tester, harness);
    });

    testWidgets('can reveal and hide the password', (tester) async {
      final harness = await pumpRegistrationForm(tester);
      final passwordField = find.byKey(const ValueKey('sync-password'));
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('sync-password-visibility')),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(passwordField).obscureText, isFalse);

      await _teardown(tester, harness);
    });
  });

  group('responsive layout', () {
    for (final width in <double>[360, 400, 768, 1024, 1440]) {
      testWidgets('no overflow at ${width.toInt()} px', (tester) async {
        api.attempt = testAttempt(
          ProvisioningState.ready,
          projectRef: testProjectRef,
        );
        final harness = await _pumpSyncSettings(
          tester,
          backend: testProvisionedBackend(),
          api: api,
          signedIn: true,
          surfaceSize: Size(width, 2600),
        );
        await tester.runAsync(() async {
          await InitialSyncStateStore(harness.database).write(
            InitialSyncRecord(
              phase: InitialSyncPhase.complete,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        });
        await settle(tester);

        expect(tester.takeException(), isNull);
        // Every top-level section stays reachable at every width.
        expect(find.text('Planner account'), findsOneWidget);
        expect(find.byKey(const ValueKey('sync-enable-toggle')), findsOneWidget);
        expect(find.text('Sync now'), findsOneWidget);
        expect(find.text(cloudStorageTitle), findsOneWidget);
        expect(find.byKey(const ValueKey('sync-status-card')), findsOneWidget);

        await _teardown(tester, harness);
      });
    }
  });
}

/// True when the rendered requirement line shows the satisfied icon.
bool _requirementMet(WidgetTester tester, String ruleId) {
  final line = find.byKey(ValueKey<String>('password-rule-$ruleId'));
  return find
      .descendant(of: line, matching: find.byIcon(Icons.check_circle))
      .evaluate()
      .isNotEmpty;
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
  Size surfaceSize = const Size(1200, 2600),
}) async {
  final store = FakeSecureKeyValueStore();
  final client = FakeRuntimeAuthClient();
  final anonymous = AnonymousDatabaseFixture.create();
  // These cases assert on cards stacked below the fold; a default test surface
  // would leave them unbuilt because a ListView builds lazily.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
      // The cloud-storage card probes the project host while it is open; a real
      // HttpClient cannot run under the widget test's fake clock, so the answer
      // is scripted. A reachable host is the normal READY case.
      backendProjectProbeProvider.overrideWithValue(
        FakeProjectProbe()..result = BackendProjectProbeResult.exists,
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
