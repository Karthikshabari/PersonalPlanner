import '../domain/backend_connection_profile.dart';
import '../domain/cloud_connection_lifecycle.dart';
import '../domain/provisioning_state.dart';
import '../domain/runtime_backend.dart';
import 'auth_repository.dart';
import 'connection_profile_store.dart';
import 'provisioning_capability_store.dart';

/// Explicit, ordered lifecycle operations for the provisioned cloud connection.
///
/// This is the only place that corresponds to the user-facing actions that are
/// *not* plain Auth operations:
///
/// * **sign out** — an Auth concern, owned by [AuthRepository] and the runtime
///   Auth stack. It clears exactly one project's session and nothing else.
/// * **disable Cloud Sync** — a per-account product preference, owned by
///   `syncEnabledProvider`. The connection, the session and the baseline stay.
/// * **disconnect** — this service: stop synchronization, sign out of exactly
///   this project, then stop resolving the stored backend while remembering its
///   client-safe endpoint for a later reconnect.
///
/// Invariants:
///
/// * nothing here deletes a local account database, a queued outbox operation,
///   or the user's Supabase project;
/// * synchronization is stopped *before* any connection state is cleared, so an
///   in-flight cycle cannot acknowledge work after ownership was dropped;
/// * only the project in [ProvisionedRuntimeBackend] is affected, so project A's
///   session and remembered endpoint are untouched by project B's lifecycle.
class CloudLifecycleService {
  CloudLifecycleService({
    required this.profileStore,
    required this.capabilityStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ConnectionProfileStore profileStore;
  final ProvisioningCapabilityStore capabilityStore;
  final DateTime Function() _clock;

  /// Stops using [backend] on this device without destroying anything.
  ///
  /// Order matters:
  ///
  /// 1. [stopSync] releases the engine and the first-sync coordinator, so no
  ///    cycle can still be mutating through the connection being severed;
  /// 2. the project-scoped Auth session is cleared (only this project's
  ///    namespace);
  /// 3. the durable profile is kept but marked disconnected, so the Planner
  ///    runs local-only while a later reconnect can reuse the exact same
  ///    user-owned project, local database and completed baseline;
  /// 4. the now-useless provisioning capability of that attempt is removed from
  ///    secure storage.
  ///
  /// The durable profile is validated *first*, so a mismatch or an unreadable
  /// document fails without signing the user out or stopping anything: an
  /// ambiguous connection is never half-severed.
  Future<CloudLifecycleResult> disconnect({
    required ProvisionedRuntimeBackend backend,
    required Future<void> Function() stopSync,
    AuthRepository? authRepository,
  }) async {
    final BackendConnectionProfile? profile;
    try {
      profile = await profileStore.read();
    } on ConnectionProfileStoreException {
      return const CloudLifecycleResult.failed(cloudDisconnectFailedMessage);
    }
    if (profile == null || profile.state != ProvisioningState.ready) {
      return const CloudLifecycleResult.failed(cloudDisconnectFailedMessage);
    }
    if (profile.projectRef != backend.projectRef) {
      // The stored connection is no longer the one being disconnected. Never
      // write the flag onto a different project, and never sever the session of
      // a backend this action does not own.
      return const CloudLifecycleResult.failed(cloudDisconnectFailedMessage);
    }

    await stopSync();

    String? warning;
    try {
      await authRepository?.signOut();
    } catch (_) {
      // AuthRepository removes this project's persisted session in a `finally`,
      // so the local connection is severed either way. The remote sign-out
      // request may fail while offline; that must not block the disconnect.
      warning =
          'Signed out on this device. The cloud service could not be told '
          'right now; that is retried the next time this account is used.';
    }

    if (!profile.connectionDisabled) {
      try {
        await profileStore.save(
          profile.copyWith(
            generation: profile.generation + 1,
            updatedAt: _clock().toUtc(),
            connectionDisabled: true,
          ),
          expectedGeneration: profile.generation,
        );
      } on ConnectionProfileStoreException {
        // Sync has already stopped and this device has already been signed out;
        // only the durable flag is missing. Reporting "left unchanged" here
        // would contradict the cleared session and the stopped engine.
        return CloudLifecycleResult.failed(
          authRepository == null
              ? cloudDisconnectSyncStoppedStateFailureMessage
              : cloudDisconnectSignedOutStateFailureMessage,
        );
      } on StaleConnectionProfileException {
        return CloudLifecycleResult.failed(
          authRepository == null
              ? cloudDisconnectSyncStoppedStateFailureMessage
              : cloudDisconnectSignedOutStateFailureMessage,
        );
      }
    }

    final transactionId = profile.provisioningTransactionId;
    if (transactionId != null) {
      try {
        await capabilityStore.delete(transactionId: transactionId);
      } on ProvisioningCapabilityStoreException {
        // A leftover capability is scoped to a finished transaction and cannot
        // resume provisioning, so this is best effort only.
      }
    }
    return CloudLifecycleResult.completed(message: warning);
  }

  /// Re-activates the remembered backend of [projectRef].
  ///
  /// Only the durable flag changes. The stored project ref, URL, publishable
  /// key, local account database and completed Phase G baseline are all reused,
  /// so reconnecting is not a new provisioning attempt and cannot upload
  /// existing Planner data into a different project.
  Future<CloudLifecycleResult> reconnect({required String projectRef}) async {
    final BackendConnectionProfile? profile;
    try {
      profile = await profileStore.read();
    } on ConnectionProfileStoreException {
      return const CloudLifecycleResult.failed(cloudDisconnectFailedMessage);
    }
    if (profile == null || profile.projectRef != projectRef) {
      return const CloudLifecycleResult.notApplicable(
        message:
            'The remembered cloud backend is no longer available on this '
            'device. Start cloud setup to connect a backend.',
      );
    }
    if (!profile.connectionDisabled) {
      return const CloudLifecycleResult.completed();
    }
    try {
      await profileStore.save(
        profile.copyWith(
          generation: profile.generation + 1,
          updatedAt: _clock().toUtc(),
          connectionDisabled: false,
        ),
        expectedGeneration: profile.generation,
      );
    } on ConnectionProfileStoreException {
      return const CloudLifecycleResult.failed(cloudDisconnectFailedMessage);
    } on StaleConnectionProfileException {
      return const CloudLifecycleResult.failed(cloudDisconnectFailedMessage);
    }
    return const CloudLifecycleResult.completed();
  }
}
