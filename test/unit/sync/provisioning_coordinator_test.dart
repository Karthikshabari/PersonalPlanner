import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_planner/features/sync/data/connection_profile_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_capability_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

const _projectRef = 'abcdefghijklmnopqrst';
const _publishableKey = 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu';
const _capability = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD';
const _projectName = 'personal-planner-safe-project';
const _transactionA = '0123456789abcdef0123456789abcdef';
const _transactionB = 'ffffffffffffffffffffffffffffffff';
const _transactionsPath = '/v1/provisioning/transactions';

String _snapshotPath(String transactionId) =>
    '/v1/provisioning/transactions/$transactionId';

class _FakeTransport implements ProvisioningTransport {
  final List<ProvisioningHttpRequest> requests = <ProvisioningHttpRequest>[];
  final Map<String, List<ProvisioningHttpResponse>> _responses = {};
  final Map<String, Object> _failures = {};
  final Set<String> _held = <String>{};
  final Map<String, Completer<void>> _gates = {};

  static String keyOf(String method, String path) => '$method $path';

  static String keyFor(ProvisioningHttpRequest request) =>
      keyOf(request.method, request.uri.path);

  void reply(String method, String path, Object body, {int status = 200}) {
    _responses
        .putIfAbsent(keyOf(method, path), () => <ProvisioningHttpResponse>[])
        .add(
          ProvisioningHttpResponse(
            statusCode: status,
            body: body is String ? body : jsonEncode(body),
          ),
        );
  }

  void fail(String method, String path, Object error) {
    _failures[keyOf(method, path)] = error;
  }

  void hold(String method, String path) {
    final key = keyOf(method, path);
    _held.add(key);
    _gates[key] = Completer<void>();
  }

  void release(String method, String path) {
    final key = keyOf(method, path);
    _held.remove(key);
    _gates.remove(key)?.complete();
  }

  List<String> get keys => requests.map(keyFor).toList();

  @override
  Future<ProvisioningHttpResponse> send(ProvisioningHttpRequest request) async {
    requests.add(request);
    final key = keyFor(request);
    final gate = _gates[key];
    if (_held.contains(key) && gate != null) await gate.future;
    final failure = _failures[key];
    if (failure != null) throw failure;
    final queue = _responses[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('unexpected provisioning request: $key');
    }
    if (queue.length > 1) return queue.removeAt(0);
    return queue.first;
  }
}

class _MemoryCapabilityStore implements ProvisioningCapabilityStore {
  final Map<String, String> values = <String, String>{};
  bool unavailable = false;

  @override
  Future<void> write({
    required String transactionId,
    required String capability,
  }) async {
    _guard();
    values[transactionId] = capability;
  }

  @override
  Future<String?> read({required String transactionId}) async {
    _guard();
    return values[transactionId];
  }

  @override
  Future<void> delete({required String transactionId}) async {
    _guard();
    values.remove(transactionId);
  }

  void _guard() {
    if (unavailable) {
      throw const ProvisioningCapabilityStoreException(
        ProvisioningCapabilityFailure.unavailable,
        'Secure storage is unavailable (StateError).',
      );
    }
  }
}

class _FailingProfileStore extends ConnectionProfileStore {
  _FailingProfileStore({required super.directory});

  bool failSaves = false;

  @override
  Future<BackendConnectionProfile> save(
    BackendConnectionProfile profile, {
    int? expectedGeneration,
  }) {
    if (failSaves) {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.writeFailed,
        'The backend profile could not be saved.',
      );
    }
    return super.save(profile, expectedGeneration: expectedGeneration);
  }
}

Map<String, dynamic> _snapshotBody(
  String state, {
  String? projectRef,
  String? error,
  Map<String, dynamic>? runtimeConfig,
}) => <String, dynamic>{
  'schema': 2,
  'state': state,
  'createdAt': 1,
  'updatedAt': 2,
  'expiresAt': 3600000,
  'createAttempts': 0,
  'expensiveAttempts': 0,
  'projectRef': ?projectRef,
  'error': ?error,
  'runtimeConfig': ?runtimeConfig,
};

Map<String, dynamic> _runtimeConfigBody() => <String, dynamic>{
  'projectRef': _projectRef,
  'projectUrl': 'https://$_projectRef.supabase.co',
  'publishableKey': _publishableKey,
};

Map<String, dynamic> _grantBody(String transactionId) => <String, dynamic>{
  'transactionId': transactionId,
  'accessToken': _capability,
  'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize?client_id=x',
  'expiresIn': 3600,
};

