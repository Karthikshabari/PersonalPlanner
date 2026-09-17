import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/provisioning_client.dart';
import '../../domain/backend_connection_profile.dart';
import '../../domain/provisioning_coordinator.dart';
import '../../domain/provisioning_state.dart';
import '../../providers/provisioning_providers.dart';

/// Deterministic, internal Supabase project name for one provisioning attempt.
///
/// The transaction id is already part of the durable non-secret profile, so the
/// derived name is stable across retries, screen rebuilds and app restarts
/// without persisting anything extra, and it carries no personal information.
/// The result satisfies the Worker's `^personal-planner-[a-z0-9-]{3,55}$` rule.
String provisioningProjectName(String transactionId) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(transactionId)) {
    throw ArgumentError.value(
      transactionId,
      'transactionId',
      'must be a 32 character lowercase hexadecimal transaction id',
    );
  }
  return 'personal-planner-${transactionId.substring(0, 12)}';
}

// User-facing copy. Kept here so widgets and tests share one wording.
const cloudSetupUnavailableMessage =
    'Cloud setup is unavailable in this build because no provisioning '
    'control-plane URL is configured. Personal Planner keeps working locally.';
const cloudSetupLocalOnlyBody =
    'Cloud sync is optional. Personal Planner can create a Supabase project '
    'that belongs to you.';
const cloudSetupAuthorizationBody =
    'Personal Planner will ask Supabase for permission to create and configure '
    'one project inside an organization you choose.';
const cloudSetupWaitingMessage =
    'Waiting for Supabase authorization. Finish the steps in your browser, then '
    'choose Check authorization.';
const cloudSetupStillWaitingMessage =
    'Supabase authorization is not complete yet. Finish it in your browser, '
    'then try again.';
const cloudSetupBrowserLaunchFailedMessage =
    'The authorization page could not be opened. Try again, or open it from '
    'your browser.';
const cloudSetupRetryableMessage =
    "Cloud setup couldn't continue right now. Your Planner data is safe "
    'locally. Try again.';
const cloudSetupRestartMessage =
    'This setup session expired. Start cloud setup again.';
const cloudSetupMissingCapabilityMessage =
    'This setup session can no longer be resumed. Start cloud setup again.';
const cloudSetupTerminalMessage =
    "Cloud setup couldn't be completed. Start again or continue using Personal "
    'Planner locally.';
const cloudSetupProtocolMessage =
    'Cloud setup returned an unexpected response. Please try again later.';
const cloudSetupStaleMessage =
    'Cloud setup changed on this device. Try again to continue the active '
    'session.';
const cloudSetupNeedsUserActionMessage =
    'That Supabase organization is no longer available for setup. Choose an '
    'organization and try again.';
const cloudSetupReadyBody =
    'Your cloud backend is ready. Connect your Planner account below. Planner '
    'data synchronization is not enabled yet.';
const cloudSetupLeaveHint =
    'You can leave this screen. Setup continues safely and you can come back to '
    'it later.';

/// Presentation phases for the Settings → Sync cloud-setup card.
///
/// These are derived from the authoritative C2 state; they are not a second
/// provisioning state machine and carry no transition rules of their own.
enum ProvisioningUiPhase {
  /// No provisioning control-plane URL is configured for this build.
  unavailable,

  /// No cloud attempt exists; the Planner is local-only.
  localOnly,

  /// A transaction exists and the user still has to authorize Supabase.
  waitingForAuthorization,

  /// Organizations were discovered and the user must choose one.
  organizationSelection,

  /// The cloud backend is being created, migrated or verified.
  provisioning,

  /// A transient problem; retrying is safe.
  retryableError,

  /// The attempt cannot continue; the user must start setup again.
  restartRequired,

  /// The Worker reported an unrecoverable failure.
  terminalError,

  /// The client-safe backend profile is provisioned and persisted.
  ready,
}

/// User-facing progress stages inside [ProvisioningUiPhase.provisioning].
enum CloudSetupStage { creatingProject, preparingDatabase, verifyingSetup }

class ProvisioningUiState {
  const ProvisioningUiState({
    required this.phase,
    this.stage,
    this.transactionId,
    this.errorCode,
    this.organizations = const <ProvisioningOrganization>[],
    this.selectedOrganization,
    this.readyProfile,
    this.busy = false,
    this.authorizationUrlAvailable = false,
    this.message,
  });

  final ProvisioningUiPhase phase;
  final CloudSetupStage? stage;

  /// Debug-only identifiers; never credentials.
  final String? transactionId;
  final String? errorCode;

