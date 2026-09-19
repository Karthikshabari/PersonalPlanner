import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/connection_profile_store.dart';
import 'package:personal_planner/features/sync/data/management_attempt_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_capability_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

/// Live check against the **deployed** provisioning Worker.
///
/// Skipped unless `PP_LIVE_WORKER=1` is set, because it needs network access to
/// the production control plane. It proves the path behind the "Re-authorize
/// Supabase" and "Disconnect Supabase access" buttons really reaches the
/// deployed Worker for a READY backend — the failure that manual testing caught,
/// where the post-READY credential was gone and the buttons did nothing.
///
/// It deliberately stops before the browser consent: approving Supabase
/// authorization requires the user's own browser session and must never be
/// automated on their behalf.
void main() {
  final live = Platform.environment['PP_LIVE_WORKER'] == '1';

  test(
    'the deployed Worker answers the post-READY management path',
    () async {
      final directory = await Directory.systemTemp.createTemp('pp-live-mgmt');
      addTearDown(() => directory.delete(recursive: true));
      final profileStore = ConnectionProfileStore(directory: directory);
      final attemptStore = ManagementAttemptStore(
        storage: _MemorySecureStore(),
      );
      final coordinator = ProvisioningCoordinator(
        profileStore: profileStore,
        capabilityStore: _MemoryCapabilityStore(),
        managementAttemptStore: attemptStore,
        client: ProvisioningClient.fromConfig(),
      );
      final now = DateTime.now().toUtc();
      await profileStore.save(
        BackendConnectionProfile(
          profileId: 'profile-live',
          generation: 1,
          state: ProvisioningState.ready,
          createdAt: now,
          updatedAt: now,
          projectRef: 'abcdefghijklmnopqrst',
          projectUrl: 'https://abcdefghijklmnopqrst.supabase.co',
          publishableKey: 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJM84zu',
          provisioningTransactionId: '0123456789abcdef0123456789abcdef',
        ),
        expectedGeneration: null,
      );

      // Pressing "Re-authorize Supabase" must reach the deployed Worker and
      // yield a real Supabase consent URL, even though the provisioning
      // capability of this attempt was destroyed when it reached READY.
      final started = await coordinator.startManagementCheck();
      expect(started.outcome, ManagementStartOutcome.authorizationReady);
      final url = started.authorizationUrl!;
      expect(url.host, 'api.supabase.com');
      expect(url.queryParameters['redirect_uri'], contains('/oauth/callback'));
      expect(url.queryParameters['state'], isNotNull);
      expect(await attemptStore.read(), isNotNull);

      // Without the browser consent the Worker must fail closed: no Management
      // credential exists, so nothing may be concluded about the project.
      final checked = await coordinator.completeManagementCheck();
      expect(checked.outcome, ManagementCheckOutcome.needsAuthorization);
      final profile = (await profileStore.read())!;
      expect(profile.remoteMissing, isFalse);
      expect(profile.state, ProvisioningState.ready);
      expect(profile.projectRef, 'abcdefghijklmnopqrst');

      // Pressing "Disconnect Supabase access" must report the truth rather than
      // a fake success.
      final revoked = await coordinator.revokeManagementAccess();
      expect(revoked.outcome, ManagementRevokeOutcome.nothingHeld);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: live
        ? false
        : 'set PP_LIVE_WORKER=1 to run the live deployed-Worker check',
  );
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<bool> containsKey({required String key}) async =>
      values.containsKey(key);

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;
}

class _MemoryCapabilityStore implements ProvisioningCapabilityStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({
    required String transactionId,
    required String capability,
  }) async => values[transactionId] = capability;

  @override
  Future<String?> read({required String transactionId}) async =>
      values[transactionId];

  @override
  Future<void> delete({required String transactionId}) async {
    values.remove(transactionId);
  }
}
