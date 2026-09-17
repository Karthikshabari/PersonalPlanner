import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/sync/data/initial_sync_gateway.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A call observed at either remote boundary, in order, so a test can prove
/// what happened before what.
class RemoteCall {
  const RemoteCall(this.boundary, this.name, [this.detail]);

  final String boundary;
  final String name;
  final Object? detail;

  @override
  String toString() =>
      detail == null ? '$boundary.$name' : '$boundary.$name($detail)';
}

/// Server-accurate stand-in for the Phase G discovery/claim RPCs.
///
/// One instance represents one account on the server, so two "devices" in a
/// test share it exactly the way two clients of the same account share the real
/// RPCs: the same claim row, the same lease judgement and the same fencing.
class FakeInitialSyncGateway implements InitialSyncRemoteGateway {
  FakeInitialSyncGateway({
    required this.calls,
    this.hasHistory = false,
    this.nextChangeId = 1,
    this.changeCount = 0,
    this.liveRowTotal = 0,
    this.tombstonedRowTotal = 0,
    this.claimToken,
    this.claimCompleted = false,
  });

  final List<RemoteCall> calls;
  bool hasHistory;
  int nextChangeId;
  int changeCount;
  int liveRowTotal;
  int tombstonedRowTotal;

  /// Baseline claim currently recorded on the server, if any.
  String? claimToken;
  bool claimCompleted;
  DateTime? claimClaimedAt;

  /// Server-side judgement that the current claim's lease has lapsed. A test
  /// sets this the way real elapsed time would; the client never decides expiry
  /// from its own clock.
  bool leaseExpired = false;

  int stateCalls = 0;
  int claimCalls = 0;
  int completeCalls = 0;
  final List<({String token, int observed})> claims = [];
  final List<String> completions = [];

  /// Server-side Planner data and change feed of this account. They live here
  /// (not on a device's gateway) so two devices in a test contend for one
  /// account exactly like two clients of the same Supabase project.
  final List<Map<String, dynamic>> remoteChanges = <Map<String, dynamic>>[];
  int nextServerVersion = 1;
  int applyAttempts = 0;
  int appliedCount = 0;
  int rejectedMutations = 0;

  bool get baselineInProgress => claimToken != null && !claimCompleted;

  /// Simulated transport failures.
  Object? stateError;
  Object? claimError;
  Object? completeError;

  /// Blocks discovery until completed, so a test can observe a timeout.
  Completer<void>? stateGate;

  /// Status override for the next claim response. Defaults to the modelled
  /// server decision.
  String? claimStatusOverride;

  /// Runs while a discovery request is in flight, so a test can simulate an
  /// account switch or a concurrent remote writer.
  void Function()? onState;

  /// Runs while a claim request is in flight.
  void Function()? onClaim;

  /// Runs when the server is asked to complete the baseline, before the
  /// completion is recorded, so a test can assert what had been uploaded.
  void Function()? onComplete;

  /// Server-computed establishment: a completed baseline establishes the
  /// account even with zero Planner rows, and durable pre-Phase-G history
  /// establishes a legacy account. An in-progress first baseline is NOT
  /// established.
  bool get established =>
      claimCompleted || (claimToken == null && hasHistory);

  @override
  Future<Object?> accountState() async {
    stateCalls += 1;
    calls.add(const RemoteCall('initial', 'accountState'));
    onState?.call();
    final error = stateError;
    if (error != null) throw error;
    final gate = stateGate;
    if (gate != null) await gate.future;
    return <String, dynamic>{
      'has_history': hasHistory,
      'baseline_state': claimCompleted
          ? 'completed'
          : (claimToken == null ? 'none' : 'in_progress'),
      'established': established,
      'next_change_id': nextChangeId,
      'next_server_version': nextChangeId,
      'change_count': changeCount,
      'live_row_total': liveRowTotal,
      'tombstoned_row_total': tombstonedRowTotal,
      'live_rows': const <String, dynamic>{},
      'tombstoned_rows': const <String, dynamic>{},
      'initial_baseline': claimToken == null
          ? null
          : <String, dynamic>{
              'token': claimToken,
              'observed_next_change_id': 1,
              'claimed_at':
                  (claimClaimedAt ??
                          DateTime.now().toUtc().subtract(
                            leaseExpired
                                ? const Duration(hours: 1)
                                : const Duration(minutes: 1),
                          ))
                      .toIso8601String(),
              'completed_at': claimCompleted
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
              'expired': claimCompleted ? false : leaseExpired,
            },
    };
  }

