/// Provisioning lifecycle states for a user-owned Supabase backend.
///
/// Every state except [ProvisioningState.localOnly] mirrors the durable Worker
/// state names in `provisioning/src/production.ts` (`STATES` and `NEXT`).
/// Dart identifiers are camelCase to satisfy this repository's lints, so
/// persisted values must always use [wireName].
enum ProvisioningState {
  /// Flutter-local only. No cloud backend is configured yet, so the Planner
  /// runs exactly as it does without any Supabase configuration.
  ///
  /// This is deliberately the one state that the Worker never reports.
  localOnly,

  /// The provisioning transaction exists and the user still has to authorize
  /// Supabase Management access.
  authorizationPending,

  /// Supabase accepted the authorization and the user selected one of their
  /// organizations.
  organizationSelected,

  /// A project-create POST is in flight (or was reserved) for this
  /// transaction.
  projectCreating,

  /// The create outcome is ambiguous. The Worker must reconcile against the
  /// organization before any further create is allowed.
  projectReconciliationRequired,

  /// Authoritative reconciliation proved that no matching project exists, so
  /// one bounded create attempt is authorized.
  projectRetryAuthorized,

  /// A project ref is durably recorded. The project may still be starting.
  projectWaiting,

  /// Canonical migrations are being applied or verified against history.
  migrating,

  /// A migration outcome was ambiguous (or the project was not ready), so
  /// official migration history must be reconciled before another POST.
  migrationReconciliationRequired,

  /// Fixed schema, RLS, grant, and capability verification is running.
  verifying,

  /// The backend is verified and the client-safe project configuration is
  /// available.
  ready,

  /// A terminal provisioning failure. Progress cannot continue on this
  /// transaction; recovery means a new provisioning attempt.
  terminalError,

  /// The transaction TTL elapsed. Expiry clears Management credentials
  /// server-side; recovery means a new provisioning attempt.
  expired;

  /// True when the provisioning Worker itself can report this state.
  ///
  /// [ProvisioningState.localOnly] exists only inside Flutter.
  bool get isWorkerReported => this != ProvisioningState.localOnly;

  /// True when the transaction can no longer progress.
  ///
  /// Restarting from these states is a new provisioning attempt with a new
  /// profile identity, never an in-place transition.
  bool get isTerminal =>
      this == ProvisioningState.terminalError ||
      this == ProvisioningState.expired;

  /// True only for a fully verified backend.
  bool get isReady => this == ProvisioningState.ready;

  /// True while later calls to the transaction endpoints may still progress.
  bool get isInProgress => isWorkerReported && !isTerminal && !isReady;

  /// The exact state name used by the provisioning Worker and by persistence.
  String get wireName => switch (this) {
    ProvisioningState.localOnly => 'local_only',
    ProvisioningState.authorizationPending => 'authorization_pending',
    ProvisioningState.organizationSelected => 'organization_selected',
    ProvisioningState.projectCreating => 'project_creating',
    ProvisioningState.projectReconciliationRequired =>
      'project_reconciliation_required',
    ProvisioningState.projectRetryAuthorized => 'project_retry_authorized',
    ProvisioningState.projectWaiting => 'project_waiting',
    ProvisioningState.migrating => 'migrating',
    ProvisioningState.migrationReconciliationRequired =>
      'migration_reconciliation_required',
    ProvisioningState.verifying => 'verifying',
    ProvisioningState.ready => 'ready',
    ProvisioningState.terminalError => 'terminal_error',
    ProvisioningState.expired => 'expired',
  };

  /// Parses a persisted or Worker-reported state name.
  ///
  /// Returns null for unknown values so callers can fail closed with their own
  /// domain error instead of guessing a state.
  static ProvisioningState? tryFromWireName(String value) {
    for (final state in ProvisioningState.values) {
      if (state.wireName == value) return state;
    }
    return null;
  }

  /// States this state may move to.
  ///
  /// Worker-reported sets are copied from the Worker's own transition table so
  /// Flutter can never accept a mutation the control plane cannot produce.
  Set<ProvisioningState> get allowedNextStates => switch (this) {
    ProvisioningState.localOnly => const {
      ProvisioningState.authorizationPending,
    },
    ProvisioningState.authorizationPending => const {
      ProvisioningState.organizationSelected,
      // Exact mapped or explicitly adopted projects are already verified.
      ProvisioningState.ready,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.organizationSelected => const {
      ProvisioningState.projectCreating,
      // Another device may have bound the account while this one selected an organization.
      ProvisioningState.ready,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.projectCreating => const {
      ProvisioningState.projectReconciliationRequired,
      ProvisioningState.projectWaiting,
      ProvisioningState.expired,
    },
    ProvisioningState.projectReconciliationRequired => const {
      ProvisioningState.projectRetryAuthorized,
      ProvisioningState.projectWaiting,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.projectRetryAuthorized => const {
      ProvisioningState.projectCreating,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.projectWaiting => const {
      ProvisioningState.migrating,
      ProvisioningState.expired,
    },
    ProvisioningState.migrating => const {
      ProvisioningState.migrationReconciliationRequired,
      ProvisioningState.verifying,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.migrationReconciliationRequired => const {
      ProvisioningState.migrating,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.verifying => const {
      ProvisioningState.ready,
      ProvisioningState.terminalError,
      ProvisioningState.expired,
    },
    ProvisioningState.ready => const {ProvisioningState.expired},
    ProvisioningState.terminalError => const {ProvisioningState.expired},
    ProvisioningState.expired => const <ProvisioningState>{},
  };

  /// True when a stored profile may move from this state to [next].
  ///
  /// Re-observing the same state is allowed: polling returns the same state
  /// repeatedly while only timestamps or diagnostic codes change.
  bool canTransitionTo(ProvisioningState next) => canTransition(this, next);
}

/// Transition validator mirroring the Worker's `canTransition` helper.
///
/// The Worker states follow `NEXT` in `provisioning/src/production.ts`.
/// The only Flutter-local edge is `localOnly -> authorizationPending`, which
/// is how starting a first provisioning attempt is represented.
bool canTransition(ProvisioningState from, ProvisioningState to) {
  if (from == to) return true;
  return from.allowedNextStates.contains(to);
}

/// Thrown when a stored profile would move through an impossible transition.
class ProvisioningStateTransitionException implements Exception {
  const ProvisioningStateTransitionException({
    required this.from,
    required this.to,
  });

  final ProvisioningState from;
  final ProvisioningState to;

  @override
  String toString() =>
      'Illegal provisioning transition: ${from.wireName} -> ${to.wireName}';
}
