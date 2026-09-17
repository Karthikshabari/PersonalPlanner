import 'package:flutter/foundation.dart' show immutable;

import '../../../core/models/planner_account_scope.dart';
import 'backend_connection_profile.dart';
import 'provisioning_state.dart';
import 'runtime_auth_namespaces.dart';

/// Client-safe Supabase endpoint used for normal Planner data synchronization.
@immutable
class RuntimeSupabaseEndpoint {
  const RuntimeSupabaseEndpoint({
    required this.url,
    required this.publishableKey,
  });

  final String url;
  final String publishableKey;

  @override
  bool operator ==(Object other) =>
      other is RuntimeSupabaseEndpoint &&
      other.url == url &&
      other.publishableKey == publishableKey;

  @override
  int get hashCode => Object.hash(url, publishableKey);

  /// Deliberately omits [publishableKey]: client-safe is not the same as
  /// something worth echoing into diagnostics.
  @override
  String toString() => 'RuntimeSupabaseEndpoint(url: $url)';
}

/// Which Supabase runtime, if any, this installation talks to.
///
/// Deliberately tiny: it answers "which Supabase client, if any, is the current
/// runtime Auth backend, and is normal Planner data sync allowed for it?" It is
/// not a general cloud-service model.
sealed class RuntimeBackend {
  const RuntimeBackend();

  /// Secure-storage namespace for this backend's runtime Auth material, or
  /// null when there is no runtime Auth backend at all.
  RuntimeAuthNamespaces? get authNamespaces;

  /// Canonical local account scope for an authenticated user of this backend.
  ///
  /// Returns null when there is no runtime Auth backend, or when [authUserId]
  /// is not a plausible Supabase Auth user id (fail closed rather than
  /// inventing a namespace).
  PlannerAccountScope? accountScopeFor(String authUserId);

  /// Endpoint allowed to carry normal Planner data, or null while this backend
  /// must not synchronize Planner data.
  RuntimeSupabaseEndpoint? get plannerDataSyncEndpoint;

  /// True only while normal Planner task/category synchronization may run.
  ///
  /// A provisioned user-owned backend is intentionally false for Phase EF:
  /// runtime Auth is wired, Planner data synchronization is Phase G.
  bool get allowsPlannerDataSync => plannerDataSyncEndpoint != null;
}

/// No Supabase runtime at all: the Planner runs exactly as it does with no
/// cloud configuration.
final class LocalOnlyRuntimeBackend extends RuntimeBackend {
  const LocalOnlyRuntimeBackend();

  @override
  RuntimeAuthNamespaces? get authNamespaces => null;

  @override
  PlannerAccountScope? accountScopeFor(String authUserId) => null;

  @override
  RuntimeSupabaseEndpoint? get plannerDataSyncEndpoint => null;

  @override
  bool operator ==(Object other) => other is LocalOnlyRuntimeBackend;

  @override
  // Every instance is equal to every other, so any constant is a valid hash.
  int get hashCode => 31;

  @override
  String toString() => 'LocalOnlyRuntimeBackend()';
}

/// The compile-time developer Supabase project.
///
/// Keeps the historical runtime behaviour: global Auth storage keys and the
/// auth user id as the whole local account identity.
final class LegacyStaticRuntimeBackend extends RuntimeBackend {
  const LegacyStaticRuntimeBackend({
    required this.url,
    required this.publishableKey,
  });

  final String url;
  final String publishableKey;

  @override
  RuntimeAuthNamespaces get authNamespaces =>
      const RuntimeAuthNamespaces.legacyStatic();

  @override
  PlannerAccountScope? accountScopeFor(String authUserId) =>
      PlannerAccountScope.tryLegacyStatic(authUserId);

  @override
  RuntimeSupabaseEndpoint get plannerDataSyncEndpoint =>
      RuntimeSupabaseEndpoint(url: url, publishableKey: publishableKey);

  @override
  bool operator ==(Object other) =>
      other is LegacyStaticRuntimeBackend &&
      other.url == url &&
      other.publishableKey == publishableKey;

  @override
  int get hashCode => Object.hash(url, publishableKey);

  @override
  String toString() => 'LegacyStaticRuntimeBackend(url: $url)';
}