  /// Mirrors the migration's claim decision order, including the takeover and
  /// recovery rules.
  @override
  Future<Object?> claimBaseline({
    required String claimToken,
    required int observedNextChangeId,
  }) async {
    claimCalls += 1;
    claims.add((token: claimToken, observed: observedNextChangeId));
    calls.add(RemoteCall('initial', 'claimBaseline', observedNextChangeId));
    onClaim?.call();
    final error = claimError;
    if (error != null) throw error;
    final override = claimStatusOverride;
    if (override != null) {
      claimStatusOverride = null;
      return <String, dynamic>{
        'status': override,
        'next_change_id': nextChangeId,
      };
    }
    // 1. Same token resumes and renews its own incomplete claim.
    if (this.claimToken == claimToken && !claimCompleted) {
      leaseExpired = false;
      return <String, dynamic>{
        'status': 'claimed',
        'next_change_id': nextChangeId,
        'claim_token': claimToken,
        'resumed': true,
      };
    }
    // 2. A completed baseline is permanent.
    if (this.claimToken != null && claimCompleted) {
      return <String, dynamic>{
        'status': 'remote_in_use',
        'baseline_state': 'completed',
        'next_change_id': nextChangeId,
      };
    }
    // 3./4. A foreign claim already owns establishment.
    if (this.claimToken != null) {
      if (!leaseExpired) {
        return <String, dynamic>{
          'status': 'claim_held',
          'next_change_id': nextChangeId,
          'claim_token': this.claimToken,
        };
      }
      if (hasHistory || nextChangeId != 1) {
        return <String, dynamic>{
          'status': 'recovery_required',
          'next_change_id': nextChangeId,
          'claim_token': this.claimToken,
        };
      }
      if (observedNextChangeId != nextChangeId) {
        return <String, dynamic>{
          'status': 'baseline_changed',
          'next_change_id': nextChangeId,
        };
      }
      this.claimToken = claimToken;
      claimClaimedAt = DateTime.now().toUtc();
      leaseExpired = false;
      return <String, dynamic>{
        'status': 'claimed',
        'next_change_id': nextChangeId,
        'claim_token': claimToken,
        'resumed': false,
        'took_over_expired_claim': true,
      };
    }
    // 5. Legacy established account, then the truly unused account.
    if (hasHistory) {
      return <String, dynamic>{
        'status': 'remote_in_use',
        'baseline_state': 'legacy',
        'next_change_id': nextChangeId,
      };
    }
    if (observedNextChangeId != nextChangeId) {
      return <String, dynamic>{
        'status': 'baseline_changed',
        'next_change_id': nextChangeId,
      };
    }
    this.claimToken = claimToken;
    claimCompleted = false;
    claimClaimedAt = DateTime.now().toUtc();
    leaseExpired = false;
    return <String, dynamic>{
      'status': 'claimed',
      'next_change_id': nextChangeId,
      'claim_token': claimToken,
      'resumed': false,
    };
  }

  @override
  Future<Object?> completeBaseline({required String claimToken}) async {
    completeCalls += 1;
    completions.add(claimToken);
    calls.add(const RemoteCall('initial', 'completeBaseline'));
    onComplete?.call();
    final error = completeError;
    if (error != null) throw error;
    if (this.claimToken != claimToken) {
      return const <String, dynamic>{'status': 'unknown_claim'};
    }
    claimCompleted = true;
    return <String, dynamic>{
      'status': 'completed',
      'next_change_id': nextChangeId,
    };
  }
}

/// Thrown by the fake mutation boundary when the server fences a caller that no
/// longer owns the in-progress initial baseline claim.
class FakeFencedMutationException implements Exception {
  const FakeFencedMutationException(this.message);

  final String message;

  @override
  String toString() => message;
}

const fakeFencedMutationMessage =
    'Initial baseline claim is no longer owned by this device';

