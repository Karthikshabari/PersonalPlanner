import 'dart:async';

import '../../../core/utils/uuid.dart';
import '../data/connection_profile_store.dart';
import '../data/provisioning_capability_store.dart';
import '../data/provisioning_client.dart';
import 'backend_connection_profile.dart';
import 'provisioning_state.dart';

/// Outcome of one provisioning coordinator action.
enum ProvisioningOutcome {
  /// No provisioning attempt exists; the Planner stays local-only.
  localOnly,

  /// The authoritative Worker state can still progress.
  inProgress,

  /// The user must act before provisioning can continue.
  needsUserAction,

  /// A transient problem; the last authoritative state is unchanged.
  retryable,

  /// The attempt cannot continue; a new provisioning attempt is required.
  restartRequired,

  /// The Worker reported an unrecoverable failure.
  terminal,

  /// The backend is verified and the client-safe profile was persisted.
  ready,

  /// Durable state says an attempt is active but its capability is missing.
  capabilityMissing,

  /// The control plane answered with something this client cannot trust.
  protocolError,

  /// A newer attempt replaced this one; the outdated result was discarded.
  stale,
}

/// Typed result of a coordinator action.
///
/// Expected conditions (offline, expired, missing capability, …) are reported
/// here rather than thrown, so a future UI can render them directly.
class ProvisioningResult {
  const ProvisioningResult({
    required this.outcome,
    this.profile,
    this.snapshot,
    this.organizations = const <ProvisioningOrganization>[],
    this.message,
    this.authorizationUrl,
  });

  final ProvisioningOutcome outcome;
  final BackendConnectionProfile? profile;
  final ProvisioningSnapshot? snapshot;
  final List<ProvisioningOrganization> organizations;
  final String? message;
  final Uri? authorizationUrl;

  bool get isReady => outcome == ProvisioningOutcome.ready;

  @override
  String toString() =>
      'ProvisioningResult(${outcome.name}'
      '${profile == null ? '' : ', state: ${profile!.state.wireName}'})';
}

/// Durable, non-secret view of one provisioning attempt.
class ProvisioningAttempt {
  const ProvisioningAttempt({
    required this.profile,
    required this.transactionId,
    required this.hasCapability,
  });

  final BackendConnectionProfile profile;
  final String transactionId;
  final bool hasCapability;

  ProvisioningState get state => profile.state;

  bool get isActive => profile.state.isInProgress;

  bool get isResumable => isActive && hasCapability;
}

/// Orchestrates the frozen production provisioning API against durable local
/// state.
///
/// The coordinator owns no UI and no Supabase runtime client. It exposes small
/// explicit actions so a future screen can drive them, retry them, and explain
/// them. The authoritative Worker state lives in the Phase B
/// [BackendConnectionProfile]; the provisioning capability lives only in
/// secure storage; nothing else is a source of truth.
class ProvisioningCoordinator {
  ProvisioningCoordinator({
    required this.profileStore,
    required this.capabilityStore,
    required this.client,
    String Function()? profileIdFactory,
    DateTime Function()? clock,
  }) : _newProfileId = profileIdFactory ?? _defaultProfileId,
       _clock = clock ?? DateTime.now;

  static final RegExp _organizationSlugPattern = RegExp(r'^[a-z0-9-]{3,80}$');
  static final RegExp _projectNamePattern = RegExp(
    r'^personal-planner-[a-z0-9-]{3,55}$',
  );

  /// Durable, non-secret backend profile storage.
  final ConnectionProfileStore profileStore;

  /// Secure storage for the short-lived provisioning capability.
  final ProvisioningCapabilityStore capabilityStore;

  /// Typed client for the frozen provisioning API.
  final ProvisioningClient client;
  final String Function() _newProfileId;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  /// Deterministic replay key for organization selection.
  ///
  /// The Worker requires a stable key of at least 32 characters and stores it
  /// with the selection, so deriving it from the durable transaction id keeps
  /// retries of the same attempt identical without persisting another field.
  static String idempotencyKeyFor(String transactionId) =>
      'personal-planner-selection-$transactionId';

  /// Reads the durable attempt without touching the network.
  Future<ProvisioningAttempt?> loadAttempt() => _serialized(() async {
    final profile = await _profileOrNull();
    final transactionId = profile?.provisioningTransactionId;
    if (profile == null || transactionId == null) return null;
    return ProvisioningAttempt(
      profile: profile,
      transactionId: transactionId,
      hasCapability: await _hasCapability(transactionId),
    );
  });

