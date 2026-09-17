import 'package:flutter/foundation.dart' show immutable;

/// Secure-storage namespace for the runtime Supabase Auth material of exactly
/// one runtime backend.
///
/// Supabase Auth sessions and PKCE verifiers are only valid inside the project
/// that issued them, so both namespaces are scoped by project ref for a
/// provisioned backend. The compile-time developer backend keeps the historical
/// global keys so already-persisted development sessions keep working.
///
/// A project ref is 20 characters of `[a-z0-9]`, so the `.`-separated keys are
/// unambiguous and can never collide with the legacy global key.
@immutable
class RuntimeAuthNamespaces {
  const RuntimeAuthNamespaces._({
    required this.projectRef,
    required this.sessionKey,
    required this.pkceKeyPrefix,
  });

  /// Namespace of the compile-time developer Supabase configuration.
  const RuntimeAuthNamespaces.legacyStatic()
    : projectRef = null,
      sessionKey = legacySessionKey,
      pkceKeyPrefix = legacyPkceKeyPrefix;

  /// Namespace of one provisioned user-owned Supabase project.
  factory RuntimeAuthNamespaces.forProject(String projectRef) {
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw ArgumentError.value(
        projectRef,
        'projectRef',
        'must be a 20 character lowercase Supabase project ref',
      );
    }
    return RuntimeAuthNamespaces._(
      projectRef: projectRef,
      sessionKey: 'personal_planner.supabase.$projectRef.session',
      pkceKeyPrefix: 'personal_planner.supabase.$projectRef.pkce.',
    );
  }

  /// Historical session key of the compile-time developer backend.
  static const String legacySessionKey = 'personal_planner.supabase.session';

  /// Historical PKCE key prefix of the compile-time developer backend.
  static const String legacyPkceKeyPrefix = 'personal_planner.supabase.pkce.';

  /// Project ref of the provisioned backend, or null for the legacy backend.
  final String? projectRef;

  /// Key holding this backend's persisted Auth session, if any.
  final String sessionKey;

  /// Prefix of this backend's PKCE verifier keys.
  final String pkceKeyPrefix;

  /// True when this namespace is isolated by project ref.
  bool get isProjectScoped => projectRef != null;

  /// Storage key for one PKCE verifier key inside this namespace.
  String pkceKey(String key) => '$pkceKeyPrefix$key';

  @override
  bool operator ==(Object other) =>
      other is RuntimeAuthNamespaces &&
      other.projectRef == projectRef &&
      other.sessionKey == sessionKey &&
      other.pkceKeyPrefix == pkceKeyPrefix;

  @override
  int get hashCode => Object.hash(projectRef, sessionKey, pkceKeyPrefix);

  @override
  String toString() =>
      'RuntimeAuthNamespaces(projectRef: ${projectRef ?? 'legacy'})';
}