const fakeNoActiveClaimMessage =
    'No active initial baseline claim: this account is being established by a '
    'fenced first synchronization';

/// Recording stand-in for the v1/v2 Planner data protocol.
///
/// [remoteChanges] are the rows the account already holds. Applied operations
/// are recorded and (optionally) echoed into the feed, exactly like the
/// append-only server change log.
class FakeSyncRemoteGateway implements SyncRemoteGateway {
  FakeSyncRemoteGateway({
    required this.calls,
    this.echoApplied = false,
    this.account,
  });

  final List<RemoteCall> calls;
  bool echoApplied;

  /// The shared server-side account this connection belongs to, when a test
  /// models two devices on one account. Null keeps the simple scripted mode.
  final FakeInitialSyncGateway? account;

  final List<Map<String, dynamic>> remoteChanges = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> appliedOperations = <Map<String, dynamic>>[];

  /// Server-side change feed served by pull (shared when a shared account is
  /// configured, so a second device can observe the first device's uploads).
  List<Map<String, dynamic>> get feed => account?.remoteChanges ?? remoteChanges;

  int capabilityCalls = 0;
  int applyCalls = 0;
  int pullCalls = 0;

  /// Mutations refused by the server-side fence (scripted mode; the shared
  /// account keeps its own counter).
  int rejectedMutations = 0;
  int appliedCount = 0;
  int _changeId = 0;
  int _serverVersion = 0;

  Object? capabilityError;
  Object? applyError;
  Object? pullError;

  /// When true, [applyError] is thrown *after* the server-side mutation and
  /// change-log entry happen: the exact "server applied, client never learned"
  /// crash shape.
  bool applyErrorAfterRecord = false;

  /// Runs before an apply is acknowledged, so a test can simulate a concurrent
  /// writer or an account switch.
  void Function()? onApply;

  /// Asynchronous variant of [onApply] for hooks that must await a server-side
  /// action (for example a competing claim) before the mutation is evaluated.
  Future<void> Function()? onApplyAsync;

  /// Runs while a pull request is in flight, so a test can create local Planner
  /// work during a remote-first restore.
  Future<void> Function()? onPull;

