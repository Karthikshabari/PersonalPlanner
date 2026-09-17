import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/cloud_lifecycle_service.dart';
import 'package:personal_planner/features/sync/data/connection_profile_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_capability_store.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/cloud_connection_lifecycle.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';

import '../../helpers/runtime_auth_fakes.dart';

/// Phase H disconnect/reconnect semantics.
///
/// The point of these tests is the *ordering* and the *scope*: synchronization
/// is stopped before anything is cleared, only the active project's session is
/// touched, the local Planner database is never involved, and the remembered
/// endpoint survives so a reconnect reuses the same project.
void main() {
  late Directory directory;
  late ConnectionProfileStore profileStore;
  late _RecordingCapabilityStore capabilities;
  late FakeSecureKeyValueStore secure;
  late FakeRuntimeAuthClient client;
  late AuthRepository repository;
  late CloudLifecycleService service;
  late List<String> events;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('planner_lifecycle_');
    profileStore = ConnectionProfileStore(directory: directory);
    capabilities = _RecordingCapabilityStore();
    secure = FakeSecureKeyValueStore();
    client = FakeRuntimeAuthClient();
    repository = AuthRepository(client);
    events = <String>[];
    service = CloudLifecycleService(
      profileStore: profileStore,
      capabilityStore: capabilities,
      clock: () => runtimeAuthTestClock,
    );
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  Future<BackendConnectionProfile> storeReadyProfile({
    String projectRef = projectRefA,
    int generation = 3,
    String transactionId = '0123456789abcdef0123456789abcdef',
  }) async {
    final profile = BackendConnectionProfile(
      profileId: 'profile-1',
      generation: generation,
      state: ProvisioningState.ready,
      createdAt: runtimeAuthTestClock,
      updatedAt: runtimeAuthTestClock,
      projectRef: projectRef,
      projectUrl: 'https://$projectRef.supabase.co',
      publishableKey: publishableKeyA,
      provisioningTransactionId: transactionId,
    );
    await profileStore.save(profile);
    return profile;
  }

  test('disconnect stops sync before it clears the session and connection', () async {
    final profile = await storeReadyProfile();
    capabilities.values[profile.provisioningTransactionId!] = 'capability-value';
    final namespaces = RuntimeAuthNamespaces.forProject(projectRefA);
    secure.values[namespaces.sessionKey] = 'project-a-session';
    secure.values[RuntimeAuthNamespaces.forProject(projectRefB).sessionKey] =
        'project-b-session';

    final backend = testProvisionedBackend(projectRef: projectRefA);
    final result = await service.disconnect(
      backend: backend,
      stopSync: () async => events.add('stopSync'),
      authRepository: _RecordingAuthRepository(
        client,
        sessionStorage: SecureSupabaseLocalStorage(
          storage: secure,
          sessionKey: namespaces.sessionKey,
        ),
        onSignOut: () => events.add('signOut'),
      ),
    );

    expect(result.outcome, CloudLifecycleOutcome.completed);
    expect(events, ['stopSync', 'signOut']);
    expect(client.signOutCalls, 1);
    // Only this project's session was cleared; another project's namespace is
    // byte-for-byte untouched.
    expect(secure.values.containsKey(namespaces.sessionKey), isFalse);
    expect(
      secure.values[RuntimeAuthNamespaces.forProject(projectRefB).sessionKey],
      'project-b-session',
    );

    final stored = await profileStore.read();
    expect(stored?.connectionDisabled, isTrue);
    expect(stored?.generation, profile.generation + 1);
    // The remembered endpoint is fully preserved for a later reconnect.
    expect(stored?.projectRef, projectRefA);
    expect(stored?.publishableKey, publishableKeyA);
    expect(stored?.provisioningTransactionId, profile.provisioningTransactionId);
    // The finished attempt's provisioning capability is gone.
    expect(
      capabilities.values.containsKey(profile.provisioningTransactionId!),
      isFalse,
    );
    expect(capabilities.deleted, [profile.provisioningTransactionId]);
  });

  test('disconnect refuses a profile that belongs to another project', () async {
    await storeReadyProfile(projectRef: projectRefB);
    final namespaces = RuntimeAuthNamespaces.forProject(projectRefA);
    secure.values[namespaces.sessionKey] = 'project-a-session';

    final result = await service.disconnect(
      backend: testProvisionedBackend(projectRef: projectRefA),
      stopSync: () async => events.add('stopSync'),
      authRepository: _RecordingAuthRepository(
        client,
        sessionStorage: SecureSupabaseLocalStorage(
          storage: secure,
          sessionKey: namespaces.sessionKey,
        ),
        onSignOut: () => events.add('signOut'),
      ),
    );

    expect(result.outcome, CloudLifecycleOutcome.failed);
    // Nothing was half-severed: no stop, no sign-out, no session removal.
    expect(events, isEmpty);
    expect(secure.values[namespaces.sessionKey], 'project-a-session');
    expect((await profileStore.read())?.connectionDisabled, isFalse);
  });

  test('disconnect refuses to act on an unreadable stored profile', () async {
    final file = File(
      '${directory.path}/$plannerBackendProfileFileName',
    );
    await file.writeAsString('{not json');

    final result = await service.disconnect(
      backend: testProvisionedBackend(projectRef: projectRefA),
      stopSync: () async => events.add('stopSync'),
      authRepository: repository,
    );

    expect(result.outcome, CloudLifecycleOutcome.failed);
    expect(events, isEmpty);
  });

  test('reconnect re-enables the same remembered project only', () async {
    final profile = await storeReadyProfile();
    await profileStore.save(
      profile.copyWith(
        generation: profile.generation + 1,
        connectionDisabled: true,
      ),
      expectedGeneration: profile.generation,
    );

    final result = await service.reconnect(projectRef: projectRefB);
    expect(result.outcome, CloudLifecycleOutcome.notApplicable);
    expect((await profileStore.read())?.connectionDisabled, isTrue);

    final reconnected = await service.reconnect(projectRef: projectRefA);
    expect(reconnected.outcome, CloudLifecycleOutcome.completed);
    final stored = await profileStore.read();
    expect(stored?.connectionDisabled, isFalse);
    expect(stored?.projectRef, projectRefA);
    expect(stored?.generation, profile.generation + 2);
  });

  test('reconnecting an already connected backend changes nothing', () async {
    final profile = await storeReadyProfile();

    final result = await service.reconnect(projectRef: projectRefA);

    expect(result.outcome, CloudLifecycleOutcome.completed);
    expect((await profileStore.read())?.generation, profile.generation);
  });
}

class _RecordingAuthRepository extends AuthRepository {
  _RecordingAuthRepository(
    super.client, {
    super.sessionStorage,
    required this.onSignOut,
  });

  final void Function() onSignOut;

  @override
  Future<void> signOut() async {
    onSignOut();
    await super.signOut();
  }
}

class _RecordingCapabilityStore implements ProvisioningCapabilityStore {
  final Map<String, String> values = <String, String>{};
  final List<String> deleted = <String>[];

  @override
  Future<void> write({
    required String transactionId,
    required String capability,
  }) async {
    values[transactionId] = capability;
  }

  @override
  Future<String?> read({required String transactionId}) async =>
      values[transactionId];

  @override
  Future<void> delete({required String transactionId}) async {
    deleted.add(transactionId);
    values.remove(transactionId);
  }
}
