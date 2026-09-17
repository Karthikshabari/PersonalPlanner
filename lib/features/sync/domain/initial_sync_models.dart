import 'dart:convert';

/// Durable phase of the Phase G first synchronization of one provisioned
/// account.
///
/// The phase is stored in the account-scoped local database, so it is
/// automatically scoped to the canonical `(projectRef, authUserId)` identity:
/// Project A / user X and Project B / user X cannot observe each other's
/// first-sync state.
enum InitialSyncPhase {
  /// Nothing has been determined yet, or the account has not tried.
  unresolved,

  /// Remote discovery is running. A crash here simply re-runs discovery.
  discovering,

  /// Remote Planner data exists. It must be restored locally before any local
  /// mutation may be pushed.
  remoteExisting,

  /// The remote-first restore (pull to the durable cursor) is running.
  restoring,

  /// The remote account is provably unused: no change rows, no live rows and no
  /// tombstones. Local adoption may be considered.
  remoteEmpty,

  /// The remote is empty and meaningful offline-only (anonymous) Planner data
  /// exists. Only an explicit user confirmation may import it.
  adoptionRequired,

  /// Local Planner data (already in this account database, or imported from
  /// anonymous storage) is waiting to be uploaded.
  uploading,

  /// Local and remote both contain meaningful Planner data, or another device
  /// is establishing the baseline. Nothing is pushed or pulled automatically.
  conflict,

  /// Discovery, restore or upload failed in a way that can be retried. The
  /// remote state stays explicitly unknown; it is never treated as empty.
  retryable,

  /// A safe baseline exists. Normal provisioned synchronization may run.
  complete;

  String get wireValue => switch (this) {
    InitialSyncPhase.unresolved => 'unresolved',
    InitialSyncPhase.discovering => 'discovering',
    InitialSyncPhase.remoteExisting => 'remote_existing',
    InitialSyncPhase.restoring => 'restoring',
    InitialSyncPhase.remoteEmpty => 'remote_empty',
    InitialSyncPhase.adoptionRequired => 'adoption_required',
    InitialSyncPhase.uploading => 'uploading',
    InitialSyncPhase.conflict => 'conflict',
    InitialSyncPhase.retryable => 'retryable',
    InitialSyncPhase.complete => 'complete',
  };

  static InitialSyncPhase? tryParse(Object? value) {
    for (final phase in InitialSyncPhase.values) {
      if (phase.wireValue == value?.toString()) return phase;
    }
    return null;
  }

  /// True while this phase describes work in progress. A crash in a transient
  /// phase is recovered by re-running discovery, which is authoritative.
  bool get isTransient =>
      this == InitialSyncPhase.discovering ||
      this == InitialSyncPhase.restoring ||
      this == InitialSyncPhase.uploading;

  /// The one condition that unlocks normal provisioned synchronization.
  bool get baselineComplete => this == InitialSyncPhase.complete;
}

/// Durable first-sync state of the account database currently open.
class InitialSyncRecord {
  const InitialSyncRecord({
    required this.phase,
    this.claimToken,
    this.observedBaselineChangeId,
    this.detail,
    this.updatedAt,
  });

  static const InitialSyncRecord initial = InitialSyncRecord(
    phase: InitialSyncPhase.unresolved,
  );

  final InitialSyncPhase phase;

  /// Local record of the baseline claim this client holds. Never a credential:
  /// it only identifies this device's own claim on the server.
  final String? claimToken;

  /// `sync_state.next_change_id` observed when the claim was created. The
  /// server re-checks it atomically before the claim is granted.
  final int? observedBaselineChangeId;

  /// Small diagnostic payload for the user-facing state (counts and reasons).
  final Map<String, dynamic>? detail;

  final DateTime? updatedAt;

  bool get baselineComplete => phase.baselineComplete;

