import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/backend_project_probe.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';
import 'package:personal_planner/features/sync/presentation/widgets/cloud_setup_preflight.dart';
import 'package:personal_planner/features/sync/presentation/widgets/cloud_setup_card.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';

import '../helpers/provisioning_fakes.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required ProvisioningApi? api,
  required FakeBrowserLauncher launcher,
  FakeProjectProbe? probe,
  Future<void> Function()? onUseOfflineOnly,
  Future<void> Function()? onStopUsingCloud,
  Duration pollInterval = const Duration(hours: 1),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        provisioningApiProvider.overrideWithValue(api),
        browserLauncherProvider.overrideWithValue(launcher),
        // The ready card probes its own project host; tests script the answer
        // so no real network call is attempted.
        backendProjectProbeProvider.overrideWithValue(probe ?? _probe),
        // No periodic work during widget tests; the card still performs its
        // initial load/resume exactly once.
        provisioningPollIntervalProvider.overrideWith((ref) => pollInterval),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudSetupCard(
              onUseOfflineOnly: onUseOfflineOnly,
              // The production screen always supplies this lifecycle action;
              // the default keeps the advanced section's real control present.
              onStopUsingCloud: onStopUsingCloud ?? () async {},
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  for (var frame = 0; frame < 4; frame += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Advances the widget-test clock past several automatic refresh intervals
/// without ever sleeping for real.
Future<void> _pollTicks(WidgetTester tester, {int ticks = 10}) async {
  for (var tick = 0; tick < ticks; tick += 1) {
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Opens the collapsed "Supabase connection" disclosure.
Future<void> _openAdvancedAccess(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey('cloud-advanced-access'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// Starts a temporary Supabase authorization so the real cancel action exists.
Future<void> _startTemporaryAccess(
  WidgetTester tester,
  FakeProvisioningApi api,
) async {
  api.startManagementResult = ManagementStartResult(
    outcome: ManagementStartOutcome.authorizationReady,
    authorizationUrl: Uri.parse(
      'https://api.supabase.com/v1/oauth/authorize?client_id=client',
    ),
  );
  await _openAdvancedAccess(tester);
  await tester.tap(find.byKey(const ValueKey('cloud-reauthorize-action')));
  await _settle(tester);
}

final FakeProjectProbe _probe = FakeProjectProbe();

void main() {
  late FakeProvisioningApi api;
  late FakeBrowserLauncher launcher;

  setUp(() {
    api = FakeProvisioningApi();
    launcher = FakeBrowserLauncher();
    _probe
      // A reachable project host is the normal READY case. Tests that need an
      // unreachable host override this explicitly.
      ..result = BackendProjectProbeResult.exists
      ..probed.clear();
  });

  testWidgets('shows an unavailable state without a control plane', (
    tester,
  ) async {
    await _pumpCard(tester, api: null, launcher: launcher);

    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text(cloudSetupUnavailableMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-enable-action')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('shows the pre-flight and creates nothing when cancelled', (
    tester,
  ) async {
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text('Set up cloud storage'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-enable-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud-setup-preflight')), findsOneWidget);
    expect(find.text(cloudSetupPreflightBody), findsOneWidget);
    expect(find.text('Creates 1 Supabase project'), findsOneWidget);
    expect(
      find.text('Personal Planner configures the project automatically'),
      findsOneWidget,
    );
    expect(find.text('Nothing is created until you continue'), findsOneWidget);
    // The unverifiable storage estimate is never presented as a fact.
    expect(find.textContaining('30'), findsNothing);
    expect(
      find.textContaining('a small amount of your Supabase project storage'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('cloud-preflight-cancel')));
    await tester.pumpAndSettle();

    expect(api.startAttemptCount, 0);
    // Only the durable-state read happens; no provisioning call is made.
    expect(
      api.calls.where((call) => call != 'loadAttempt'),
      isEmpty,
    );
    expect(launcher.opened, isEmpty);
    // The screen is unchanged and still offers the same first action.
    expect(find.byKey(const ValueKey('cloud-enable-action')), findsOneWidget);
    expect(find.text('Set up cloud storage'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('continues the existing provisioning flow exactly once', (
    tester,
  ) async {
    api.startResult = ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      profile: testProfile(ProvisioningState.authorizationPending),
      authorizationUrl: testAuthorizationUrl,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await tester.tap(find.byKey(const ValueKey('cloud-enable-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-preflight-continue')));
    await _settle(tester);

    expect(api.startAttemptCount, 1);
    expect(launcher.opened, <Uri>[testAuthorizationUrl]);
    expect(find.text(cloudStorageWaitingStatus), findsOneWidget);
    // A second tap while the first attempt is running cannot start another.
    expect(find.byKey(const ValueKey('cloud-enable-action')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('cannot submit the pre-flight twice', (tester) async {
    api.startResult = ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      profile: testProfile(ProvisioningState.authorizationPending),
      authorizationUrl: testAuthorizationUrl,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await tester.tap(find.byKey(const ValueKey('cloud-enable-action')));
    await tester.pumpAndSettle();
    // Confirming closes the dialog immediately, so a rapid second tap cannot
    // reach either the pre-flight or the provisioning entry point again.
    await tester.tap(find.byKey(const ValueKey('cloud-preflight-continue')));
    await tester.tap(
      find.byKey(const ValueKey('cloud-preflight-continue')),
      warnIfMissed: false,
    );
    await _settle(tester);

    expect(api.startAttemptCount, 1);

    await _unmount(tester);
  });

  testWidgets('waits for authorization with a manual check action', (
    tester,
  ) async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    // Supabase authorization is not finished yet, so discovery cannot run.
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    // The manual control is the fallback, not the expected path: the screen
    // refreshes itself while it waits.
    expect(find.text('Refresh status'), findsOneWidget);
    expect(find.text(cloudStorageWaitingStatus), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-check-authorization')));
    await _settle(tester);

    expect(api.calls, contains('refresh'));
    expect(api.startAttemptCount, 0);
    expect(find.textContaining('not complete yet'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('preselects one organization but requires Continue', (
    tester,
  ) async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    api.selectResult = testInProgress(ProvisioningState.projectWaiting);
    await _pumpCard(tester, api: api, launcher: launcher);

    // The user finishes authorizing in the browser, then asks to continue.
    api.organizationsResult = testOrganizations(
      const <ProvisioningOrganization>[
        ProvisioningOrganization(id: 'org-1', name: 'Ks_Planner', slug: 'ks'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('cloud-check-authorization')));
    await _settle(tester);

    expect(find.text('Ks_Planner'), findsOneWidget);
    expect(api.selections, isEmpty);

    await tester.tap(find.byKey(const ValueKey('cloud-continue-action')));
    await _settle(tester);

    expect(api.selections.single.slug, 'ks');
    expect(
      api.selections.single.projectName,
      provisioningProjectName(testTransactionId),
    );

    await _unmount(tester);
  });

  testWidgets('lets the user choose between several organizations', (
    tester,
  ) async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    api.selectResult = testInProgress(ProvisioningState.projectWaiting);
    await _pumpCard(tester, api: api, launcher: launcher);

    api.organizationsResult = testOrganizations(
      const <ProvisioningOrganization>[
        ProvisioningOrganization(id: 'org-1', name: 'Ks_Planner', slug: 'ks'),
        ProvisioningOrganization(id: 'org-2', name: 'Second', slug: 'second'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('cloud-check-authorization')));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('cloud-organization-second')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('cloud-continue-action')));
    await _settle(tester);

    expect(api.selections.single.slug, 'second');

    await _unmount(tester);
  });

  testWidgets('shows safe progress while the backend is set up', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.migrating,
      projectRef: testProjectRef,
    );
    api.migrateResult = testInProgress(
      ProvisioningState.migrating,
      projectRef: testProjectRef,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.textContaining('Configuring your database'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // One card, one indicator, one truthful stage line. The waiting screen
    // must never stack two identical indeterminate bars.
    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text('Refresh status'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets(
    'authorization completed elsewhere continues this device automatically',
    (tester) async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.organizationsResult = ProvisioningResult(
        outcome: ProvisioningOutcome.restartRequired,
        profile: testProfile(ProvisioningState.authorizationPending),
      );
      await _pumpCard(
        tester,
        api: api,
        launcher: launcher,
        pollInterval: const Duration(milliseconds: 20),
      );

      expect(find.text(cloudStorageWaitingStatus), findsOneWidget);

      // The consent is finished on the phone. This device gets no deep link at
      // all; the only way forward is the automatic status refresh.
      api.organizationsResult = testOrganizations(
        const <ProvisioningOrganization>[
          ProvisioningOrganization(
            id: 'org-1',
            name: 'Ks_Planner',
            slug: 'ks',
          ),
        ],
      );
      await _pollTicks(tester);

      expect(
        find.text(cloudSetupAuthorizationConfirmedMessage),
        findsOneWidget,
      );
      expect(find.text('Choose a Supabase organization'), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('offers Retry after a transient failure', (tester) async {
    api.attempt = testAttempt(
      ProvisioningState.projectWaiting,
      projectRef: testProjectRef,
    );
    api.migrateResult = const ProvisioningResult(
      outcome: ProvisioningOutcome.retryable,
      message: 'Provisioning stopped: operation_in_progress (HTTP 409).',
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text('Cloud setup paused'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Start Again'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud-retry-action')));
    await _settle(tester);

    // Retry continues the SAME transaction and never starts a new attempt.
    expect(api.calls.where((call) => call == 'migrate').length, greaterThan(1));
    expect(api.startAttemptCount, 0);

    await _unmount(tester);
  });

  testWidgets(
    'Start Again abandons a retryable attempt and starts a new transaction',
    (tester) async {
      const newTransactionId = 'ffffffffffffffffffffffffffffffff';
      api.attempt = testAttempt(
        ProvisioningState.verifying,
        projectRef: testProjectRef,
      );
      api.verifyResult = const ProvisioningResult(
        outcome: ProvisioningOutcome.retryable,
        message: 'Provisioning stopped: invalid_request (HTTP 400).',
      );
      api.startResult = ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        profile: testProfile(
          ProvisioningState.authorizationPending,
          transactionId: newTransactionId,
        ),
        authorizationUrl: testAuthorizationUrl,
      );
      await _pumpCard(tester, api: api, launcher: launcher);

      expect(find.text('Cloud setup paused'), findsOneWidget);
      final verifyCallsBefore = api.calls
          .where((call) => call == 'verify')
          .length;

      await tester.tap(find.byKey(const ValueKey('cloud-start-again')));
      await _settle(tester);

      // A brand-new transaction was requested for the authorization flow, and
      // the abandoned attempt was not advanced again.
      expect(api.startAttemptCount, 1);
      expect(
        api.calls.where((call) => call == 'verify').length,
        verifyCallsBefore,
      );
      expect(launcher.opened, <Uri>[testAuthorizationUrl]);
      expect(find.text(cloudStorageWaitingStatus), findsOneWidget);
      // Transaction identifiers are never rendered, not even behind a
      // disclosure.
      expect(find.textContaining(newTransactionId), findsNothing);
      expect(find.text('Technical details'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'keeps Open authorization page available on a retryable failure',
    (tester) async {
      api.startResult = ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        profile: testProfile(ProvisioningState.authorizationPending),
        authorizationUrl: testAuthorizationUrl,
      );
      api.refreshResult = const ProvisioningResult(
        outcome: ProvisioningOutcome.retryable,
        message: 'Provisioning stopped: rate_limited (HTTP 429).',
      );
      await _pumpCard(tester, api: api, launcher: launcher);

      await tester.tap(find.byKey(const ValueKey('cloud-enable-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cloud-preflight-continue')));
      await _settle(tester);
      expect(find.text(cloudStorageWaitingStatus), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cloud-check-authorization')));
      await _settle(tester);

      expect(find.text('Cloud setup paused'), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-retry-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-start-again')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cloud-open-authorization')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('cloud-open-authorization')));
      await _settle(tester);
      expect(launcher.opened, <Uri>[
        testAuthorizationUrl,
        testAuthorizationUrl,
      ]);

      await _unmount(tester);
    },
  );

  testWidgets('offers Start Setup Again for an expired session', (
    tester,
  ) async {
    api.attempt = testAttempt(ProvisioningState.expired);
    api.startResult = ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      profile: testProfile(ProvisioningState.authorizationPending),
      authorizationUrl: testAuthorizationUrl,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text('Start Setup Again'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-restart-action')));
    await _settle(tester);

    expect(api.startAttemptCount, 1);

    await _unmount(tester);
  });

  testWidgets('shows a safe terminal failure', (tester) async {
    api.attempt = testAttempt(
      ProvisioningState.terminalError,
      errorCode: 'project_identity_ambiguous',
      projectRef: testProjectRef,
    );
    api.startResult = ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      profile: testProfile(ProvisioningState.authorizationPending),
      authorizationUrl: testAuthorizationUrl,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text("Cloud setup couldn't be completed"), findsOneWidget);
    expect(find.textContaining('Start again'), findsOneWidget);
    expect(find.textContaining('HTTP'), findsNothing);

    expect(find.byKey(const ValueKey('cloud-restart-action')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-restart-action')));
    await _settle(tester);
    expect(api.startAttemptCount, 1);

    await _unmount(tester);
  });

  testWidgets('reports a ready backend without claiming Planner sync', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    api.verifyResult = ProvisioningResult(
      outcome: ProvisioningOutcome.ready,
      profile: testProfile(ProvisioningState.ready, projectRef: testProjectRef),
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    // One authoritative status, not a "ready" block plus a second one.
    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text(cloudStorageConnectedStatus), findsOneWidget);
    expect(find.text(cloudSetupReadyBody), findsOneWidget);
    expect(find.textContaining(testProjectRef), findsNothing);
    expect(find.text('Sync now'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    // A connected backend is never offered a restart action here.
    expect(find.byKey(const ValueKey('cloud-restart-action')), findsNothing);
    expect(find.byKey(const ValueKey('cloud-start-again')), findsNothing);
    expect(find.textContaining(testPublishableKey), findsNothing);
    // The advanced area is secondary and collapsed by default.
    expect(find.text(cloudSetupSupabaseAccessTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-reauthorize-action')),
      findsNothing,
    );
    expect(find.text(cloudSetupCheckConnectionLabel), findsNothing);
    expect(find.byKey(const ValueKey('cloud-open-dashboard')), findsOneWidget);
    expect(find.text('Open Supabase'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud-open-dashboard')));
    await _settle(tester);
    expect(
      launcher.opened.last,
      Uri.parse('https://supabase.com/dashboard/project/$testProjectRef'),
    );

    await _unmount(tester);
  });

  testWidgets('resumes an existing attempt instead of starting a new one', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    api.verifyResult = testInProgress(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(api.startAttemptCount, 0);
    expect(api.calls, contains('verify'));
    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.textContaining('Finishing setup'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('stays usable on a phone-sized surface', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(tester.takeException(), isNull);
    expect(find.text(cloudStorageWaitingStatus), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-check-authorization')),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets(
    'keeps Supabase access secondary and truthful when nothing is held',
    (tester) async {
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
      await _pumpCard(tester, api: api, launcher: launcher);

      expect(find.text(cloudSetupSupabaseAccessTitle), findsOneWidget);
      expect(find.text(cloudSetupSupabaseAccessBody), findsOneWidget);
      // Nothing prominent offers a revoke that would have nothing to revoke.
      expect(find.text('Disconnect Supabase access'), findsNothing);
      expect(find.byKey(const ValueKey('cloud-revoke-action')), findsNothing);
      // The technical labels are gone from the ordinary screen.
      expect(find.text('Re-authorize Supabase'), findsNothing);
      expect(find.text('Cloud project'), findsNothing);
      expect(find.textContaining(testProjectRef), findsNothing);

      await tester.tap(find.byKey(const ValueKey('cloud-advanced-access')));
      await tester.pumpAndSettle();

      // Nothing is held, so no passive "access released" line is needed and
      // the ordinary check action is the only maintenance control.
      expect(
        find.byKey(const ValueKey('cloud-management-status')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('cloud-reauthorize-action')),
        findsOneWidget,
      );
      expect(find.text(cloudSetupCheckConnectionLabel), findsOneWidget);
      // The device-level lifecycle action is separated from the check, and
      // explains what it does not delete.
      expect(find.text(cloudSetupStopUsingCloudLabel), findsOneWidget);
      expect(find.text(cloudSetupStopUsingCloudSupport), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cloud-stop-using-cloud-action')),
        findsOneWidget,
      );
      expect(
        find.text(cloudSetupStopUsingCloudLabel),
        findsOneWidget,
      );

      await _unmount(tester);
    },
  );

  testWidgets('an unreachable project host is never shown as deleted', (
    tester,
  ) async {
    _probe.result = BackendProjectProbeResult.indeterminate;
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text(cloudStorageTitle), findsOneWidget);
    expect(find.text(cloudStorageUnreachableStatus), findsOneWidget);
    expect(find.text(cloudSetupProjectUnreachableHintMessage), findsOneWidget);
    // Temporary connectivity trouble never offers the deleted-project path.
    expect(find.text(cloudRemoteMissingTitle), findsNothing);
    expect(find.text('Set up cloud storage again'), findsNothing);
    expect(find.byKey(const ValueKey('cloud-setup-again-action')), findsNothing);
    expect(find.text('Open Supabase'), findsNothing);
    // Both non-destructive options stay available.
    expect(find.byKey(const ValueKey('cloud-retry-probe-action')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-reauthorize-action')),
      findsOneWidget,
    );
    expect(api.calls, isNot(contains('markRemoteMissing')));

    // "Try again" probes again without touching durable state.
    final probesBefore = _probe.probed.length;
    await tester.tap(find.byKey(const ValueKey('cloud-retry-probe-action')));
    await _settle(tester);
    expect(_probe.probed.length, greaterThan(probesBefore));
    expect(api.calls, isNot(contains('markRemoteMissing')));

    await _unmount(tester);
  });

  testWidgets('a recovered probe returns the card to Connected', (tester) async {
    _probe.result = BackendProjectProbeResult.indeterminate;
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    await _pumpCard(tester, api: api, launcher: launcher);
    expect(find.text(cloudStorageUnreachableStatus), findsOneWidget);

    _probe.result = BackendProjectProbeResult.exists;
    await tester.tap(find.byKey(const ValueKey('cloud-retry-probe-action')));
    await _settle(tester);

    expect(find.text(cloudStorageConnectedStatus), findsOneWidget);
    expect(find.text(cloudSetupReadyBody), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Check cloud connection opens the consent page and shows progress', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    final consent = Uri.parse(
      'https://api.supabase.com/v1/oauth/authorize?client_id=client',
    );
    api.startManagementResult = ManagementStartResult(
      outcome: ManagementStartOutcome.authorizationReady,
      authorizationUrl: consent,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await _openAdvancedAccess(tester);
    await tester.tap(find.byKey(const ValueKey('cloud-reauthorize-action')));
    await _settle(tester);

    expect(api.calls, contains('startManagementCheck'));
    expect(launcher.opened, contains(consent));
    expect(find.text(cloudSetupReauthorizeStartedMessage), findsOneWidget);
    // While the browser consent is outstanding the temporary access is shown as
    // active and offers a real cancel action.
    expect(find.text(cloudSetupSupabaseAccessPending), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-revoke-action')), findsOneWidget);
    expect(
      find.text(cloudSetupCancelAccessLabel),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets('Check cloud connection explains an unavailable Worker', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.startManagementResult = const ManagementStartResult(
      outcome: ManagementStartOutcome.retryable,
      message: 'The provisioning service could not be reached.',
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await _openAdvancedAccess(tester);
    await tester.tap(find.byKey(const ValueKey('cloud-reauthorize-action')));
    await _settle(tester);

    expect(launcher.opened, isEmpty);
    expect(
      find.text('The provisioning service could not be reached.'),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets('an authoritative missing answer shows the recovery card', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.completeManagementResult = const ManagementCheckResult(
      outcome: ManagementCheckOutcome.missing,
      status: 'missing',
    );
    api.startManagementResult = ManagementStartResult(
      outcome: ManagementStartOutcome.authorizationReady,
      authorizationUrl: Uri.parse(
        'https://api.supabase.com/v1/oauth/authorize?client_id=client',
      ),
    );
    var usedOffline = false;
    await _pumpCard(
      tester,
      api: api,
      launcher: launcher,
      onUseOfflineOnly: () async => usedOffline = true,
    );

    await _openAdvancedAccess(tester);
    await tester.tap(find.byKey(const ValueKey('cloud-reauthorize-action')));
    await _settle(tester);

    // The user completes the consent in the browser and returns to the app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    expect(find.text(cloudRemoteMissingTitle), findsOneWidget);
    expect(find.text(cloudRemoteMissingBody), findsOneWidget);
    expect(find.text('Set up cloud storage again'), findsOneWidget);
    expect(find.text('Use offline-only mode'), findsOneWidget);
    // A missing project is never offered a dashboard link or a new project
    // without an explicit confirmation.
    expect(find.text('Open Supabase'), findsNothing);
    expect(find.byKey(const ValueKey('cloud-open-dashboard')), findsNothing);
    expect(find.textContaining(testProjectRef), findsNothing);

    // Creating a replacement project asks first, and cancelling creates
    // nothing.
    await tester.tap(find.byKey(const ValueKey('cloud-setup-again-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cloud-setup-preflight')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-preflight-cancel')));
    await _settle(tester);
    expect(api.startAttemptCount, 0);
    // The recovery state itself is unchanged.
    expect(find.text(cloudRemoteMissingTitle), findsOneWidget);
    expect(find.text('Set up cloud storage again'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cloud-use-offline-only-action')),
    );
    await _settle(tester);
    expect(usedOffline, isTrue);

    await _unmount(tester);
  });

  testWidgets('confirms before cancelling temporary Supabase access', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.revokeManagementResult = const ManagementRevokeResult(
      outcome: ManagementRevokeOutcome.revoked,
    );
    await _pumpCard(tester, api: api, launcher: launcher);
    await _startTemporaryAccess(tester, api);

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel Supabase access?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(api.calls, isNot(contains('revokeManagementAccess')));

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-revoke-confirm')));
    await _settle(tester);

    expect(api.calls, contains('revokeManagementAccess'));
    expect(find.text(cloudSetupRevokedMessage), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('never claims a disconnect it did not perform', (tester) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.revokeManagementResult = const ManagementRevokeResult(
      outcome: ManagementRevokeOutcome.nothingHeld,
    );
    await _pumpCard(tester, api: api, launcher: launcher);
    await _startTemporaryAccess(tester, api);

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-revoke-confirm')));
    await _settle(tester);

    expect(find.text(cloudSetupNothingToRevokeMessage), findsOneWidget);
    // Nothing is held afterwards, so the prominent cancel action disappears.
    expect(find.byKey(const ValueKey('cloud-revoke-action')), findsNothing);
    expect(
      find.byKey(const ValueKey('cloud-management-status')),
      findsNothing,
    );

    await _unmount(tester);
  });

  testWidgets('explains an unconfirmed revocation instead of faking it', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.revokeManagementResult = const ManagementRevokeResult(
      outcome: ManagementRevokeOutcome.unconfirmed,
    );
    await _pumpCard(tester, api: api, launcher: launcher);
    await _startTemporaryAccess(tester, api);

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-revoke-confirm')));
    await _settle(tester);

    expect(find.text(cloudSetupRevokeUnconfirmedMessage), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('resumes setup when the app returns from the browser', (
    tester,
  ) async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    // The first pass still sees no completed authorization: the Worker has no
    // Management credential yet, which the controller reports as "still
    // waiting" rather than as a failure.
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    await _pumpCard(tester, api: api, launcher: launcher);
    expect(find.text(cloudStorageWaitingStatus), findsOneWidget);
    final callsBeforeResume = api.calls.length;

    api.organizationsResult = testOrganizations(<ProvisioningOrganization>[
      const ProvisioningOrganization(
        id: 'org-1',
        name: 'Ks_Planner',
        slug: 'ks',
      ),
    ]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    expect(api.calls.length, greaterThan(callsBeforeResume));
    expect(find.text('Choose a Supabase organization'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _unmount(tester);
  });
}
