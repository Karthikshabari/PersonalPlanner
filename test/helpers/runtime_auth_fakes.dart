import 'dart:async';
import 'dart:convert';

import 'package:personal_planner/features/sync/data/runtime_auth_client.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two distinct user-owned projects, and two distinct auth users.
///
/// The point of Phase EF is that the *same* auth user id in [projectRefA] and
/// [projectRefB] must never resolve to the same local Planner account.
const projectRefA = 'abcdefghijklmnopqrst';
const projectRefB = 'zyxwvutsrqponmlkjihg';
const authUserIdX = '11111111-1111-4111-8111-111111111111';
const authUserIdY = '22222222-2222-4222-8222-222222222222';
const publishableKeyA = 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu';
const publishableKeyB = 'sb_publishable_AbCdEfGhIjKlMnOpQrStUvWxYz012345';
final runtimeAuthTestClock = DateTime.utc(2026, 9, 16, 12);

/// Session whose access token carries a real `exp` claim, so `expiresAt` and
/// `hasUsableAccessToken` behave like production.
Session testAuthSession({
  required String authUserId,
  DateTime? issuedAt,
  Duration validFor = const Duration(hours: 1),
  String? email,
}) {
  // Defaults to "now" so `hasUsableAccessToken` behaves like production even
  // though the fixture clock is fixed.
  final issued = issuedAt ?? DateTime.now().toUtc();
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': issued.add(validFor).millisecondsSinceEpoch ~/ 1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return Session(
    accessToken: 'header.$payload.access-secret',
    refreshToken: 'refresh-secret',
    tokenType: 'bearer',
    user: User(
      id: authUserId,
      email: email,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
    ),
  );
}

ProvisionedRuntimeBackend testProvisionedBackend({
  String projectRef = projectRefA,
  String publishableKey = publishableKeyA,
  String profileId = 'profile-1',
  int generation = 1,
  String? emailConfirmationRedirect,
}) => ProvisionedRuntimeBackend(
  profileId: profileId,
  generation: generation,
  projectRef: projectRef,
  projectUrl: 'https://$projectRef.supabase.co',
  publishableKey: publishableKey,
  emailConfirmationRedirect: emailConfirmationRedirect,
);

BackendConnectionProfile testReadyProfile({
  String projectRef = projectRefA,
  String publishableKey = publishableKeyA,
  String profileId = 'profile-1',
  int generation = 1,
  String transactionId = '0123456789abcdef0123456789abcdef',
  String? emailConfirmationRedirect,
}) => BackendConnectionProfile(
  profileId: profileId,
  generation: generation,
  state: ProvisioningState.ready,
  createdAt: runtimeAuthTestClock,
  updatedAt: runtimeAuthTestClock,
  provisioningTransactionId: transactionId,
  authEmailConfirmationRedirect: emailConfirmationRedirect,
  projectRef: projectRef,
  projectUrl: 'https://$projectRef.supabase.co',
  publishableKey: publishableKey,
);

/// Scriptable stand-in for one project's Auth namespace.
///
/// It records every call so a test can prove that an operation for project A
/// never reached project B's client (or the legacy client).
class FakeRuntimeAuthClient implements RuntimeAuthClient {
  FakeRuntimeAuthClient({this.session});

  Session? session;
  final StreamController<AuthState> _events =
      StreamController<AuthState>.broadcast();

  final List<String> restoredSessions = <String>[];
  final List<({String email, String password})> signInCalls =
      <({String email, String password})>[];
  final List<({String email, String password, String emailRedirectTo})>
  signUpCalls = <({String email, String password, String emailRedirectTo})>[];
  final List<String> acceptedCallbackCodes = <String>[];
  int refreshCalls = 0;
  int signOutCalls = 0;

  /// Simulates an unusable stored session (for example a value written by a
  /// different GoTrue version).
  Object? restoreError;

  /// Session a successful Auth callback establishes for this project.
  ///
  /// Null makes [exchangeCodeForSession] fail the way the SDK does when no code
  /// verifier is stored for this project.
  Session? callbackSession;

  /// Scripted failure for [exchangeCodeForSession].
  Object? callbackError;

  @override
  Session? get currentSession => session;

  @override
  User? get currentUser => session?.user;

  @override
  Stream<AuthState> get authStateChanges => _events.stream;

  @override
  Future<void> setInitialSession(String persistedSession) async {
    restoredSessions.add(persistedSession);
    final error = restoreError;
    if (error != null) throw error;
    // Mirrors the installed GoTrue client: malformed JSON and wrong-shaped
    // documents surface as FormatException/TypeError, a document without an
    // access token as AuthException.
    final restored = Session.fromJson(
      Map<String, dynamic>.from(jsonDecode(persistedSession) as Map),
    );
    if (restored == null) {
      session = null;
      throw const AuthException(
        'Current session is missing data.',
        code: 'session_missing',
      );
    }
    session = restored;
  }

  @override
  Future<void> refreshSession() async {
    refreshCalls += 1;
  }

  @override
  Future<void> exchangeCodeForSession(String authCode) async {
    acceptedCallbackCodes.add(authCode);
    final error = callbackError;
    if (error != null) throw error;
    final next = callbackSession;
    if (next == null) {
      throw const AuthException(
        'Code verifier could not be found in local storage.',
      );
    }
    session = next;
    _events.add(AuthState(AuthChangeEvent.signedIn, next));
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String emailRedirectTo,
  }) async {
    signUpCalls.add((
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
    ));
    return AuthResponse(session: session);
  }

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls.add((email: email, password: password));
    return AuthResponse(session: session);
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    session = null;
    _events.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  /// Publishes a signed-in session the way the SDK would.
  void emitSignedIn(Session next) {
    session = next;
    _events.add(AuthState(AuthChangeEvent.signedIn, next));
  }

  /// Publishes a rotated session the way the SDK would.
  void emitTokenRefreshed(Session next) {
    session = next;
    _events.add(AuthState(AuthChangeEvent.tokenRefreshed, next));
  }

  Future<void> close() => _events.close();
}

/// In-memory [SecureKeyValueStore] holding several namespaces at once, so a
/// test can prove that one project's write or delete never touches another
/// project's key.
class FakeSecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};
  final List<String> operations = <String>[];

  @override
  Future<bool> containsKey({required String key}) async =>
      values.containsKey(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    operations.add('write:$key');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    operations.add('delete:$key');
    values.remove(key);
  }
}