  void seedChanges(Iterable<Map<String, dynamic>> changes) {
    if (account != null) {
      final feed = account!.remoteChanges;
      for (final change in changes) {
        account!.nextServerVersion += 1;
        final payload = change['payload'] is Map
            ? Map<String, dynamic>.from(change['payload'] as Map)
            : <String, dynamic>{};
        payload['server_version'] = account!.nextServerVersion;
        feed.add(
          Map<String, dynamic>.from(change)
            ..['change_id'] = feed.length + 1
            ..['server_version'] = account!.nextServerVersion
            ..['payload'] = payload
            ..['server_timestamp'] = DateTime.now().toUtc().toIso8601String(),
        );
      }
      account!.hasHistory = true;
      account!.changeCount = feed.length;
      account!.nextChangeId = feed.length + 1;
      return;
    }
    for (final change in changes) {
      _changeId += 1;
      _serverVersion += 1;
      final payload = change['payload'] is Map
          ? Map<String, dynamic>.from(change['payload'] as Map)
          : <String, dynamic>{};
      payload['server_version'] = _serverVersion;
      remoteChanges.add(
        Map<String, dynamic>.from(change)
          ..['change_id'] = _changeId
          ..['server_version'] = _serverVersion
          ..['payload'] = payload
          ..['server_timestamp'] = DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  static int _changeIdOf(Map<String, dynamic> change) =>
      change['change_id'] is num
      ? (change['change_id'] as num).toInt()
      : 0;

  @override
  Future<Object?> getCapabilities() async {
    capabilityCalls += 1;
    calls.add(const RemoteCall('data', 'capabilities'));
    final error = capabilityError;
    if (error != null) throw error;
    return <String, dynamic>{
      'protocol_version': 2,
      'payload_versions': <int>[1, 2],
      'schedule_duration_projection': true,
      'inbox_content_version': true,
      'due_date': true,
      'plan_title_history': true,
      'manual_actual_source': true,
      'timer_state_machine': true,
      'day_contexts': true,
      'recurrence_removal_provenance': true,
      'initial_sync_baseline': true,
      'initial_sync_fencing': true,
    };
  }

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
    String? baselineToken,
  }) async {
    applyCalls += 1;
    calls.add(RemoteCall('data', 'apply', '$tableName/$recordId'));
    account?.applyAttempts += 1;
    onApply?.call();
    final asyncHook = onApplyAsync;
    if (asyncHook != null) await asyncHook();
    // Server-enforced fencing, mirroring the migration:
    //
    //  * a tokened call is the v3 entry point of the *in-progress* first
    //    baseline, so it is only accepted while this device still owns it - even
    //    after another claimant completed the baseline, a stale token can never
    //    mutate;
    //  * an untokened call is v1/v2 ordinary synchronization, which is refused
    //    while any first baseline is in progress.
    final shared = account;
    if (shared != null) {
      final inProgress = shared.baselineInProgress;
      if (baselineToken != null) {
        if (!inProgress || baselineToken != shared.claimToken) {
          shared.rejectedMutations += 1;
          throw const FakeFencedMutationException(fakeFencedMutationMessage);
        }
        // A verified mutation renews the claimant's lease (server clock).
        shared.leaseExpired = false;
        shared.hasHistory = true;
      } else if (inProgress) {
        shared.rejectedMutations += 1;
        throw const FakeFencedMutationException(fakeNoActiveClaimMessage);
      }
    }
    final error = applyError;
    if (error != null && !applyErrorAfterRecord) throw error;
    appliedOperations.add(<String, dynamic>{
      'operation_id': operationId,
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'payload_version': payloadVersion,
      'payload': payload,
    });
    _changeId += 1;
    _serverVersion += 1;
    final changeId = shared == null
        ? _changeId
        : shared.remoteChanges.length + 1;
    final serverVersion = shared != null
        ? (shared.nextServerVersion += 1)
        : _serverVersion;
    if (shared != null) {
      shared.appliedCount += 1;
    } else {
      appliedCount += 1;
    }
    if (echoApplied) {
      (shared?.remoteChanges ?? remoteChanges).add(<String, dynamic>{
        'change_id': changeId,
        'operation_id': operationId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'server_version': serverVersion,
        'server_timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      });
    }
    if (shared != null) {
      shared.changeCount = shared.remoteChanges.length;
      shared.nextChangeId = shared.remoteChanges.length + 1;
    }
    if (error != null) throw error;
    return <String, dynamic>{
      'status': 'applied',
      'server_version': serverVersion,
      'change_id': changeId,
      'server_timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// The historical `apply_sync_operation(uuid,text,text,text,bigint,jsonb)`
  /// entry point: an authenticated, untokened mutation path that must be fenced
  /// exactly like v2 while a first baseline is in progress.
  Future<Object?> applyLegacyV1Operation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
  }) => applyOperation(
    operationId: operationId,
    tableName: tableName,
    recordId: recordId,
    operation: operation,
    expectedServerVersion: expectedServerVersion,
    payload: payload,
    payloadVersion: 1,
  );

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async {
    pullCalls += 1;
    calls.add(RemoteCall('data', 'pull', afterChangeId));
    final hook = onPull;
    if (hook != null) await hook();
    final error = pullError;
    if (error != null) throw error;
    return feed
        .where((change) => _changeIdOf(change) > afterChangeId)
        .take(limit)
        .toList();
  }
}

/// Factory seam used by provider tests.
class FakeSyncRemoteFactory implements SyncRemoteFactory {
  FakeSyncRemoteFactory({
    required this.initialSyncGateway,
    required this.syncGateway,
  });

  final FakeInitialSyncGateway initialSyncGateway;
  final FakeSyncRemoteGateway syncGateway;
  int clientsCreated = 0;

  @override
  SyncRemoteGateway createSyncGateway(SupabaseClient client) => syncGateway;

  @override
  InitialSyncRemoteGateway createInitialSyncGateway(SupabaseClient client) {
    clientsCreated += 1;
    return initialSyncGateway;
  }
}

/// Opens fresh connections to one anonymous database file, so the coordinator
/// (which opens and closes the offline database) behaves like production.
class AnonymousDatabaseFixture {
  AnonymousDatabaseFixture._(this._file);

  static AnonymousDatabaseFixture create() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = Directory.systemTemp.createTempSync('pp_anon_');
    return AnonymousDatabaseFixture._(
      File('${directory.path}/personal_planner.sqlite3'),
    );
  }

  final File _file;

  Future<AppDatabase> open() async =>
      AppDatabase(
        NativeDatabase(
          _file,
          setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
        ),
      );

  /// Runs [action] against the anonymous database and closes it afterwards.
  Future<T> use<T>(Future<T> Function(AppDatabase db) action) async {
    final database = await open();
    try {
      return await action(database);
    } finally {
      await database.close();
    }
  }

  void delete() {
    try {
      _file.parent.deleteSync(recursive: true);
    } on FileSystemException {
      // The temporary directory is best-effort cleanup.
    }
  }
}

/// Inserts one Planner category directly, which the sync triggers turn into a
/// durable outbox insert — the same shape any user-authored local row has.
Future<void> insertLocalCategory(
  AppDatabase db, {
  required String id,
  required String name,
  DateTime? at,
}) async {
  final now = at ?? DateTime.utc(2026, 9, 1, 9);
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          name: name,
          colorHex: '#4285F4',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

/// Inserts one scheduled Planner task directly, producing a sync insert
/// operation with a real schedule (so payload validation accepts it).
Future<void> insertLocalTask(
  AppDatabase db, {
  required String id,
  required String title,
  String? categoryId,
  DateTime? at,
}) async {
  final now = at ?? DateTime.utc(2026, 9, 1, 9);
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          title: title,
          startTime: Value(now),
          endTime: Value(now.add(const Duration(hours: 1))),
          categoryId: Value(categoryId),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

/// Remote change fixture for a category row.
Map<String, dynamic> remoteCategoryChange({
  required String id,
  required String name,
  required int changeId,
  required int serverVersion,
  String colorHex = '#34A853',
  int sortOrder = 0,
}) => <String, dynamic>{
  'change_id': changeId,
  'operation_id': 'remote-op-category-$id',
  'table_name': 'categories',
  'record_id': id,
  'operation': 'insert',
  'server_version': serverVersion,
  'server_timestamp': DateTime.utc(2026, 9, 2, 9).toIso8601String(),
  'payload': <String, dynamic>{
    'id': id,
    'name': name,
    'color_hex': colorHex,
    'sort_order': sortOrder,
    'is_focus': 0,
    'created_at': DateTime.utc(2026, 9, 2, 8).toIso8601String(),
    'updated_at': DateTime.utc(2026, 9, 2, 8).toIso8601String(),
    'deleted_at': null,
    'server_version': serverVersion,
  },
};

/// Remote change fixture for a scheduled task row.
Map<String, dynamic> remoteTaskChange({
  required String id,
  required String title,
  required int changeId,
  required int serverVersion,
  String? categoryId,
}) {
  final start = DateTime.utc(2026, 9, 2, 10);
  return <String, dynamic>{
    'change_id': changeId,
    'operation_id': 'remote-op-task-$id',
    'table_name': 'tasks',
    'record_id': id,
    'operation': 'insert',
    'server_version': serverVersion,
    'server_timestamp': DateTime.utc(2026, 9, 2, 9).toIso8601String(),
    'payload': <String, dynamic>{
      'id': id,
      'title': title,
      'description': null,
      'start_time': start.toIso8601String(),
      'end_time': start.add(const Duration(hours: 1)).toIso8601String(),
      'estimated_duration_min': 60,
      'actual_duration_min': null,
      'manual_duration_adjustment_min': 0,
      'manual_actual_set': 0,
      'category_id': categoryId,
      'priority': 0,
      'status': 'planned',
      'notes': null,
      'recurring_rule_id': null,
      'recurrence_removal_reason': null,
      'rescheduled_from_id': null,
      'rescheduled_to_id': null,
      'is_inbox': 0,
      'inbox_content_version': 0,
      'due_date': null,
      'missed_at': null,
      'plan_title_history_json': '[]',
      'display_plan_change_id': null,
      'created_at': start.toIso8601String(),
      'updated_at': start.toIso8601String(),
      'deleted_at': null,
      'server_version': serverVersion,
    },
  };
}