  /// Creates a new provisioning transaction and a new local attempt.
  Future<ProvisioningResult> startAttempt() => _serialized(() async {
    BackendConnectionProfile? existing;
    try {
      existing = await profileStore.read();
    } on ConnectionProfileStoreException catch (error) {
      if (!_isReplaceable(error.failure)) {
        return _result(
          ProvisioningOutcome.retryable,
          message:
              'The stored backend profile could not be read, so no '
              'provisioning attempt was started.',
        );
      }
      // A corrupt/unsupported document may only be replaced by an explicit
      // fresh attempt, which is exactly what this action is.
      existing = null;
    }

    final ProvisioningGrant grant;
    try {
      grant = await client.createTransaction();
    } on ProvisioningApiException catch (error) {
      return _failure(error, profile: existing);
    }

    try {
      await capabilityStore.write(
        transactionId: grant.transactionId,
        capability: grant.capability,
      );
    } on ProvisioningCapabilityStoreException {
      // Without secure storage the transaction cannot be resumed, so nothing
      // durable is written and the transaction is left to expire server-side.
      return _result(
        ProvisioningOutcome.retryable,
        profile: existing,
        message:
            'Secure storage is unavailable, so the provisioning attempt was '
            'not started.',
      );
    }

    final now = _clock().toUtc();
    final BackendConnectionProfile profile;
    try {
      profile = BackendConnectionProfile(
        profileId: _newProfileId(),
        generation: (existing?.generation ?? 0) + 1,
        state: ProvisioningState.authorizationPending,
        createdAt: now,
        updatedAt: now,
        provisioningTransactionId: grant.transactionId,
      );
    } on BackendProfileValidationException {
      await _discardCapability(grant.transactionId);
      return _result(
        ProvisioningOutcome.protocolError,
        profile: existing,
        message: 'The new provisioning attempt could not be represented.',
      );
    }

    try {
      await profileStore.save(
        profile,
        expectedGeneration: existing?.generation,
      );
    } on StaleConnectionProfileException {
      await _discardCapability(grant.transactionId);
      return _result(
        ProvisioningOutcome.stale,
        profile: existing,
        message: 'Another provisioning attempt replaced this one.',
      );
    } on ConnectionProfileStoreException {
      await _discardCapability(grant.transactionId);
      return _result(
        ProvisioningOutcome.retryable,
        profile: existing,
        message: 'The new provisioning attempt could not be saved.',
      );
    }

    final superseded = existing?.provisioningTransactionId;
    if (superseded != null && superseded != grant.transactionId) {
      await _discardCapability(superseded);
    }
    return _result(
      ProvisioningOutcome.inProgress,
      profile: profile,
      authorizationUrl: grant.authorizationUrl,
    );
  });

  /// Re-reads the authoritative Worker state and persists it durably.
  Future<ProvisioningResult> refresh() => _serialized(
    () => _withAttempt((attempt, capability) async {
      final snapshot = await client.snapshot(
        attempt.transactionId,
        capability: capability,
      );
      return _applySnapshot(attempt, snapshot);
    }),
  );

  /// Lists the organizations the authorized Management account can use.
  Future<ProvisioningResult> listOrganizations() => _serialized(
    () => _withAttempt((attempt, capability) async {
      final organizations = await client.organizations(
        attempt.transactionId,
        capability: capability,
      );
      return _result(
        ProvisioningOutcome.inProgress,
        profile: attempt.profile,
        organizations: organizations,
      );
    }),
  );

  /// Selects one organization and the project name for this attempt.
  ///
  /// [projectName] must satisfy the Worker's `personal-planner-*` contract.
  /// Choosing the name is a product decision owned by a later phase, so this
  /// action never invents one.
  Future<ProvisioningResult> selectOrganization({
    required String organizationSlug,
    required String projectName,
  }) {
    if (!_organizationSlugPattern.hasMatch(organizationSlug)) {
      throw ArgumentError.value(
        organizationSlug,
        'organizationSlug',
        'must match ${_organizationSlugPattern.pattern}',
      );
    }
    if (!_projectNamePattern.hasMatch(projectName)) {
      throw ArgumentError.value(
        projectName,
        'projectName',
        'must match ${_projectNamePattern.pattern}',
      );
    }
    return _serialized(
      () => _withAttempt((attempt, capability) async {
        try {
          final snapshot = await client.selectOrganization(
            attempt.transactionId,
            capability: capability,
            slug: organizationSlug,
            projectName: projectName,
            idempotencyKey: idempotencyKeyFor(attempt.transactionId),
          );
          return await _applySnapshot(attempt, snapshot);
        } on ProvisioningApiException catch (error) {
          if (error.kind == ProvisioningErrorKind.worker &&
              error.code == 'invalid_request') {
            // An identical earlier selection may already have been applied
            // while its response was lost. The authoritative state decides.
            final current = await client.snapshot(
              attempt.transactionId,
              capability: capability,
            );
            if (current.state != ProvisioningState.authorizationPending) {
              return await _applySnapshot(attempt, current);
            }
          }
          return _failure(error, profile: attempt.profile);
        }
      }),
    );
  }