  InitialSyncRecord copyWith({
    InitialSyncPhase? phase,
    String? claimToken,
    bool clearClaimToken = false,
    int? observedBaselineChangeId,
    Map<String, dynamic>? detail,
    bool clearDetail = false,
    DateTime? updatedAt,
  }) => InitialSyncRecord(
    phase: phase ?? this.phase,
    claimToken: clearClaimToken ? null : (claimToken ?? this.claimToken),
    observedBaselineChangeId: clearClaimToken
        ? null
        : (observedBaselineChangeId ?? this.observedBaselineChangeId),
    detail: clearDetail ? null : (detail ?? this.detail),
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// One remote row-count snapshot used to explain a remote state to the user.
class RemoteAccountSummary {
  const RemoteAccountSummary({
    required this.hasHistory,
    required this.nextChangeId,
    required this.changeCount,
    required this.liveRowTotal,
    required this.tombstonedRowTotal,
  });

  final bool hasHistory;
  final int nextChangeId;
  final int changeCount;
  final int liveRowTotal;
  final int tombstonedRowTotal;
}

/// Local Planner content measured before any first-sync decision.
class LocalDataSummary {
  const LocalDataSummary({
    required this.liveRecords,
    required this.tombstonedRecords,
    required this.pendingOperations,
  });

  static const LocalDataSummary empty = LocalDataSummary(
    liveRecords: 0,
    tombstonedRecords: 0,
    pendingOperations: 0,
  );

  /// User-authored live rows. Untouched built-in default categories are not
  /// counted, so a freshly seeded database is still "empty".
  final int liveRecords;

  /// Soft-deleted rows. Deletion intent is durable evidence and is therefore
  /// counted as meaningful for conflict detection.
  final int tombstonedRecords;

  /// Durable outbox entries that have not been acknowledged yet.
  final int pendingOperations;

  bool get hasMeaningfulData =>
      liveRecords > 0 || tombstonedRecords > 0 || pendingOperations > 0;
}

/// Provider/UI view of the durable record, with tolerant detail decoding.
class InitialSyncStatus {
  const InitialSyncStatus({
    required this.phase,
    this.message,
    this.claimToken,
    this.observedBaselineChangeId,
    this.remote,
    this.local,
    this.updatedAt,
  });

  static const InitialSyncStatus notApplicable = InitialSyncStatus(
    phase: InitialSyncPhase.complete,
    message: 'This runtime backend does not use the provisioned setup path.',
  );

  static const InitialSyncStatus unresolved = InitialSyncStatus(
    phase: InitialSyncPhase.unresolved,
  );

  final InitialSyncPhase phase;
  final String? message;
  final String? claimToken;
  final int? observedBaselineChangeId;
  final RemoteAccountSummary? remote;
  final LocalDataSummary? local;
  final DateTime? updatedAt;

  bool get baselineComplete => phase.baselineComplete;

  static InitialSyncStatus fromRecord(InitialSyncRecord record) {
    final detail = record.detail ?? const <String, dynamic>{};
    return InitialSyncStatus(
      phase: record.phase,
      message: detail['message']?.toString(),
      claimToken: record.claimToken,
      observedBaselineChangeId: record.observedBaselineChangeId,
      remote: _remoteFromDetail(detail['remote']),
      local: _localFromDetail(detail['local']),
      updatedAt: record.updatedAt,
    );
  }

  static RemoteAccountSummary? _remoteFromDetail(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final nextChangeId = _int(map['next_change_id']);
    if (nextChangeId == null) return null;
    return RemoteAccountSummary(
      hasHistory: map['has_history'] == true,
      nextChangeId: nextChangeId,
      changeCount: _int(map['change_count']) ?? 0,
      liveRowTotal: _int(map['live_row_total']) ?? 0,
      tombstonedRowTotal: _int(map['tombstoned_row_total']) ?? 0,
    );
  }

  static LocalDataSummary? _localFromDetail(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return LocalDataSummary(
      liveRecords: _int(map['live_records']) ?? 0,
      tombstonedRecords: _int(map['tombstoned_records']) ?? 0,
      pendingOperations: _int(map['pending_operations']) ?? 0,
    );
  }

  static int? _int(Object? value) {
    if (value is num && value == value.toInt()) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// Authoritative server view of one provisioned account (Phase G discovery).
/// Server protocol state of the first synchronization baseline.
///
/// The server is the authority: [none] (nothing established yet),
/// [inProgress] (exactly one fenced claimant owns establishment) or
/// [completed] (a permanent establishment event, valid even with zero rows).
enum RemoteBaselineState {
  none,
  inProgress,
  completed;

  static RemoteBaselineState tryParse(Object? value) => switch (
    value?.toString()
  ) {
    'in_progress' => RemoteBaselineState.inProgress,
    'completed' => RemoteBaselineState.completed,
    _ => RemoteBaselineState.none,
  };
}

class RemoteAccountSnapshot {
  const RemoteAccountSnapshot({
    required this.hasHistory,
    required this.nextChangeId,
    required this.changeCount,
    required this.liveRowTotal,
    required this.tombstonedRowTotal,
    required this.baselineState,
    required this.established,
    this.claim,
  });

  final bool hasHistory;

  final RemoteBaselineState baselineState;

  /// True when the server considers this account already established: either a
  /// completed baseline (even with zero Planner rows) or durable pre-Phase-G
  /// Planner history. An in-progress first baseline is explicitly not
  /// established, so partial uploaded rows can never be mistaken for finished
  /// cloud data.
  final bool established;

  /// Monotonic baseline token: the next change id this account will allocate.
  ///
  /// Every accepted mutation, including tombstones, advances it, so an
  /// unchanged value proves nothing was applied since discovery.
  final int nextChangeId;
  final int changeCount;
  final int liveRowTotal;
  final int tombstonedRowTotal;
  final RemoteBaselineClaim? claim;

  factory RemoteAccountSnapshot.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid remote account state response');
    }
    final map = Map<String, dynamic>.from(raw);
    final hasHistory = map['has_history'];
    final nextChangeId = _requireInt(map, 'next_change_id');
    if (hasHistory is! bool) {
      throw const FormatException('Remote account state is missing history');
    }
    final baselineState = RemoteBaselineState.tryParse(map['baseline_state']);
    // `established` is server-authoritative. The local fallback keeps the rule
    // total for a response that does not carry the field.
    final established = map['established'] is bool
        ? map['established'] as bool
        : (baselineState == RemoteBaselineState.completed ||
              (baselineState == RemoteBaselineState.none && hasHistory));
    return RemoteAccountSnapshot(
      hasHistory: hasHistory,
      baselineState: baselineState,
      established: established,
      nextChangeId: nextChangeId,
      changeCount: _int(map['change_count']) ?? 0,
      liveRowTotal: _int(map['live_row_total']) ?? 0,
      tombstonedRowTotal: _int(map['tombstoned_row_total']) ?? 0,
      claim: RemoteBaselineClaim.tryFromJson(map['initial_baseline']),
    );
  }

  Map<String, dynamic> toDetailJson() => <String, dynamic>{
    'has_history': hasHistory,
    'baseline_state': baselineState.name,
    'established': established,
    'next_change_id': nextChangeId,
    'change_count': changeCount,
    'live_row_total': liveRowTotal,
    'tombstoned_row_total': tombstonedRowTotal,
  };

  static int _requireInt(Map<String, dynamic> map, String key) {
    final value = _int(map[key]);
    if (value == null) {
      throw FormatException('Remote account state is missing $key');
    }
    return value;
  }

  static int? _int(Object? value) {
    if (value is num && value == value.toInt()) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// The baseline claim currently recorded on the server for this account.
class RemoteBaselineClaim {
  const RemoteBaselineClaim({
    required this.token,
    this.observedNextChangeId,
    this.claimedAt,
    this.completedAt,
    this.expired = false,
    this.leaseExpiresAt,
  });

  final String token;
  final int? observedNextChangeId;
  final DateTime? claimedAt;
  final DateTime? completedAt;

  /// Server-computed: the lease lapsed while the baseline is still incomplete.
  /// The client never decides expiry from its own clock.
  final bool expired;
  final DateTime? leaseExpiresAt;

  bool get completed => completedAt != null;

  static RemoteBaselineClaim? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final token = map['token']?.toString();
    if (token == null || token.isEmpty) return null;
    return RemoteBaselineClaim(
      token: token,
      observedNextChangeId: RemoteAccountSnapshot._int(
        map['observed_next_change_id'],
      ),
      claimedAt: DateTime.tryParse('${map['claimed_at'] ?? ''}')?.toUtc(),
      completedAt: DateTime.tryParse('${map['completed_at'] ?? ''}')?.toUtc(),
      expired: map['expired'] == true,
      leaseExpiresAt: DateTime.tryParse(
        '${map['lease_expires_at'] ?? ''}',
      )?.toUtc(),
    );
  }
}

enum RemoteBaselineClaimStatus {
  claimed,

  /// The server recorded the claimed baseline as established.
  completed,

  /// The account already contains Planner data; the claim was not granted.
  remoteInUse,

  /// Another writer moved the account between discovery and the claim.
  baselineChanged,

  /// Another device currently holds the (unexpired) baseline claim.
  claimHeld,

  /// The server refuses to hand over an abandoned claim because the account
  /// already carries data that may belong to that unfinished first baseline.
  /// The client must surface needs-attention rather than merge or retry blindly.
  recoveryRequired,

  /// The server did not recognise the claim token at completion time.
  unknownClaim;
}

class RemoteBaselineClaimResult {
  const RemoteBaselineClaimResult({
    required this.status,
    required this.nextChangeId,
    this.claimToken,
  });

  final RemoteBaselineClaimStatus status;
  final int nextChangeId;
  final String? claimToken;

  factory RemoteBaselineClaimResult.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid baseline claim response');
    }
    final map = Map<String, dynamic>.from(raw);
    final status = switch (map['status']?.toString()) {
      'claimed' => RemoteBaselineClaimStatus.claimed,
      'completed' => RemoteBaselineClaimStatus.completed,
      'remote_in_use' => RemoteBaselineClaimStatus.remoteInUse,
      'baseline_changed' => RemoteBaselineClaimStatus.baselineChanged,
      'claim_held' => RemoteBaselineClaimStatus.claimHeld,
      'recovery_required' => RemoteBaselineClaimStatus.recoveryRequired,
      'unknown_claim' => RemoteBaselineClaimStatus.unknownClaim,
      final other => throw FormatException('Unknown baseline status: $other'),
    };
    return RemoteBaselineClaimResult(
      status: status,
      nextChangeId:
          RemoteAccountSnapshot._int(map['next_change_id']) ??
          RemoteAccountSnapshot._int(map['actual_next_change_id']) ??
          0,
      claimToken: map['claim_token']?.toString(),
    );
  }
}

/// Serializes the diagnostic detail written next to a durable phase.
String encodeInitialSyncDetail(Map<String, dynamic> detail) =>
    jsonEncode(detail);

Map<String, dynamic>? decodeInitialSyncDetail(String? source) {
  if (source == null || source.isEmpty) return null;
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
}