Future<void> _awaitRequests(_FakeTransport transport, int count) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (transport.requests.length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail(
    'expected $count provisioning request(s), saw ${transport.requests.length}',
  );
}

void main() {
  late Directory directory;
  late _FailingProfileStore profileStore;
  late _MemoryCapabilityStore capabilityStore;
  late _FakeTransport transport;
  late DateTime clock;
  var profileCounter = 0;
  var seedCounter = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('planner_provisioning_');
    profileStore = _FailingProfileStore(directory: directory);
    capabilityStore = _MemoryCapabilityStore();
    transport = _FakeTransport();
    clock = DateTime.utc(2026, 9, 16, 12);
    profileCounter = 0;
    seedCounter = 0;
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  ProvisioningCoordinator buildCoordinator() => ProvisioningCoordinator(
    profileStore: profileStore,
    capabilityStore: capabilityStore,
    client: ProvisioningClient(
      baseUrl: Uri.parse('https://worker.test'),
      transport: transport,
    ),
    profileIdFactory: () => 'profile-${++profileCounter}',
    clock: () => clock,
  );

  Future<BackendConnectionProfile> seedProfile({
    required ProvisioningState state,
    String transactionId = _transactionA,
    bool withCapability = true,
    bool withProject = false,
  }) async {
    final existing = await profileStore.read();
    seedCounter += 1;
    final profile = BackendConnectionProfile(
      profileId: 'profile-seed$seedCounter',
      generation: (existing?.generation ?? 0) + 1,
      state: state,
      createdAt: clock,
      updatedAt: clock,
      provisioningTransactionId: transactionId,
      projectRef: withProject ? _projectRef : null,
      projectUrl: withProject ? 'https://$_projectRef.supabase.co' : null,
      publishableKey: state == ProvisioningState.ready ? _publishableKey : null,
    );
    await profileStore.save(profile, expectedGeneration: existing?.generation);
    if (withCapability) {
      await capabilityStore.write(
        transactionId: transactionId,
        capability: _capability,
      );
    }
    return profile;
  }

  String profileFile() =>
      File(p.join(directory.path, plannerBackendProfileFileName))
          .readAsStringSync();

  group('start', () {
    test(
      'creates a durable attempt and keeps the capability out of it',
      () async {
        transport.reply('POST', _transactionsPath, _grantBody(_transactionA));
        final coordinator = buildCoordinator();

        final result = await coordinator.startAttempt();

        expect(result.outcome, ProvisioningOutcome.inProgress);
        expect(result.authorizationUrl?.host, 'api.supabase.com');
        expect(result.profile!.state, ProvisioningState.authorizationPending);
        expect(result.profile!.provisioningTransactionId, _transactionA);
        expect(result.profile!.generation, 1);
        expect(capabilityStore.values[_transactionA], _capability);

        final persisted = profileFile();
        expect(persisted, contains(_transactionA));
        expect(persisted, isNot(contains(_capability)));
        expect(persisted, isNot(contains('capability')));
        expect(persisted, isNot(contains('accessToken')));

        final attempt = await buildCoordinator().loadAttempt();
        expect(attempt!.transactionId, _transactionA);
        expect(attempt.hasCapability, isTrue);
        expect(attempt.isActive, isTrue);
      },
    );

    test('replaces an earlier attempt and drops its capability', () async {
      transport.reply('POST', _transactionsPath, _grantBody(_transactionA));
      transport.reply('POST', _transactionsPath, _grantBody(_transactionB));

      final first = await buildCoordinator().startAttempt();
      final second = await buildCoordinator().startAttempt();

      expect(second.profile!.profileId, isNot(first.profile!.profileId));
      expect(second.profile!.generation, 2);
      expect(second.profile!.provisioningTransactionId, _transactionB);
      expect(capabilityStore.values.containsKey(_transactionA), isFalse);
      expect(capabilityStore.values[_transactionB], _capability);
    });

    test('writes nothing when secure storage is unavailable', () async {
      transport.reply('POST', _transactionsPath, _grantBody(_transactionA));
      capabilityStore.unavailable = true;

      final result = await buildCoordinator().startAttempt();

      expect(result.outcome, ProvisioningOutcome.retryable);
      expect(result.profile, isNull);
      expect(await profileStore.read(), isNull);
    });

    test('reports a network failure without starting anything', () async {
      transport.fail(
        'POST',
        _transactionsPath,
        const ProvisioningApiException(
          ProvisioningErrorKind.network,
          'The provisioning service could not be reached.',
        ),
      );

      final result = await buildCoordinator().startAttempt();

      expect(result.outcome, ProvisioningOutcome.retryable);
      expect(await profileStore.read(), isNull);
      expect(capabilityStore.values, isEmpty);
    });
  });

  group('state advancement', () {
    test('stays local-only when no attempt exists', () async {
      final result = await buildCoordinator().refresh();

      expect(result.outcome, ProvisioningOutcome.localOnly);
      expect(transport.requests, isEmpty);
    });

    test('persists legal advancement and skips unchanged rewrites', () async {
      await seedProfile(state: ProvisioningState.authorizationPending);
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('organization_selected'),
      );
      final coordinator = buildCoordinator();

      final advanced = await coordinator.refresh();

      expect(advanced.outcome, ProvisioningOutcome.inProgress);
      expect(advanced.profile!.state, ProvisioningState.organizationSelected);
      expect(advanced.profile!.generation, 2);

      final again = await coordinator.refresh();
      expect(again.profile!.state, ProvisioningState.organizationSelected);
      expect(again.profile!.generation, 2);
    });

    test(
      'walks the Worker graph when a poll gap hid intermediate states',
      () async {
        await seedProfile(state: ProvisioningState.authorizationPending);
        transport.reply(
          'GET',
          _snapshotPath(_transactionA),
          _snapshotBody('verifying', projectRef: _projectRef),
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.inProgress);
        expect(result.profile!.state, ProvisioningState.verifying);
        expect(result.profile!.generation, 6);
        expect((await profileStore.read())!.state, ProvisioningState.verifying);
      },
    );

    test('reports an unreachable reported state instead of guessing', () async {
      await seedProfile(state: ProvisioningState.expired);
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('verifying', projectRef: _projectRef),
      );

      final result = await buildCoordinator().refresh();

      expect(result.outcome, ProvisioningOutcome.protocolError);
      expect((await profileStore.read())!.state, ProvisioningState.expired);
    });

    test('keeps the last authoritative state when the network fails', () async {
      await seedProfile(
        state: ProvisioningState.projectWaiting,
        withProject: true,
      );
      transport.fail(
        'GET',
        _snapshotPath(_transactionA),
        const ProvisioningApiException(
          ProvisioningErrorKind.timeout,
          'The provisioning request timed out.',
        ),
      );

      final result = await buildCoordinator().refresh();

      expect(result.outcome, ProvisioningOutcome.retryable);
      final stored = (await profileStore.read())!;
      expect(stored.state, ProvisioningState.projectWaiting);
      expect(stored.generation, 1);
    });

    test(
      'reports a missing capability without contacting the control plane',
      () async {
        await seedProfile(
          state: ProvisioningState.projectWaiting,
          withCapability: false,
          withProject: true,
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.capabilityMissing);
        expect(result.message, contains('start a new provisioning attempt'));
        expect(transport.requests, isEmpty);
        expect(
          (await profileStore.read())!.state,
          ProvisioningState.projectWaiting,
        );
      },
    );

    test(
      'distinguishes unavailable secure storage from a missing capability',
      () async {
        await seedProfile(
          state: ProvisioningState.projectWaiting,
          withProject: true,
        );
        capabilityStore.unavailable = true;

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.retryable);
        expect(transport.requests, isEmpty);
      },
    );
  });

  group('worker actions', () {
    test('lists organizations through the transaction boundary', () async {
      await seedProfile(state: ProvisioningState.authorizationPending);
      transport.reply(
        'GET',
        '${_snapshotPath(_transactionA)}/organizations',
        <String, dynamic>{
          'organizations': <dynamic>[
            <String, dynamic>{
              'id': 'org-1',
              'name': 'Owner Org',
              'slug': 'owner-org',
            },
          ],
        },
      );

      final result = await buildCoordinator().listOrganizations();

      expect(result.outcome, ProvisioningOutcome.inProgress);
      expect(result.organizations.single.slug, 'owner-org');
      expect(
        transport.requests.single.headers['authorization'],
        'Provisioning $_capability',
      );
    });

    test('selects an organization with the exact Worker contract', () async {
      await seedProfile(state: ProvisioningState.authorizationPending);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/organization',
        _snapshotBody('organization_selected'),
      );

      final result = await buildCoordinator().selectOrganization(
        organizationSlug: 'owner-org',
        projectName: _projectName,
      );

      expect(result.outcome, ProvisioningOutcome.inProgress);
      expect(result.profile!.state, ProvisioningState.organizationSelected);

      final body =
          jsonDecode(transport.requests.single.body!) as Map<String, dynamic>;
      expect(body, <String, dynamic>{
        'slug': 'owner-org',
        'projectName': _projectName,
        'idempotencyKey': ProvisioningCoordinator.idempotencyKeyFor(
          _transactionA,
        ),
      });
      expect(
        (body['idempotencyKey']! as String).length,
        greaterThanOrEqualTo(32),
      );
    });

    test('recovers when the selection was already applied but the response was lost', () async {
      await seedProfile(state: ProvisioningState.authorizationPending);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/organization',
        <String, dynamic>{'error': 'invalid_request'},
        status: 400,
      );
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('organization_selected'),
      );

      final result = await buildCoordinator().selectOrganization(
        organizationSlug: 'owner-org',
        projectName: _projectName,
      );

      expect(result.outcome, ProvisioningOutcome.inProgress);
      expect(result.profile!.state, ProvisioningState.organizationSelected);
      expect(transport.keys, <String>[
        'POST ${_snapshotPath(_transactionA)}/organization',
        'GET ${_snapshotPath(_transactionA)}',
      ]);
    });

    test(
      'rejects local input that cannot satisfy the Worker contract',
      () async {
        await seedProfile(state: ProvisioningState.authorizationPending);
        final coordinator = buildCoordinator();

        expect(
          () => coordinator.selectOrganization(
            organizationSlug: 'Owner Org',
            projectName: _projectName,
          ),
          throwsArgumentError,
        );
        expect(
          () => coordinator.selectOrganization(
            organizationSlug: 'owner-org',
            projectName: 'my-project',
          ),
          throwsArgumentError,
        );
        expect(transport.requests, isEmpty);
      },
    );

    test('follows the Worker state machine for create and reconcile', () async {
      await seedProfile(state: ProvisioningState.organizationSelected);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/create',
        _snapshotBody('project_creating'),
      );
      final created = await buildCoordinator().createOrContinueProject();
      expect(created.profile!.state, ProvisioningState.projectCreating);

      await seedProfile(state: ProvisioningState.projectReconciliationRequired);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/reconcile',
        _snapshotBody('project_retry_authorized'),
      );
      final reconciled = await buildCoordinator().createOrContinueProject();
      expect(
        reconciled.profile!.state,
        ProvisioningState.projectRetryAuthorized,
      );

      await seedProfile(
        state: ProvisioningState.projectWaiting,
        withProject: true,
      );
      final beforeWaiting = transport.requests.length;
      final noOp = await buildCoordinator().createOrContinueProject();
      expect(noOp.outcome, ProvisioningOutcome.inProgress);
      expect(noOp.message, contains('not the next step'));
      expect(transport.requests.length, beforeWaiting);

      expect(transport.keys.where((key) => key.contains('/create')).length, 1);
      expect(
        transport.keys.where((key) => key.contains('/reconcile')).length,
        1,
      );
    });

    test('reports an in-progress conflict as retryable', () async {
      await seedProfile(state: ProvisioningState.projectCreating);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/create',
        <String, dynamic>{'error': 'operation_in_progress'},
        status: 409,
      );

      final result = await buildCoordinator().createOrContinueProject();

      expect(result.outcome, ProvisioningOutcome.retryable);
      expect(
        (await profileStore.read())!.state,
        ProvisioningState.projectCreating,
      );
    });

    test('migrates and verifies only where the Worker allows it', () async {
      await seedProfile(
        state: ProvisioningState.projectWaiting,
        withProject: true,
      );
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/migrate',
        _snapshotBody('migrating', projectRef: _projectRef),
        status: 202,
      );
      final migrated = await buildCoordinator().migrate();
      expect(migrated.outcome, ProvisioningOutcome.inProgress);
      expect(migrated.profile!.state, ProvisioningState.migrating);

      await seedProfile(state: ProvisioningState.verifying, withProject: true);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/verify',
        _snapshotBody('verifying', projectRef: _projectRef),
        status: 202,
      );
      final verified = await buildCoordinator().verify();
      expect(verified.outcome, ProvisioningOutcome.inProgress);
      expect(verified.profile!.state, ProvisioningState.verifying);

      await seedProfile(state: ProvisioningState.migrating, withProject: true);
      final beforeWrongStep = transport.requests.length;
      final wrongStep = await buildCoordinator().verify();
      expect(wrongStep.message, contains('not the next step'));
      expect(transport.requests.length, beforeWrongStep);
    });
  });

  group('terminal outcomes', () {
    test('persists a terminal verification failure and cleans up', () async {
      await seedProfile(state: ProvisioningState.verifying, withProject: true);
      transport.reply(
        'POST',
        '${_snapshotPath(_transactionA)}/verify',
        _snapshotBody('terminal_error', error: 'verification_failed'),
      );

      final result = await buildCoordinator().verify();

      expect(result.outcome, ProvisioningOutcome.terminal);
      final stored = (await profileStore.read())!;
      expect(stored.state, ProvisioningState.terminalError);
      expect(stored.errorCode, 'verification_failed');
      expect(capabilityStore.values, isEmpty);
    });

    test('cleans up an expired transaction and requires a restart', () async {
      await seedProfile(state: ProvisioningState.verifying, withProject: true);
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('expired', error: 'provisioning_expired'),
      );

      final result = await buildCoordinator().refresh();

      expect(result.outcome, ProvisioningOutcome.restartRequired);
      expect((await profileStore.read())!.state, ProvisioningState.expired);
      expect(capabilityStore.values, isEmpty);
    });

    test(
      'maps a Worker restart requirement without inventing a state',
      () async {
        await seedProfile(state: ProvisioningState.authorizationPending);
        transport.fail(
          'GET',
          _snapshotPath(_transactionA),
          const ProvisioningApiException(
            ProvisioningErrorKind.worker,
            'Provisioning stopped: oauth_expired (HTTP 401).',
            code: 'oauth_expired',
            statusCode: 401,
          ),
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.restartRequired);
        expect(
          (await profileStore.read())!.state,
          ProvisioningState.authorizationPending,
        );
      },
    );
  });

  group('ready completion', () {
    test(
      'validates the configuration, persists it, then removes the capability',
      () async {
        await seedProfile(
          state: ProvisioningState.verifying,
          withProject: true,
        );
        transport.reply(
          'GET',
          _snapshotPath(_transactionA),
          _snapshotBody(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: _runtimeConfigBody(),
          ),
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.ready);
        final stored = (await profileStore.read())!;
        expect(stored.state, ProvisioningState.ready);
        expect(stored.projectRef, _projectRef);
        expect(stored.projectUrl, 'https://$_projectRef.supabase.co');
        expect(stored.publishableKey, _publishableKey);
        expect(stored.generation, 2);
        expect(capabilityStore.values, isEmpty);

        final persisted = profileFile();
        expect(persisted, contains(_publishableKey));
        expect(persisted, isNot(contains(_capability)));
        expect(persisted, isNot(contains('capability')));
      },
    );

    test(
      'completes a poll-gap arrival at ready through legal transitions',
      () async {
        await seedProfile(
          state: ProvisioningState.migrating,
          withProject: true,
        );
        transport.reply(
          'GET',
          _snapshotPath(_transactionA),
          _snapshotBody(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: _runtimeConfigBody(),
          ),
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.ready);
        expect((await profileStore.read())!.state, ProvisioningState.ready);
        expect(capabilityStore.values, isEmpty);
      },
    );

    test('rejects a runtime configuration the Phase B model refuses', () async {
      await seedProfile(state: ProvisioningState.verifying, withProject: true);
      for (final config in <Map<String, dynamic>>[
        <String, dynamic>{
          'projectRef': _projectRef,
          'projectUrl': 'https://someone-else.supabase.co',
          'publishableKey': _publishableKey,
        },
        <String, dynamic>{
          'projectRef': _projectRef,
          'projectUrl': 'https://$_projectRef.supabase.co',
          'publishableKey': 'sb_secret_abcdefghijklmnopqrstuvwxyz',
        },
        <String, dynamic>{
          'projectRef': 'ABCDEFGHIJKLMNOPQRST',
          'projectUrl': 'https://ABCDEFGHIJKLMNOPQRST.supabase.co',
          'publishableKey': _publishableKey,
        },
      ]) {
        transport.reply(
          'GET',
          _snapshotPath(_transactionA),
          _snapshotBody(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: config,
          ),
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.protocolError);
        expect((await profileStore.read())!.state, ProvisioningState.verifying);
        expect(capabilityStore.values[_transactionA], _capability);
      }
    });

    test(
      'retains the capability when the final profile cannot be saved',
      () async {
        await seedProfile(
          state: ProvisioningState.verifying,
          withProject: true,
        );
        transport.reply(
          'GET',
          _snapshotPath(_transactionA),
          _snapshotBody(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: _runtimeConfigBody(),
          ),
        );
        profileStore.failSaves = true;

        final failed = await buildCoordinator().refresh();

        expect(failed.outcome, ProvisioningOutcome.retryable);
        expect(capabilityStore.values[_transactionA], _capability);
        expect((await profileStore.read())!.state, ProvisioningState.verifying);

        profileStore.failSaves = false;
        final completed = await buildCoordinator().refresh();

        expect(completed.outcome, ProvisioningOutcome.ready);
        expect((await profileStore.read())!.state, ProvisioningState.ready);
        expect(capabilityStore.values, isEmpty);
      },
    );

    test(
      'finishes capability cleanup when completion already happened',
      () async {
        await seedProfile(state: ProvisioningState.ready, withProject: true);
        transport.reply(
          'GET',
          _snapshotPath(_transactionA),
          _snapshotBody(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: _runtimeConfigBody(),
          ),
        );

        final result = await buildCoordinator().refresh();

        expect(result.outcome, ProvisioningOutcome.ready);
        expect(capabilityStore.values, isEmpty);
        expect((await profileStore.read())!.state, ProvisioningState.ready);
      },
    );
  });

  group('concurrency and resume', () {
    test('a stale response cannot overwrite a newer attempt', () async {
      await seedProfile(state: ProvisioningState.authorizationPending);
      final coordinatorA = buildCoordinator();
      transport.hold('GET', _snapshotPath(_transactionA));
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('organization_selected'),
      );
      transport.reply('POST', _transactionsPath, _grantBody(_transactionB));

      final pending = coordinatorA.refresh();
      await _awaitRequests(transport, 1);

      final started = await buildCoordinator().startAttempt();
      expect(started.profile!.profileId, isNot('profile-seed'));

      transport.release('GET', _snapshotPath(_transactionA));
      final stale = await pending;

      expect(stale.outcome, ProvisioningOutcome.stale);
      final stored = (await profileStore.read())!;
      expect(stored.profileId, started.profile!.profileId);
      expect(stored.provisioningTransactionId, _transactionB);
      expect(stored.state, ProvisioningState.authorizationPending);
    });

    test('overlapping calls on one coordinator run one at a time', () async {
      await seedProfile(state: ProvisioningState.authorizationPending);
      transport.hold('GET', _snapshotPath(_transactionA));
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('organization_selected'),
      );
      final coordinator = buildCoordinator();

      final first = coordinator.refresh();
      await _awaitRequests(transport, 1);
      final second = coordinator.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transport.requests, hasLength(1));

      transport.release('GET', _snapshotPath(_transactionA));
      final results = await Future.wait(<Future<ProvisioningResult>>[
        first,
        second,
      ]);

      expect(
        results.every(
          (result) => result.outcome == ProvisioningOutcome.inProgress,
        ),
        isTrue,
      );
      expect(transport.requests, hasLength(2));
    });

    test('a restarted coordinator resumes from durable state and secure storage', () async {
      transport.reply('POST', _transactionsPath, _grantBody(_transactionA));
      final started = await buildCoordinator().startAttempt();
      expect(started.outcome, ProvisioningOutcome.inProgress);

      // A brand new coordinator over the same stores, as after an app restart.
      transport.reply(
        'GET',
        _snapshotPath(_transactionA),
        _snapshotBody('organization_selected'),
      );
      final resumed = buildCoordinator();
      final attempt = await resumed.loadAttempt();
      expect(attempt!.hasCapability, isTrue);
      expect(attempt.state, ProvisioningState.authorizationPending);

      final result = await resumed.refresh();

      expect(result.outcome, ProvisioningOutcome.inProgress);
      expect(result.profile!.state, ProvisioningState.organizationSelected);
      expect(
        transport.requests.last.headers['authorization'],
        'Provisioning $_capability',
      );
    });

    test('a corrupt profile does not block starting a new attempt', () async {
      File(p.join(directory.path, plannerBackendProfileFileName))
          .writeAsStringSync('{"format_version":1,"state":');
      transport.reply('POST', _transactionsPath, _grantBody(_transactionB));

      final result = await buildCoordinator().startAttempt();

      expect(result.outcome, ProvisioningOutcome.inProgress);
      expect(
        (await profileStore.read())!.provisioningTransactionId,
        _transactionB,
      );
    });
  });
}
