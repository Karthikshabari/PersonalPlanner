import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/planner_account_scope.dart';
import '../../../core/providers/database_provider.dart';
import '../data/anonymous_data_adoption.dart';
import '../data/auth_repository.dart';
import '../data/initial_sync_coordinator.dart';
import '../data/initial_sync_gateway.dart';
import '../data/initial_sync_state_store.dart';
import '../data/sync_repository.dart';
import '../domain/auth_callback_notice.dart';
import '../domain/auth_session_controller.dart';
import '../domain/initial_sync_models.dart';
import '../domain/runtime_backend.dart';
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

/// Sanitized outcome of the most recent provisioned Auth callback, or null.
///
/// A rejected callback never changes the session or the active scope; this is
/// only the bounded message the Sync screen can show next to the sign-in form.
final authCallbackNoticeProvider = StreamProvider<AuthCallbackNotice?>((ref) {
  return _authCallbackNoticeStream(ref.watch(authSessionControllerProvider));
});

Stream<AuthCallbackNotice?> _authCallbackNoticeStream(
  AuthSessionController? controller,
) async* {
  if (controller == null) {
    yield null;
    return;
  }
  yield controller.lastCallbackNotice;
  yield* controller.callbackNotices;
}

/// Bootstrap supplies the canonical identity of the database currently open in
/// this container. A token cannot select a different account's local outbox,
/// and two Supabase projects that issued the same auth user id are still
/// different accounts.
final openAccountScopeProvider = Provider<PlannerAccountScope?>((ref) => null);

/// Opens the stable anonymous/offline-only database. Overridable so tests can
/// supply a temporary file-backed database instead of the platform application
/// directory.
final anonymousDatabaseFactoryProvider =
    Provider<Future<AppDatabase> Function()>((ref) => AppDatabase.open);

