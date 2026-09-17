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
        pkceAsyncStorage: SecureSupabasePkceStorage(
          namespaces: backend.authNamespaces,
          storage: secureStorage,
        ),
      );

  SupabaseClient create(ProvisionedRuntimeBackend backend) {
    final options = authOptionsFor(backend);
    final builder = clientBuilder;
    if (builder != null) {
      return builder(backend.projectUrl, backend.publishableKey, options);
    }
    return SupabaseClient(
      backend.projectUrl,
      backend.publishableKey,
      authOptions: options,
    );
  }
}
