import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_session_storage.dart';

/// The small auth surface used by app-lifetime state. Keeping this boundary
/// independent of [SupabaseClient] makes refresh and event ordering testable
/// without supplying credentials to a test process.
abstract interface class AuthSessionRepository {
  Session? get currentSession;

  Stream<AuthState> get authStateChanges;

  Future<void> refreshSession();
}

/// Auth boundary. The rest of the app receives only session/user state and
/// never reaches Supabase directly.
class AuthRepository implements AuthSessionRepository {
  AuthRepository(this._client, {this.sessionStorage});

  final SupabaseClient _client;
  final SecureSupabaseLocalStorage? sessionStorage;

  static const emailConfirmationRedirect =
      'com.personalplanner.personal_planner://login-callback';

  @override
  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp(String email, String password) =>
      _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: emailConfirmationRedirect,
      );

  Future<AuthResponse> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  /// Delegates rotation/retry ownership to the SDK. The controller serializes
  /// requests for this method so an expiry cannot start concurrent refreshes.
  @override
  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }

  /// Supabase emits the terminal event before its remote sign-out request has
  /// completed. Queueing a final deletion after that request ensures an older
  /// refresh write cannot resurrect credentials after a user logs out.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } finally {
      final storage = sessionStorage;
      if (storage != null) {
        await storage.removePersistedSession();
        await storage.settle();
      }
    }
  }
}

/// Converts known auth failures to safe UI text without exposing access or
/// refresh tokens, PKCE values, passwords, or raw request payloads.
String safeAuthError(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Email or password is incorrect.';
  }
  if (message.contains('already registered') ||
      message.contains('user already exists')) {
    return 'That email is already registered.';
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
