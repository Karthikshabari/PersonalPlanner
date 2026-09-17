import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../data/auth_repository.dart';
import '../data/connection_profile_store.dart';
import '../data/runtime_auth_client.dart';
import '../domain/auth_session_controller.dart';
import '../domain/runtime_backend.dart';

/// Runtime Auth resources of the selected backend.
///
/// The client itself is owned by the app bootstrap, which also owns
/// `Supabase.instance` for the legacy developer path. This value only carries
/// what the provider graph needs to resolve the active backend and its Auth
/// boundary.
@immutable
class RuntimeAuthStack {
  const RuntimeAuthStack({
    required this.backend,
    this.repository,
    this.controller,
  });

  /// No Supabase runtime at all.
  const RuntimeAuthStack.localOnly()
    : backend = const LocalOnlyRuntimeBackend(),
      repository = null,
      controller = null;

  final RuntimeBackend backend;

  /// Auth boundary of [backend], or null when there is no runtime Auth.
  final AuthRepository? repository;

  /// App-lifetime session reducer for [repository], when one exists.
  ///
  /// Bootstrap supplies it for both runtime paths so exactly one controller
  /// observes exactly one client.
  final AuthSessionController? controller;

  bool get hasRuntimeAuth => repository != null && controller != null;
}

/// Holds the active [RuntimeAuthStack].
///
/// Bootstrap creates the container override with the resolved stack, and
/// replaces the value when a backend finishes provisioning while the app is
/// running, so no dynamic client ever becomes a global mutable singleton.
class RuntimeAuthStackNotifier extends Notifier<RuntimeAuthStack> {
  RuntimeAuthStackNotifier([RuntimeAuthStack? initialState])
    : _initialState = initialState;

  final RuntimeAuthStack? _initialState;

  @override
  RuntimeAuthStack build() => _initialState ?? _defaultRuntimeAuthStack();

  void replace(RuntimeAuthStack next) => state = next;
}

final runtimeAuthStackProvider =
    NotifierProvider<RuntimeAuthStackNotifier, RuntimeAuthStack>(
      RuntimeAuthStackNotifier.new,
    );

/// The runtime backend the current provider container is scoped to.
final runtimeBackendProvider = Provider<RuntimeBackend>(
  (ref) => ref.watch(runtimeAuthStackProvider).backend,
);

/// Fallback resolution for isolated provider tests and for libraries that read
/// these providers outside a bootstrapped app.
///
/// It can only ever describe the compile-time developer configuration: a
/// provisioned profile needs a durable file read, which the app bootstrap does
/// before the first frame.
RuntimeAuthStack _defaultRuntimeAuthStack() {
  final backend = resolveRuntimeBackend(
    legacyStaticConfigured: SupabaseConfig.isConfigured,
    legacyStaticUrl: SupabaseConfig.url,
    legacyStaticPublishableKey: SupabaseConfig.publishableKey,
  );
  if (backend is! LegacyStaticRuntimeBackend) {
    return RuntimeAuthStack(backend: backend);
  }
  return RuntimeAuthStack(
    backend: backend,
    repository: AuthRepository(
      SupabaseRuntimeAuthClient(Supabase.instance.client),
    ),
  );
}

/// Bootstrap-owned hook that re-reads durable connection state.
///
/// The Settings → Sync cloud-setup card asks for this when provisioning reaches
/// READY, so the runtime Auth client of the new user-owned project is created
/// without restarting the Planner. It is a no-op when the active backend
/// already matches durable state, or when compile-time configuration wins.
abstract interface class RuntimeBackendReloader {
  Future<void> reload();
}

/// Null when nothing owns runtime backend lifecycle (tests, and any container
/// that bootstrap did not build).
final runtimeBackendReloaderProvider = Provider<RuntimeBackendReloader?>(
  (ref) => null,
);

/// Bootstrap-owned health of the durable backend profile.
///
/// Local-only is the correct fallback for an unreadable profile, but it must
/// never be *indistinguishable* from "no cloud backend was ever configured":
/// the user would see cloud setup as untouched while their stored connection
/// silently stopped working. Bootstrap publishes the real outcome here so Sync
/// settings can offer the explicit repair path.
class BackendProfileHealthNotifier extends Notifier<BackendProfileHealth> {
  BackendProfileHealthNotifier([
    BackendProfileHealth initialState = BackendProfileHealth.ok,
  ]) : _initialState = initialState;

  final BackendProfileHealth _initialState;

  @override
  BackendProfileHealth build() => _initialState;

  void replace(BackendProfileHealth next) => state = next;
}

final backendProfileHealthProvider =
    NotifierProvider<BackendProfileHealthNotifier, BackendProfileHealth>(
      BackendProfileHealthNotifier.new,
    );