  final List<ProvisioningOrganization> organizations;
  final ProvisioningOrganization? selectedOrganization;
  final BackendConnectionProfile? readyProfile;
  final bool busy;

  /// True when this session still holds the authorization URL to re-open.
  final bool authorizationUrlAvailable;

  final String? message;

  bool get isReady => phase == ProvisioningUiPhase.ready;

  bool get canStartSetup =>
      phase == ProvisioningUiPhase.localOnly ||
      phase == ProvisioningUiPhase.restartRequired ||
      phase == ProvisioningUiPhase.terminalError;

  ProvisioningUiState copyWith({
    ProvisioningUiPhase? phase,
    String? message,
    bool clearMessage = false,
    ProvisioningOrganization? selectedOrganization,
    List<ProvisioningOrganization>? organizations,
    bool? busy,
    bool? authorizationUrlAvailable,
  }) => ProvisioningUiState(
    phase: phase ?? this.phase,
    stage: stage,
    transactionId: transactionId,
    errorCode: errorCode,
    organizations: organizations ?? this.organizations,
    selectedOrganization: selectedOrganization ?? this.selectedOrganization,
    readyProfile: readyProfile,
    busy: busy ?? this.busy,
    authorizationUrlAvailable:
        authorizationUrlAvailable ?? this.authorizationUrlAvailable,
    message: clearMessage ? null : (message ?? this.message),
  );
}

class ProvisioningUiController extends AsyncNotifier<ProvisioningUiState> {
  Timer? _timer;
  bool _operationInFlight = false;
  Uri? _authorizationUrl;

  @override
  Future<ProvisioningUiState> build() async {
    ref.onDispose(_cancelTimer);
    final api = ref.read(provisioningApiProvider);
    if (api == null) {
      return const ProvisioningUiState(
        phase: ProvisioningUiPhase.unavailable,
        message: cloudSetupUnavailableMessage,
      );
    }
    return _loadLocal(api);
  }

  ProvisioningApi? get _api => ref.read(provisioningApiProvider);

  /// Called when the setup card becomes visible.
  ///
  /// Loads durable local state first (no network), then resumes an in-flight
  /// attempt and starts conservative polling while the screen is open.
  Future<void> startWatching() async {
    final api = _api;
    if (api == null) return;
    _applyState(await _loadLocal(api));
    final phase = state.value?.phase;
    if (phase == ProvisioningUiPhase.waitingForAuthorization ||
        phase == ProvisioningUiPhase.provisioning) {
      _startTimer();
      await advance();
    }
  }

  /// Called when the setup card is removed; polling never outlives the screen.
  void stopWatching() => _cancelTimer();

  /// Reloads durable state without touching the network.
  Future<void> reload() async {
    final api = _api;
    if (api == null) return;
    _applyState(await _loadLocal(api));
  }

  /// "Enable Cloud Sync": creates a new provisioning attempt for a new attempt
  /// only; supersession and cleanup stay inside the C2 coordinator.
  Future<void> startSetup() => _run(() async {
    final api = _api;
    if (api == null) return;
    final result = await api.startAttempt();
    _authorizationUrl = result.authorizationUrl;
    if (result.outcome == ProvisioningOutcome.inProgress &&
        result.authorizationUrl != null) {
      final opened = await ref
          .read(browserLauncherProvider)
          .open(result.authorizationUrl!);
      if (!opened) {
        _applyResult(
          const ProvisioningResult(
            outcome: ProvisioningOutcome.retryable,
            message: cloudSetupBrowserLaunchFailedMessage,
          ),
          transactionId: result.profile?.provisioningTransactionId,
          authorizationUrlAvailable: true,
        );
        return;
      }
      _applyState(
        ProvisioningUiState(
          phase: ProvisioningUiPhase.waitingForAuthorization,
          transactionId: result.profile?.provisioningTransactionId,
          authorizationUrlAvailable: true,
          message: cloudSetupWaitingMessage,
        ),
      );
      _startTimer();
      return;
    }
    _applyResult(result);
  });

  /// Re-opens the authorization page for the current attempt when it is known.
  Future<void> openAuthorizationPage() => _run(() async {
    final url = _authorizationUrl;
    if (url == null) return;
    final opened = await ref.read(browserLauncherProvider).open(url);
    if (!opened) {
      _update(
        (current) =>
            current.copyWith(message: cloudSetupBrowserLaunchFailedMessage),
      );
    }
  });

  /// "Check authorization" / "Continue".
  Future<void> checkAuthorization() => _run(() async {
    final api = _api;
    if (api == null) return;
    await _continueAfterAuthorization(api);
  });

