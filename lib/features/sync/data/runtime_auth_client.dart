import 'package:supabase_flutter/supabase_flutter.dart';

/// Narrow, client-explicit view of exactly one runtime Supabase Auth backend.
///
/// Everything the Planner runtime needs from a project's Auth namespace lives
/// here, so the rest of the app never has to assume that the global
/// `Supabase.instance` singleton represents the active cloud backend. One
/// instance wraps one client, so an Auth call for project A can never be
/// dispatched to project B.
abstract interface class RuntimeAuthClient {
  Session? get currentSession;

  User? get currentUser;

  Stream<AuthState> get authStateChanges;

  /// Restores a session string that was previously read from this client's
  /// own project-scoped storage.
  Future<void> setInitialSession(String persistedSession);

  Future<void> refreshSession();

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String emailRedirectTo,
  });

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// The real implementation, wrapping an explicit [SupabaseClient].
///
/// For the provisioned path that client is built from the client-safe READY
/// backend profile and is never the global singleton.
class SupabaseRuntimeAuthClient implements RuntimeAuthClient {
  SupabaseRuntimeAuthClient(this._client);

  final SupabaseClient _client;

  // Reading this getter throws for a client constructed with a custom
  // `accessToken` callback (the third-party-token sync client). That form is
  // never used as a runtime Auth client.
  GoTrueClient get _auth => _client.auth;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  @override
  Future<void> setInitialSession(String persistedSession) =>
      _auth.setInitialSession(persistedSession);

  @override
  Future<void> refreshSession() => _auth.refreshSession();

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String emailRedirectTo,
  }) => _auth.signUp(
    email: email,
    password: password,
    emailRedirectTo: emailRedirectTo,
  );

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) => _auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signOut() => _auth.signOut();
}