  /// Drives project creation strictly through the Worker's own state machine.
  ///
  /// Reconciliation is never skipped: a transaction waiting on reconciliation
  /// calls the reconcile route, which cannot create a project, and create is
  /// only requested from the states the Worker authorizes.
  Future<ProvisioningResult> createOrContinueProject() => _serialized(
    () => _withAttempt((attempt, capability) async {
      final snapshot = switch (attempt.profile.state) {
        ProvisioningState.organizationSelected ||
        ProvisioningState.projectRetryAuthorized ||
        ProvisioningState.projectCreating => await client.create(
          attempt.transactionId,
          capability: capability,
        ),
        ProvisioningState.projectReconciliationRequired =>
          await client.reconcile(attempt.transactionId, capability: capability),
        _ => null,
      };
      if (snapshot == null) {
        return _result(
          ProvisioningOutcome.inProgress,
          profile: attempt.profile,
          message:
              'Project creation is not the next step for '
              '${attempt.profile.state.wireName}.',
        );
      }
      return _applySnapshot(attempt, snapshot);
    }),
  );

  /// Runs the Worker's canonical migration step.
  Future<ProvisioningResult> migrate() => _serialized(
    () => _withAttempt((attempt, capability) async {
      if (!const {
        ProvisioningState.projectWaiting,
        ProvisioningState.migrationReconciliationRequired,
        ProvisioningState.migrating,
      }.contains(attempt.profile.state)) {
        return _result(
          ProvisioningOutcome.inProgress,
          profile: attempt.profile,
          message:
              'Migration is not the next step for '
              '${attempt.profile.state.wireName}.',
        );
      }
      return _applySnapshot(
        attempt,
        await client.migrate(attempt.transactionId, capability: capability),
      );
    }),
  );

  /// Runs fixed backend verification.
  Future<ProvisioningResult> verify() => _serialized(
    () => _withAttempt((attempt, capability) async {
      if (attempt.profile.state != ProvisioningState.verifying) {
        return _result(
          ProvisioningOutcome.inProgress,
          profile: attempt.profile,
          message:
              'Verification is not the next step for '
              '${attempt.profile.state.wireName}.',
        );
      }
      return _applySnapshot(
        attempt,
        await client.verify(attempt.transactionId, capability: capability),
      );
    }),
  );

  Future<ProvisioningResult> _withAttempt(
    Future<ProvisioningResult> Function(
      ProvisioningAttempt attempt,
      String capability,
    )
    action,
  ) async {
    final BackendConnectionProfile? profile;
    try {
      profile = await profileStore.read();
    } on ConnectionProfileStoreException catch (error) {
      return _result(
        _isReplaceable(error.failure)
            ? ProvisioningOutcome.protocolError
            : ProvisioningOutcome.retryable,
        message: error.message,
      );
    }
    if (profile == null || profile.state == ProvisioningState.localOnly) {
      return _result(ProvisioningOutcome.localOnly);
    }
    final transactionId = profile.provisioningTransactionId;
    if (transactionId == null) {
      return _result(
        ProvisioningOutcome.protocolError,
        profile: profile,
        message: 'The stored backend profile has no provisioning transaction.',
      );
    }
    final String? capability;
    try {
      capability = await capabilityStore.read(transactionId: transactionId);
    } on ProvisioningCapabilityStoreException {
      return _result(
        ProvisioningOutcome.retryable,
        profile: profile,
        message:
            'Secure storage is unavailable, so the provisioning capability '
            'could not be read.',
      );
    }
    if (capability == null) {
      return _result(
        ProvisioningOutcome.capabilityMissing,
        profile: profile,
        message:
            'The provisioning capability is missing, so this attempt cannot '
            'continue; start a new provisioning attempt.',
      );
    }
    final attempt = ProvisioningAttempt(
      profile: profile,
      transactionId: transactionId,
      hasCapability: true,
    );
    try {
      return await action(attempt, capability);
    } on ProvisioningApiException catch (error) {
      return _failure(error, profile: profile);
    }
  }

