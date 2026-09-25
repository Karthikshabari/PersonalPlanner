import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/management_callback.dart';
import '../../data/backend_project_probe.dart';
import '../../data/provisioning_client.dart';
import '../../domain/backend_connection_profile.dart';
import '../../domain/provisioning_coordinator.dart';
import '../../domain/provisioning_state.dart';
import '../../providers/deep_link_providers.dart';
import '../../providers/provisioning_providers.dart';
import '../../providers/runtime_backend_providers.dart';

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
  return 'personal-planner-$transactionId';
}

// User-facing copy. Kept here so widgets and tests share one wording.
const cloudSetupUnavailableMessage =
    'Cloud setup is unavailable in this build because no provisioning '
    'control-plane URL is configured. Personal Planner keeps working locally.';
const cloudStorageTitle = 'Cloud storage';
const cloudStorageConnectedStatus = 'Connected';
const cloudStorageUnreachableStatus = 'Connection unavailable';
const cloudStorageDisconnectedStatus = 'Disconnected';
const cloudStorageWaitingStatus = 'Waiting for Supabase authorization';
const cloudSetupLocalOnlyBody =
    'Cloud sync is optional. Set up private cloud storage that belongs to you.';
const cloudSetupAuthorizationBody =
    'Personal Planner will ask Supabase for permission to create and configure '
    'one project inside an organization you choose.';
const cloudSetupWaitingMessage =
    'Waiting for Supabase authorization. Finish the steps in your browser — '
    'setup continues automatically, even if you authorize on another device.';
const cloudSetupCreationAuthorizationWaitingMessage =
    'Finish Supabase authorization in your browser. Return here, then press '
    'Create project.';
const cloudSetupStillWaitingMessage =
    'Supabase authorization is not complete yet. Finish it in your browser; '
    'setup continues automatically.';
const cloudSetupAuthorizationConfirmedMessage =
    'Supabase authorization confirmed. Continuing setup…';
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
const cloudSetupQuotaMessage =
    'Supabase could not create another active project because your project '
    'limit was reached. Pause or remove an unused project in Supabase, then '
    'try again. Your Planner data is safe.';
const cloudSetupCreationRejectedMessage =
    'Supabase rejected project creation. Check your organization permissions '
    'and plan in Supabase before starting setup again. Your Planner data is safe.';
const cloudSetupProjectHealthFailedMessage =
    'Supabase reports that the new project failed to start. Check its status '
    'in the Supabase Dashboard. Your Planner data is safe.';
String cloudSetupTerminalMessageForCode(String? code) => switch (code) {
  'project_quota_reached' => cloudSetupQuotaMessage,
  'project_creation_rejected' => cloudSetupCreationRejectedMessage,
  'project_health_failed' => cloudSetupProjectHealthFailedMessage,
  _ => cloudSetupTerminalMessage,
};
const cloudSetupIndeterminateMessage =
    'Supabase may have created the project, but its response could not be '
    'confirmed. Check for the project before trying setup again. Your Planner '
    'data is safe.';
const cloudSetupRateLimitedMessage =
    'Supabase is limiting project creation requests. Wait a minute, then '
    'retry this same setup attempt.';
const cloudSetupReadyBody = 'Your Planner data can sync across your devices.';
const cloudSetupDisconnectedBody =
    'Cloud sync is disconnected on this device. Your Planner data stays on '
    'this device and your Supabase project was not deleted. Reconnect to the '
    'same project to use it again.';
const cloudSetupReconnectedBody =
    'Reconnected to your cloud backend. Sign in to the account that owns this '
    'project to resume synchronization. Your Planner data was not changed.';
const cloudSetupLeaveHint =
    'This can take a little while. You can leave this screen and come back '
    'later — setup continues safely.';
const cloudSetupAuthorizationReturnedMessage =
    'Supabase authorization returned. Continuing cloud setup…';
const cloudSetupReauthorizeStartedMessage =
    'Connecting to Supabase. Finish the authorization in your browser; '
    'Personal Planner continues automatically.';
const cloudSetupReauthorizeUnavailableMessage =
    'Supabase access cannot be re-authorized right now. Try again.';
const cloudSetupRevokedMessage =
    'Temporary Supabase access was cancelled. Your Supabase project, Planner '
    'account, and local data are unchanged.';
const cloudSetupRevokeNotRetainedMessage =
    'Personal Planner is not holding temporary Supabase access for this '
    'project, so there is nothing left to cancel here. If Supabase still lists '
    'Personal Planner under your authorized applications, remove it in your '
    'Supabase account settings.';
const cloudSetupRevokeFailedMessage =
    'Supabase access could not be revoked right now. Nothing changed; try '
    'again when you are online.';
const cloudSetupManagementUnavailableMessage =
    'This device can no longer manage Supabase access for this backend. Start '
    'cloud setup again to restore it.';
const cloudSetupSupabaseAccessBody =
    'Personal Planner connects to Supabase only when it needs to set up or '
    'check your cloud storage.';
const cloudSetupSupabaseAccessTitle = 'Supabase connection';
const cloudSetupSupabaseAccessPending =
    'Waiting for Supabase to confirm the new authorization.';
const cloudSetupMappingConflictMessage =
    'This device remembers a different cloud project. Your Supabase account '
    'is linked to another verified Personal Planner cloud. You can use that '
    'project; data stored for this device’s previous project will remain on '
    'this device.';
const cloudSetupLegacyRecoveryEmptyMessage =
    'The project remembered on this device could not be verified, and no '
    'other Personal Planner cloud was found for this Supabase account. '
    'Your local data is unchanged. You can set up a new cloud project.';
