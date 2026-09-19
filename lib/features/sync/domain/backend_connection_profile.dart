import 'package:flutter/foundation.dart' show immutable, listEquals;

import 'provisioning_state.dart';

/// Version of the persisted [BackendConnectionProfile] document.
///
/// A document declaring any other version is rejected rather than
/// reinterpreted: the profile decides which user-owned backend this
/// installation talks to, so silently ignoring unknown content could bind the
/// Planner to the wrong project. Adding fields therefore requires a version
/// bump, with one narrow documented exception: an optional field whose absence
/// keeps the exact previous meaning and which this build fully handles. Such a
/// field (`connection_disabled`) cannot rewrite how existing content is
/// interpreted, and bumping the version for it would instead reject every
/// already-stored READY profile, stranding a connected installation.
const int plannerBackendProfileFormatVersion = 1;

/// Thrown when profile data is well formed but is not a valid client-safe
/// description of a Personal Planner backend.
class BackendProfileValidationException implements Exception {
  const BackendProfileValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a persisted document declares a format version this build
/// cannot read.
class UnsupportedBackendProfileFormatException implements Exception {
  const UnsupportedBackendProfileFormatException(this.formatVersion);

  final Object? formatVersion;

  @override
  String toString() =>
      'Unsupported backend profile format version: $formatVersion';
}

/// The narrow compatibility facts a provisioned backend reports.
///
/// Only values the sync client actually gates on are modelled; there is
/// deliberately no free-form metadata map.
@immutable
class BackendCompatibility {
  BackendCompatibility({
    required this.protocolVersion,
    required List<int> payloadVersions,
  }) : payloadVersions = List<int>.unmodifiable(payloadVersions) {
    if (protocolVersion < 1) {
      throw const BackendProfileValidationException(
        'Backend compatibility protocol version must be at least 1.',
      );
    }
    if (this.payloadVersions.isEmpty) {
      throw const BackendProfileValidationException(
        'Backend compatibility requires at least one payload version.',
      );
    }
    var previous = 0;
    for (final version in this.payloadVersions) {
      if (version <= previous) {
        throw const BackendProfileValidationException(
          'Backend compatibility payload versions must be strictly '
          'increasing positive integers.',
        );
      }
      previous = version;
    }
  }

  factory BackendCompatibility.fromJson(Map<String, dynamic> json) {
    _rejectUnknownFields(json, const {
      'protocol_version',
      'payload_versions',
    }, 'Backend compatibility');
    final protocolVersion = json['protocol_version'];
    if (protocolVersion is! int) {
      throw const BackendProfileValidationException(
        'Backend compatibility protocol_version must be an integer.',
      );
    }
    final rawVersions = json['payload_versions'];
    if (rawVersions is! List) {
      throw const BackendProfileValidationException(
        'Backend compatibility payload_versions must be a list.',
      );
    }
    final payloadVersions = <int>[];
    for (final version in rawVersions) {
      if (version is! int) {
        throw const BackendProfileValidationException(
          'Backend compatibility payload_versions must contain integers.',
        );
      }
      payloadVersions.add(version);
    }
    return BackendCompatibility(
      protocolVersion: protocolVersion,
      payloadVersions: payloadVersions,
    );
  }

  final int protocolVersion;
  final List<int> payloadVersions;

  Map<String, dynamic> toJson() => {
    'protocol_version': protocolVersion,
    'payload_versions': payloadVersions,
  };

  @override
  bool operator ==(Object other) =>
      other is BackendCompatibility &&
      other.protocolVersion == protocolVersion &&
      listEquals(other.payloadVersions, payloadVersions);

  @override
  int get hashCode =>
      Object.hash(protocolVersion, Object.hashAll(payloadVersions));