  Future<ProvisioningResult> _applySnapshot(
    ProvisioningAttempt attempt,
    ProvisioningSnapshot snapshot,
  ) async {
    if (snapshot.transactionId != attempt.transactionId) {
      return _stale(attempt);
    }
    if (snapshot.state == ProvisioningState.ready) {
      return _completeReady(attempt, snapshot);
    }
    final now = _clock().toUtc();
    final target = attempt.profile.copyWith(
      state: snapshot.state,
      updatedAt: now,
      errorCode: snapshot.errorCode,
      projectRef: snapshot.projectRef ?? attempt.profile.projectRef,
    );
    var persisted = attempt.profile;
    if (_differs(attempt.profile, target)) {
      final steps = _stepsTo(attempt.profile, target, now);
      if (steps == null) {
        return _unreachableState(attempt, snapshot, target.state);
      }
      final failure = await _persistSteps(attempt, steps, snapshot);
      if (failure != null) return failure;
      persisted = steps.last;
    }
    if (persisted.state == ProvisioningState.terminalError ||
        persisted.state == ProvisioningState.expired) {
      // The Worker can no longer resume this transaction, so neither can we.
      await _discardCapability(attempt.transactionId);
    }
    return _result(
      _outcomeForState(persisted.state),
      profile: persisted,
      snapshot: snapshot,
    );
  }

  Future<ProvisioningResult> _completeReady(
    ProvisioningAttempt attempt,
    ProvisioningSnapshot snapshot,
  ) async {
    final config = snapshot.runtimeConfig;
    if (config == null) {
      return _result(
        ProvisioningOutcome.protocolError,
        profile: attempt.profile,
        snapshot: snapshot,
        message:
            'The provisioning service reported ready without a runtime '
            'configuration.',
      );
    }
    final BackendConnectionProfile? stored;
    try {
      stored = await profileStore.read();
    } on ConnectionProfileStoreException catch (error) {
      return _result(
        ProvisioningOutcome.retryable,
        profile: attempt.profile,
        snapshot: snapshot,
        message: error.message,
      );
    }
    if (stored == null) return _stale(attempt);
    if (stored.state == ProvisioningState.ready &&
        stored.profileId == attempt.profile.profileId) {
      // Completion already happened (for example a retry after a cleanup
      // failure), so only the capability cleanup remains.
      final removed = await _discardCapability(attempt.transactionId);
      return _result(
        ProvisioningOutcome.ready,
        profile: stored,
        snapshot: snapshot,
        message: removed
            ? null
            : 'Provisioning completed, but the temporary capability could not '
                  'be removed yet.',
      );
    }
    if (stored.profileId != attempt.profile.profileId ||
        stored.generation != attempt.profile.generation) {
      return _stale(attempt, stored);
    }
    final now = _clock().toUtc();
    // Poll gaps can hide intermediate states, so completion walks the Worker's
    // own transition graph; every persisted step stays a legal transition.
    final path = _pathTo(attempt.profile.state, ProvisioningState.verifying);
    if (path == null) {
      return _unreachableState(attempt, snapshot, ProvisioningState.ready);
    }
    var generation = attempt.profile.generation;
    var running = attempt.profile;
    final steps = <BackendConnectionProfile>[];
    for (final state in path) {
      generation += 1;
      final step = running.copyWith(
        generation: generation,
        state: state,
        updatedAt: now,
      );
      steps.add(step);
      running = step;
    }
    final BackendConnectionProfile ready;
    try {
      // The Phase B model stays the single authority for what a usable
      // client-safe backend configuration is.
      generation += 1;
      ready = BackendConnectionProfile(
        profileId: attempt.profile.profileId,
        generation: generation,
        state: ProvisioningState.ready,
        createdAt: attempt.profile.createdAt,
        updatedAt: now,
        projectRef: config.projectRef,
        projectUrl: config.projectUrl,
        publishableKey: config.publishableKey,
        installationId: attempt.profile.installationId,
        compatibility: attempt.profile.compatibility,
        provisioningTransactionId: attempt.transactionId,
      );
    } on BackendProfileValidationException catch (error) {
      return _result(
        ProvisioningOutcome.protocolError,
        profile: attempt.profile,
        snapshot: snapshot,
        message: 'The runtime configuration was rejected: ${error.message}',
      );
    }
    if (steps.isNotEmpty) {
      final failure = await _persistSteps(attempt, steps, snapshot);
      if (failure != null) return failure;
    }
    try {
      await profileStore.save(
        ready,
        expectedGeneration: steps.isEmpty
            ? attempt.profile.generation
            : steps.last.generation,
      );
    } on StaleConnectionProfileException {
      return _stale(attempt);
    } on ConnectionProfileStoreException {
      // Retain the capability: completion can be retried safely.
      return _result(
        ProvisioningOutcome.retryable,
        profile: attempt.profile,
        snapshot: snapshot,
        message:
            'The verified backend profile could not be saved; the provisioning '
            'capability was kept so completion can be retried.',
      );
    }
    final removed = await _discardCapability(attempt.transactionId);
    return _result(
      ProvisioningOutcome.ready,
      profile: ready,
      snapshot: snapshot,
      message: removed
          ? null
          : 'Provisioning completed, but the temporary capability could not '
                'be removed yet.',
    );
  }