const cloudSetupMappedProjectDeletedMessage =
    'Supabase reported that the cloud project linked to this account is gone. '
    'Your local Planner data remains. If you choose to replace it, Personal '
    'Planner will check again before allowing a new cloud setup.';

/// Label of the *authoritative* project check: it asks Supabase directly
/// (through a short Management authorization in the browser) whether this
/// backend still exists. It is deliberately distinct from the lightweight
/// "Try again" host probe, which can only say reachable / not reachable and
/// can never prove deletion.
const cloudSetupVerifyWithSupabaseLabel = 'Verify with Supabase';
const cloudSetupCancelAccessLabel = 'Cancel Supabase access';
const cloudSetupStopUsingCloudLabel = 'Stop using cloud on this device';
const cloudSetupStopUsingCloudSupport =
    'Your local Planner data and Supabase project will remain.';
const cloudSetupReauthorizeStartingMessage = 'Starting Supabase authorization…';
const cloudSetupReauthorizedMessage =
    'Connection is working. Your Planner data can sync across your devices.';
const cloudSetupReauthorizedWithRedirectMessage =
    'Connection is working. Your Planner data can sync across your devices.';
const cloudSetupReauthorizeIncompleteMessage =
    'The Supabase authorization was not completed, so nothing was checked. '
    'You can try again.';
const cloudSetupCheckIndeterminateMessage =
    'Supabase could not be reached to confirm your cloud project, so nothing '
    'was changed. Your local Planner data is safe; try again later.';
const cloudSetupRevokeCheckingMessage = 'Checking Supabase access…';
const cloudSetupProjectUnreachableHintMessage =
    'Your cloud project couldn\'t be reached right now. That usually means you '
    'are offline; the host check cannot tell whether the project was deleted. '
    'Your local Planner data is safe. Check cloud project with Supabase if the '
    'problem persists.';
const cloudSetupProjectAccessHintMessage =
    'Supabase rejected the cloud health check. The project may still exist; '
    'your local Planner data is safe. Check cloud project with Supabase to '
    'confirm its status.';
const cloudSetupNothingToRevokeMessage =
    'Personal Planner is not holding temporary Supabase access right now, so '
    'there is nothing to cancel. Access is released as soon as each check '
    'finishes. If Supabase still lists Personal Planner under your authorized '
    'applications, remove it in your Supabase account settings.';
const cloudSetupRevokeUnconfirmedMessage =
    'Personal Planner removed the temporary access it held, but Supabase could '
    'not confirm the authorization was cancelled. Your project was not '
    'touched; if Supabase still lists Personal Planner, remove it in your '
    'Supabase account settings.';
const cloudRemoteMissingTitle = 'Project unavailable';
const cloudRemoteMissingBody =
    'The Supabase project that was connected to Personal Planner no longer '
    'exists, so cloud sync cannot continue. Nothing on this device was '
    'deleted: your local Planner data is still here. Set up new cloud storage, '
    'or keep working offline.';

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

  /// An organization is selected; creation still needs an explicit press.
  creationConfirmation,

  /// The selected organization is retained, but Management OAuth must renew.
  creationAuthorizationRequired,

  /// Verified legacy Planner projects need an explicit first binding.
  candidateSelection,

  /// The account mapping points to a project Supabase confirmed missing.
  mappedProjectDeleted,

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

  /// A verified backend is stored, but the user explicitly disconnected it on
  /// this device. It can be reconnected without provisioning anything new.
  disconnected,

  /// Supabase authoritatively reported that the project this device is
  /// configured for no longer exists. Nothing local was deleted: the user
  /// chooses between setting up new cloud storage and staying offline-only.
  remoteMissing,
}

/// User-facing progress stages inside [ProvisioningUiPhase.provisioning].
enum CloudSetupStage {
  preparingProject,
  waitingForProject,
  installingPlannerSchema,
  verifyingCloudStorage,
}

/// Presentation-only result of the bounded project-host probe.
///
/// This is not a provisioning state: the authoritative lifecycle stays
/// [ProvisioningUiPhase.ready] unless Supabase itself answers that the project
/// is gone. It only lets the card say "connection unavailable" instead of
/// claiming a healthy connection it could not confirm.
enum CloudReachability { unknown, reachable, unavailable }

/// Retry only a failed READY-project host probe, with a capped idle interval.
/// A healthy connection has no probe timer.
Duration cloudReachabilityRetryDelay(int consecutiveFailures) {
  const delays = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];
  final index = (consecutiveFailures - 1).clamp(0, delays.length - 1);
  return delays[index];
}

final cloudReachabilityRetryDelayProvider = Provider<Duration Function(int)>(
  (ref) => cloudReachabilityRetryDelay,
);

class ProvisioningUiState {
  const ProvisioningUiState({
    required this.phase,
    this.stage,
    this.transactionId,
    this.errorCode,
    this.organizations = const <ProvisioningOrganization>[],
    this.candidates = const <ProvisioningCandidate>[],
    this.selectedCandidate,
    this.selectedOrganization,
    this.readyProfile,
    this.managementCheckInFlight = false,
    this.mappingConflict = false,
    this.legacyRecovery = false,
    this.legacyRecoveryEmpty = false,
    this.busy = false,
    this.authorizationUrlAvailable = false,
    this.authorizationRetryAvailable = false,
    this.reachability = CloudReachability.unknown,
    this.authorizationConfirmed = false,
    this.message,
  });

  final ProvisioningUiPhase phase;
  final CloudSetupStage? stage;

  /// Debug-only identifiers; never credentials.
  final String? transactionId;
  final String? errorCode;