  @override
  String toString() =>
      'BackendCompatibility(protocolVersion: $protocolVersion, '
      'payloadVersions: $payloadVersions)';
}

/// Client-safe description of the user-owned Supabase backend this
/// installation is connected to, plus the state of its provisioning.
///
/// Everything here is safe for a shipped client: a project ref, the project
/// URL, the publishable key, narrow compatibility facts, and sanitized
/// provisioning status.
///
/// Deliberately absent: Management OAuth client secrets, Management access or
/// refresh tokens, database passwords, service-role or secret project keys,
/// JWTs, Planner session material, and the provisioning transaction
/// capability. The capability returned when a transaction is created is a
/// short-lived provisioning credential, not a Supabase token; it belongs in
/// secure storage with its own lifetime, so it must never become a field of
/// this profile.
@immutable
class BackendConnectionProfile {
  BackendConnectionProfile({
    required this.profileId,
    required this.generation,
    required this.state,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.projectRef,
    this.projectUrl,
    this.publishableKey,
    this.installationId,
    this.compatibility,
    this.resumeState,
    this.errorCode,
    this.provisioningTransactionId,
    this.authEmailConfirmationRedirect,
    this.remoteMissing = false,
    this.connectionDisabled = false,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    _validate();
  }

  /// The clean starting point used before any provisioning has happened.
  ///
  /// A local-only profile carries no backend or provisioning data at all, so
  /// the Planner keeps behaving exactly like an unconfigured installation.
  factory BackendConnectionProfile.localOnly({
    required String profileId,
    required DateTime createdAt,
    int generation = 1,
  }) => BackendConnectionProfile(
    profileId: profileId,
    generation: generation,
    state: ProvisioningState.localOnly,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  /// Local identity of this connection. Stable across app restarts and
  /// distinct from the Supabase project ref.
  final String profileId;

  /// Monotonically increasing local version of this profile.
  final int generation;

  /// Latest known provisioning state.
  final ProvisioningState state;

  /// Verified 20-character Supabase project ref, once one is known.
  final String? projectRef;

  /// Canonical project URL: `https://<projectRef>.supabase.co`.
  final String? projectUrl;

  /// Client-safe Supabase publishable key. Never a secret key.
  final String? publishableKey;

  /// Reserved for the future installation marker.
  ///
  /// No marker mechanism exists yet, so this stays null until that decision
  /// lands; the field exists so a later phase does not have to change the
  /// persisted format shape for a value it already plans to verify.
  final String? installationId;

  /// Verified protocol/payload compatibility, once verification has run.
  final BackendCompatibility? compatibility;

  /// Resumable Worker state recorded by Flutter after a local interruption.
  ///
  /// Only resumable Worker-reported states are accepted; terminal states and
  /// `ready` are not resumable.
  final ProvisioningState? resumeState;

  /// Sanitized, stable diagnostic code. Never a raw HTTP body or stack trace.
  final String? errorCode;

  /// Provisioning transaction id used to resume an in-flight setup.
  final String? provisioningTransactionId;

  /// Exact Supabase Auth redirect the provisioning Worker verified for this
  /// project's confirmation emails, once a backend reaches READY.
  ///
  /// The Worker records it so the app only ever asks Supabase to send a
  /// confirmation link back to a destination that project's own redirect allow
  /// list accepts. It is absent for a backend verified before this field
  /// existed, and the app then keeps its original scheme-based callback — which
  /// is why absence must never be reinterpreted as "the Worker landing page is
  /// configured".
  final String? authEmailConfirmationRedirect;

  /// True only after authoritative evidence that the user's Supabase project no
  /// longer exists (a 404 from Supabase for this exact project).
  ///
  /// Absence keeps the original meaning ("not known to be deleted"), so a
  /// profile written before this field existed is never reinterpreted. A
  /// transient network failure, outage, or rate limit never sets it: the local
  /// profile and every local Planner database stay exactly as they are, and the
  /// user chooses explicitly between setting up new cloud storage and staying
  /// offline-only. Nothing here deletes the old profile or its history.
  final bool remoteMissing;

  /// True when the user explicitly stopped using this provisioned backend
  /// without deleting it.
  ///
  /// A disconnected profile keeps the client-safe endpoint of the same
  /// user-owned project so reconnecting reuses the exact same local account
  /// database (and its completed Phase G baseline) instead of provisioning a
  /// different project. It is never resolved into a runtime backend while it is
  /// disabled: the Planner runs local-only and no Auth client is created.
  ///
  /// Only a READY profile may be disconnected, and disconnecting never removes
  /// the local Planner data or deletes the Supabase project.
  final bool connectionDisabled;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'format_version': plannerBackendProfileFormatVersion,
    'profile_id': profileId,
    'generation': generation,
    'state': state.wireName,
    if (resumeState != null) 'resume_state': resumeState!.wireName,
    if (errorCode != null) 'error_code': errorCode,
    if (projectRef != null) 'project_ref': projectRef,
    if (projectUrl != null) 'project_url': projectUrl,
    if (publishableKey != null) 'publishable_key': publishableKey,
    if (installationId != null) 'installation_id': installationId,
    if (compatibility != null) 'compatibility': compatibility!.toJson(),
    if (provisioningTransactionId != null)
      'provisioning_transaction_id': provisioningTransactionId,
    if (authEmailConfirmationRedirect != null)
      'auth_email_confirmation_redirect': authEmailConfirmationRedirect,
    if (remoteMissing) 'remote_missing': true,
    // Absent means "connected", so a document written before this field existed
    // keeps its exact original meaning.
    if (connectionDisabled) 'connection_disabled': true,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory BackendConnectionProfile.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['format_version'];
    if (formatVersion is! int) {
      throw const BackendProfileValidationException(
        'Backend profile format_version must be an integer.',
      );
    }
    if (formatVersion != plannerBackendProfileFormatVersion) {
      throw UnsupportedBackendProfileFormatException(formatVersion);
    }
    _rejectUnknownFields(json, const {
      'format_version',
      'profile_id',
      'generation',
      'state',
      'resume_state',
      'error_code',
      'project_ref',
      'project_url',
      'publishable_key',
      'installation_id',
      'compatibility',
      'provisioning_transaction_id',
      'auth_email_confirmation_redirect',
      'remote_missing',
      'connection_disabled',
      'created_at',
      'updated_at',
    }, 'Backend profile');

    final state = _requiredString(json, 'state');
    final parsedState = ProvisioningState.tryFromWireName(state);
    if (parsedState == null) {
      throw BackendProfileValidationException(
        'Backend profile state has an unsupported value: $state',
      );
    }

    final resumeState = _optionalString(json, 'resume_state');
    ProvisioningState? parsedResumeState;
    if (resumeState != null) {
      parsedResumeState = ProvisioningState.tryFromWireName(resumeState);
      if (parsedResumeState == null) {
        throw BackendProfileValidationException(
          'Backend profile resume_state has an unsupported value: '
          '$resumeState',
        );
      }
    }

    final rawCompatibility = json['compatibility'];
    BackendCompatibility? compatibility;
    if (rawCompatibility != null) {
      if (rawCompatibility is! Map<String, dynamic>) {
        throw const BackendProfileValidationException(
          'Backend profile compatibility must be an object.',
        );
      }
      compatibility = BackendCompatibility.fromJson(rawCompatibility);
    }

    return BackendConnectionProfile(
      profileId: _requiredString(json, 'profile_id'),
      generation: _requiredInt(json, 'generation'),
      state: parsedState,
      createdAt: _requiredTimestamp(json, 'created_at'),
      updatedAt: _requiredTimestamp(json, 'updated_at'),
      projectRef: _optionalString(json, 'project_ref'),
      projectUrl: _optionalString(json, 'project_url'),
      publishableKey: _optionalString(json, 'publishable_key'),
      installationId: _optionalString(json, 'installation_id'),
      compatibility: compatibility,
      resumeState: parsedResumeState,
      errorCode: _optionalString(json, 'error_code'),
      provisioningTransactionId: _optionalString(
        json,
        'provisioning_transaction_id',
      ),
      authEmailConfirmationRedirect: _optionalString(
        json,
        'auth_email_confirmation_redirect',
      ),
      remoteMissing: _optionalBool(json, 'remote_missing') ?? false,
      connectionDisabled: _optionalBool(json, 'connection_disabled') ?? false,
    );
  }

  /// Returns a copy with the provided fields replaced.
  ///
  /// Nullable fields use an internal sentinel: omit a field to keep it, or
  /// pass `null` explicitly to clear it.
  BackendConnectionProfile copyWith({
    String? profileId,
    int? generation,
    ProvisioningState? state,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? projectRef = _unset,
    Object? projectUrl = _unset,
    Object? publishableKey = _unset,
    Object? installationId = _unset,
    Object? compatibility = _unset,
    Object? resumeState = _unset,
    Object? errorCode = _unset,
    Object? provisioningTransactionId = _unset,
    Object? authEmailConfirmationRedirect = _unset,
    bool? remoteMissing,
    bool? connectionDisabled,
  }) => BackendConnectionProfile(
    profileId: profileId ?? this.profileId,
    generation: generation ?? this.generation,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    projectRef: identical(projectRef, _unset)
        ? this.projectRef
        : projectRef as String?,
    projectUrl: identical(projectUrl, _unset)
        ? this.projectUrl
        : projectUrl as String?,
    publishableKey: identical(publishableKey, _unset)
        ? this.publishableKey
        : publishableKey as String?,
    installationId: identical(installationId, _unset)
        ? this.installationId
        : installationId as String?,
    compatibility: identical(compatibility, _unset)
        ? this.compatibility
        : compatibility as BackendCompatibility?,
    resumeState: identical(resumeState, _unset)
        ? this.resumeState
        : resumeState as ProvisioningState?,
    errorCode: identical(errorCode, _unset)
        ? this.errorCode
        : errorCode as String?,
    provisioningTransactionId: identical(provisioningTransactionId, _unset)
        ? this.provisioningTransactionId
        : provisioningTransactionId as String?,
    authEmailConfirmationRedirect:
        identical(authEmailConfirmationRedirect, _unset)
        ? this.authEmailConfirmationRedirect
        : authEmailConfirmationRedirect as String?,
    remoteMissing: remoteMissing ?? this.remoteMissing,
    connectionDisabled: connectionDisabled ?? this.connectionDisabled,
  );

  /// True when this profile describes a READY user-owned backend that the user
  /// explicitly stopped using, and which can therefore be reconnected without
  /// provisioning anything new.
  bool get canReconnect =>
      connectionDisabled && state == ProvisioningState.ready;

  /// Validates that [next] may replace this profile in durable storage.
  ///
  /// Enforces a strictly increasing generation, immutable project identity for
  /// the same connection, and only transitions the Worker itself can produce.
  /// A different [profileId] is a different provisioning attempt (or a
  /// re-discovered connection), so it needs no state continuity — only a
  /// newer generation.
  void validateReplacement(BackendConnectionProfile next) {
    if (next.generation <= generation) {
      throw BackendProfileValidationException(
        'Backend profile generation must increase (stored $generation, '
        'got ${next.generation}).',
      );
    }
    if (next.profileId != profileId) return;
    if (!state.canTransitionTo(next.state)) {
      throw ProvisioningStateTransitionException(from: state, to: next.state);
    }
    final storedRef = projectRef;
    final nextRef = next.projectRef;
    if (storedRef != null && nextRef != null && storedRef != nextRef) {
      throw BackendProfileValidationException(
        'Backend profile $profileId cannot change its project ref; start a '
        'new profile instead.',
      );
    }
  }

  void _validate() {
    _requireMatch(
      profileId,
      RegExp(r'^[A-Za-z0-9_-]{1,64}$'),
      'profileId',
      'a short identifier of letters, digits, dashes or underscores',
    );
    if (generation < 1) {
      throw const BackendProfileValidationException(
        'Backend profile generation must be at least 1.',
      );
    }
    if (updatedAt.isBefore(createdAt)) {
      throw const BackendProfileValidationException(
        'Backend profile updatedAt cannot be earlier than createdAt.',
      );
    }

    final ref = projectRef;
    if (ref != null) {
      _requireMatch(
        ref,
        RegExp(r'^[a-z]{20}$'),
        'projectRef',
        'a 20-character lowercase Supabase project ref',
      );
    }

    final url = projectUrl;
    if (url != null) {
      if (ref == null) {
        throw const BackendProfileValidationException(
          'Backend profile projectUrl requires a projectRef.',
        );
      }
      _validateProjectUrl(url, ref);
    }

    final key = publishableKey;
    if (key != null) {
      _requireMatch(
        key,
        RegExp(r'^sb_publishable_[A-Za-z0-9_-]{16,256}$'),
        'publishableKey',
        'a Supabase publishable key (sb_publishable_...)',
      );
    }

    final installation = installationId;
    if (installation != null) {
      _requireMatch(
        installation,
        RegExp(r'^[A-Za-z0-9_-]{8,64}$'),
        'installationId',
        'an opaque installation identifier',
      );
    }

    final resume = resumeState;
    if (resume != null) {
      if (!resume.isWorkerReported) {
        throw const BackendProfileValidationException(
          'Backend profile resumeState must be a Worker-reported state.',
        );
      }
      if (resume.isTerminal || resume.isReady) {
        throw const BackendProfileValidationException(
          'Backend profile resumeState must be a resumable Worker state.',
        );
      }
    }

    final code = errorCode;
    if (code != null) {
      _requireMatch(
        code,
        RegExp(r'^[a-z][a-z0-9_]{2,47}$'),
        'errorCode',
        'a sanitized lowercase diagnostic code',
      );
    }

    final transaction = provisioningTransactionId;
    if (transaction != null) {
      _requireMatch(
        transaction,
        RegExp(r'^[a-f0-9]{32}$'),
        'provisioningTransactionId',
        'a 32-character lowercase hexadecimal transaction id',
      );
    }

    final confirmationRedirect = authEmailConfirmationRedirect;
    if (confirmationRedirect != null) {
      // Only the exact https landing page the Worker verified may be persisted:
      // it is sent to Supabase Auth as `emailRedirectTo`, so a value that is
      // not a plain https URL could redirect a confirmation link elsewhere.
      final parsed = Uri.tryParse(confirmationRedirect);
      if (confirmationRedirect.length > 256 ||
          confirmationRedirect.contains(',') ||
          parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty ||
          parsed.hasFragment) {
        throw const BackendProfileValidationException(
          'Backend profile authEmailConfirmationRedirect must be a plain '
          'https URL.',
        );
      }
    }

    for (final entry in <(String, String?)>[
      ('profileId', profileId),
      ('projectRef', ref),
      ('projectUrl', url),
      ('publishableKey', key),
      ('installationId', installation),
      ('resumeState', resume?.wireName),
      ('errorCode', code),
      ('provisioningTransactionId', transaction),
    ]) {
      final value = entry.$2;
      if (value != null) _rejectCredentialShape(entry.$1, value);
    }

    if (state == ProvisioningState.localOnly) {
      if (ref != null ||
          url != null ||
          key != null ||
          installation != null ||
          compatibility != null ||
          resume != null ||
          code != null ||
          transaction != null) {
        throw const BackendProfileValidationException(
          'A local-only backend profile must not carry backend or '
          'provisioning data.',
        );
      }
    }
    if (state == ProvisioningState.ready) {
      if (ref == null || url == null || key == null) {
        throw const BackendProfileValidationException(
          'A ready backend profile requires projectRef, projectUrl and '
          'publishableKey.',
        );
      }
    }
    // A disconnected profile is a *remembered* backend: it keeps the complete
    // client-safe endpoint so reconnecting reuses the same project, which is
    // only meaningful for a verified backend.
    if (connectionDisabled && state != ProvisioningState.ready) {
      throw const BackendProfileValidationException(
        'Only a ready backend profile can be disconnected.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BackendConnectionProfile &&
      other.profileId == profileId &&
      other.generation == generation &&
      other.state == state &&
      other.projectRef == projectRef &&
      other.projectUrl == projectUrl &&
      other.publishableKey == publishableKey &&
      other.installationId == installationId &&
      other.compatibility == compatibility &&
      other.resumeState == resumeState &&
      other.errorCode == errorCode &&
      other.provisioningTransactionId == provisioningTransactionId &&
      other.connectionDisabled == connectionDisabled &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    profileId,
    generation,
    state,
    projectRef,
    projectUrl,
    publishableKey,
    installationId,
    compatibility,
    resumeState,
    errorCode,
    provisioningTransactionId,
    connectionDisabled,
    createdAt,
    updatedAt,
  );

  /// Intentionally omits [publishableKey]: it is client-safe, but it has no
  /// business being echoed into diagnostics.
  @override
  String toString() =>
      'BackendConnectionProfile(profileId: $profileId, '
      'generation: $generation, state: ${state.wireName}'
      '${projectRef == null ? '' : ', projectRef: $projectRef'})';
}

const Object _unset = Object();

const Set<String> _forbiddenCredentialMarkers = {
  'sb_secret_',
  'sbp_',
  'sba_',
  'service_role',
  'supabase_service',
  'access_token',
  'refresh_token',
  'private key',
  'begin rsa',
  'begin openssh',
};

final RegExp _jwtShape = RegExp(
  r'^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$',
  caseSensitive: false,
);

/// Secondary safeguard only. The primary protection is that this model has no
/// field capable of holding a Management credential, a database password, or a
/// session token.
void _rejectCredentialShape(String field, String value) {
  final lowered = value.toLowerCase();
  for (final marker in _forbiddenCredentialMarkers) {
    if (lowered.contains(marker)) {
      throw BackendProfileValidationException(
        '$field must not contain credential material.',
      );
    }
  }
  if (_jwtShape.hasMatch(value)) {
    throw BackendProfileValidationException('$field must not contain a token.');
  }
}

void _validateProjectUrl(String url, String projectRef) {
  if (url.contains('PASTE_')) {
    throw const BackendProfileValidationException(
      'Backend profile projectUrl must not be a placeholder.',
    );
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const BackendProfileValidationException(
      'Backend profile projectUrl must be a plain https project URL.',
    );
  }
  if (uri.host != '$projectRef.supabase.co') {
    throw const BackendProfileValidationException(
      'Backend profile projectUrl must be https://<projectRef>.supabase.co '
      'for its projectRef.',
    );
  }
}

void _requireMatch(
  String value,
  RegExp pattern,
  String field,
  String description,
) {
  if (!pattern.hasMatch(value)) {
    throw BackendProfileValidationException(
      'Backend profile $field must be $description.',
    );
  }
}

void _rejectUnknownFields(
  Map<String, dynamic> json,
  Set<String> allowed,
  String context,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw BackendProfileValidationException(
        '$context contains unsupported field: $key',
      );
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw BackendProfileValidationException(
      'Backend profile $key must be a string.',
    );
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw BackendProfileValidationException(
      'Backend profile $key must be a string.',
    );
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw BackendProfileValidationException(
      'Backend profile $key must be an integer.',
    );
  }
  return value;
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) {
    throw BackendProfileValidationException(
      'Backend profile $key must be a boolean.',
    );
  }
  return value;
}

DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw BackendProfileValidationException(
      'Backend profile $key must be an ISO-8601 timestamp.',
    );
  }
  return parsed;
}