  /// Selects an organization locally; nothing is provisioned until Continue.
  void selectOrganization(ProvisioningOrganization organization) {
    _update((current) => current.copyWith(selectedOrganization: organization));
  }

  /// Confirms the chosen organization for the current attempt.
  Future<void> continueSetup() => _run(() async {
    final api = _api;
    final current = state.value;
    final selected = current?.selectedOrganization;
    final transactionId = current?.transactionId;
    if (api == null || selected == null || transactionId == null) return;
    final result = await api.selectOrganization(
      organizationSlug: selected.slug,
      projectName: provisioningProjectName(transactionId),
    );
    _applyResult(result);
  });

  /// Retries the next authoritative step.
  Future<void> retry() => advance();

  /// "Start again": the C2 coordinator supersedes the previous attempt.
  Future<void> startAgain() => startSetup();

  /// Advances setup by exactly one authoritative step.
  Future<void> advance() => _run(() async {
    final api = _api;
    if (api == null) return;
    final attempt = await api.loadAttempt();
    if (attempt == null) {
      _applyState(
        const ProvisioningUiState(phase: ProvisioningUiPhase.localOnly),
      );
      return;
    }
    switch (attempt.state) {
      case ProvisioningState.localOnly:
      case ProvisioningState.ready:
      case ProvisioningState.expired:
      case ProvisioningState.terminalError:
        _applyState(_stateForAttempt(attempt));
        return;
      case ProvisioningState.authorizationPending:
        await _continueAfterAuthorization(api);
        return;
      case ProvisioningState.organizationSelected:
      case ProvisioningState.projectCreating:
      case ProvisioningState.projectReconciliationRequired:
      case ProvisioningState.projectRetryAuthorized:
        _applyResult(await api.createOrContinueProject());
        return;
      case ProvisioningState.projectWaiting:
      case ProvisioningState.migrating:
      case ProvisioningState.migrationReconciliationRequired:
        _applyResult(await api.migrate());
        return;
      case ProvisioningState.verifying:
        _applyResult(await api.verify());
        return;
    }
  });

  Future<void> _continueAfterAuthorization(ProvisioningApi api) async {
    final refreshed = await api.refresh();
    if (refreshed.outcome != ProvisioningOutcome.inProgress) {
      _applyResult(refreshed);
      return;
    }
    final organizations = await api.listOrganizations();
    if (organizations.outcome == ProvisioningOutcome.restartRequired) {
      // The Worker has no Management credential yet: the user has not finished
      // authorizing in the browser.
      _update(
        (current) => current.copyWith(
          phase: ProvisioningUiPhase.waitingForAuthorization,
          authorizationUrlAvailable: _authorizationUrl != null,
          message: cloudSetupStillWaitingMessage,
        ),
      );
      return;
    }
    if (organizations.outcome != ProvisioningOutcome.inProgress) {
      _applyResult(organizations);
      return;
    }
    _applyState(
      ProvisioningUiState(
        phase: ProvisioningUiPhase.organizationSelection,
        transactionId:
            refreshed.profile?.provisioningTransactionId ??
            state.value?.transactionId,
        organizations: organizations.organizations,
        selectedOrganization: organizations.organizations.length == 1
            ? organizations.organizations.single
            : null,
        authorizationUrlAvailable: _authorizationUrl != null,
        message: cloudSetupAuthorizationBody,
      ),
    );
  }

  Future<ProvisioningUiState> _loadLocal(ProvisioningApi api) async {
    final attempt = await api.loadAttempt();
    if (attempt == null) {
      return const ProvisioningUiState(phase: ProvisioningUiPhase.localOnly);
    }
    return _stateForAttempt(attempt);
  }

  ProvisioningUiState _stateForAttempt(ProvisioningAttempt attempt) {
    if (attempt.state == ProvisioningState.ready) {
      return ProvisioningUiState(
        phase: ProvisioningUiPhase.ready,
        transactionId: attempt.transactionId,
        readyProfile: attempt.profile,
      );
    }
    if (attempt.state == ProvisioningState.localOnly) {
      return const ProvisioningUiState(phase: ProvisioningUiPhase.localOnly);
    }
    if (!attempt.hasCapability) {
      return ProvisioningUiState(
        phase: ProvisioningUiPhase.restartRequired,
        transactionId: attempt.transactionId,
        message: cloudSetupMissingCapabilityMessage,
      );
    }
    if (attempt.state == ProvisioningState.expired) {
      return ProvisioningUiState(
        phase: ProvisioningUiPhase.restartRequired,
        transactionId: attempt.transactionId,
        message: cloudSetupRestartMessage,
      );
    }
    if (attempt.state == ProvisioningState.terminalError) {
      return ProvisioningUiState(
        phase: ProvisioningUiPhase.terminalError,
        transactionId: attempt.transactionId,
        errorCode: attempt.profile.errorCode,
        message: cloudSetupTerminalMessage,
      );
    }
    return _provisioningState(
      transactionId: attempt.transactionId,
      workerState: attempt.state,
    );
  }

