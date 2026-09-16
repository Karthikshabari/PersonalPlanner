import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_planner/features/sync/data/connection_profile_store.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

const _projectRef = 'abcdefghijklmnopqrst';
const _projectUrl = 'https://abcdefghijklmnopqrst.supabase.co';
const _publishableKey = 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu';
const _transactionId = '0123456789abcdef0123456789abcdef';

final _createdAt = DateTime.utc(2026, 9, 16, 12);

BackendConnectionProfile _profile({
  String profileId = 'profile-a',
  int generation = 1,
  ProvisioningState state = ProvisioningState.authorizationPending,
  String? projectRef,
  String? installationId,
  String? errorCode,
}) => BackendConnectionProfile(
  profileId: profileId,
  generation: generation,
  state: state,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  projectRef: projectRef,
  projectUrl: projectRef == null ? null : 'https://$projectRef.supabase.co',
  publishableKey: state == ProvisioningState.ready ? _publishableKey : null,
  installationId: installationId,
  compatibility: state == ProvisioningState.ready
      ? BackendCompatibility(protocolVersion: 2, payloadVersions: const [1, 2])
      : null,
  provisioningTransactionId: _transactionId,
  errorCode: errorCode,
);

void main() {
  late Directory directory;
  late ConnectionProfileStore store;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('planner_profile_');
    store = ConnectionProfileStore(directory: directory);
    file = File(p.join(directory.path, plannerBackendProfileFileName));
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  test('missing document reads as no profile', () async {
    expect(await store.read(), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('writes and reads the profile back', () async {
    final profile = _profile();

    await store.save(profile);

    expect(file.existsSync(), isTrue);
    expect(await store.read(), equals(profile));

    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['format_version'], plannerBackendProfileFormatVersion);
    expect(decoded['state'], 'authorization_pending');
  });

  test('requires the stored generation to update', () async {
    await store.save(_profile());

    final second = _profile(
      generation: 2,
      state: ProvisioningState.organizationSelected,
    );
    await store.save(second, expectedGeneration: 1);
    expect((await store.read())!.generation, 2);

    expect(
      () => store.save(second, expectedGeneration: 1),
      throwsA(isA<StaleConnectionProfileException>()),
    );
    expect(
      () => store.save(_profile(generation: 3)),
      throwsA(isA<StaleConnectionProfileException>()),
    );
    expect(
      () => store.save(_profile(generation: 3), expectedGeneration: 9),
      throwsA(isA<StaleConnectionProfileException>()),
    );

    // The stale writes above must not have touched the stored profile.
    expect((await store.read())!.generation, 2);
    expect((await store.read())!.state, ProvisioningState.organizationSelected);
  });

  test('rejects a write that does not advance the generation', () async {
    final stored = _profile(generation: 2);
    await store.save(_profile(generation: 1));
    await store.save(stored, expectedGeneration: 1);

    expect(
      () => store.save(_profile(generation: 2), expectedGeneration: 2),
      throwsA(isA<BackendProfileValidationException>()),
    );
    expect((await store.read())!.generation, 2);
    expect((await store.read())!.state, ProvisioningState.authorizationPending);
  });

  test(
    'rejects an illegal state transition and keeps the previous profile',
    () async {
      await store.save(_profile());

      final illegal = _profile(
        generation: 2,
        state: ProvisioningState.verifying,
        projectRef: _projectRef,
        installationId: 'installation-0001',
      );
      expect(
        () => store.save(illegal, expectedGeneration: 1),
        throwsA(isA<ProvisioningStateTransitionException>()),
      );

      final stored = (await store.read())!;
      expect(stored.generation, 1);
      expect(stored.state, ProvisioningState.authorizationPending);
    },
  );

  test('walks the full Worker lifecycle one generation at a time', () async {
    const path = <(ProvisioningState, String?)>[
      (ProvisioningState.authorizationPending, null),
      (ProvisioningState.organizationSelected, null),
      (ProvisioningState.projectCreating, null),
      (ProvisioningState.projectReconciliationRequired, null),
      (ProvisioningState.projectRetryAuthorized, null),
      (ProvisioningState.projectCreating, null),
      (ProvisioningState.projectWaiting, _projectRef),
      (ProvisioningState.migrating, _projectRef),
      (ProvisioningState.migrationReconciliationRequired, _projectRef),
      (ProvisioningState.migrating, _projectRef),
      (ProvisioningState.verifying, _projectRef),
      (ProvisioningState.ready, _projectRef),
    ];

    BackendConnectionProfile? latest;
    for (var index = 0; index < path.length; index += 1) {
      final (state, projectRef) = path[index];
      final generation = index + 1;
      latest = await store.save(
        _profile(
          generation: generation,
          state: state,
          projectRef: projectRef,
          installationId: generation == path.length
              ? 'installation-0001'
              : null,
        ),
        expectedGeneration: index == 0 ? null : generation - 1,
      );
      final persisted = (await store.read())!;
      expect(persisted.state, state);
      expect(persisted.generation, generation);
    }

    expect(latest!.state, ProvisioningState.ready);
    final stored = (await store.read())!;
    expect(stored.state, ProvisioningState.ready);
    expect(stored.projectRef, _projectRef);
    expect(stored.projectUrl, _projectUrl);
    expect(stored.publishableKey, _publishableKey);
    expect(stored.installationId, 'installation-0001');
  });

  test('reports a corrupt document and only replaces it explicitly', () async {
    file.writeAsStringSync('{"format_version":1,"state":');

    await expectLater(
      store.read(),
      throwsA(
        isA<ConnectionProfileStoreException>().having(
          (error) => error.failure,
          'failure',
          ConnectionProfileStoreFailure.corrupt,
        ),
      ),
    );
    expect(
      () => store.save(_profile(), expectedGeneration: 1),
      throwsA(isA<ConnectionProfileStoreException>()),
    );

    await store.save(_profile(profileId: 'profile-b'));

    final stored = (await store.read())!;
    expect(stored.profileId, 'profile-b');
    expect(stored.generation, 1);
  });

  test('rejects documents that are valid JSON but not a profile', () async {
    for (final contents in <String>[
      '',
      'not json',
      '[]',
      '"profile"',
      '{"profile_id":"profile-a"}',
      '{"format_version":1,"profile_id":"profile-a","generation":1,'
          '"state":"not_a_state","created_at":"2026-09-16T12:00:00.000Z",'
          '"updated_at":"2026-09-16T12:00:00.000Z"}',
    ]) {
      file.writeAsStringSync(contents);
      await expectLater(
        store.read(),
        throwsA(isA<ConnectionProfileStoreException>()),
        reason: contents,
      );
    }
  });

  test('reports unsupported format versions instead of guessing', () async {
    final json = _profile().toJson()..['format_version'] = 99;
    file.writeAsStringSync(jsonEncode(json));

    await expectLater(
      store.read(),
      throwsA(
        isA<ConnectionProfileStoreException>().having(
          (error) => error.failure,
          'failure',
          ConnectionProfileStoreFailure.unsupportedVersion,
        ),
      ),
    );
    expect(
      () => store.save(_profile(), expectedGeneration: 1),
      throwsA(isA<ConnectionProfileStoreException>()),
    );
  });

  test('refuses documents larger than the accepted bound', () async {
    file.writeAsStringSync('x' * (plannerBackendProfileMaxBytes + 1));

    await expectLater(
      store.read(),
      throwsA(
        isA<ConnectionProfileStoreException>().having(
          (error) => error.failure,
          'failure',
          ConnectionProfileStoreFailure.tooLarge,
        ),
      ),
    );
  });

  test('ignores a leftover temporary file from an interrupted write', () async {
    final temporary = File('${file.path}$plannerBackendProfileTemporarySuffix');
    final profile = _profile();
    await store.save(profile);

    // A crash between the temporary write and the rename leaves the previous
    // profile authoritative.
    temporary.writeAsStringSync('{"format_version":1,"state":');
    expect(await store.read(), equals(profile));

    // A crash on the very first write leaves no profile at all, and the torn
    // temporary file is never promoted.
    file.deleteSync();
    expect(await store.read(), isNull);

    final recovered = await store.save(_profile(generation: 2));
    expect(recovered.generation, 2);
    expect(await store.read(), equals(recovered));
  });

  test('keeps the serialized profile bounded and client-safe', () async {
    final longKey = 'sb_publishable_${'a' * 256}';
    final profile = BackendConnectionProfile(
      profileId: 'p' * 64,
      generation: 1,
      state: ProvisioningState.ready,
      createdAt: _createdAt,
      updatedAt: _createdAt,
      projectRef: _projectRef,
      projectUrl: _projectUrl,
      publishableKey: longKey,
      installationId: 'i' * 64,
      compatibility: BackendCompatibility(
        protocolVersion: 2,
        payloadVersions: const [1, 2],
      ),
      provisioningTransactionId: _transactionId,
    );

    await store.save(profile);

    final text = file.readAsStringSync();
    expect(text.length, lessThan(plannerBackendProfileMaxBytes));
    expect(await store.read(), equals(profile));
  });

  test('never persists secret-shaped material', () async {
    expect(
      () => _profile(profileId: 'sb_secret_abcdefghijklmnopqrst'),
      throwsA(isA<BackendProfileValidationException>()),
    );
    expect(
      () => BackendConnectionProfile(
        profileId: 'profile-a',
        generation: 1,
        state: ProvisioningState.ready,
        createdAt: _createdAt,
        updatedAt: _createdAt,
        projectRef: _projectRef,
        projectUrl: _projectUrl,
        publishableKey: 'sb_secret_abcdefghijklmnopqrstuvwxyz',
      ),
      throwsA(isA<BackendProfileValidationException>()),
    );

    await store.save(_profile(errorCode: 'project_creation_failed'));

    final text = file.readAsStringSync().toLowerCase();
    expect(text, isNot(contains('sb_secret_')));
    expect(text, isNot(contains('service_role')));
    expect(text, isNot(contains('password')));
    expect(text, isNot(contains('eyj')));
    expect(text, isNot(contains('management')));
  });

  test(
    'allows a different profile identity to replace the connection',
    () async {
      await store.save(_profile());
      final replacement = _profile(
        profileId: 'profile-b',
        generation: 2,
        state: ProvisioningState.ready,
        projectRef: _projectRef,
      );

      await store.save(replacement, expectedGeneration: 1);

      expect(await store.read(), equals(replacement));
    },
  );
}
