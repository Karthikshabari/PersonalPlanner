import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/config/management_callback.dart';
import 'package:personal_planner/features/sync/data/app_link_source.dart';
import 'package:personal_planner/features/sync/data/backend_project_probe.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';
import 'package:personal_planner/features/sync/providers/deep_link_providers.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';

import '../../helpers/provisioning_fakes.dart';

void main() {
  late FakeProvisioningApi api;
  late FakeBrowserLauncher launcher;
  late FakeProjectProbe probe;
  late ProviderContainer container;

  void buildContainer({ProvisioningApi? withApi, AppLinkSource? linkSource}) {
    container = ProviderContainer(
      overrides: [
        provisioningApiProvider.overrideWithValue(withApi),
        browserLauncherProvider.overrideWithValue(launcher),
        if (linkSource != null)
          appLinkSourceProvider.overrideWithValue(linkSource),
        backendProjectProbeProvider.overrideWithValue(probe),
        provisioningPollIntervalProvider.overrideWith(
          (ref) => const Duration(hours: 1),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  /// Container variant for the automatic-refresh tests, which need a poll
  /// interval that actually elapses. Everything else stays identical.
  void buildPollingContainer({
    required ProvisioningApi api,
    Duration interval = const Duration(milliseconds: 20),
  }) {
    container = ProviderContainer(
      overrides: [
        provisioningApiProvider.overrideWithValue(api),
        browserLauncherProvider.overrideWithValue(launcher),
        backendProjectProbeProvider.overrideWithValue(probe),
        provisioningPollIntervalProvider.overrideWith((ref) => interval),
      ],
    );
    addTearDown(container.dispose);
  }

  /// Deterministic wait: no fixed sleeps, just bounded polling for a condition.
  Future<void> waitFor(
    bool Function() condition, {
    int attempts = 400,
    String? reason,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail(reason ?? 'condition was not reached');
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
    probe = FakeProjectProbe();
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
    'one verified legacy cloud requires explicit Use this project',
    () async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.resolutionResult = const ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        resolutionComplete: true,
        candidates: <ProvisioningCandidate>[
          ProvisioningCandidate(
            projectRef: 'abcdefghijklmnopqrst',
            name: 'Renamed cloud',
          ),
        ],
      );
      api.adoptionResult = ProvisioningResult(
        outcome: ProvisioningOutcome.ready,
        profile: testProfile(
          ProvisioningState.ready,
          projectRef: testProjectRef,
        ),
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().checkAuthorization();
      expect(current().phase, ProvisioningUiPhase.candidateSelection);
      expect(current().selectedCandidate?.name, 'Renamed cloud');
      expect(api.calls, contains('resolveProject'));
      expect(api.calls, isNot(contains('listOrganizations')));
      expect(
        api.calls.where((call) => call.startsWith('adoptProject')),
        isEmpty,
      );

      await controller().useSelectedCandidate();
      expect(current().phase, ProvisioningUiPhase.ready);
      expect(api.calls, contains('adoptProject:abcdefghijklmnopqrst'));
    },
  );

  test('multiple verified clouds are not chosen by list order', () async {
    api.attempt = testAttempt(ProvisioningState.authorizationPending);
    api.refreshResult = testInProgress(ProvisioningState.authorizationPending);
    api.resolutionResult = const ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      resolutionComplete: true,
      candidates: <ProvisioningCandidate>[
        ProvisioningCandidate(
          projectRef: 'abcdefghijklmnopqrst',
          name: 'Planner X',
        ),
        ProvisioningCandidate(
          projectRef: 'bcdefghijklmnopqrstu',
          name: 'Planner Y',
        ),
      ],
    );
    buildContainer(withApi: api);
    await loadState();

    await controller().checkAuthorization();
    expect(current().phase, ProvisioningUiPhase.candidateSelection);
    expect(current().selectedCandidate, isNull);
    expect(api.calls.where((call) => call.startsWith('adoptProject')), isEmpty);
    controller().selectCandidate(current().candidates.last);
    expect(current().selectedCandidate?.projectRef, 'bcdefghijklmnopqrstu');
  });

  test(
    'mapped project becomes ready without organization enumeration',
    () async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.resolutionResult = ProvisioningResult(
        outcome: ProvisioningOutcome.ready,
        profile: testProfile(
          ProvisioningState.ready,
          projectRef: testProjectRef,
        ),
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().checkAuthorization();
      expect(current().phase, ProvisioningUiPhase.ready);
      expect(api.calls, isNot(contains('listOrganizations')));
    },
  );

  test(
    'manual refresh exposes callback failure and retries the same attempt',
    () async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = ProvisioningResult(
        outcome: ProvisioningOutcome.retryable,
        profile: testProfile(ProvisioningState.authorizationPending),
        snapshot: const ProvisioningSnapshot(
          transactionId: testTransactionId,
          state: ProvisioningState.authorizationPending,
          authorizationFailed: true,
        ),
        message: 'Supabase authorization could not be completed.',
      );
      final newUrl = Uri.parse(
        'https://api.supabase.com/v1/oauth/authorize?state=new',
      );
      api.retryAuthorizationResult = ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        profile: testProfile(ProvisioningState.authorizationPending),
        authorizationUrl: newUrl,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().checkAuthorization();
      expect(current().phase, ProvisioningUiPhase.retryableError);
      expect(current().authorizationRetryAvailable, isTrue);
      expect(current().authorizationUrlAvailable, isFalse);
      expect(api.calls, isNot(contains('resolveProject')));
      await controller().retry();
      expect(api.calls, contains('retryAuthorization'));
      expect(api.startAttemptCount, 0);
      expect(launcher.opened, <Uri>[newUrl]);
      expect(current().transactionId, testTransactionId);
      expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);
    },
  );

  test('mapping conflict keeps READY until linked cloud is chosen', () async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.completeManagementResult = const ManagementCheckResult(
      outcome: ManagementCheckOutcome.mappingConflict,
      mappedProjectRef: 'bcdefghijklmnopqrstu',
    );
    api.recoverMappedResult = ProvisioningResult(
      outcome: ProvisioningOutcome.ready,
      profile: testProfile(
        ProvisioningState.ready,
        projectRef: 'bcdefghijklmnopqrstu',
      ),
    );
    buildContainer(withApi: api);
    await loadState();

    await controller().completeManagementCheck();
    expect(current().phase, ProvisioningUiPhase.ready);
    expect(current().mappingConflict, isTrue);
    expect(current().readyProfile?.projectRef, testProjectRef);
    expect(api.calls, isNot(contains('recoverMappedProject')));

    await controller().useMappedProject();
    expect(current().readyProfile?.projectRef, 'bcdefghijklmnopqrstu');
    expect(api.calls, contains('recoverMappedProject'));
  });

  test('invalid local project offers verified legacy recovery', () async {
    api.attempt = testAttempt(
      ProvisioningState.ready,
      projectRef: testProjectRef,
    );
    api.completeManagementResult = const ManagementCheckResult(
      outcome: ManagementCheckOutcome.candidateRecovery,
      candidates: <ProvisioningCandidate>[
        ProvisioningCandidate(
          projectRef: 'bcdefghijklmnopqrstu',
          name: 'Recovered cloud',
        ),
      ],
    );
    api.recoverMappedResult = ProvisioningResult(
      outcome: ProvisioningOutcome.ready,
      profile: testProfile(
        ProvisioningState.ready,
        projectRef: 'bcdefghijklmnopqrstu',
      ),
    );
    buildContainer(withApi: api);
    await loadState();
    await controller().completeManagementCheck();

    expect(current().phase, ProvisioningUiPhase.candidateSelection);
    expect(current().legacyRecovery, isTrue);
    expect(current().selectedCandidate?.projectRef, 'bcdefghijklmnopqrstu');
    await controller().useSelectedCandidate();
    expect(current().phase, ProvisioningUiPhase.ready);
    expect(api.calls, contains('recoverCandidateProject:bcdefghijklmnopqrstu'));
  });

  test(
    'deleted mapping waits for explicit replacement before new setup',
    () async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.resolutionResult = const ProvisioningResult(
        outcome: ProvisioningOutcome.projectDeleted,
      );
      buildContainer(withApi: api);
      await loadState();
      await controller().checkAuthorization();
      expect(current().phase, ProvisioningUiPhase.mappedProjectDeleted);
      expect(api.calls, isNot(contains('replaceDeletedProject')));

      api.resolutionResult = const ProvisioningResult(
        outcome: ProvisioningOutcome.inProgress,
        resolutionComplete: true,
      );
      await controller().replaceDeletedProject();
      expect(api.calls, contains('replaceDeletedProject'));
      expect(current().phase, ProvisioningUiPhase.organizationSelection);
    },
  );

  test(
    'retryable discovery failure never offers new project creation',
    () async {
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.resolutionResult = const ProvisioningResult(
        outcome: ProvisioningOutcome.retryable,
        message: 'candidate_discovery_failed',
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().checkAuthorization();
      expect(current().phase, ProvisioningUiPhase.retryableError);
      expect(api.calls, isNot(contains('listOrganizations')));
    },
  );

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
      expect(current().stage, CloudSetupStage.waitingForProject);
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
    expect(current().stage, CloudSetupStage.installingPlannerSchema);

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
    expect(current().stage, CloudSetupStage.verifyingCloudStorage);
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

    // Retry continues the same transaction rather than starting a new one.
    expect(api.calls.where((call) => call == 'migrate'), hasLength(2));
    expect(api.startAttemptCount, 0);
    expect(current().phase, ProvisioningUiPhase.provisioning);
  });

  test('start again from a retryable failure creates a new attempt', () async {
    const newTransactionId = 'ffffffffffffffffffffffffffffffff';
    api.attempt = testAttempt(
      ProvisioningState.verifying,
      projectRef: testProjectRef,
    );
    api.verifyResult = const ProvisioningResult(
      outcome: ProvisioningOutcome.retryable,
      message: 'Provisioning stopped: invalid_request (HTTP 400).',
    );
    buildContainer(withApi: api);
    await loadState();
    await controller().advance();

    expect(current().phase, ProvisioningUiPhase.retryableError);
    final verifyCallsBefore = api.calls
        .where((call) => call == 'verify')
        .length;

    api.startResult = ProvisioningResult(
      outcome: ProvisioningOutcome.inProgress,
      profile: testProfile(
        ProvisioningState.authorizationPending,
        transactionId: newTransactionId,
      ),
      authorizationUrl: testAuthorizationUrl,
    );
    await controller().startAgain();

    // A brand-new transaction was requested, the abandoned one was not
    // retried, and the UI returned to the authorization flow for the new id.
    expect(api.startAttemptCount, 1);
    expect(
      api.calls.where((call) => call == 'verify').length,
      verifyCallsBefore,
    );
    expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);
    expect(current().transactionId, newTransactionId);
    expect(current().transactionId, isNot(testTransactionId));
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

  group('Supabase authorization returns from the browser', () {
    test('resumes provisioning without the user pressing anything', () async {
      final links = StreamController<String>();
      addTearDown(links.close);
      final source = AppLinkSource(platformLinks: links.stream);
      addTearDown(source.dispose);
      await source.start();

      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.organizationsResult = testOrganizations(<ProvisioningOrganization>[
        const ProvisioningOrganization(id: 'org-1', name: 'Ks', slug: 'ks'),
      ]);
      buildContainer(withApi: api, linkSource: source);
      await loadState();
      expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);

      links.add(ManagementCallback.redirectUrl);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.calls, contains('refresh'));
      expect(api.calls, contains('listOrganizations'));
      expect(current().phase, ProvisioningUiPhase.organizationSelection);
    });

    test(
      'a Management callback completes the check the user started',
      () async {
        final links = StreamController<String>();
        addTearDown(links.close);
        final source = AppLinkSource(platformLinks: links.stream);
        addTearDown(source.dispose);
        await source.start();

        api.attempt = testAttempt(
          ProvisioningState.ready,
          projectRef: testProjectRef,
        );
        api.startManagementResult = ManagementStartResult(
          outcome: ManagementStartOutcome.authorizationReady,
          authorizationUrl: Uri.parse(
            'https://api.supabase.com/v1/oauth/authorize?client_id=client',
          ),
        );
        api.completeManagementResult = const ManagementCheckResult(
          outcome: ManagementCheckOutcome.exists,
          status: 'ACTIVE_HEALTHY',
        );
        buildContainer(withApi: api, linkSource: source);
        await loadState();

        await controller().reauthorizeSupabaseAccess();
        expect(launcher.opened, hasLength(1));
        expect(current().managementCheckInFlight, isTrue);

        links.add(ManagementCallback.redirectUrl);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(api.calls, contains('completeManagementCheck'));
        expect(current().managementCheckInFlight, isFalse);
        expect(current().message, cloudSetupReauthorizedMessage);
        expect(current().phase, ProvisioningUiPhase.ready);
      },
    );

    test('a failed browser callback drops only the pending check', () async {
      final links = StreamController<String>();
      addTearDown(links.close);
      final source = AppLinkSource(platformLinks: links.stream);
      addTearDown(source.dispose);
      await source.start();
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
      api.startManagementResult = ManagementStartResult(
        outcome: ManagementStartOutcome.authorizationReady,
        authorizationUrl: Uri.parse(
          'https://api.supabase.com/v1/oauth/authorize?client_id=client',
        ),
      );
      buildContainer(withApi: api, linkSource: source);
      await loadState();
      await controller().reauthorizeSupabaseAccess();

      links.add('${ManagementCallback.redirectUrl}?result=failed');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.calls, contains('abandonManagementCheck'));
      expect(api.calls, isNot(contains('completeManagementCheck')));
      expect(current().managementCheckInFlight, isFalse);
      expect(current().phase, ProvisioningUiPhase.ready);
      expect(current().readyProfile?.projectRef, testProjectRef);
    });
  });

  group('automatic progress refresh', () {
    test('a waiting screen refreshes progress by itself', () async {
      api.attempt = testAttempt(ProvisioningState.projectWaiting);
      api.migrateResult = testInProgress(
        ProvisioningState.projectWaiting,
        projectRef: testProjectRef,
      );
      buildPollingContainer(api: api);
      await loadState();

      await controller().startWatching();
      await waitFor(() => api.calls.where((c) => c == 'migrate').length >= 2);

      // No user action was needed: the screen checked twice on its own.
      expect(current().phase, ProvisioningUiPhase.provisioning);
      expect(current().busy, isFalse);
    });

    test('authorization completed on another device is detected', () async {
      // Cross-device: no deep link ever reaches this process. The transaction
      // is still authorization_pending until the Worker sees the consent, so
      // the automatic check is what has to notice it.
      api.attempt = testAttempt(ProvisioningState.authorizationPending);
      api.refreshResult = testInProgress(
        ProvisioningState.authorizationPending,
      );
      api.organizationsResult = ProvisioningResult(
        outcome: ProvisioningOutcome.restartRequired,
        profile: testProfile(ProvisioningState.authorizationPending),
      );
      buildPollingContainer(api: api);
      await loadState();
      await controller().startWatching();
      await waitFor(() => api.calls.contains('listOrganizations'));
      expect(current().phase, ProvisioningUiPhase.waitingForAuthorization);

      // The phone finishes the Supabase consent; the Worker now has the
      // Management credential for this same transaction.
      api.organizationsResult = testOrganizations(
        const <ProvisioningOrganization>[
          ProvisioningOrganization(id: 'org-1', name: 'Ks_Planner', slug: 'ks'),
        ],
      );

      await waitFor(
        () => current().phase == ProvisioningUiPhase.organizationSelection,
        reason: 'automatic refresh must detect the completed authorization',
      );
      expect(current().authorizationConfirmed, isTrue);
      expect(current().selectedOrganization?.slug, 'ks');
    });

    test('automatic refresh never overlaps a slow request', () async {
      final slow = _CountingProvisioningApi()
        ..attempt = testAttempt(ProvisioningState.projectWaiting)
        ..migrateResult = testInProgress(
          ProvisioningState.projectWaiting,
          projectRef: testProjectRef,
        );
      buildPollingContainer(api: slow);
      await loadState();

      slow.gate = Completer<void>();
      final watching = controller().startWatching();
      await waitFor(() => slow.inFlight == 1);
      // Several poll intervals elapse while the first request is still open.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(slow.maxInFlight, 1);
      expect(slow.inFlight, 1);

      slow.gate!.complete();
      slow.gate = null;
      await watching;
      await waitFor(() => slow.inFlight == 0);
    });

    test('automatic refresh stops once the phase is terminal', () async {
      api.attempt = testAttempt(
        ProvisioningState.verifying,
        projectRef: testProjectRef,
      );
      api.verifyResult = ProvisioningResult(
        outcome: ProvisioningOutcome.ready,
        profile: testProfile(
          ProvisioningState.ready,
          projectRef: testProjectRef,
        ),
      );
      buildPollingContainer(api: api);
      await loadState();

      await controller().startWatching();
      await waitFor(() => current().phase == ProvisioningUiPhase.ready);
      final callsWhenReady = api.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(current().phase, ProvisioningUiPhase.ready);
      expect(api.calls.length, callsWhenReady);
    });

    test('automatic refresh stops when the screen is closed', () async {
      api.attempt = testAttempt(ProvisioningState.projectWaiting);
      api.migrateResult = testInProgress(
        ProvisioningState.projectWaiting,
        projectRef: testProjectRef,
      );
      buildPollingContainer(api: api);
      await loadState();

      await controller().startWatching();
      await waitFor(() => api.calls.contains('migrate'));
      controller().stopWatching();
      final callsWhenClosed = api.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(api.calls.length, callsWhenClosed);
    });

    test('a transient refresh failure keeps the durable state', () async {
      api.attempt = testAttempt(
        ProvisioningState.projectWaiting,
        projectRef: testProjectRef,
      );
      api.migrateResult = testInProgress(
        ProvisioningState.projectWaiting,
        projectRef: testProjectRef,
      );
      buildPollingContainer(api: api);
      await loadState();
      await controller().startWatching();
      await waitFor(() => api.calls.contains('migrate'));

      // A transport problem on the next tick must not mark anything deleted or
      // surface an error to the user.
      api.migrateError = const ProvisioningApiException(
        ProvisioningErrorKind.network,
        'The provisioning service could not be reached.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(current().phase, ProvisioningUiPhase.provisioning);
      expect(current().stage, CloudSetupStage.waitingForProject);
      expect(current().busy, isFalse);
      expect(api.calls, isNot(contains('markRemoteMissing')));
    });

    test('the manual refresh fallback still works', () async {
      api.attempt = testAttempt(ProvisioningState.projectWaiting);
      api.migrateResult = testInProgress(
        ProvisioningState.verifying,
        projectRef: testProjectRef,
      );
      buildContainer(withApi: api);
      await loadState();
      await controller().startWatching();

      // startWatching already advanced once; the explicit action advances
      // again along the same existing pathway.
      final before = api.calls.where((c) => c == 'migrate').length;
      await controller().advance();

      expect(api.calls.where((c) => c == 'migrate').length, before + 1);
      expect(current().phase, ProvisioningUiPhase.provisioning);
    });
  });

  group('Supabase access lifecycle', () {
    void readyAttempt() {
      api.attempt = testAttempt(
        ProvisioningState.ready,
        projectRef: testProjectRef,
      );
    }

    test('Re-authorize opens the Supabase consent page', () async {
      readyAttempt();
      final consent = Uri.parse(
        'https://api.supabase.com/v1/oauth/authorize?client_id=client',
      );
      api.startManagementResult = ManagementStartResult(
        outcome: ManagementStartOutcome.authorizationReady,
        authorizationUrl: consent,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().reauthorizeSupabaseAccess();

      expect(api.calls, contains('startManagementCheck'));
      expect(launcher.opened, <Uri>[consent]);
      expect(current().message, cloudSetupReauthorizeStartedMessage);
      expect(current().managementCheckInFlight, isTrue);
    });

    test('reports a refused browser hand-off instead of pretending', () async {
      readyAttempt();
      launcher.succeeds = false;
      api.startManagementResult = ManagementStartResult(
        outcome: ManagementStartOutcome.authorizationReady,
        authorizationUrl: Uri.parse(
          'https://api.supabase.com/v1/oauth/authorize?client_id=client',
        ),
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().reauthorizeSupabaseAccess();

      expect(current().message, cloudSetupBrowserLaunchFailedMessage);
      expect(current().managementCheckInFlight, isFalse);
    });

    test('reports an unavailable Worker instead of a silent no-op', () async {
      readyAttempt();
      api.startManagementResult = const ManagementStartResult(
        outcome: ManagementStartOutcome.retryable,
        message: 'offline',
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().reauthorizeSupabaseAccess();

      expect(launcher.opened, isEmpty);
      expect(current().message, 'offline');
    });

    test('an authoritative missing answer switches to recovery', () async {
      readyAttempt();
      api.completeManagementResult = const ManagementCheckResult(
        outcome: ManagementCheckOutcome.missing,
        status: 'missing',
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().completeManagementCheck();

      expect(current().phase, ProvisioningUiPhase.remoteMissing);
      expect(current().errorCode, 'missing');
      // The stored profile is preserved for the recovery card.
      expect(current().readyProfile?.projectRef, testProjectRef);
    });

    test(
      'an indeterminate answer keeps READY and explains the retry',
      () async {
        readyAttempt();
        api.completeManagementResult = const ManagementCheckResult(
          outcome: ManagementCheckOutcome.indeterminate,
          status: 'indeterminate',
        );
        buildContainer(withApi: api);
        await loadState();

        await controller().completeManagementCheck();

        expect(current().phase, ProvisioningUiPhase.ready);
        expect(current().message, cloudSetupCheckIndeterminateMessage);
      },
    );

    test(
      'a browser callback still in flight keeps the check pending',
      () async {
        readyAttempt();
        api.completeManagementResult = const ManagementCheckResult(
          outcome: ManagementCheckOutcome.authorizationPending,
          message: 'Waiting for Supabase authorization to finish.',
        );
        buildContainer(withApi: api);
        await loadState();

        await controller().completeManagementCheck();

        expect(current().phase, ProvisioningUiPhase.ready);
        expect(current().managementCheckInFlight, isTrue);
        expect(current().readyProfile?.projectRef, testProjectRef);
      },
    );

    test('reports a completed revocation', () async {
      readyAttempt();
      api.revokeManagementResult = const ManagementRevokeResult(
        outcome: ManagementRevokeOutcome.revoked,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().disconnectSupabaseAccess();

      expect(api.calls, contains('revokeManagementAccess'));
      expect(current().message, cloudSetupRevokedMessage);
    });

    test('never claims success when no credential was held', () async {
      readyAttempt();
      api.revokeManagementResult = const ManagementRevokeResult(
        outcome: ManagementRevokeOutcome.nothingHeld,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().disconnectSupabaseAccess();

      expect(current().message, cloudSetupNothingToRevokeMessage);
    });

    test('reports an unconfirmed revocation as a limitation', () async {
      readyAttempt();
      api.revokeManagementResult = const ManagementRevokeResult(
        outcome: ManagementRevokeOutcome.unconfirmed,
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().disconnectSupabaseAccess();

      expect(current().message, cloudSetupRevokeUnconfirmedMessage);
    });

    test('reports a transient revocation failure as retryable', () async {
      readyAttempt();
      api.revokeManagementResult = const ManagementRevokeResult(
        outcome: ManagementRevokeOutcome.retryable,
        message: 'offline',
      );
      buildContainer(withApi: api);
      await loadState();

      await controller().disconnectSupabaseAccess();

      expect(current().message, 'offline');
    });

    test('a 404 from the project host switches to recovery', () async {
      readyAttempt();
      probe.result = BackendProjectProbeResult.missing;
      api.remoteMissingRecorded = true;
      buildContainer(withApi: api);
      await loadState();

      await controller().verifyProjectHost();

      expect(api.calls, contains('markRemoteMissing'));
      expect(current().phase, ProvisioningUiPhase.remoteMissing);
    });

    test('a network failure at the project host changes nothing', () async {
      readyAttempt();
      probe.result = BackendProjectProbeResult.indeterminate;
      buildContainer(withApi: api);
      await loadState();

      await controller().verifyProjectHost();

      expect(api.calls, isNot(contains('markRemoteMissing')));
      expect(current().phase, ProvisioningUiPhase.ready);
      // READY is preserved, and the user is told how to get an authoritative
      // answer instead of being left with a state that looks healthy.
      expect(current().message, cloudSetupProjectUnreachableHintMessage);
    });

    test('a successful runtime sync clears transient unavailability without management access', () async {
      readyAttempt();
      probe.result = BackendProjectProbeResult.indeterminate;
      buildContainer(withApi: api);
      await loadState();
      await controller().verifyProjectHost();

      final callsBeforeRecovery = List<String>.of(api.calls);
      controller().noteRuntimeReachable();

      expect(current().phase, ProvisioningUiPhase.ready);
      expect(current().reachability, CloudReachability.reachable);
      expect(current().message, isNull);
      expect(api.calls, callsBeforeRecovery);
      expect(api.calls, isNot(contains('startManagementCheck')));
      expect(api.calls, isNot(contains('markRemoteMissing')));
    });
  });
}

/// Records how many status requests are open at once, and can hold one open.
class _CountingProvisioningApi extends FakeProvisioningApi {
  int inFlight = 0;
  int maxInFlight = 0;
  Completer<void>? gate;

  @override
  Future<ProvisioningResult> migrate() async {
    inFlight += 1;
    maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
    try {
      final hold = gate;
      if (hold != null) await hold.future;
      return await super.migrate();
    } finally {
      inFlight -= 1;
    }
  }
}