  /// Builds the profiles to persist in order to move from [from] to [target].
  ///
  /// When the Worker advanced more than one state between polls, the
  /// intermediate states are walked so every persisted step remains a legal
  /// transition. Returns null when [target] is unreachable.
  List<BackendConnectionProfile>? _stepsTo(
    BackendConnectionProfile from,
    BackendConnectionProfile target,
    DateTime now,
  ) {
    final path = _pathTo(from.state, target.state);
    if (path == null) return null;
    if (path.isEmpty) return <BackendConnectionProfile>[target];
    final steps = <BackendConnectionProfile>[];
    var generation = from.generation;
    var running = from;
    for (final state in path) {
      generation += 1;
      final step = state == target.state
          ? target.copyWith(generation: generation, updatedAt: now)
          : running.copyWith(
              generation: generation,
              state: state,
              updatedAt: now,
            );
      steps.add(step);
      running = step;
    }
    return steps;
  }

  /// Shortest legal transition path from [from] to [to], or null when the
  /// Worker cannot produce that change on one transaction.
  List<ProvisioningState>? _pathTo(
    ProvisioningState from,
    ProvisioningState to,
  ) {
    if (from == to) return const <ProvisioningState>[];
    final queue = <List<ProvisioningState>>[
      <ProvisioningState>[from],
    ];
    final visited = <ProvisioningState>{from};
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      for (final next in path.last.allowedNextStates) {
        if (!visited.add(next)) continue;
        final extended = <ProvisioningState>[...path, next];
        if (next == to) return extended.sublist(1);
        queue.add(extended);
      }
    }
    return null;
  }

  /// Persists [steps] in order, each a single legal transition from the one
  /// before it, and only while the stored profile is still this attempt.
  Future<ProvisioningResult?> _persistSteps(
    ProvisioningAttempt attempt,
    List<BackendConnectionProfile> steps,
    ProvisioningSnapshot snapshot,
  ) async {
    var expected = attempt.profile;
    for (final step in steps) {
      final guard = await _guardAgainst(expected, attempt, snapshot);
      if (guard != null) return guard;
      try {
        await profileStore.save(step, expectedGeneration: expected.generation);
      } on StaleConnectionProfileException {
        return _stale(attempt);
      } on ProvisioningStateTransitionException catch (error) {
        return _unreachableState(
          attempt,
          snapshot,
          step.state,
          detail: '$error',
        );
      } on BackendProfileValidationException catch (error) {
        return _result(
          ProvisioningOutcome.protocolError,
          profile: attempt.profile,
          snapshot: snapshot,
          message: error.message,
        );
      } on ConnectionProfileStoreException catch (error) {
        return _result(
          ProvisioningOutcome.retryable,
          profile: attempt.profile,
          snapshot: snapshot,
          message: error.message,
        );
      }
      expected = step;
    }
    return null;
  }

  /// Returns a failure result unless the stored profile is still the one
  /// [expected] describes. The store keeps its own generation guard, so this is
  /// only a fast, clearer rejection.
  Future<ProvisioningResult?> _guardAgainst(
    BackendConnectionProfile expected,
    ProvisioningAttempt attempt,
    ProvisioningSnapshot? snapshot,
  ) async {
    final BackendConnectionProfile? stored;
    try {
      stored = await profileStore.read();
    } on ConnectionProfileStoreException catch (error) {
      return _result(
        ProvisioningOutcome.retryable,
        profile: attempt.profile,
        snapshot: snapshot,
        message: error.message,
      );
    }
    if (stored == null ||
        stored.profileId != expected.profileId ||
        stored.generation != expected.generation) {
      return _stale(attempt, stored);
    }
    return null;
  }

  ProvisioningResult _unreachableState(
    ProvisioningAttempt attempt,
    ProvisioningSnapshot snapshot,
    ProvisioningState state, {
    String? detail,
  }) => _result(
    ProvisioningOutcome.protocolError,
    profile: attempt.profile,
    snapshot: snapshot,
    message:
        'The provisioning service reported ${state.wireName}, which this '
        'attempt cannot reach${detail == null ? '' : ': $detail'}.',
  );

  bool _differs(
    BackendConnectionProfile current,
    BackendConnectionProfile next,
  ) =>
      current.state != next.state ||
      current.errorCode != next.errorCode ||
      current.projectRef != next.projectRef ||
      current.provisioningTransactionId != next.provisioningTransactionId;

  Future<BackendConnectionProfile?> _profileOrNull() async {
    try {
      return await profileStore.read();
    } on ConnectionProfileStoreException {
      return null;
    }
  }

  Future<bool> _hasCapability(String transactionId) async {
    try {
      return await capabilityStore.read(transactionId: transactionId) != null;
    } on ProvisioningCapabilityStoreException {
      return false;
    }
  }

  Future<bool> _discardCapability(String transactionId) async {
    try {
      await capabilityStore.delete(transactionId: transactionId);
      return true;
    } on ProvisioningCapabilityStoreException {
      return false;
    }
  }

  bool _isReplaceable(ConnectionProfileStoreFailure failure) =>
      failure == ConnectionProfileStoreFailure.corrupt ||
      failure == ConnectionProfileStoreFailure.unsupportedVersion ||
      failure == ConnectionProfileStoreFailure.tooLarge;

  ProvisioningOutcome _outcomeForState(ProvisioningState state) =>
      switch (state) {
        ProvisioningState.ready => ProvisioningOutcome.ready,
        ProvisioningState.terminalError => ProvisioningOutcome.terminal,
        ProvisioningState.expired => ProvisioningOutcome.restartRequired,
        _ => ProvisioningOutcome.inProgress,
      };

  ProvisioningResult _failure(
    ProvisioningApiException error, {
    BackendConnectionProfile? profile,
  }) => switch (error.failureClass) {
    ProvisioningFailureClass.retryable => _result(
      ProvisioningOutcome.retryable,
      profile: profile,
      message: error.message,
    ),
    ProvisioningFailureClass.actionRequired => _result(
      ProvisioningOutcome.needsUserAction,
      profile: profile,
      message: error.message,
    ),
    ProvisioningFailureClass.terminal => _result(
      ProvisioningOutcome.terminal,
      profile: profile,
      message: error.message,
    ),
    ProvisioningFailureClass.restartRequired => _result(
      ProvisioningOutcome.restartRequired,
      profile: profile,
      message: error.message,
    ),
    ProvisioningFailureClass.protocol => _result(
      ProvisioningOutcome.protocolError,
      profile: profile,
      message: error.message,
    ),
  };

  ProvisioningResult _stale(
    ProvisioningAttempt attempt, [
    BackendConnectionProfile? stored,
  ]) => _result(
    ProvisioningOutcome.stale,
    profile: stored ?? attempt.profile,
    message:
        'A newer provisioning attempt replaced this one, so the outdated '
        'result was discarded.',
  );

  ProvisioningResult _result(
    ProvisioningOutcome outcome, {
    BackendConnectionProfile? profile,
    ProvisioningSnapshot? snapshot,
    List<ProvisioningOrganization> organizations =
        const <ProvisioningOrganization>[],
    String? message,
    Uri? authorizationUrl,
  }) => ProvisioningResult(
    outcome: outcome,
    profile: profile,
    snapshot: snapshot,
    organizations: organizations,
    message: message,
    authorizationUrl: authorizationUrl,
  );

  /// Serializes coordinator actions so two overlapping calls cannot persist
  /// contradictory progress. Durable generation checks remain authoritative.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

String _defaultProfileId() => 'prov-${generateUuidV7()}';
