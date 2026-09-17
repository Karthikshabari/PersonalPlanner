import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/runtime_supabase_client.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/runtime_auth_fakes.dart';

/// Session restore and sign-out have to be provable without a network, without
/// a real Supabase client, and without a real OS keyring.
void main() {
  late FakeSecureKeyValueStore store;
  late FakeRuntimeAuthClient projectAClient;
  late FakeRuntimeAuthClient projectBClient;
  late AuthRepository projectARepository;
  late AuthRepository projectBRepository;
  late SecureSupabaseLocalStorage projectAStorage;
  late SecureSupabaseLocalStorage projectBStorage;

  final namespacesA = RuntimeAuthNamespaces.forProject(projectRefA);
  final namespacesB = RuntimeAuthNamespaces.forProject(projectRefB);

  setUp(() {
    store = FakeSecureKeyValueStore();
    projectAClient = FakeRuntimeAuthClient();
    projectBClient = FakeRuntimeAuthClient();
    projectAStorage = SecureSupabaseLocalStorage(
      storage: store,
      sessionKey: namespacesA.sessionKey,
    );
    projectBStorage = SecureSupabaseLocalStorage(
      storage: store,
      sessionKey: namespacesB.sessionKey,
    );
    projectARepository = AuthRepository(
      projectAClient,
      sessionStorage: projectAStorage,
    );
    projectBRepository = AuthRepository(
      projectBClient,
      sessionStorage: projectBStorage,
    );
  });

  tearDown(() async {
    await projectARepository.dispose();
    await projectBRepository.dispose();
    await projectAClient.close();
    await projectBClient.close();
  });

  test('project A restores exactly its own scoped session', () async {
    final session = testAuthSession(authUserId: authUserIdX);
    store.values[namespacesA.sessionKey] = jsonEncode(session.toJson());

    await projectARepository.attachScopedSessionStorage();

    expect(projectAClient.restoredSessions, hasLength(1));
    expect(projectAClient.currentSession?.user.id, authUserIdX);
    expect(projectAClient.currentSession?.refreshToken, 'refresh-secret');
  });

  test('project A session never restores into project B', () async {
    final session = testAuthSession(authUserId: authUserIdX);
    store.values[namespacesA.sessionKey] = jsonEncode(session.toJson());

    await projectBRepository.attachScopedSessionStorage();

    expect(projectBClient.restoredSessions, isEmpty);
    expect(projectBClient.currentSession, isNull);
    // The other project's stored session is left untouched on disk.
    expect(store.values[namespacesA.sessionKey], isNotNull);
  });

  test(
    'a legacy global session never authenticates a provisioned project',
    () async {
      final session = testAuthSession(authUserId: authUserIdX);
      store.values[RuntimeAuthNamespaces.legacySessionKey] = jsonEncode(
        session.toJson(),
      );

      await projectARepository.attachScopedSessionStorage();

      expect(projectAClient.restoredSessions, isEmpty);
      expect(projectAClient.currentSession, isNull);
    },
  );

  test(
    'an unreadable stored session leaves the project unauthenticated',
    () async {
      store.values[namespacesA.sessionKey] = 'not-a-session';
      projectAClient.restoreError = const AuthException('Invalid session');

      await projectARepository.attachScopedSessionStorage();

      expect(projectAClient.currentSession, isNull);
      expect(projectAClient.restoredSessions, hasLength(1));
    },
  );

  test(
    'a secure-storage read failure never looks like an empty session',
    () async {
      final outcomes = <SecureSessionStorageOutcome>[];
      final failingStore = _FailingReadSecureStore();
      final storage = SecureSupabaseLocalStorage(
        storage: failingStore,
        sessionKey: namespacesA.sessionKey,
        onOutcome: outcomes.add,
      );
      final repository = AuthRepository(
        FakeRuntimeAuthClient(),
        sessionStorage: storage,
      );
      addTearDown(repository.dispose);

      // Bootstrap must see the failure: silently continuing would open the
      // anonymous database while the user believes the account is connected.
      await expectLater(
        repository.attachScopedSessionStorage(),
        throwsA(isA<StateError>()),
      );
      expect(failingStore.readKeys, [namespacesA.sessionKey]);
      expect(
        outcomes
            .where((outcome) => !outcome.succeeded)
            .map((outcome) => outcome.operation),
        contains(SecureSessionStorageOperation.accessToken),
      );
    },
  );

  test('the installed GoTrue client reports malformed stored sessions as '
      'per-value failures', () async {
    // Documents the exception shapes the recovery path relies on, against the
    // real package rather than a fake.
    final auth = GoTrueClient(
      url: 'https://$projectRefA.supabase.co/auth/v1',
      autoRefreshToken: false,
    );
    addTearDown(auth.dispose);

    await expectLater(
      auth.setInitialSession('not-json{'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      auth.setInitialSession('[1,2]'),
      throwsA(isA<TypeError>()),
    );
    await expectLater(
      auth.setInitialSession('{"refresh_token":"refresh-secret"}'),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'a corrupt project A session is dropped without touching project B',
    () async {
      final session = testAuthSession(authUserId: authUserIdY);
      store.values[namespacesA.sessionKey] = 'not-json{';
      store.values[namespacesB.sessionKey] = jsonEncode(session.toJson());
      store.values[RuntimeAuthNamespaces.legacySessionKey] = jsonEncode(
        session.toJson(),
      );

      // Bootstrap has to keep running, unauthenticated, instead of failing
      // startup and re-reading the same corrupt value on every retry.
      await projectARepository.attachScopedSessionStorage();

      expect(projectAClient.currentSession, isNull);
      expect(projectAClient.restoredSessions, ['not-json{']);
      expect(store.values[namespacesA.sessionKey], isNull);
      expect(store.values[namespacesB.sessionKey], isNotNull);
      expect(store.values[RuntimeAuthNamespaces.legacySessionKey], isNotNull);
      // Nothing from the recovered project leaked into the other one.
      expect(projectBClient.restoredSessions, isEmpty);
    },
  );

  test('valid JSON of the wrong shape is recovered the same way', () async {
    for (final corrupt in [
      '[1,2]',
      '"a string"',
      '{"access_token":42}',
      '{"refresh_token":"refresh-secret"}',
    ]) {
      final freshStore = FakeSecureKeyValueStore();
      final client = FakeRuntimeAuthClient();
      final repository = AuthRepository(
        client,
        sessionStorage: SecureSupabaseLocalStorage(
          storage: freshStore,
          sessionKey: namespacesA.sessionKey,
        ),
      );
      freshStore.values[namespacesA.sessionKey] = corrupt;
      freshStore.values[namespacesB.sessionKey] = 'other-project-session';

      await repository.attachScopedSessionStorage();

      expect(client.currentSession, isNull, reason: corrupt);
      expect(
        freshStore.values[namespacesA.sessionKey],
        isNull,
        reason: corrupt,
      );
      expect(
        freshStore.values[namespacesB.sessionKey],
        'other-project-session',
        reason: corrupt,
      );
      await repository.dispose();
      await client.close();
    }
  });

  test(
    'a storage failure during corrupt-value recovery stays explicit',
    () async {
      final failingStore = _FailingReadSecureStore()
        ..corruptValue = 'not-json{';
      final storage = SecureSupabaseLocalStorage(
        storage: failingStore,
        sessionKey: namespacesA.sessionKey,
      );
      final repository = AuthRepository(
        FakeRuntimeAuthClient(),
        sessionStorage: storage,
      );
      addTearDown(repository.dispose);

      // The stored value is corrupt, but the namespace could not be cleaned up:
      // that is secure-storage infrastructure, so it must not be silently
      // reported as "this account is simply signed out".
      await expectLater(
        repository.attachScopedSessionStorage(),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('a non-session failure from the client is never swallowed', () async {
    store.values[namespacesA.sessionKey] = jsonEncode(
      testAuthSession(authUserId: authUserIdX).toJson(),
    );
    projectAClient.restoreError = StateError('secure storage unavailable');

    await expectLater(
      projectARepository.attachScopedSessionStorage(),
      throwsA(isA<StateError>()),
    );
    expect(store.values[namespacesA.sessionKey], isNotNull);
  });

  test('signing in targets only the client of the ready profile', () async {
    await projectARepository.attachScopedSessionStorage();

    await projectARepository.signIn('person@example.com', 'secret');

    expect(projectAClient.signInCalls.single.email, 'person@example.com');
    expect(projectBClient.signInCalls, isEmpty);
  });

  test(
    'a signed-in session is persisted only into its own namespace',
    () async {
      await projectARepository.attachScopedSessionStorage();
      await projectBRepository.attachScopedSessionStorage();
      final session = testAuthSession(authUserId: authUserIdX);

      projectAClient.emitSignedIn(session);
      await projectAStorage.settle();
      await projectBStorage.settle();

      expect(store.values[namespacesA.sessionKey], isNotNull);
      expect(store.values[namespacesB.sessionKey], isNull);
      expect(store.values[RuntimeAuthNamespaces.legacySessionKey], isNull);
      final persisted = jsonDecode(
        store.values[namespacesA.sessionKey]!,
      ) as Map<String, dynamic>;
      expect((persisted['user'] as Map<String, dynamic>)['id'], authUserIdX);
    },
  );

  test('sign-out clears only the scoped session of that project', () async {
    final session = testAuthSession(authUserId: authUserIdX);
    store.values[namespacesA.sessionKey] = jsonEncode(session.toJson());
    store.values[namespacesB.sessionKey] = jsonEncode(session.toJson());
    projectAClient.session = session;
    projectBClient.session = session;

    await projectARepository.attachScopedSessionStorage();
    await projectARepository.signOut();

    expect(projectAClient.signOutCalls, 1);
    expect(store.values[namespacesA.sessionKey], isNull);
    // The other project's session and the legacy global session are untouched.
    expect(store.values[namespacesB.sessionKey], isNotNull);
    expect(projectBClient.signOutCalls, 0);
  });

  test(
    'a client signed-out event removes only its own persisted session',
    () async {
      final session = testAuthSession(authUserId: authUserIdX);
      store.values[namespacesA.sessionKey] = jsonEncode(session.toJson());
      store.values[namespacesB.sessionKey] = jsonEncode(session.toJson());
      projectAClient.session = session;

      await projectARepository.attachScopedSessionStorage();
      // The SDK emits the terminal event before its sign-out request finishes.
      await projectAClient.signOut();
      await projectAStorage.settle();

      expect(store.values[namespacesA.sessionKey], isNull);
      expect(store.values[namespacesB.sessionKey], isNotNull);
    },
  );

  test('disposing the repository never deletes a stored session', () async {
    final session = testAuthSession(authUserId: authUserIdX);
    store.values[namespacesA.sessionKey] = jsonEncode(session.toJson());

    await projectARepository.attachScopedSessionStorage();
    await projectARepository.dispose();

    expect(store.values[namespacesA.sessionKey], isNotNull);
  });

  group('runtime client factory', () {
    test(
      'builds the client from the ready profile with scoped PKCE storage',
      () {
        final backend = testProvisionedBackend();
        final builder = _RecordingClientBuilder();
        addTearDown(builder.dispose);
        final factory = RuntimeSupabaseClientFactory(
          secureStorage: store,
          clientBuilder: builder.call,
        );

        factory.create(backend);

        expect(builder.url, 'https://$projectRefA.supabase.co');
        expect(builder.key, publishableKeyA);
        expect(builder.options.autoRefreshToken, isTrue);
        expect(builder.options.authFlowType, AuthFlowType.pkce);
        final pkce = builder.options.pkceAsyncStorage!;
        expect(pkce, isA<SecureSupabasePkceStorage>());
        expect(
          (pkce as SecureSupabasePkceStorage).namespaces.sessionKey,
          namespacesA.sessionKey,
        );
      },
    );

    test('PKCE verifiers for two projects never share a key', () async {
      final builder = _RecordingClientBuilder();
      addTearDown(builder.dispose);
      final factory = RuntimeSupabaseClientFactory(
        secureStorage: store,
        clientBuilder: builder.call,
      );

      factory.create(testProvisionedBackend());
      final pkceA =
          builder.options.pkceAsyncStorage! as SecureSupabasePkceStorage;
      factory.create(
        testProvisionedBackend(
          projectRef: projectRefB,
          publishableKey: publishableKeyB,
        ),
      );
      final pkceB =
          builder.options.pkceAsyncStorage! as SecureSupabasePkceStorage;

      await pkceA.setItem(key: 'verifier', value: 'project-a-secret');

      expect(await pkceB.getItem(key: 'verifier'), isNull);
      expect(
        store.values['personal_planner.supabase.$projectRefA.pkce.verifier'],
        'project-a-secret',
      );
      expect(
        pkceA.namespaces.pkceKey('verifier') ==
            pkceB.namespaces.pkceKey('verifier'),
        isFalse,
      );
    });
  });
}

/// A keyring that fails on read, which is what a locked or unavailable OS
/// keyring looks like to the storage adapter.
class _FailingReadSecureStore implements SecureKeyValueStore {
  final List<String> readKeys = <String>[];

  /// When set, reads succeed and return this value while every write/delete
  /// still fails, so the caller has to notice that the namespace could not be
  /// repaired.
  String? corruptValue;

  @override
  Future<bool> containsKey({required String key}) async =>
      throw StateError('keyring unavailable');

  @override
  Future<String?> read({required String key}) async {
    readKeys.add(key);
    final value = corruptValue;
    if (value != null) return value;
    throw StateError('keyring unavailable');
  }

  @override
  Future<void> write({required String key, required String value}) async =>
      throw StateError('keyring unavailable');

  @override
  Future<void> delete({required String key}) async =>
      throw StateError('keyring unavailable');
}

class _RecordingClientBuilder {
  String? url;
  String? key;
  AuthClientOptions options = const AuthClientOptions();
  final List<SupabaseClient> created = <SupabaseClient>[];

  SupabaseClient call(String url, String key, AuthClientOptions options) {
    this.url = url;
    this.key = key;
    this.options = options;
    // The test only inspects the wiring, so the client is created and then
    // disposed immediately to leave no refresh ticker behind.
    final client = SupabaseClient(url, key, authOptions: options);
    created.add(client);
    return client;
  }

  Future<void> dispose() async {
    for (final client in created) {
      await client.dispose();
    }
  }
}