/// A provisioned, verified user-owned Supabase project.
///
/// Every field is client-safe and comes from a validated READY
/// [BackendConnectionProfile]. Nothing here can carry a Management credential,
/// a secret key, or a database password.
final class ProvisionedRuntimeBackend extends RuntimeBackend {
  const ProvisionedRuntimeBackend({
    required this.profileId,
    required this.generation,
    required this.projectRef,
    required this.projectUrl,
    required this.publishableKey,
  });

  /// Builds the runtime backend for [profile], or null when the profile is not
  /// a READY user-owned backend.
  ///
  /// Only `state == ready` may reach runtime Auth: a partially provisioned
  /// profile never produces a client, so an unfinished setup cannot log in
  /// against half-configured infrastructure.
  static ProvisionedRuntimeBackend? tryFromProfile(
    BackendConnectionProfile? profile,
  ) {
    if (profile == null || profile.state != ProvisioningState.ready) {
      return null;
    }
    final projectRef = profile.projectRef;
    final projectUrl = profile.projectUrl;
    final publishableKey = profile.publishableKey;
    // `BackendConnectionProfile` already guarantees these for a ready profile;
    // re-checking keeps this conversion total instead of relying on `!`.
    if (projectRef == null || projectUrl == null || publishableKey == null) {
      return null;
    }
    return ProvisionedRuntimeBackend(
      profileId: profile.profileId,
      generation: profile.generation,
      projectRef: projectRef,
      projectUrl: projectUrl,
      publishableKey: publishableKey,
    );
  }

  /// Local identifier of the durable connection profile that produced this
  /// backend. Changes are how a replaced profile invalidates a live client.
  final String profileId;

  /// Generation of that profile.
  final int generation;

  final String projectRef;

  /// Canonical project URL: `https://<projectRef>.supabase.co`.
  final String projectUrl;

  /// Client-safe Supabase publishable key. Never a secret key.
  final String publishableKey;

  @override
  RuntimeAuthNamespaces get authNamespaces =>
      RuntimeAuthNamespaces.forProject(projectRef);

  @override
  PlannerAccountScope? accountScopeFor(String authUserId) =>
      PlannerAccountScope.tryProvisioned(
        projectRef: projectRef,
        authUserId: authUserId,
      );

  /// Null for Phase EF. The provisioned path has no Planner data sync, so no
  /// normal-sync endpoint exists for it yet; Phase G introduces the gated
  /// first-sync design that may change this.
  @override
  RuntimeSupabaseEndpoint? get plannerDataSyncEndpoint => null;

  @override
  bool operator ==(Object other) =>
      other is ProvisionedRuntimeBackend &&
      other.profileId == profileId &&
      other.generation == generation &&
      other.projectRef == projectRef &&
      other.projectUrl == projectUrl &&
      other.publishableKey == publishableKey;

  @override
  int get hashCode => Object.hash(
    profileId,
    generation,
    projectRef,
    projectUrl,
    publishableKey,
  );

  /// Deliberately omits [publishableKey].
  @override
  String toString() =>
      'ProvisionedRuntimeBackend(profileId: $profileId, '
      'generation: $generation, projectRef: $projectRef)';
}

/// Resolves which runtime backend this installation should use.
///
/// Precedence is deliberate:
///
/// 1. compile-time static Supabase configuration (developer/legacy path) wins,
///    so a stored profile can never silently take over an explicitly
///    configured build. Phase D already gives the static path precedence and
///    Phase EF keeps that until static mode is retired separately;
/// 2. otherwise a durable READY provisioned profile;
/// 3. otherwise local-only.
RuntimeBackend resolveRuntimeBackend({
  required bool legacyStaticConfigured,
  required String legacyStaticUrl,
  required String legacyStaticPublishableKey,
  BackendConnectionProfile? profile,
}) {
  if (legacyStaticConfigured) {
    return LegacyStaticRuntimeBackend(
      url: legacyStaticUrl,
      publishableKey: legacyStaticPublishableKey,
    );
  }
  return ProvisionedRuntimeBackend.tryFromProfile(profile) ??
      const LocalOnlyRuntimeBackend();
}
