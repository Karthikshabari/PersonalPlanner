import 'dart:convert';

enum SyncEngineState {
  synced,
  syncing,
  pending,
  offline,
  conflict,
  error,
  partialSuccess,
  permanentFailure,
  authFailure,
  refreshPaused,
  backendUnavailable,
  invalidData,
  initialSyncPending,
  notConfigured,
}

extension SyncEngineStateLabel on SyncEngineState {
  String get label => switch (this) {
    SyncEngineState.synced => 'Synced',
    SyncEngineState.syncing => 'Syncing',
    SyncEngineState.pending => 'Pending',
    SyncEngineState.offline => 'Offline',
    SyncEngineState.conflict => 'Conflict',
    SyncEngineState.error => 'Error',
    SyncEngineState.partialSuccess => 'Partially synced',
    SyncEngineState.permanentFailure => 'Action required',
    SyncEngineState.authFailure => 'Sign-in required',
    SyncEngineState.refreshPaused => 'Waiting for session refresh',
    SyncEngineState.backendUnavailable => 'Backend unavailable',
    SyncEngineState.invalidData => 'Invalid data',
    SyncEngineState.initialSyncPending => 'Cloud setup pending',
    SyncEngineState.notConfigured => 'Not configured',
  };
}

enum SyncFailureKind {
  retryable,
  permanent,
  authentication,

  /// The Planner's own cloud backend could not be reached *as this project*:
  /// the project host does not resolve, or the project answers that it does not
  /// exist. Distinct from a transient transport failure, and never a reason to
  /// modify stored configuration, local data, or the local outbox.
  backendUnavailable,
  invalidData,
}

class SyncFailure {
  final SyncFailureKind kind;
  final String message;

  const SyncFailure(this.kind, this.message);

  /// True when the failure describes the *environment* rather than the queued
  /// payload: a transport problem, or the account's own backend being
  /// unreachable.
  ///
  /// Such an operation must stay in the outbox with a backoff so it is retried
  /// when the backend comes back. It must never be parked as a permanent
  /// failure, which would ask the user to "repair" perfectly valid local data
  /// and would misreport a temporary outage as a data problem.
  bool get keepsOperationQueued =>
      kind == SyncFailureKind.retryable ||
      kind == SyncFailureKind.backendUnavailable;
}

class SyncCycleResult {
  final SyncFailure? pushFailure;
  final SyncFailure? pullFailure;

  const SyncCycleResult({this.pushFailure, this.pullFailure})
    : skipped = false;

  /// A cycle that was never run because the repository was already busy with
  /// another cycle.
  ///
  /// Nothing was pushed, nothing was pulled and no remote state was observed,
  /// so this must never be presented as a successful synchronization.
  const SyncCycleResult.skipped()
    : pushFailure = null,
      pullFailure = null,
      skipped = true;

  /// True when this result describes no work at all.
  final bool skipped;

  bool get succeeded => !skipped && pushFailure == null && pullFailure == null;

  SyncFailure? get firstFailure => pushFailure ?? pullFailure;
}

class SyncStatusSnapshot {
  final SyncEngineState state;
  final int pendingOperations;
  final int conflictCount;
  final DateTime? lastSuccessfulSync;
  final String? message;

  const SyncStatusSnapshot({
    required this.state,
    this.pendingOperations = 0,
    this.conflictCount = 0,
    this.lastSuccessfulSync,
    this.message,
  });

  SyncStatusSnapshot copyWith({
    SyncEngineState? state,
    int? pendingOperations,
    int? conflictCount,
    DateTime? lastSuccessfulSync,
    String? message,
  }) => SyncStatusSnapshot(
    state: state ?? this.state,
    pendingOperations: pendingOperations ?? this.pendingOperations,
    conflictCount: conflictCount ?? this.conflictCount,
    lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
    message: message ?? this.message,
  );
}

/// Safe identifying view of a remote change retained after validation failed.
/// The complete payload remains in local settings for a future repair tool.
class SyncQuarantinedChange {
  final String storageKey;
  final String accountId;
  final int changeId;
  final String diagnostic;
  final String? tableName;
  final String? recordId;
  final String? operation;
  final DateTime? recordedAt;