final anonymousDataAdoptionProvider = Provider<AnonymousDataAdoptionService>((
  ref,
) {
  return AnonymousDataAdoptionService(
    ref.watch(appDatabaseProvider),
    anonymousDatabaseFactory: ref.watch(anonymousDatabaseFactoryProvider),
  );
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

/// Builds the remote gateways of the selected backend. Tests substitute
/// recording fakes so the Phase G state machine runs without a network.
final syncRemoteFactoryProvider = Provider<SyncRemoteFactory>(
  (ref) => const SupabaseSyncRemoteFactory(),
);

/// The scoped Supabase client and canonical account identity of the *current*
/// authenticated account, or null when this installation must not talk to a
/// Planner data endpoint right now.
///
/// The client is created here so both the initial-sync coordinator and the
/// normal SyncRepository share exactly one scoped client per provider
/// generation. It always supplies the token captured for this generation and
/// the repository's owner guard rejects responses that arrive after the account
/// changed.
class SyncAccountBinding {
  const SyncAccountBinding({
    required this.backend,
    required this.scope,
    required this.endpoint,
    required this.client,
    this.currentAccountId,
  });

  final RuntimeBackend backend;
  final PlannerAccountScope scope;
  final RuntimeSupabaseEndpoint endpoint;
  final SupabaseClient client;

  /// Live canonical account id of the runtime Auth stack, or null when no
  /// session is active.
  final String? Function()? currentAccountId;

  String get accountId => scope.storageId;

  bool get isProvisioned => backend is ProvisionedRuntimeBackend;
}

final syncAccountBindingProvider = Provider<SyncAccountBinding?>((ref) {
  final backend = ref.watch(runtimeBackendProvider);
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
  // generation; auth/session changes dispose it and create a new one.
  final scopedClient = SupabaseClient(
    endpoint.url,
    endpoint.publishableKey,
    // This client authenticates every request through the captured callback;
    // it has no Auth session of its own to refresh.
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    accessToken: () async {
      if (controller.current.session?.user.id != session.user.id ||
          !controller.hasUsableAccessToken(session)) {
        throw const _SyncAccessTokenUnavailable();
      }
      return session.accessToken;
    },
  );
  ref.onDispose(() => unawaited(scopedClient.dispose()));
  return SyncAccountBinding(
    backend: backend,
    scope: scope,
    endpoint: endpoint,
    client: scopedClient,
    currentAccountId: () {
      final current = controller.current.session;
      if (current == null) return null;
      return backend.accountScopeFor(current.user.id)?.storageId;
    },
  );
});

/// Durable Phase G first-sync state of the currently open account database.
///
/// `notApplicable` is returned for every non-provisioned backend: the
/// provisioned first-sync gate does not apply to the compile-time developer
/// path, which keeps its historical behaviour.
final syncInitialSyncProvider =
    StreamProvider.autoDispose<InitialSyncStatus>((ref) {
      final backend = ref.watch(runtimeBackendProvider);
      if (backend is! ProvisionedRuntimeBackend) {
        return Stream.value(InitialSyncStatus.notApplicable);
      }
      return InitialSyncStateStore(ref.watch(appDatabaseProvider))
          .watch()
          .map(InitialSyncStatus.fromRecord);
    });

/// Phase G initial-synchronization orchestrator of the current provisioned
/// account, or null when this runtime has no provisioned account open.
final initialSyncCoordinatorProvider = Provider<InitialSyncCoordinator?>((
  ref,
) {
  final backend = ref.watch(runtimeBackendProvider);
  if (backend is! ProvisionedRuntimeBackend) return null;
  final binding = ref.watch(syncAccountBindingProvider);
  if (binding == null) return null;
  final database = ref.watch(appDatabaseProvider);
  final remoteFactory = ref.watch(syncRemoteFactoryProvider);
  final coordinator = InitialSyncCoordinator(
    database: database,
    scope: binding.scope,
    gateway: remoteFactory.createInitialSyncGateway(binding.client),
    repositoryFactory: () => SyncRepository.withGateway(
      database,
      remoteFactory.createSyncGateway(binding.client),
      binding.accountId,
      currentAccountId: binding.currentAccountId,
    ),
    anonymousDatabaseFactory: ref.watch(anonymousDatabaseFactoryProvider),
    currentAccountId: binding.currentAccountId,
    seedDefaultsIfEmpty: () =>
        ref.read(categoryRepositoryProvider).seedDefaultsIfEmpty(),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  // A provisioned account must determine the remote Planner state as soon as
  // it is connected, before any local mutation could be pushed. Starting here
  // (rather than only from the Settings screen) means a fresh device restores
  // its cloud data without the user opening Sync settings.
  unawaited(coordinator.start());
  return coordinator;
});

final syncRepositoryProvider = Provider<SyncRepository?>((ref) {
  final binding = ref.watch(syncAccountBindingProvider);
  if (binding == null) return null;
  // Phase G boundary: a provisioned user-owned backend gets Auth and the
  // first-sync coordinator immediately, but normal Planner data
  // synchronization - repository, engine, automatic push/pull, "Sync now" -
  // only exists once the durable initial synchronization baseline is complete.
  // Authentication alone, and a READY backend alone, are both insufficient.
  if (binding.isProvisioned &&
      !(ref.watch(syncInitialSyncProvider).value?.baselineComplete ??
          false)) {
    return null;
  }
  return SyncRepository.withGateway(
    ref.watch(appDatabaseProvider),
    ref.watch(syncRemoteFactoryProvider).createSyncGateway(binding.client),
    binding.accountId,
    currentAccountId: binding.currentAccountId,
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
  if (engine != null) return engine.status;
  // No engine means either no usable runtime Auth, or a provisioned account
  // whose initial synchronization is not complete yet. Both cases are
  // described from durable state, and neither ever claims cloud sync is
  // active.
  final backend = ref.watch(runtimeBackendProvider);
  final initialSync = ref.watch(syncInitialSyncProvider).value;
  return _authGatedStatus(
    ref.watch(authSessionControllerProvider),
    provisioned: backend is ProvisionedRuntimeBackend
        ? (initialSync ?? InitialSyncStatus.unresolved)
        : null,
  );
});

Stream<SyncStatusSnapshot> _authGatedStatus(
  AuthSessionController? controller, {
  InitialSyncStatus? provisioned,
}) async* {
  if (controller == null) {
    yield _statusForInitialSync(provisioned) ??
        const SyncStatusSnapshot(state: SyncEngineState.notConfigured);
    return;
  }
  await controller.start();
  yield _statusForAuth(controller, provisioned: provisioned);
  yield* controller.states.map(
    (_) => _statusForAuth(controller, provisioned: provisioned),
  );
}

SyncStatusSnapshot _statusForAuth(
  AuthSessionController controller, {
  InitialSyncStatus? provisioned,
}) {
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
  final initialSync = _statusForInitialSync(provisioned);
  if (initialSync != null) return initialSync;
  return const SyncStatusSnapshot(state: SyncEngineState.notConfigured);
}

/// Pre-baseline status of a provisioned account, or null once the safe initial
/// synchronization baseline exists (normal sync reports from then on) and for
/// every non-provisioned backend.
SyncStatusSnapshot? _statusForInitialSync(InitialSyncStatus? status) {
  if (status == null || status.baselineComplete) return null;
  return SyncStatusSnapshot(
    state: SyncEngineState.initialSyncPending,
    message: status.message ?? provisionedPhaseDescription(status.phase),
  );
}

String provisionedPhaseDescription(InitialSyncPhase phase) => switch (phase) {
  InitialSyncPhase.unresolved =>
    'Cloud sync setup has not run yet. Local planning keeps working.',
  InitialSyncPhase.discovering =>
    'Checking whether this cloud account already contains Planner data.',
  InitialSyncPhase.remoteExisting =>
    'Cloud Planner data was found and will be restored before anything is '
        'uploaded.',
  InitialSyncPhase.restoring =>
    'Restoring Planner data from your cloud account.',
  InitialSyncPhase.remoteEmpty =>
    'The cloud account is empty; the first upload is being prepared.',
  InitialSyncPhase.adoptionRequired =>
    'The cloud account is empty. Offline-only Planner data needs your '
        'decision before anything is uploaded.',
  InitialSyncPhase.uploading =>
    'Uploading your local Planner data to the empty cloud account.',
  InitialSyncPhase.conflict =>
    'Local and cloud Planner data both exist. Nothing was overwritten.',
  InitialSyncPhase.recoveryRequired =>
    'A previous device started the first cloud synchronization and never '
        'finished it, and the cloud already holds part of that data. Nothing '
        'was merged or overwritten; this account needs your decision.',
  InitialSyncPhase.retryable =>
    'Cloud setup will retry. Local planning keeps working.',
  InitialSyncPhase.complete => 'Cloud synchronization is ready.',
};



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