  final List<ProvisioningOrganization> organizations;
  final List<ProvisioningCandidate> candidates;
  final ProvisioningCandidate? selectedCandidate;
  final ProvisioningOrganization? selectedOrganization;
  final BackendConnectionProfile? readyProfile;

  /// True while a Supabase Management authorization this device started has not
  /// been completed yet (the browser consent is still outstanding).
  final bool managementCheckInFlight;
  final bool mappingConflict;
  final bool legacyRecovery;
  final bool legacyRecoveryEmpty;

  final bool busy;

  /// True when this session still holds the authorization URL to re-open.
  final bool authorizationUrlAvailable;

  /// The previous one-time OAuth callback was consumed without a grant.
  final bool authorizationRetryAvailable;

  /// Result of the last bounded project-host probe of a READY backend.
  final CloudReachability reachability;

  /// True for the brief transition that follows a detected Supabase
  /// authorization, so the card can acknowledge it inline.
  final bool authorizationConfirmed;

  final String? message;

  bool get isReady => phase == ProvisioningUiPhase.ready;

  bool get isDisconnected => phase == ProvisioningUiPhase.disconnected;

  bool get canStartSetup =>
      phase == ProvisioningUiPhase.localOnly ||
      phase == ProvisioningUiPhase.restartRequired ||
      phase == ProvisioningUiPhase.terminalError ||
      phase == ProvisioningUiPhase.remoteMissing;

  bool get isRemoteMissing => phase == ProvisioningUiPhase.remoteMissing;

  ProvisioningUiState copyWith({
    ProvisioningUiPhase? phase,
    String? message,
    bool clearMessage = false,
    ProvisioningOrganization? selectedOrganization,
    List<ProvisioningOrganization>? organizations,
    List<ProvisioningCandidate>? candidates,
    ProvisioningCandidate? selectedCandidate,
    bool? managementCheckInFlight,
    bool? mappingConflict,
    bool? legacyRecovery,
    bool? legacyRecoveryEmpty,
    bool? busy,
    bool? authorizationUrlAvailable,
    bool? authorizationRetryAvailable,
    CloudReachability? reachability,
    bool? authorizationConfirmed,
  }) => ProvisioningUiState(
    phase: phase ?? this.phase,
    stage: stage,
    transactionId: transactionId,
    errorCode: errorCode,
    organizations: organizations ?? this.organizations,
    candidates: candidates ?? this.candidates,
    selectedCandidate: selectedCandidate ?? this.selectedCandidate,
    selectedOrganization: selectedOrganization ?? this.selectedOrganization,
    readyProfile: readyProfile,
    managementCheckInFlight:
        managementCheckInFlight ?? this.managementCheckInFlight,
    mappingConflict: mappingConflict ?? this.mappingConflict,
    legacyRecovery: legacyRecovery ?? this.legacyRecovery,
    legacyRecoveryEmpty: legacyRecoveryEmpty ?? this.legacyRecoveryEmpty,
    busy: busy ?? this.busy,
    authorizationUrlAvailable:
        authorizationUrlAvailable ?? this.authorizationUrlAvailable,
    authorizationRetryAvailable:
        authorizationRetryAvailable ?? this.authorizationRetryAvailable,
    reachability: reachability ?? this.reachability,
    authorizationConfirmed:
        authorizationConfirmed ?? this.authorizationConfirmed,
    message: clearMessage ? null : (message ?? this.message),
  );
}

class ProvisioningUiController extends AsyncNotifier<ProvisioningUiState> {
  Timer? _timer;
  Timer? _reachabilityRetryTimer;
  int _reachabilityFailures = 0;
  bool _operationInFlight = false;
  bool _creationReconcileAttempted = false;
  bool _watching = false;
  bool _appActive = true;
  Uri? _authorizationUrl;
  StreamSubscription<String>? _linkSubscription;

