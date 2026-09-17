import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/planner_account_scope.dart';
import '../../../core/providers/database_provider.dart';
import '../data/anonymous_data_adoption.dart';
import '../data/auth_repository.dart';
import '../data/sync_repository.dart';
import '../domain/auth_session_controller.dart';
import '../domain/sync_engine.dart';
import '../domain/sync_models.dart';
import 'runtime_backend_providers.dart';
import 'sync_settings_provider.dart';

/// Auth boundary of the selected runtime backend, or null when this
/// installation has no cloud backend connected.
final authRepositoryProvider = Provider<AuthRepository?>(
  (ref) => ref.watch(runtimeAuthStackProvider).repository,
);

/// Bootstrap overrides this with its single app-lifetime reducer. The fallback
/// keeps isolated provider tests usable without a second production source.
final authSessionControllerProvider = Provider<AuthSessionController?>((ref) {
  final stack = ref.watch(runtimeAuthStackProvider);
  final controller = stack.controller;
  if (controller != null) return controller;
  final repository = stack.repository;
  if (repository == null) return null;
  final fallback = AuthSessionController(repository);
  ref.onDispose(() => unawaited(fallback.dispose()));
  return fallback;
});

/// Bootstrap supplies the canonical identity of the database currently open in
/// this container. A token cannot select a different account's local outbox,
/// and two Supabase projects that issued the same auth user id are still
/// different accounts.
final openAccountScopeProvider = Provider<PlannerAccountScope?>((ref) => null);

final anonymousDataAdoptionProvider = Provider<AnonymousDataAdoptionService>((
  ref,
) {
  return AnonymousDataAdoptionService(ref.watch(appDatabaseProvider));
});

final anonymousDataSummaryProvider =
    FutureProvider.autoDispose<AnonymousDataSummary>((ref) {
      return ref.watch(anonymousDataAdoptionProvider).inspect();
    });

final authSessionStateProvider = StreamProvider<AuthSessionState?>((ref) {
  return _authStateStream(ref.watch(authSessionControllerProvider));
});

/// Health changes never become stream errors, so a retryable SDK refresh
/// cannot terminate the session provider or tear down the local database.
final authSessionProvider = StreamProvider<Session?>((ref) {
  return _authStateStream(ref.watch(authSessionControllerProvider))
      .map((state) => state?.session);
});

Stream<AuthSessionState?> _authStateStream(
  AuthSessionController? controller,
) async* {
  if (controller == null) {
    yield null;
    return;
  }
  await controller.start();
  yield controller.current;
  yield* controller.states;
}

final connectivityProvider =
    StreamProvider.autoDispose<List<ConnectivityResult>>((ref) async* {
      final connectivity = ref.watch(syncConnectivityMonitorProvider);
      yield await connectivity.check();
      yield* connectivity.changes;
    });

final syncConnectivityMonitorProvider = Provider<SyncConnectivityMonitor>((
  ref,
) {
  return PlatformSyncConnectivityMonitor();
});

