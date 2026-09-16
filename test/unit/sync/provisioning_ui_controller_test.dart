import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';

import '../../helpers/provisioning_fakes.dart';

void main() {
  late FakeProvisioningApi api;
  late FakeBrowserLauncher launcher;
  late ProviderContainer container;

  void buildContainer({ProvisioningApi? withApi}) {
    container = ProviderContainer(
      overrides: [
        provisioningApiProvider.overrideWithValue(withApi),
        browserLauncherProvider.overrideWithValue(launcher),
        provisioningPollIntervalProvider.overrideWith(
          (ref) => const Duration(hours: 1),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<ProvisioningUiState> loadState() =>
      container.read(provisioningUiProvider.future);

  ProvisioningUiState current() =>
      container.read(provisioningUiProvider).value!;

  ProvisioningUiController controller() =>
      container.read(provisioningUiProvider.notifier);

  setUp(() {
    api = FakeProvisioningApi();
    launcher = FakeBrowserLauncher();
  });

  test(
    'reports an unavailable setup when no control plane is configured',
    () async {
      buildContainer(withApi: null);

      final state = await loadState();

      expect(state.phase, ProvisioningUiPhase.unavailable);
      expect(state.message, cloudSetupUnavailableMessage);
      expect(api.calls, isEmpty);
    },
  );

  test('stays local-only when no attempt exists', () async {
    buildContainer(withApi: api);

    expect((await loadState()).phase, ProvisioningUiPhase.localOnly);
  });

  test(
    'starts setup, launches the browser and waits for authorization',
    () async {
      api.startResult = ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        profile: testProfile(ProvisioningState.authorizationPending),
        authorizationUrl: testAuthorizationUrl,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().startSetup();

      expect(api.startAttemptCount, 1);
      expect(launcher.opened, <Uri>[testAuthorizationUrl]);
      expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);
      expect(current().authorizationUrlAvailable, isTrue);
    },
  );

  test(
    'a failed browser hand-off stays retryable and keeps the attempt',
    () async {
      api.startResult = ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        profile: testProfile(ProvisioningState.authorizationPending),
        authorizationUrl: testAuthorizationUrl,
      );
      launcher.succeeds = false;
      buildContainer(withApi: api);
      await loadState();

      await controller().startSetup();

      expect(current().phase, ProvisioningUiPhase.retryableError);
      expect(current().message, cloudSetupBrowserLaunchFailedMessage);
      expect(current().authorizationUrlAvailable, isTrue);
      expect(api.attempt, isNotNull);
      expect(api.startAttemptCount, 1);
    },
  );

  test('keeps waiting while Supabase authorization is not complete', () async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.organizationsResult = ProvisioningResult(
      outcome: ProvisioningOutcome.restartRequired,
      profile: testProfile(ProvisioningState.authorizationPending),
    );
    buildContainer(withApi: api);
    await loadState();

    await controller().checkAuthorization();

    expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);
    expect(current().message, cloudSetupStillWaitingMessage);
  });

  test('offers discovered organizations for explicit selection', () async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.organizationsResult = testOrganizations(
      const <ProvisioningOrganization>[
        ProvisioningOrganization(id: 'org-1', name: 'Ks_Planner', slug: 'ks'),
        ProvisioningOrganization(id: 'org-2', name: 'Second', slug: 'second'),
      ],
    );
    buildContainer(withApi: api);
    await loadState();

    await controller().checkAuthorization();

    expect(current().phase, ProvisioningUiPhase.organizationSelection);
    expect(current().organizations, hasLength(2));
    expect(current().selectedOrganization, isNull);
  });

  test(
    'preselects a single organization but still requires Continue',
    () async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.organizationsResult = testOrganizations(
        const <ProvisioningOrganization>[
          ProvisioningOrganization(id: 'org-1', name: 'Ks_Planner', slug: 'ks'),
        ],
      );
      buildContainer(withApi: api);
      await loadState();
      await controller().checkAuthorization();

      expect(current().selectedOrganization?.slug, 'ks');
      expect(api.selections, isEmpty);

      await controller().continueSetup();

      expect(api.selections.single.slug, 'ks');
    },
  );

  test(
    'continues with the deterministic project name for this transaction',
    () async {
      api.attempt = testAttempt(ProvisioningState.organizationSelected);
      buildContainer(withApi: api);
      await loadState();
      controller().selectOrganization(
        const ProvisioningOrganization(
          id: 'org-1',
          name: 'Ks_Planner',
          slug: 'ks',
        ),
      );
      api.selectResult = testInProgress(ProvisioningState.projectWaiting);

      await controller().continueSetup();

      expect(api.selections.single.slug, 'ks');
      expect(
        api.selections.single.projectName,
        provisioningProjectName(testTransactionId),
      );
      expect(current().phase, ProvisioningUiPhase.provisioning);
      expect(current().stage, CloudSetupStage.creatingProject);
    },
  );

  test('drives the authoritative create, migrate and verify steps', () async {
    api.attempt = testAttempt(ProvisioningState.projectCreating);
    api.createResult = testInProgress(ProvisioningState.projectWaiting);
    buildContainer(withApi: api);
    await loadState();
    await controller().advance();
    expect(api.calls, contains('createOrContinueProject'));

    api.attempt = testAttempt(
      ProvisioningState.projectWaiting,
      projectRef: testProjectRef,
    );
    api.migrateResult = testInProgress(
      ProvisioningState.migrating,
      projectRef: testProjectRef,
    );
    await controller().advance();
    expect(api.calls, contains('migrate'));
    expect(current().stage, CloudSetupStage.preparingDatabase);

    api.attempt = testAttempt(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    api.verifyResult = testInProgress(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    await controller().advance();
    expect(api.calls, contains('verify'));
    expect(current().stage, CloudSetupStage.verifyingSetup);
  });

  test('surfaces a ready backend with the persisted profile', () async {
    api.attempt = testAttempt(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    api.verifyResult = ProvisioningResult(
      outcome: ProvisioningOutcome.ready,
      profile: testProfile(ProvisioningState.ready, projectRef: testProjectRef),
    );
    buildContainer(withApi: api);
    await loadState();

    await controller().advance();

    expect(current().phase, ProvisioningUiPhase.ready);
    expect(current().readyProfile?.projectRef, testProjectRef);
    expect(current().readyProfile?.publishableKey, testPublishableKey);
  });

  test('requires a restart when the capability is missing', () async {
    api.attempt = testAttempt(
      ProvisioningState.projectWaiting,
      hasCapability: false,
      projectRef: testProjectRef,
    );
    buildContainer(withApi: api);

    final state = await loadState();

    expect(state.phase, ProvisioningUiPhase.restartRequired);
    expect(state.message, cloudSetupMissingCapabilityMessage);
  });

  test('requires a restart for an expired attempt', () async {
    api.attempt = testAttempt(ProvisioningState.expired);
    buildContainer(withApi: api);

    final state = await loadState();

    expect(state.phase, ProvisioningUiPhase.restartRequired);
    expect(state.message, cloudSetupRestartMessage);
  });

  test('shows a safe terminal message without upstream detail', () async {
    api.attempt = testAttempt(
      ProvisioningState.terminalError,
      errorCode: 'migration_history_mismatch',
      projectRef: testProjectRef,
    );
    buildContainer(withApi: api);

    final state = await loadState();

    expect(state.phase, ProvisioningUiPhase.terminalError);
    expect(state.message, cloudSetupTerminalMessage);
    expect(state.errorCode, 'migration_history_mismatch');
    expect(state.message, isNot(contains('HTTP')));
    expect(state.message, isNot(contains('<')));
  });

  test('exposes retryable failures and retries the next step', () async {
    api.attempt = testAttempt(
      ProvisioningState.projectWaiting,
      projectRef: testProjectRef,
    );
    api.migrateResult = const ProvisioningResult(
      outcome: ProvisioningOutcome.retryable,
      message: 'Provisioning stopped: operation_in_progress (HTTP 409).',
    );
    buildContainer(withApi: api);
    await loadState();
    await controller().advance();

    expect(current().phase, ProvisioningUiPhase.retryableError);

    api.migrateResult = testInProgress(
      ProvisioningState.migrating,
      projectRef: testProjectRef,
    );
    await controller().retry();

    expect(api.calls.where((call) => call == 'migrate'), hasLength(2));
    expect(current().phase, ProvisioningUiPhase.provisioning);
  });

  test(
    'starting again calls startAttempt instead of touching storage',
    () async {
      api.attempt = testAttempt(ProvisioningState.expired);
      api.startResult = ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        profile: testProfile(ProvisioningState.authorizationPending),
        authorizationUrl: testAuthorizationUrl,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().startAgain();

      expect(api.startAttemptCount, 1);
      expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);
    },
  );

  test(
    'resumes an existing attempt without creating another transaction',
    () async {
      api.attempt = testAttempt(
        ProvisioningState.projectWaiting,
        projectRef: testProjectRef,
      );
      api.migrateResult = testInProgress(
        ProvisioningState.migrating,
        projectRef: testProjectRef,
      );
      buildContainer(withApi: api);

      await loadState();
      await controller().startWatching();

      expect(api.startAttemptCount, 0);
      expect(api.calls, contains('migrate'));
      expect(current().phase, ProvisioningUiPhase.provisioning);
    },
  );

  test('a double action does not run the same operation twice', () async {
    api.attempt = testAttempt(ProvisioningState.organizationSelected);
    buildContainer(withApi: api);
    await loadState();
    controller().selectOrganization(
      const ProvisioningOrganization(
        id: 'org-1',
        name: 'Ks_Planner',
        slug: 'ks',
      ),
    );
    api.holdSelect = Completer<void>();

    final first = controller().continueSetup();
    final second = controller().continueSetup();
    api.holdSelect!.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(api.selections, hasLength(1));
  });
}