  @override
  Future<ProvisioningUiState> build() async {
    ref.onDispose(() {
      _cancelTimer();
      _cancelReachabilityRetry();
      unawaited(_linkSubscription?.cancel());
      _linkSubscription = null;
    });
    // The app-lifetime deep-link source is observed here as well, so a browser
    // hand-off resumes this screen's provisioning work without the user having
    // to switch back and press anything.
    _linkSubscription = ref.read(appLinkSourceProvider).links.listen((link) {
      if (ManagementCallback.matches(link)) {
        unawaited(_onManagementAuthorizationReturned(link));
      }
    });
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

  /// Current UI state, or null before the first build completes.
  ///
  /// Exposed so the presentation layer can decide whether a lifecycle resume is
  /// worth resuming without reading the protected notifier state directly.
  ProvisioningUiState? get current => state.value;

  /// Called when the setup card becomes visible.
  ///
  /// Loads durable local state first (no network), then resumes an in-flight
  /// attempt and starts conservative refresh while the screen is open.
  Future<void> startWatching() async {
    final api = _api;
    if (api == null) return;
    _watching = true;
    _applyState(await _loadLocal(api));
    final phase = state.value?.phase;
    if (phase == ProvisioningUiPhase.ready) {
      // A Management authorization may still be out in the browser (for example
      // when the app was restarted), so restore the in-flight marker before the
      // probe below.
      final pending = await api.hasPendingManagementAuthorization();
      if (pending) {
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: true,
            message: cloudSetupReauthorizeStartedMessage,
          ),
        );
      }
      await verifyProjectHost();
      return;
    }
    if (phase == ProvisioningUiPhase.creationConfirmation) {
      // The app may have closed after the Worker accepted Create but before
      // Flutter received its response. Read the transaction before showing a
      // fresh Create action; this GET can never submit another project.
      _applyState(
        ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.preparingProject,
          transactionId: state.value?.transactionId,
        ),
      );
      try {
        final checked = await api.refresh();
        _applyResult(checked);
      } on ProvisioningApiException {
        // The durable Worker guard remains authoritative if status is offline.
      }
      return;
    }
    if (phase == ProvisioningUiPhase.waitingForAuthorization ||
        phase == ProvisioningUiPhase.provisioning ||
        phase == ProvisioningUiPhase.retryableError) {
      await advance();
    }
  }

  /// Called when the setup card is removed; background refresh never outlives
  /// the screen.
  void stopWatching() {
    _watching = false;
    _cancelTimer();
    _cancelReachabilityRetry();
  }

  /// Suspend host retries while the card's app is backgrounded. Resume events
  /// perform an immediate probe, then restore backoff only if it still fails.
  void setReachabilityChecksActive(bool active) {
    _appActive = active;
    if (!active) {
      _cancelReachabilityRetry();
    } else {
      _syncReachabilityRetry();
    }
  }

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

  /// Starts a fresh Supabase Management authorization (browser consent).
  ///
  /// The browser hands control back through
  /// [_onManagementAuthorizationReturned], which completes the check.
  ///
  /// The Worker issues a single-use consent URL; the callback page deep-links
  /// back into the app, and [_onManagementAuthorizationReturned] completes the
  /// check. This works for a READY backend even though the provisioning
  /// capability was destroyed when setup finished.
  Future<void> reauthorizeSupabaseAccess() => _run(() async {
    final api = _api;
    if (api == null) return;
    _update(
      (current) => current.copyWith(
        managementCheckInFlight: true,
        message: cloudSetupReauthorizeStartingMessage,
      ),
    );
    final result = await api.startManagementCheck();
    final url = result.authorizationUrl;
    if (result.outcome != ManagementStartOutcome.authorizationReady ||
        url == null) {
      _update(
        (current) => current.copyWith(
          managementCheckInFlight: false,
          message: result.message ?? cloudSetupReauthorizeUnavailableMessage,
        ),
      );
      return;
    }
    final opened = await ref.read(browserLauncherProvider).open(url);
    _update(
      (current) => current.copyWith(
        managementCheckInFlight: opened,
        message: opened
            ? cloudSetupReauthorizeStartedMessage
            : cloudSetupBrowserLaunchFailedMessage,
      ),
    );
  });

  /// Revokes the Supabase Management authorization this device currently holds.
  ///
  /// The credential exists only while a Management authorization is in flight,
  /// so this is a real revocation when there is something to revoke and an
  /// explicit "nothing is held" answer otherwise — never a fake success. The
  /// Supabase project, the Planner account session, and local Planner data are
  /// never touched.
  Future<void> disconnectSupabaseAccess() => _run(() async {
    final api = _api;
    if (api == null) return;
    _update(
      (current) => current.copyWith(
        managementCheckInFlight: false,
        message: cloudSetupRevokeCheckingMessage,
      ),
    );
    final result = await api.revokeManagementAccess();
    switch (result.outcome) {
      case ManagementRevokeOutcome.revoked:
        _update(
          (current) => current.copyWith(message: cloudSetupRevokedMessage),
        );
        return;
      case ManagementRevokeOutcome.nothingHeld:
        _update(
          (current) =>
              current.copyWith(message: cloudSetupNothingToRevokeMessage),
        );
        return;
      case ManagementRevokeOutcome.unconfirmed:
        _update(
          (current) =>
              current.copyWith(message: cloudSetupRevokeUnconfirmedMessage),
        );
        return;
      case ManagementRevokeOutcome.retryable:
      case ManagementRevokeOutcome.protocolError:
        _update(
          (current) => current.copyWith(
            message: result.message ?? cloudSetupRevokeFailedMessage,
          ),
        );
        return;
    }
  });

  /// Completes an in-flight Management authorization with Supabase's answer.
  ///
  /// Only an authoritative 404 marks the backend remote-missing; a network
  /// failure leaves READY untouched and reports a retryable message.
  Future<void> completeManagementCheck() => _run(() async {
    final api = _api;
    if (api == null) return;
    final result = await api.completeManagementCheck();
    switch (result.outcome) {
      case ManagementCheckOutcome.exists:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            reachability: CloudReachability.reachable,
            message: result.readyProfileUpdated
                ? cloudSetupReauthorizedWithRedirectMessage
                : cloudSetupReauthorizedMessage,
          ),
        );
        if (result.readyProfileUpdated) {
          await ref.read(runtimeBackendReloaderProvider)?.reload();
        }
        return;
      case ManagementCheckOutcome.missing:
        _showRemoteMissing(status: result.status);
        await ref.read(runtimeBackendReloaderProvider)?.reload();
        return;
      case ManagementCheckOutcome.needsAuthorization:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            message: cloudSetupReauthorizeIncompleteMessage,
          ),
        );
        return;
      case ManagementCheckOutcome.indeterminate:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            message: cloudSetupCheckIndeterminateMessage,
          ),
        );
        return;
      case ManagementCheckOutcome.mappingConflict:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            mappingConflict: true,
            message: cloudSetupMappingConflictMessage,
          ),
        );
        return;
      case ManagementCheckOutcome.candidateRecovery:
        if (result.candidates.isEmpty) {
          _update(
            (current) => current.copyWith(
              managementCheckInFlight: false,
              legacyRecoveryEmpty: true,
              message: cloudSetupLegacyRecoveryEmptyMessage,
            ),
          );
        } else {
          _applyState(
            ProvisioningUiState(
              phase: ProvisioningUiPhase.candidateSelection,
              candidates: result.candidates,
              selectedCandidate: result.candidates.length == 1
                  ? result.candidates.single
                  : null,
              legacyRecovery: true,
            ),
          );
        }
        return;
      case ManagementCheckOutcome.authorizationPending:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: true,
            message: result.message ?? cloudSetupReauthorizeStartedMessage,
          ),
        );
        return;
      case ManagementCheckOutcome.retryable:
      case ManagementCheckOutcome.protocolError:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            message: result.message ?? cloudSetupCheckIndeterminateMessage,
          ),
        );
        return;
      case ManagementCheckOutcome.notApplicable:
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            message: cloudSetupNothingToRevokeMessage,
          ),
        );
        return;
    }
  });

  Future<void> useMappedProject() => _run(() async {
    final api = _api;
    if (api == null || !(state.value?.mappingConflict ?? false)) return;
    final result = await api.recoverMappedProject();
    if (result.outcome == ProvisioningOutcome.ready) {
      _applyResult(result);
    } else {
      _update(
        (current) => current.copyWith(
          message: result.message ?? cloudSetupRetryableMessage,
        ),
      );
    }
  });

  Future<void> replaceDeletedProject() => _run(() async {
    final api = _api;
    if (api == null) return;
    final result = await api.replaceDeletedProject();
    if (result.outcome == ProvisioningOutcome.inProgress &&
        result.resolutionComplete) {
      await _continueAfterAuthorization(api);
    } else {
      _applyResult(result);
    }
  });

  /// Handles the browser handing a Supabase authorization back to the app.
  ///
  /// A Management authorization completes the project check the user started;
  /// a provisioning authorization keeps its original meaning and resumes
  /// provisioning.
  Future<void> _onManagementAuthorizationReturned(String link) async {
    final phase = state.value?.phase;
    if (phase == null) return;
    final callbackResult = ManagementCallback.resultOf(link);
    if (callbackResult == ManagementCallbackResult.cancelled ||
        callbackResult == ManagementCallbackResult.failed ||
        callbackResult == ManagementCallbackResult.invalid) {
      if (state.value?.managementCheckInFlight ?? false) {
        await _api?.abandonManagementCheck();
        _update(
          (current) => current.copyWith(
            managementCheckInFlight: false,
            message: cloudSetupReauthorizeIncompleteMessage,
          ),
        );
      } else if (phase == ProvisioningUiPhase.waitingForAuthorization) {
        _update(
          (current) =>
              current.copyWith(message: cloudSetupReauthorizeIncompleteMessage),
        );
        // The Worker records a claimed callback failure on this transaction.
        // Read it now so the user sees Retry authorization immediately after
        // the browser returns, without waiting for the next polling interval.
        await advance();
      }
      return;
    }
    final inFlight = state.value?.managementCheckInFlight ?? false;
    if (inFlight || phase == ProvisioningUiPhase.ready) {
      await completeManagementCheck();
      return;
    }
    if (phase == ProvisioningUiPhase.waitingForAuthorization) {
      _update(
        (current) =>
            current.copyWith(message: cloudSetupAuthorizationReturnedMessage),
      );
    }
    await advance();
  }

  /// Bounded probe of the user's own project host, run while this card is open.
  ///
  /// Host reachability cannot establish whether the project was deleted.
  /// Only the exact-project Management check can make that determination.
  Future<void> verifyProjectHost() {
    _cancelReachabilityRetry();
    return _probeProjectHost(markBusy: true);
  }

  Future<void> _probeProjectHost({required bool markBusy}) => _run(() async {
    final api = _api;
    final profile = state.value?.readyProfile;
    final projectUrl = profile?.projectUrl;
    final publishableKey = profile?.publishableKey;
    if (api == null || projectUrl == null || publishableKey == null) return;
    BackendProjectProbeResult probed;
    try {
      probed = await ref
          .read(backendProjectProbeProvider)
          .probe(Uri.parse(projectUrl), publishableKey: publishableKey);
    } on Exception {
      probed = BackendProjectProbeResult.indeterminate;
    }
    if (probed == BackendProjectProbeResult.exists) {
      _reachabilityFailures = 0;
      _update(
        (current) => current.copyWith(
          reachability: CloudReachability.reachable,
          clearMessage: true,
        ),
      );
      return;
    }
    if (probed == BackendProjectProbeResult.indeterminate ||
        probed == BackendProjectProbeResult.missing ||
        probed == BackendProjectProbeResult.accessDenied) {
      _reachabilityFailures += 1;
      // A DNS failure, timeout, or outage proves nothing, so the backend stays
      // READY. The card reports the connection as unavailable without ever
      // claiming the project was deleted, and keeps an authoritative check
      // reachable for the user.
      _update(
        (current) => current.copyWith(
          reachability: CloudReachability.unavailable,
          message: probed == BackendProjectProbeResult.accessDenied
              ? cloudSetupProjectAccessHintMessage
              : cloudSetupProjectUnreachableHintMessage,
        ),
      );
      return;
    }
  }, markBusy: markBusy);

  /// Reconciles an earlier lightweight-probe failure with stronger evidence
  /// from the normal Planner data path.
  ///
  /// A successful sync round trip proves that the configured project is
  /// reachable. It says nothing about Management authorization and therefore
  /// must not start or complete a provisioning/OAuth operation.
  void noteRuntimeReachable() {
    final current = state.value;
    if (current?.phase != ProvisioningUiPhase.ready ||
        current?.reachability != CloudReachability.unavailable) {
      return;
    }
    _reachabilityFailures = 0;
    _update(
      (value) => value.copyWith(
        reachability: CloudReachability.reachable,
        clearMessage: true,
      ),
    );
  }

  /// Selects an organization locally; nothing is provisioned until Continue.
  void selectOrganization(ProvisioningOrganization organization) {
    _update((current) => current.copyWith(selectedOrganization: organization));
  }

  void selectCandidate(ProvisioningCandidate candidate) {
    _update((current) => current.copyWith(selectedCandidate: candidate));
  }

  Future<void> useSelectedCandidate() => _run(() async {
    final api = _api;
    final candidate = state.value?.selectedCandidate;
    if (api == null || candidate == null) return;
    final legacyRecovery = state.value?.legacyRecovery ?? false;
    final result = legacyRecovery
        ? await api.recoverCandidateProject(candidate.projectRef)
        : await api.adoptProject(candidate.projectRef);
    if (legacyRecovery && result.outcome != ProvisioningOutcome.ready) {
      _update(
        (current) => current.copyWith(
          message: result.message ?? cloudSetupRetryableMessage,
        ),
      );
      return;
    }
    _applyResult(result);
  });

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

  /// The only UI action that starts a new upstream project creation.
  Future<void> createProject() => _run(() async {
    final api = _api;
    if (api == null ||
        state.value?.phase != ProvisioningUiPhase.creationConfirmation) {
      return;
    }
    final attempt = await api.loadAttempt();
    if (attempt?.state != ProvisioningState.organizationSelected) return;
    _applyResult(await api.createOrContinueProject());
  });

  /// Retries the next step, issuing fresh PKCE state on the same transaction
  /// when the previous OAuth callback failed after consuming its state.
  Future<void> retry() {
    if (state.value?.phase ==
        ProvisioningUiPhase.creationAuthorizationRequired) {
      return _run(() async {
        final api = _api;
        if (api == null) return;
        final result = await api.retryAuthorization();
        final url = result.authorizationUrl;
        if (result.outcome != ProvisioningOutcome.inProgress || url == null) {
          _applyResult(result);
          return;
        }
        _authorizationUrl = url;
        final opened = await ref.read(browserLauncherProvider).open(url);
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.waitingForAuthorization,
            transactionId: result.profile?.provisioningTransactionId,
            authorizationUrlAvailable: true,
            message: opened
                ? cloudSetupCreationAuthorizationWaitingMessage
                : cloudSetupBrowserLaunchFailedMessage,
          ),
        );
      });
    }
    if (state.value?.phase == ProvisioningUiPhase.retryableError &&
        !(state.value?.authorizationRetryAvailable ?? false)) {
      return _run(() async {
        final api = _api;
        if (api == null) return;
        final attempt = await api.loadAttempt();
        if (attempt?.state == ProvisioningState.projectReconciliationRequired ||
            attempt?.state == ProvisioningState.projectRetryAuthorized) {
          _applyResult(await api.createOrContinueProject());
        } else {
          await _advanceStep();
        }
      });
    }
    if (!(state.value?.authorizationRetryAvailable ?? false)) return advance();
    return _run(() async {
      final api = _api;
      if (api == null) return;
      final result = await api.retryAuthorization();
      final url = result.authorizationUrl;
      if (result.outcome != ProvisioningOutcome.inProgress || url == null) {
        _applyResult(result);
        return;
      }
      _authorizationUrl = url;
      final opened = await ref.read(browserLauncherProvider).open(url);
      _applyState(
        ProvisioningUiState(
          phase: ProvisioningUiPhase.waitingForAuthorization,
          transactionId: result.profile?.provisioningTransactionId,
          authorizationUrlAvailable: true,
          message: opened
              ? cloudSetupWaitingMessage
              : cloudSetupBrowserLaunchFailedMessage,
        ),
      );
    });
  }

  /// "Start again": the C2 coordinator supersedes the previous attempt.
  Future<void> startAgain() => startSetup();

  /// Reconnects the remembered user-owned backend of this device.
  ///
  /// Only the durable "disconnected" flag changes. The stored project ref, URL
  /// and publishable key are reused, so nothing is provisioned and no Planner
  /// data can be uploaded to a different project. The cloud-setup card reloads
  /// the runtime Auth client when this reaches [ProvisioningUiPhase.ready].
  Future<void> reconnect() => _run(() async {
    final api = _api;
    if (api == null) return;
    final attempt = await api.loadAttempt();
    final profile = attempt?.profile;
    final projectRef = profile?.projectRef;
    if (profile == null || projectRef == null) {
      _update(
        (current) => current.copyWith(
          phase: ProvisioningUiPhase.restartRequired,
          message: cloudSetupMissingCapabilityMessage,
        ),
      );
      return;
    }
    final result = await ref
        .read(cloudLifecycleServiceProvider)
        .reconnect(projectRef: projectRef);
    if (!result.succeeded) {
      _update(
        (current) => current.copyWith(
          message: result.message ?? cloudSetupRetryableMessage,
        ),
      );
      return;
    }
    _applyState(
      ProvisioningUiState(
        phase: ProvisioningUiPhase.ready,
        transactionId: profile.provisioningTransactionId,
        readyProfile: profile,
        message: cloudSetupReconnectedBody,
      ),
    );
  });

  /// Advances setup by exactly one authoritative step.
  Future<void> advance() => _run(_advanceStep);

  /// The authoritative "next step" of the durable attempt.
  ///
  /// Shared by the manual Refresh status action and the automatic background
  /// refresh so both drive exactly the same state machine.
  Future<void> _advanceStep() async {
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
        final refreshed = await api.refresh();
        _applyResult(refreshed);
        if (refreshed.profile?.state ==
                ProvisioningState.projectReconciliationRequired &&
            !_creationReconcileAttempted) {
          _creationReconcileAttempted = true;
          _applyResult(await api.createOrContinueProject());
        }
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
  }

  Future<void> _continueAfterAuthorization(ProvisioningApi api) async {
    final refreshed = await api.refresh();
    if (refreshed.outcome != ProvisioningOutcome.inProgress) {
      _applyResult(refreshed);
      return;
    }
    // A lost organization-selection response may leave the local profile one
    // step behind the Worker. Never re-enter discovery after selection.
    if (refreshed.profile?.state != ProvisioningState.authorizationPending) {
      _applyResult(refreshed);
      return;
    }
    final resolution = await api.resolveProject();
    if (resolution.outcome == ProvisioningOutcome.ready) {
      _applyResult(resolution);
      return;
    }
    if (resolution.outcome == ProvisioningOutcome.restartRequired) {
      _update(
        (current) => current.copyWith(
          phase: ProvisioningUiPhase.waitingForAuthorization,
          authorizationUrlAvailable: _authorizationUrl != null,
          message: cloudSetupStillWaitingMessage,
        ),
      );
      return;
    }
    if (resolution.outcome != ProvisioningOutcome.inProgress ||
        !resolution.resolutionComplete) {
      _applyResult(resolution);
      return;
    }
    if (resolution.candidates.isNotEmpty) {
      _applyState(
        ProvisioningUiState(
          phase: ProvisioningUiPhase.candidateSelection,
          transactionId:
              refreshed.profile?.provisioningTransactionId ??
              state.value?.transactionId,
          candidates: resolution.candidates,
          selectedCandidate: resolution.candidates.length == 1
              ? resolution.candidates.single
              : null,
          authorizationConfirmed: true,
        ),
      );
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
        // The acknowledgement is inline and transient: it belongs to the step
        // that follows the authorization and disappears with the next stage.
        authorizationConfirmed: true,
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
      if (attempt.profile.remoteMissing) {
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.remoteMissing,
          transactionId: attempt.transactionId,
          readyProfile: attempt.profile,
        );
      }
      if (attempt.profile.connectionDisabled) {
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.disconnected,
          transactionId: attempt.transactionId,
          readyProfile: attempt.profile,
          message: cloudSetupDisconnectedBody,
        );
      }
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
        message: cloudSetupTerminalMessageForCode(attempt.profile.errorCode),
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
    bool creationAuthorizationPending = false,
    bool creationAuthorizationRequired = false,
  }) {
    switch (workerState) {
      case ProvisioningState.organizationSelected:
        if (creationAuthorizationPending) {
          return ProvisioningUiState(
            phase: ProvisioningUiPhase.waitingForAuthorization,
            transactionId: transactionId,
            message: cloudSetupCreationAuthorizationWaitingMessage,
          );
        }
        if (creationAuthorizationRequired) {
          return ProvisioningUiState(
            phase: ProvisioningUiPhase.creationAuthorizationRequired,
            transactionId: transactionId,
            message:
                'Supabase authorization expired before project creation. '
                'Reauthorize this setup, then press Create project again.',
          );
        }
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.creationConfirmation,
          transactionId: transactionId,
        );
      case ProvisioningState.projectReconciliationRequired:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.retryableError,
          transactionId: transactionId,
          message: cloudSetupIndeterminateMessage,
        );
      case ProvisioningState.projectRetryAuthorized:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.retryableError,
          transactionId: transactionId,
          message: cloudSetupRateLimitedMessage,
        );
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
          stage: CloudSetupStage.installingPlannerSchema,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
        );
      case ProvisioningState.verifying:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.verifyingCloudStorage,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
        );
      case ProvisioningState.projectWaiting:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.waitingForProject,
          transactionId: transactionId,
          authorizationUrlAvailable: _authorizationUrl != null,
        );
      default:
        return ProvisioningUiState(
          phase: ProvisioningUiPhase.provisioning,
          stage: CloudSetupStage.preparingProject,
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
        if (result.resolutionComplete && result.candidates.isNotEmpty) {
          _applyState(
            ProvisioningUiState(
              phase: ProvisioningUiPhase.candidateSelection,
              transactionId: id,
              candidates: result.candidates,
              selectedCandidate: result.candidates.length == 1
                  ? result.candidates.single
                  : null,
              authorizationConfirmed: true,
            ),
          );
          return;
        }
        final next = _provisioningState(
          transactionId: id,
          workerState: profile?.state,
          creationAuthorizationPending:
              result.snapshot?.creationAuthorizationPending ?? false,
          creationAuthorizationRequired:
              result.snapshot?.creationAuthorizationRequired ?? false,
        );
        _applyState(
          ProvisioningUiState(
            phase: next.phase,
            stage: next.stage,
            transactionId: next.transactionId,
            authorizationUrlAvailable: canReopen,
            message: next.message,
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
            message:
                result.message ??
                cloudSetupTerminalMessageForCode(profile?.errorCode),
          ),
        );
        return;
      case ProvisioningOutcome.projectDeleted:
        _cancelTimer();
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.mappedProjectDeleted,
            transactionId: id,
            message: cloudSetupMappedProjectDeletedMessage,
          ),
        );
        return;
      case ProvisioningOutcome.needsUserAction:
        if (profile?.state == ProvisioningState.organizationSelected) {
          _cancelTimer();
          _applyState(
            ProvisioningUiState(
              phase: ProvisioningUiPhase.creationAuthorizationRequired,
              transactionId: id,
              message: result.message,
            ),
          );
          return;
        }
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
        final authorizationRetry = result.snapshot?.authorizationFailed == true;
        _applyState(
          ProvisioningUiState(
            phase: ProvisioningUiPhase.retryableError,
            transactionId: id,
            authorizationUrlAvailable: authorizationRetry ? false : canReopen,
            authorizationRetryAvailable: authorizationRetry,
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

  /// Switches the card to the authoritative deleted-project recovery state.
  void _showRemoteMissing({required String? status}) {
    _cancelTimer();
    _applyState(
      ProvisioningUiState(
        phase: ProvisioningUiPhase.remoteMissing,
        transactionId: state.value?.transactionId,
        readyProfile: state.value?.readyProfile,
        errorCode: status,
      ),
    );
  }

  void _startTimer() {
    _cancelTimer();
    final interval = ref.read(provisioningPollIntervalProvider);
    _timer = Timer.periodic(interval, (_) => unawaited(_backgroundRefresh()));
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _cancelReachabilityRetry() {
    _reachabilityRetryTimer?.cancel();
    _reachabilityRetryTimer = null;
  }

  void _syncReachabilityRetry() {
    final current = state.value;
    if (!_watching ||
        !_appActive ||
        current?.phase != ProvisioningUiPhase.ready ||
        current?.reachability != CloudReachability.unavailable) {
      _cancelReachabilityRetry();
      _reachabilityFailures = 0;
      return;
    }
    if (_operationInFlight || _reachabilityRetryTimer != null) return;
    final delay = ref.read(cloudReachabilityRetryDelayProvider)(
      _reachabilityFailures,
    );
    _reachabilityRetryTimer = Timer(delay, () {
      _reachabilityRetryTimer = null;
      if (!_watching ||
          !_appActive ||
          state.value?.phase != ProvisioningUiPhase.ready ||
          state.value?.reachability != CloudReachability.unavailable ||
          _operationInFlight) {
        return;
      }
      unawaited(_retryProjectHost());
    });
  }

  Future<void> _retryProjectHost() async {
    try {
      await _probeProjectHost(markBusy: false);
    } on Exception {
      // The READY profile remains authoritative. A failed retry is still
      // unavailable and the next bounded retry is scheduled by _run.
    }
  }

  /// True while the screen is open *and* the durable state is still waiting on
  /// something the server does on its own.
  ///
  /// The refresh loop is derived from the phase, not from the action that
  /// entered it: every path into a waiting phase (Continue, Retry, Resume,
  /// reopening the screen, a lifecycle resume) gets the same automatic
  /// behaviour, and every terminal phase stops it.
  bool get _shouldRefreshInBackground {
    if (!_watching) return false;
    final phase = state.value?.phase;
    return phase == ProvisioningUiPhase.waitingForAuthorization ||
        phase == ProvisioningUiPhase.provisioning ||
        phase == ProvisioningUiPhase.retryableError;
  }

  void _syncRefreshTimer() {
    if (!_shouldRefreshInBackground) {
      _cancelTimer();
      return;
    }
    // Never restart an already-running loop: a poll changes `busy` twice, and
    // re-arming on every state change would reset the period forever.
    if (_timer != null) return;
    _startTimer();
  }

  /// One automatic progress check.
  ///
  /// Deliberately quiet: it never marks the UI busy (that flag means "a user
  /// action is running"), never surfaces an error, and cannot overlap another
  /// operation because the controller serializes runs. A transient failure
  /// simply waits for the next tick with the durable state untouched.
  Future<void> _backgroundRefresh() async {
    if (_operationInFlight || !_shouldRefreshInBackground) return;
    try {
      await _run(_advanceStep, markBusy: false);
    } catch (_) {
      // Background reconciliation never interrupts the user; the next tick
      // retries and the durable attempt stays authoritative.
    }
  }

  void _applyState(ProvisioningUiState next) {
    state = AsyncData(next);
    _syncRefreshTimer();
    _syncReachabilityRetry();
  }

  void _update(
    ProvisioningUiState Function(ProvisioningUiState current) transform,
  ) {
    final current =
        state.value ??
        const ProvisioningUiState(phase: ProvisioningUiPhase.localOnly);
    state = AsyncData(transform(current));
    _syncRefreshTimer();
    _syncReachabilityRetry();
  }

  /// Serializes UI actions so a double tap cannot start the same operation
  /// twice. The coordinator keeps its own durable protection.
  Future<void> _run(
    Future<void> Function() body, {
    bool markBusy = true,
  }) async {
    if (_operationInFlight) return;
    final enteredFrom = state.value?.phase;
    _operationInFlight = true;
    if (markBusy) _update((current) => current.copyWith(busy: true));
    try {
      await body();
    } finally {
      _operationInFlight = false;
      if (markBusy && ref.mounted) {
        _update((current) => current.copyWith(busy: false));
      }
      if (enteredFrom != ProvisioningUiPhase.ready &&
          ref.mounted &&
          state.value?.phase == ProvisioningUiPhase.ready) {
        // READY is durable at this point. Install its Auth/runtime providers
        // before checking the host, so the screen and sync use the same backend
        // without a second Management verification or an unawaited UI race.
        await ref.read(runtimeBackendReloaderProvider)?.reload();
        if (ref.mounted) await verifyProjectHost();
      }
      if (ref.mounted) _syncReachabilityRetry();
    }
  }
}

final provisioningUiProvider =
    AsyncNotifierProvider<ProvisioningUiController, ProvisioningUiState>(
      ProvisioningUiController.new,
    );