  const SyncQuarantinedChange({
    required this.storageKey,
    required this.accountId,
    required this.changeId,
    required this.diagnostic,
    this.tableName,
    this.recordId,
    this.operation,
    this.recordedAt,
  });

  factory SyncQuarantinedChange.fromSetting(String key, String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Invalid quarantine record');
    }
    final map = Map<String, dynamic>.from(decoded);
    final rawChange = map['raw_change'];
    final raw = rawChange is Map
        ? Map<String, dynamic>.from(rawChange)
        : const <String, dynamic>{};
    return SyncQuarantinedChange(
      storageKey: key,
      accountId: '${map['account_id'] ?? ''}',
      changeId: _intValue(map['change_id']),
      diagnostic: '${map['diagnostic'] ?? 'Remote change requires review.'}',
      tableName: raw['table_name']?.toString(),
      recordId: raw['record_id']?.toString(),
      operation: raw['operation']?.toString(),
      recordedAt: DateTime.tryParse('${map['recorded_at'] ?? ''}')?.toUtc(),
    );
  }

  static int _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class SyncRpcAcknowledgement {
  final String status;
  final int serverVersion;
  final int changeId;
  final DateTime serverTimestamp;
  final Map<String, dynamic>? remoteSnapshot;
  final int? actualServerVersion;

  const SyncRpcAcknowledgement({
    required this.status,
    required this.serverVersion,
    required this.changeId,
    required this.serverTimestamp,
    this.remoteSnapshot,
    this.actualServerVersion,
  });

  factory SyncRpcAcknowledgement.fromJson(Object? value) {
    final map = _map(value);
    final timestamp =
        DateTime.tryParse(
          '${map['server_timestamp'] ?? map['serverTimestamp'] ?? ''}',
        ) ??
        DateTime.now().toUtc();
    return SyncRpcAcknowledgement(
      status: '${map['status'] ?? 'error'}',
      serverVersion: _int(map['server_version'] ?? map['serverVersion']),
      changeId: _int(map['change_id'] ?? map['changeId']),
      serverTimestamp: timestamp.toUtc(),
      remoteSnapshot: map['remote_snapshot'] is Map
          ? Map<String, dynamic>.from(map['remote_snapshot'] as Map)
          : null,
      actualServerVersion: map['actual_server_version'] == null
          ? null
          : _int(map['actual_server_version']),
    );
  }
}

class SyncRemoteChange {
  final int changeId;
  final String operationId;
  final String tableName;
  final String recordId;
  final String operation;
  final int serverVersion;
  final DateTime serverTimestamp;
  final Map<String, dynamic> payload;

  const SyncRemoteChange({
    required this.changeId,
    required this.operationId,
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.serverVersion,
    required this.serverTimestamp,
    required this.payload,
  });

  factory SyncRemoteChange.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Sync change is not an object');
    }
    final map = Map<String, dynamic>.from(value);
    final rawPayload =
        map['payload'] ?? map['row_payload'] ?? <String, dynamic>{};
    final decodedPayload = rawPayload is String
        ? jsonDecode(rawPayload)
        : rawPayload;
    if (decodedPayload is! Map) {
      throw const FormatException('Sync payload is not an object');
    }
    final payload = Map<String, dynamic>.from(decodedPayload);
    return SyncRemoteChange(
      changeId: _int(map['change_id'] ?? map['changeId']),
      operationId: '${map['operation_id'] ?? map['operationId']}',
      tableName: '${map['table_name'] ?? map['tableName']}',
      recordId: '${map['record_id'] ?? map['recordId']}',
      operation: '${map['operation']}',
      serverVersion: _int(map['server_version'] ?? map['serverVersion']),
      serverTimestamp:
          (DateTime.tryParse(
                    '${map['server_timestamp'] ?? map['serverTimestamp'] ?? ''}',
                  ) ??
                  DateTime.now())
              .toUtc(),
      payload: payload,
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
