import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/auth_callback.dart';
import '../domain/password_policy.dart';
import 'runtime_auth_client.dart';
import 'runtime_auth_callback.dart';
import 'secure_session_storage.dart';

/// The small auth surface used by app-lifetime state. Keeping this boundary
/// independent of [SupabaseClient] makes refresh and event ordering testable
/// without supplying credentials to a test process.
abstract interface class AuthSessionRepository {
  Session? get currentSession;

  Stream<AuthState> get authStateChanges;

  Future<void> refreshSession();
}

/// Auth boundary for exactly one runtime backend.
///
/// The rest of the app receives only session/user state and never reaches
/// Supabase directly. The client is supplied explicitly, so a repository built
/// for project A cannot authenticate against project B or against the
/// compile-time developer project.
class AuthRepository implements AuthSessionRepository {
  AuthRepository(this.client, {this.sessionStorage, this.provisionedAuthFlow});

  final RuntimeAuthClient client;

  /// Secure storage holding this backend's persisted session.
  ///
  /// The compile-time developer backend uses the historical global key and is
  /// restored/persisted by supabase_flutter's own singleton wrapper. The
  /// provisioned backend uses a project-scoped key and is restored/persisted by
  /// this repository (see [attachScopedSessionStorage]).
  final SecureSupabaseLocalStorage? sessionStorage;

  /// Pending-provisioned-flow bookkeeping of exactly this project.
  ///
  /// Null for the compile-time developer backend, whose historical deep-link
  /// behaviour stays owned by `supabase_flutter`'s singleton wrapper.
  final ProvisionedAuthCallbackFlow? provisionedAuthFlow;

  StreamSubscription<AuthState>? _sessionPersistence;

  @override
  Session? get currentSession => client.currentSession;

  User? get currentUser => client.currentUser;

  @override
  Stream<AuthState> get authStateChanges => client.authStateChanges;

  /// Restores this backend's persisted session, then keeps [sessionStorage] in
  /// sync with later Auth events.
  ///
  /// Used by the provisioned runtime path only. `supabase_flutter` only
  /// restores and persists sessions for its own singleton wrapper, and a
  /// dynamically created client has no such wrapper, so the session lifecycle
  /// is owned here instead.
  ///
  /// A stored value this project cannot decode is confined to this project:
  /// only this backend's scoped value is dropped and the runtime stays
  /// unauthenticated, so a corrupt session can never keep the Planner from
  /// opening. A secure-storage *infrastructure* failure is deliberately not
  /// handled here — it propagates so the caller can report an explicit
  /// bootstrap failure instead of silently treating the account as signed out.
  Future<void> attachScopedSessionStorage() async {
    final storage = sessionStorage;
    if (storage == null) return;
    final persisted = await storage.accessToken();
    if (persisted != null) {
      try {
        await client.setInitialSession(persisted);
      } catch (error) {
        if (!_isUnusableStoredSessionValue(error)) rethrow;
        // Confined to this project's namespace: no other project's session and
        // no legacy static session is touched.
        await storage.removePersistedSession();
        await storage.settle();
      }
    }
    _sessionPersistence ??= client.authStateChanges.listen(
      _persistSession,
      onError: (_) {
        // Stream errors are surfaced by AuthSessionController as health, never
        // as an implicit signed-out state.
      },
      cancelOnError: false,
    );
  }

  void _persistSession(AuthState event) {
    final storage = sessionStorage;
    if (storage == null) return;
    final session = event.session;
    if (session != null) {
      unawaited(storage.persistSession(jsonEncode(session.toJson())));
      return;
    }
    if (event.event == AuthChangeEvent.signedOut) {
      unawaited(storage.removePersistedSession());
    }
  }