  ProvisioningUiState _provisioningState({
    required String? transactionId,
    required ProvisioningState? workerState,
  }) {
    switch (workerState) {
      case ProvisioningState.authorizationPending:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.waitingForAuthorization,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
          message: cloudSetupWaitingMessage,
        );
      case ProvisioningState.migrating:
      case ProvisioningState.migrationReconciliationRequired:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.preparingDatabase,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
        );
      case ProvisioningState.verifying:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.verifyingSetup,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
        );
      default:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.creatingProject,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
        );
    }
  }

  void _applyResult(
    ProvisioningResult result, {
    String? transactionId,
    bool? authorizationUrlAvailable,
  }) {
    final profile = result.profile;
    final id =
        profile?.provisioningTransactionId ??
        transactionId ??
        state.value?.transactionId;
    final canReopen = authorizationUrlAvailable ?? (_authorizationUrl != null);
    switch (result.outcome) {
      case ProvisioningOutcome.ready:
        _cancelTimer();
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.ready,
            transactionId: id,
            readyProfile: profile,
          ),
        );
        return;
      case ProvisioningOutcome.localOnly:
        _applyState(
          const ProvisioningUiState(phase: ProvisioningUiPhase.localOnly),
        );
        return;
      case ProvisioningOutcome.inProgress:
        final next = _provisioningState(
          transactionId: id,
          workerState: profile?.state,
        );
        _applyState(
          ProvisioningUiState(
            phase: next.phase,
            stage: next.stage,
            transactionId: next.transactionId,
            authorizationUrlAvailable: canReopen,
          ),
        );
        return;
      case ProvisioningOutcome.capabilityMissing:
        _cancelTimer();
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.restartRequired,
            transactionId: id,
            message: cloudSetupMissingCapabilityMessage,
          ),
        );
        return;
      case ProvisioningOutcome.restartRequired:
        _cancelTimer();
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.restartRequired,
            transactionId: id,
            message: result.message ?? cloudSetupRestartMessage,
          ),
        );
        return;
      case ProvisioningOutcome.terminal:
        _cancelTimer();
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.terminalError,
            transactionId: id,
            errorCode: profile?.errorCode,
            message: result.message ?? cloudSetupTerminalMessage,
          ),
        );
        return;
      case ProvisioningOutcome.needsUserAction:
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.retryableError,
            transactionId: id,
            message: cloudSetupNeedsUserActionMessage,
          ),
        );
        return;
      case ProvisioningOutcome.stale:
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.retryableError,
            transactionId: id,
            message: cloudSetupStaleMessage,
          ),
        );
        return;
      case ProvisioningOutcome.retryable:
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.retryableError,
            transactionId: id,
            authorizationUrlAvailable: canReopen,
            message: result.message ?? cloudSetupRetryableMessage,
          ),
        );
        return;
      case ProvisioningOutcome.protocolError:
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.retryableError,
            transactionId: id,
            authorizationUrlAvailable: canReopen,
            message: result.message ?? cloudSetupProtocolMessage,
          ),
        );
        return;
    }
  }

  void _startTimer() {
    _cancelTimer();
    final interval = ref.read(provisioningPollIntervalProvider);
    _timer = Timer.periodic(interval, (_) => unawaited(advance()));
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _applyState(ProvisioningUiState next) => state = AsyncData(next);

  void _update(
    ProvisioningUiState Function(ProvisioningUiState current) transform,
  ) {
    final current =
        state.value ??
        const ProvisioningUiState(phase: ProvisioningUiPhase.localOnly);
    state = AsyncData(transform(current));
  }

  /// Serializes UI actions so a double tap cannot start the same operation
  /// twice. The coordinator keeps its own durable protection.
  Future<void> _run(Future<void> Function() body) async {
    if (_operationInFlight) return;
    _operationInFlight = true;
    _update((current) => current.copyWith(busy: true));
    try {
      await body();
    } finally {
      _operationInFlight = false;
      _update((current) => current.copyWith(busy: false));
    }
  }
}

final provisioningUiProvider =
    AsyncNotifierProvider<ProvisioningUiController, ProvisioningUiState>(
      ProvisioningUiController.new,
    );
