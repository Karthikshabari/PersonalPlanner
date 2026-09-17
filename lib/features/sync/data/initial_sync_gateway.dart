import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_repository.dart';

/// Remote boundary of the Phase G initial synchronization.
///
/// Kept separate from [SyncRemoteGateway] so the stable v1/v2 Planner data
/// protocol is untouched and existing gateways stay valid. Both are created
/// from the same scoped client, which is bound to one canonical
/// `(projectRef, authUserId)` account.
abstract interface class InitialSyncRemoteGateway {
  /// Authoritative discovery of this account's remote Planner state.
  Future<Object?> accountState();

  /// Atomic emptiness + baseline compare-and-set, plus the exclusive claim that
  /// serializes baseline establishment between devices.
  Future<Object?> claimBaseline({
    required String claimToken,
    required int observedNextChangeId,
  });

  /// Records that the claimed baseline is established.
  Future<Object?> completeBaseline({required String claimToken});
}

class SupabaseInitialSyncGateway implements InitialSyncRemoteGateway {
  SupabaseInitialSyncGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> accountState() =>
      _client.rpc('planner_sync_account_state');

  @override
  Future<Object?> claimBaseline({
    required String claimToken,
    required int observedNextChangeId,
  }) => _client.rpc(
    'planner_claim_initial_baseline',
    params: {
      'p_claim_token': claimToken,
      'p_observed_next_change_id': observedNextChangeId,
    },
  );

  @override
  Future<Object?> completeBaseline({required String claimToken}) => _client.rpc(
    'planner_complete_initial_baseline',
    params: {'p_claim_token': claimToken},
  );
}

/// Testable seam that turns one scoped [SupabaseClient] into the remote
/// gateways this app needs.
///
/// Production always uses [SupabaseSyncRemoteFactory]. Unit and widget tests
/// substitute recording fakes so the Phase G state machine can be exercised
/// deterministically without a network or a real hosted project.
abstract interface class SyncRemoteFactory {
  SyncRemoteGateway createSyncGateway(SupabaseClient client);

  InitialSyncRemoteGateway createInitialSyncGateway(SupabaseClient client);
}

class SupabaseSyncRemoteFactory implements SyncRemoteFactory {
  const SupabaseSyncRemoteFactory();

  @override
  SyncRemoteGateway createSyncGateway(SupabaseClient client) =>
      SupabaseSyncRemoteGateway(client);

  @override
  InitialSyncRemoteGateway createInitialSyncGateway(SupabaseClient client) =>
      SupabaseInitialSyncGateway(client);
}