  /// Signs up on exactly this backend, asking the confirmation email to return
  /// to the destination this project's Supabase Auth configuration actually
  /// allows.
  ///
  /// A backend provisioned by a Worker that verified the HTTPS landing page
  /// uses that page, so a confirmation opened on a device without the app still
  /// gets a usable result. A backend verified before that page existed keeps
  /// the canonical custom-scheme callback: asking Supabase for a redirect the
  /// project rejects would silently fall back to the project Site URL and make
  /// the confirmation link useless.
  ///
  /// For the provisioned path the pending flow is recorded *before* the request
  /// is sent, so the marker and the PKCE verifier the SDK writes are created
  /// together and a cold-started app can still route the callback later.
  Future<AuthResponse> signUp(String email, String password) async {
    final flow = provisionedAuthFlow;
    await flow?.begin();
    try {
      final response = await client.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo:
            flow?.backend.emailConfirmationRedirect ?? AuthCallback.redirectUrl,
      );
      if (response.session != null) {
        // Confirmation is not required: there is no pending email link.
        await flow?.clear();
      }
      return response;
    } on AuthException catch (error) {
      final status = error.statusCode;
      if (flow != null && status != null && status.startsWith('4')) {
        // The Auth server definitively rejected the sign-up, so no
        // confirmation email is outstanding.
        await flow.clear();
      }
      rethrow;
    }
  }

  Future<AuthResponse> signIn(String email, String password) =>
      client.signInWithPassword(email: email.trim(), password: password);

  /// Delegates rotation/retry ownership to the SDK. The controller serializes
  /// requests for this method so an expiry cannot start concurrent refreshes.
  @override
  Future<void> refreshSession() async {
    await client.refreshSession();
  }

  /// Supabase emits the terminal event before its remote sign-out request has
  /// completed. Queueing a final deletion after that request ensures an older
  /// refresh write cannot resurrect credentials after a user logs out.
  Future<void> signOut() async {
    try {
      await client.signOut();
    } finally {
      final storage = sessionStorage;
      if (storage != null) {
        await storage.removePersistedSession();
        await storage.settle();
      }
      // Sign-out abandons any pending email confirmation of this project, so an
      // old callback cannot re-establish a session the user just ended.
      await provisionedAuthFlow?.clear();
    }
  }

  /// Releases the session listener. Storage itself is left intact: signing out
  /// or switching backends must not delete another backend's namespace, and the
  /// scoped session is only removed by an explicit sign-out.
  Future<void> dispose() async {
    await _sessionPersistence?.cancel();
    _sessionPersistence = null;
  }
}

/// True when [error] means "the *stored session value* is not a usable
/// session", which is a per-project data problem.
///
/// Verified against the installed gotrue (2.27.2)
/// `GoTrueClient.setInitialSession`, which:
///
/// * calls `json.decode` → [FormatException] for malformed JSON;
/// * passes the decoded value to `Session.fromJson`, whose parameter type makes
///   a non-object document (a list, string, number, or null) a [TypeError], and
///   whose body throws [FormatException] for a missing or non-object `user`;
/// * throws [AuthException] (`sessionMissing`) when the document has no
///   `access_token`, and [TypeError] when a token field has the wrong type.
///
/// Anything else — a keyring/plugin/platform failure, for instance — is secure
/// storage infrastructure rather than a corrupt value, and must stay
/// distinguishable to the caller.
bool _isUnusableStoredSessionValue(Object error) =>
    error is FormatException || error is TypeError || error is AuthException;

/// Converts known auth failures to safe UI text without exposing access or
/// refresh tokens, PKCE values, passwords, or raw request payloads.
String safeAuthError(Object error) {
  // A rejected password is not a networking or credential problem, so it must
  // never be reported with the generic message below.
  if (isPasswordPolicyFailure(error)) return passwordPolicyErrorMessage();
  final message = error.toString().toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Email or password is incorrect.';
  }
  if (message.contains('already registered') ||
      message.contains('user already exists')) {
    return 'That email is already registered.';
  }
  if (message.contains('email not confirmed') ||
      message.contains('not confirmed')) {
    return 'This email has not been confirmed yet. Open the confirmation link '
        'from your email, then log in again.';
  }
  if (message.contains('email') && message.contains('invalid')) {
    return 'Enter a valid email address.';
  }
  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('timeout') ||
      message.contains('connection')) {
    return 'Network unavailable. Your local data is still safe.';
  }
  return 'Authentication failed. Check your details and try again.';
}

/// True when Supabase rejected the chosen *password* rather than the request.
///
/// Supabase reports a policy rejection as `weak_password`; older servers
/// omitted the code and only sent a human message, so the message is checked
/// as well. Nothing here depends on a guessed password policy — the server
/// stays the authority and this only makes its answer understandable.
bool isPasswordPolicyFailure(Object error) {
  if (error is AuthWeakPasswordException) return true;
  if (error is AuthException && error.code == 'weak_password') return true;
  final message = error.toString().toLowerCase();
  if (message.contains('weak_password') || message.contains('weak password')) {
    return true;
  }
  if (message.contains('known to be weak')) return true;
  if (message.contains('password') &&
      (message.contains('too short') ||
          message.contains('should be at least') ||
          message.contains('at least one character'))) {
    return true;
  }
  return false;
}

/// User-facing text for a password Supabase itself rejected.
///
/// The guaranteed local minimum is stated, and anything stronger is presented
/// as belonging to the user's own Supabase project instead of being invented.
String passwordPolicyErrorMessage() =>
    'Supabase rejected this password. Use at least '
    '${PlannerPasswordPolicy.minimumLength} characters, and add letters, '
    'numbers and symbols if your Supabase project asks for a stronger one.';
