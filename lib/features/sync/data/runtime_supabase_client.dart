import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/runtime_backend.dart';
import 'secure_session_storage.dart';

/// Builds the explicit Supabase client for a provisioned user-owned backend.
///
/// Deliberate constraints:
///
/// * input is a validated READY [ProvisionedRuntimeBackend], so only
///   `projectUrl` and the client-safe publishable key are used;
/// * it never calls `Supabase.initialize`, so the global singleton keeps
///   representing the compile-time developer configuration only;
/// * PKCE verifier storage is namespaced by project ref, so a PKCE flow started
///   for project A cannot be consumed by project B;
/// * the provisioning capability, Management tokens, and any secret key are
///   not reachable from here.
class RuntimeSupabaseClientFactory {
  const RuntimeSupabaseClientFactory({this.secureStorage, this.clientBuilder});

  /// Secure key/value boundary used for this project's PKCE verifiers.
  ///
  /// Null uses the platform keyring, which is what production does; tests
  /// inject an in-memory store.
  final SecureKeyValueStore? secureStorage;

  /// Test seam producing the client. When null a real [SupabaseClient] is
  /// created. Tests use it to capture the exact URL, key, and Auth options
  /// without starting a client isolate and its refresh ticker.
  final SupabaseClient Function(
    String url,
    String key,
    AuthClientOptions authOptions,
  )?
  clientBuilder;

  /// The Auth options of a provisioned runtime client.
  ///
  /// Exposed so tests can assert the namespace wiring without building a
  /// client.
  AuthClientOptions authOptionsFor(ProvisionedRuntimeBackend backend) =>
      AuthClientOptions(
        autoRefreshToken: true,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: pkceStorageFor(backend),
      );

  /// Project-scoped PKCE storage of [backend].
  ///
  /// Exposed so the callback router checks the same verifier the client writes,
  /// without introducing a second, project-independent namespace.
  SecureSupabasePkceStorage pkceStorageFor(ProvisionedRuntimeBackend backend) =>
      SecureSupabasePkceStorage(
        namespaces: backend.authNamespaces,
        storage: secureStorage,
      );

  /// Builds [backend]'s client together with the PKCE storage wired into it.
  ///
  /// The caller that also handles deep links needs both, and both must describe
  /// exactly the same project namespace.
  ({SupabaseClient client, SecureSupabasePkceStorage pkceStorage})
  createWithStorage(ProvisionedRuntimeBackend backend) {
    final pkceStorage = pkceStorageFor(backend);
    final options = AuthClientOptions(
      autoRefreshToken: true,
      authFlowType: AuthFlowType.pkce,
      pkceAsyncStorage: pkceStorage,
    );
    final builder = clientBuilder;
    if (builder != null) {
      return (
        client: builder(backend.projectUrl, backend.publishableKey, options),
        pkceStorage: pkceStorage,
      );
    }
    return (
      client: SupabaseClient(
        backend.projectUrl,
        backend.publishableKey,
        authOptions: options,
      ),
      pkceStorage: pkceStorage,
    );
  }

  SupabaseClient create(ProvisionedRuntimeBackend backend) =>
      createWithStorage(backend).client;
}
