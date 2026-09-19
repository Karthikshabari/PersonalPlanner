import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';
import 'package:personal_planner/features/sync/presentation/widgets/cloud_setup_card.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';

import '../helpers/provisioning_fakes.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required ProvisioningApi? api,
  required FakeBrowserLauncher launcher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        provisioningApiProvider.overrideWithValue(api),
        browserLauncherProvider.overrideWithValue(launcher),
        // No periodic work during widget tests; the card still performs its
        // initial load/resume exactly once.
        provisioningPollIntervalProvider.overrideWith(
          (ref) => const Duration(hours: 1),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CloudSetupCard())),
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  late FakeProvisioningApi api;
  late FakeBrowserLauncher launcher;

  setUp(() {
    api = FakeProvisioningApi();
    launcher = FakeBrowserLauncher();
  });

  testWidgets('shows an unavailable state without a control plane', (
    tester,
  ) async {
    await _pumpCard(tester, api: null, launcher: launcher);

    expect(find.text('Cloud sync'), findsOneWidget);
    expect(find.text(cloudSetupUnavailableMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-enable-action')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('offers Enable Cloud Sync and starts setup once', (tester) async {
    api.startResult = ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      profile: testProfile(ProvisioningState.authorizationPending),
      authorizationUrl: testAuthorizationUrl,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text('Enable Cloud Sync'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-enable-action')));
    await _settle(tester);

    expect(api.startAttemptCount, 1);
    expect(launcher.opened, <Uri>[testAuthorizationUrl]);
    expect(find.text('Authorize Supabase'), findsOneWidget);

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

    expect(find.text('Check authorization'), findsOneWidget);
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

    expect(find.text('Setting up your cloud backend'), findsOneWidget);
    expect(find.textContaining('Installing Planner schema'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await _unmount(tester);
  });

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
      expect(find.text('Authorize Supabase'), findsOneWidget);
      expect(find.textContaining(newTransactionId), findsNothing);
      await tester.tap(find.text('Technical details'));
      await _settle(tester);
      expect(find.textContaining(newTransactionId), findsOneWidget);

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
      await _settle(tester);
      expect(find.text('Authorize Supabase'), findsOneWidget);

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

    expect(find.text('Cloud storage ready'), findsOneWidget);
    expect(find.textContaining(testProjectRef), findsNothing);
    expect(find.text('Sync now'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    // A connected backend is never offered a restart action here.
    expect(find.byKey(const ValueKey('cloud-restart-action')), findsNothing);
    expect(find.byKey(const ValueKey('cloud-start-again')), findsNothing);
    expect(find.textContaining(testPublishableKey), findsNothing);
    expect(
      find.textContaining('Sign in or create a Planner account'),
      findsOneWidget,
    );
    // Account connection is available now; Planner data synchronization only
    // starts after the Phase G first synchronization is complete.
    expect(find.textContaining('begin syncing across devices'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-open-dashboard')), findsOneWidget);

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
    expect(find.text('Setting up your cloud backend'), findsOneWidget);
    expect(find.textContaining('Verifying cloud storage'), findsOneWidget);

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
    expect(find.text('Authorize Supabase'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-check-authorization')),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets(
    'separates the Planner account, the cloud project, and Supabase access',
    (tester) async {
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
      await _pumpCard(tester, api: api, launcher: launcher);

      // The cloud project is one card, with the dashboard behind its own action.
      expect(find.text('Cloud project'), findsOneWidget);
      expect(find.text('Open Supabase Dashboard'), findsOneWidget);

      // Management access is a distinct, clearly-labelled advanced section whose
      // two actions have different consequences.
      expect(find.text('Advanced · Supabase access'), findsOneWidget);
      expect(find.text(cloudSetupSupabaseAccessBody), findsOneWidget);
      expect(find.text('Re-authorize Supabase'), findsOneWidget);
      expect(find.text('Disconnect Supabase access'), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-sign-out-action')), findsNothing);
      expect(
        find.byKey(const ValueKey('cloud-management-status')),
        findsOneWidget,
      );

      await _unmount(tester);
    },
  );

  testWidgets('re-authorizes Supabase access by opening the consent page', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    final consent = Uri.parse(
      'https://api.supabase.com/v1/oauth/authorize?client_id=client',
    );
    api.startManagementResult = ManagementAuthorizationResult(
      outcome: ManagementAuthorizationOutcome.completed,
      authorizationUrl: consent,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await tester.tap(find.byKey(const ValueKey('cloud-reauthorize-action')));
    await _settle(tester);

    expect(api.calls, contains('startManagementAuthorization'));
    expect(launcher.opened, contains(consent));
    expect(find.text(cloudSetupReauthorizeStartedMessage), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('tells the user when a released authorization is unconfirmed', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.managementStatusResult = const ManagementAuthorizationResult(
      outcome: ManagementAuthorizationOutcome.completed,
      status: ProvisioningManagementAuthorization(
        authorized: false,
        pending: false,
        releaseUnconfirmed: true,
      ),
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    expect(find.text(cloudSetupSupabaseAccessReleased), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('confirms before disconnecting Supabase access', (tester) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.revokeManagementResult = const ManagementAuthorizationResult(
      outcome: ManagementAuthorizationOutcome.completed,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect Supabase access?'), findsOneWidget);

    // Leaving the dialog alone must not revoke anything.
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(api.calls, isNot(contains('revokeManagementAuthorization')));

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-revoke-confirm')));
    await _settle(tester);

    expect(api.calls, contains('revokeManagementAuthorization'));
    expect(find.text(cloudSetupRevokedMessage), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('explains the retained-token limitation instead of faking it', (
    tester,
  ) async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.revokeManagementResult = const ManagementAuthorizationResult(
      outcome: ManagementAuthorizationOutcome.notRetained,
    );
    await _pumpCard(tester, api: api, launcher: launcher);

    await tester.tap(find.byKey(const ValueKey('cloud-revoke-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-revoke-confirm')));
    await _settle(tester);

    expect(find.text(cloudSetupRevokeNotRetainedMessage), findsOneWidget);

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
    expect(find.text('Authorize Supabase'), findsOneWidget);
    final callsBeforeResume = api.calls.length;

    // The user finished in the browser and came back; no button was pressed.
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