final syncRepositoryProvider = Provider<SyncRepository?>((ref) {
  final backend = ref.watch(runtimeBackendProvider);
  // Phase EF boundary: only the compile-time developer backend carries a
  // normal Planner data endpoint. A provisioned user-owned backend has runtime
  // Auth but no Planner data synchronization yet, so it gets no repository, no
  // engine, and no "Sync now"; Phase G owns that decision.
  final endpoint = backend.plannerDataSyncEndpoint;
  if (endpoint == null) return null;
  final controller = ref.watch(authSessionControllerProvider);
  final session = ref.watch(authSessionStateProvider).value?.session;
  final openScope = ref.watch(openAccountScopeProvider);
  final enabled = ref.watch(syncEnabledProvider).value ?? true;
  if (controller == null || session == null || !enabled) {
    return null;
  }
  // The canonical account scope is (projectRef, authUserId), so this guard also
  // rejects a same-user-id session that belongs to a different project.
  final scope = backend.accountScopeFor(session.user.id);
  if (scope == null || openScope != scope) return null;
  if (!controller.hasUsableAccessToken(session)) {
    unawaited(controller.requestRefreshIfNeeded());
    return null;
  }
  // Do not let an in-flight request read the mutable singleton auth session.
  // This scoped client always supplies the token captured for this provider
  // generation; auth/session changes dispose this repository and create a new
  // one. The repository's owner guard also prevents a stale provider from
  // applying a response after the account changes.
  final scopedClient = SupabaseClient(
    endpoint.url,
    endpoint.publishableKey,
    accessToken: () async {
      if (controller.current.session?.user.id != session.user.id ||
          !controller.hasUsableAccessToken(session)) {
        throw const _SyncAccessTokenUnavailable();
      }
      return session.accessToken;
    },
  );
  ref.onDispose(() => unawaited(scopedClient.dispose()));
  return SyncRepository(
    ref.watch(appDatabaseProvider),
    scopedClient,
    scope.storageId,
    currentAccountId: () {
      final current = controller.current.session;
      if (current == null) return null;
      return backend.accountScopeFor(current.user.id)?.storageId;
    },
  );
});

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final repository = ref.watch(syncRepositoryProvider);
  if (repository == null) return null;
  final engine = SyncEngine(
    ref.watch(appDatabaseProvider),
    repository,
    ref.watch(syncConnectivityMonitorProvider),
    authController: ref.watch(authSessionControllerProvider),
  );
  ref.onDispose(() => unawaited(engine.stop()));
  unawaited(engine.start());
  return engine;
});

final syncStatusProvider = StreamProvider.autoDispose<SyncStatusSnapshot>((
  ref,
) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) {
    return _authGatedStatus(ref.watch(authSessionControllerProvider));
  }
  return engine.status;
});

Stream<SyncStatusSnapshot> _authGatedStatus(
  AuthSessionController? controller,
) async* {
  if (controller == null) {
    yield const SyncStatusSnapshot(state: SyncEngineState.notConfigured);
    return;
  }
  await controller.start();
  yield _statusForAuth(controller);
  yield* controller.states.map((_) => _statusForAuth(controller));
}

SyncStatusSnapshot _statusForAuth(AuthSessionController controller) {
  final state = controller.current;
  if (state.health == AuthSessionHealth.reauthenticationRequired) {
    return const SyncStatusSnapshot(
      state: SyncEngineState.authFailure,
      message:
          'Session ended. Sign in again; local data remains on this device.',
    );
  }
  if (state.health == AuthSessionHealth.storageError) {
    return const SyncStatusSnapshot(
      state: SyncEngineState.error,
      message:
          'Secure session storage needs attention. Retry the app bootstrap.',
    );
  }
  if (state.health == AuthSessionHealth.retryingRefresh ||
      (state.session != null && !controller.hasUsableAccessToken())) {
    return const SyncStatusSnapshot(
      state: SyncEngineState.refreshPaused,
      message: 'Session refresh is pending; local work is safe.',
    );
  }
  return const SyncStatusSnapshot(state: SyncEngineState.notConfigured);
}

class _SyncAccessTokenUnavailable implements Exception {
  const _SyncAccessTokenUnavailable();
}

final syncConflictsProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(appDatabaseProvider).syncDao.watchConflicts();
});

final syncPermanentOperationsProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(appDatabaseProvider).syncDao.watchPermanentOperations();
});

final syncQuarantinedChangesProvider = StreamProvider.autoDispose((ref) {
  return ref
      .watch(appDatabaseProvider)
      .syncDao
      .watchQuarantinedChanges()
      .map((settings) => settings.map(_decodeQuarantine).toList());
});

SyncQuarantinedChange _decodeQuarantine(AppSetting setting) {
  try {
    return SyncQuarantinedChange.fromSetting(setting.key, setting.value);
  } catch (_) {
    return SyncQuarantinedChange(
      storageKey: setting.key,
      accountId: '',
      changeId: 0,
      diagnostic: 'A retained sync record could not be decoded.',
    );
  }
}
