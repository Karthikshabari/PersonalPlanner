import 'package:flutter/foundation.dart' show immutable;

/// Canonical identity of one authenticated Planner account.
///
/// A Supabase Auth user id is only meaningful **inside** one Supabase project,
/// so the Planner account identity is the pair `(projectRef, authUserId)` and
/// never the auth user id alone. Two user-owned projects can hand out the same
/// auth user id, and those two accounts must never share local Planner state.
///
/// [storageId] is the deterministic, filesystem-safe identifier every local
/// namespace is derived from: the account database file name, the secured Auth
/// session key, the PKCE key prefix, the sync cursor key, and the background
/// timer scope.
@immutable
class PlannerAccountScope {
  const PlannerAccountScope._({required this.authUserId, this.projectRef});

  /// The provisioned, user-owned backend scope.
  ///
  /// Throws [ArgumentError] when [projectRef] is not a 20-character lowercase
  /// Supabase project ref or [authUserId] is not a lowercase UUID.
  factory PlannerAccountScope.provisioned({
    required String projectRef,
    required String authUserId,
  }) {
    _validate(projectRef: projectRef, authUserId: authUserId);
    return PlannerAccountScope._(
      projectRef: projectRef,
      authUserId: authUserId,
    );
  }

  /// The compile-time developer Supabase backend.
  ///
  /// That backend has no project ref available to the client, and its
  /// historical local data has to keep the exact identity it already had, so
  /// the scope is the auth user id alone. Project-aware runtimes never use
  /// this form.
  factory PlannerAccountScope.legacyStatic(String authUserId) {
    _validate(projectRef: null, authUserId: authUserId);
    return PlannerAccountScope._(authUserId: authUserId);
  }

  /// [PlannerAccountScope.provisioned] without throwing.
  ///
  /// Provider code builds scopes from live session values, so a malformed id
  /// must fail closed (no scope) rather than break the provider graph.
  static PlannerAccountScope? tryProvisioned({
    required String projectRef,
    required String authUserId,
  }) {
    if (!isProjectRef(projectRef) || !isAuthUserId(authUserId)) return null;
    return PlannerAccountScope._(
      projectRef: projectRef,
      authUserId: authUserId,
    );
  }

  /// [PlannerAccountScope.legacyStatic] without throwing.
  static PlannerAccountScope? tryLegacyStatic(String authUserId) {
    if (!isAuthUserId(authUserId)) return null;
    return PlannerAccountScope._(authUserId: authUserId);
  }

  /// The 20-character Supabase project ref, or null when this backend has no
  /// project ref of its own (local-only developer configuration).
  final String? projectRef;

  /// Supabase Auth user id. Unique only within [projectRef].
  final String authUserId;

  /// True when this account belongs to a provisioned user-owned project.
  bool get isProjectScoped => projectRef != null;

  /// Deterministic identifier for every local namespace of this account.
  ///
  /// The project-scoped form is unambiguous: a project ref is exactly 20
  /// characters of `[a-z0-9]` and therefore can never contain the separator.
  String get storageId {
    final ref = projectRef;
    if (ref == null) return authUserId;
    return 'project_${ref}__user_$authUserId';
  }

  /// True when [value] is the storage id of some account scope.
  static bool isStorageId(String value) =>
      isAuthUserId(value) || isProjectScopedStorageId(value);

  /// True when [value] is a `project_<ref>__user_<uuid>` storage id.
  static bool isProjectScopedStorageId(String value) =>
      _projectScopedStorageIdShape.hasMatch(value);

  /// True when [value] is a lowercase Supabase Auth user id (UUID).
  static bool isAuthUserId(String value) => _authUserIdShape.hasMatch(value);

  /// True when [value] is a 20-character lowercase Supabase project ref.
  static bool isProjectRef(String value) => _projectRefShape.hasMatch(value);

  @override
  bool operator ==(Object other) =>
      other is PlannerAccountScope &&
      other.projectRef == projectRef &&
      other.authUserId == authUserId;

  @override
  int get hashCode => Object.hash(projectRef, authUserId);

  @override
  String toString() =>
      'PlannerAccountScope(projectRef: ${projectRef ?? 'none'}, '
      'authUserId: $authUserId)';
}

/// Lowercase Supabase Auth user ids are UUIDs.
final RegExp _authUserIdShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Supabase project refs are exactly 20 lowercase alphanumeric characters.
final RegExp _projectRefShape = RegExp(r'^[a-z0-9]{20}$');

final RegExp _projectScopedStorageIdShape = RegExp(
  r'^project_[a-z0-9]{20}__user_'
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

void _validate({required String? projectRef, required String authUserId}) {
  if (projectRef != null && !PlannerAccountScope.isProjectRef(projectRef)) {
    throw ArgumentError.value(
      projectRef,
      'projectRef',
      'must be a 20 character lowercase Supabase project ref',
    );
  }
  if (!PlannerAccountScope.isAuthUserId(authUserId)) {
    throw ArgumentError.value(
      authUserId,
      'authUserId',
      'must be a lowercase Supabase Auth user id (UUID)',
    );
  }
}
