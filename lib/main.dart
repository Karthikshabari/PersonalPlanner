import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/database/app_database.dart';
import 'core/models/planner_account_scope.dart';
import 'core/providers/database_provider.dart';
import 'core/router/app_router.dart';
import 'core/utils/date_utils.dart';
import 'core/widgets/error_panel.dart';
import 'features/recurring/providers/recurring_providers.dart';
import 'features/settings/providers/notification_settings_providers.dart';
import 'features/sync/data/auth_repository.dart';
import 'features/sync/data/app_link_source.dart';
import 'features/sync/data/connection_profile_store.dart';
import 'features/sync/data/initial_sync_state_store.dart';
import 'features/sync/data/runtime_auth_client.dart';
import 'features/sync/data/runtime_auth_callback.dart';
import 'features/sync/data/runtime_supabase_client.dart';
import 'features/sync/data/secure_session_storage.dart';
import 'features/sync/domain/backend_connection_profile.dart';
import 'features/sync/domain/auth_session_controller.dart';
import 'features/sync/domain/runtime_backend.dart';
import 'features/sync/domain/sync_engine.dart';
import 'features/sync/providers/runtime_backend_providers.dart';
import 'features/sync/providers/deep_link_providers.dart';
import 'features/sync/providers/sync_providers.dart';
import 'features/timer/domain/notification_service.dart';
import 'features/timer/domain/timer_service.dart';
import 'features/timer/platform/android_foreground_timer.dart';
import 'features/timer/providers/timer_providers.dart';
import 'platform/desktop/window_manager.dart';

_RuntimeAuthBootstrap? _runtimeAuthBootstrap;

/// App-lifetime runtime Auth resources of the selected backend.
///
/// Exactly one exists at a time and the bootstrap owns it, including disposal,
/// so a dynamically created client never becomes a global mutable singleton.
class _RuntimeAuthBootstrap {
  const _RuntimeAuthBootstrap({
    required this.backend,
    required this.repository,
    required this.authController,
    this.authCallbackRouter,
    this.ownedClient,
  });

  final RuntimeBackend backend;

  /// Secure-storage-aware Auth boundary. Sign-out cleanup and the scoped
  /// session lifecycle of the provisioned path live here.
  final AuthRepository repository;

  final AuthSessionController authController;

  /// Provisioned deep-link router of [backend], or null for the compile-time
  /// developer path, whose deep links stay owned by `supabase_flutter`.
  final ProvisionedAuthCallbackRouter? authCallbackRouter;

  /// The dynamically created client of the provisioned path, owned and disposed
  /// here. Null for the compile-time developer path, whose client is the
  /// app-wide `Supabase.instance` singleton.
  final SupabaseClient? ownedClient;

  RuntimeAuthStack get stack => RuntimeAuthStack(
    backend: backend,
    repository: repository,
    controller: authController,
  );

  Future<void> dispose() async {
    await authCallbackRouter?.dispose();
    final client = ownedClient;
    if (client == null) {
      // The compile-time developer client is the app-wide singleton.
      await authController.dispose();
      await repository.dispose();
      return;
    }
    await _releaseRuntimeAuthResources(
      client: client,
      controller: authController,
      repository: repository,
    );
  }
}

/// Durable backend-profile read outcome, including why it could not be used.
///
/// [health] is `ok` for "no profile" and for a successfully read profile, so a
/// caller can distinguish "never configured" from "configured but unreadable".
@immutable
class ProvisionedBackendRead {
  const ProvisionedBackendRead({
    this.backend,
    this.health = BackendProfileHealth.ok,
  });

  /// The active provisioned backend, or null when there is none (including an
  /// explicitly disconnected profile).
  final ProvisionedRuntimeBackend? backend;

  /// Health of the stored document itself.
  final BackendProfileHealth health;
}

/// Test seams of the bootstrap lifecycle.
///
/// Production always uses the defaults. Bootstrap tests substitute an in-memory
/// database opener, a no-op local-service layer and scripted runtime Auth steps,
/// so the real account-scope switch lifecycle can run without platform plugins,
/// a keyring, or a network.
@visibleForTesting
class PlannerBootstrapSeams {
  const PlannerBootstrapSeams({
    this.readProvisionedBackend = _readProvisionedBackend,
    this.installProvisionedRuntimeAuth = _createProvisionedRuntimeAuth,
    this.appLinkSource,
    this.openDatabase = AppDatabase.open,
    this.initializeLocalServices = _initializeLocalServices,
    this.shutdownLocalServices = _shutdownLocalServicesForSeam,
  });

  /// Reads the durable connection profile and returns the READY provisioned
  /// backend, or null when there is none or it is explicitly disconnected.
  ///
  /// The failure travels with the result so bootstrap can publish a
  /// recoverable needs-attention state instead of silently presenting an
  /// unusable stored connection as "never configured".
  final Future<ProvisionedBackendRead> Function() readProvisionedBackend;

  /// Installs the runtime Auth resources of [backend].
  ///
  /// The app-lifetime deep-link source travels with it so the Planner Auth
  /// callback router observes the same single platform subscription as the
  /// provisioning UI.
  final Future<void> Function(
    ProvisionedRuntimeBackend backend,
    AppLinkSource links,
  )
  installProvisionedRuntimeAuth;

  /// App-lifetime deep-link source, or null for an inert one.
  ///
  /// Production always supplies the started source; tests that never deliver a
  /// link leave it null.
  final AppLinkSource? appLinkSource;

  /// Opens the database of an account scope id (null is the anonymous one).
  final Future<AppDatabase> Function({String? accountId}) openDatabase;

  /// Initializes the non-cloud local services of an opened account database.
  final Future<SyncEngine?> Function(
    ProviderContainer container, {
    required Future<void> Function() beforeWindowClose,
  })
  initializeLocalServices;

  /// Releases an opened account database and its local services.
  ///
  /// [persistWindow] is false only while the desktop window is closing.
  final Future<void> Function(
    ProviderContainer container,
    AppDatabase database,
    SyncEngine? engine,
    bool persistWindow,
  )
  shutdownLocalServices;
}

/// Root widget of the app.
///
/// [main] runs this after resolving runtime Auth. Bootstrap tests build the same
/// widget with [PlannerBootstrapSeams].
@visibleForTesting
Widget plannerBootstrap({
  Object? initialBootstrapError,
  BackendProfileHealth initialProfileHealth = BackendProfileHealth.ok,
  PlannerBootstrapSeams seams = const PlannerBootstrapSeams(),
}) => _PlannerBootstrap(
  initialBootstrapError: initialBootstrapError,
  initialProfileHealth: initialProfileHealth,
  seams: seams,
);

/// Installs runtime Auth resources for a bootstrap test.
///
/// Production installs them through [_createProvisionedRuntimeAuth].
@visibleForTesting
void installRuntimeAuthBootstrapForTesting({
  required RuntimeBackend backend,
  required AuthRepository repository,
  required AuthSessionController controller,
}) {
  _runtimeAuthBootstrap = _RuntimeAuthBootstrap(
    backend: backend,
    repository: repository,
    authController: controller,
  );
}

/// Releases whatever runtime Auth stack is installed. Test helper.
@visibleForTesting
Future<void> resetRuntimeAuthBootstrapForTesting() =>
    _disposeRuntimeAuthBootstrap();

/// The account database and provider container the Planner must have open.
///
/// The pair matters: a container is only valid for one runtime Auth stack
/// **instance** (a replaced stack must rebuild it even when the account scope
/// looks unchanged) and for one canonical `(projectRef, authUserId)` scope, so
/// two projects that issued the same auth user id can never share one.
@immutable
class _AccountDatabaseTarget {
  const _AccountDatabaseTarget({
    required this.runtimeAuth,
    required this.accountScope,
  });

  /// Runtime Auth resources this container belongs to. Compared by identity: a
  /// replacement installs a new instance.
  final _RuntimeAuthBootstrap? runtimeAuth;

  /// Canonical account scope of the database. Null is the anonymous database.
  final PlannerAccountScope? accountScope;

  /// Storage id of the database this target opens.
  String? get accountId => accountScope?.storageId;

  @override
  bool operator ==(Object other) =>
      other is _AccountDatabaseTarget &&
      identical(other.runtimeAuth, runtimeAuth) &&
      other.accountScope == accountScope;

  @override
  int get hashCode => Object.hash(accountScope, identityHashCode(runtimeAuth));
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.demangleStackTrace = _demangleStackTrace;
  ErrorWidget.builder = (_) => const ErrorPanel(
    message: 'This screen could not be displayed. Please retry.',
  );
  // Exactly one subscription to the platform deep-link stream for the whole app
  // lifetime, started before anything can deliver a link. Linux cold starts
  // reach the process as command-line arguments, so they are replayed here.
  final appLinkSource = AppLinkSource(launchArguments: arguments);
  await appLinkSource.start();
  final seams = PlannerBootstrapSeams(appLinkSource: appLinkSource);
  Object? bootstrapError;
  var profileHealth = BackendProfileHealth.ok;
  try {
    profileHealth = await _initializeRuntimeAuth(seams);
  } catch (error, stack) {
    bootstrapError = error;
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  }
  runApp(
    plannerBootstrap(
      initialBootstrapError: bootstrapError,
      initialProfileHealth: profileHealth,
      seams: seams,
    ),
  );
}

/// Drift and other async libraries can propagate package:stack_trace objects.
/// Flutter's error presenter expects VM-format traces on desktop platforms.
StackTrace _demangleStackTrace(StackTrace stack) {
  if (stack is Trace) return stack.vmTrace;
  if (stack is Chain) return stack.toTrace().vmTrace;
  return stack;
}

/// Resolves and prepares the runtime Auth backend once, before the first frame.
///
/// Only local reads happen here. No network call may block startup, so an
/// unreachable, unfinished, or unreadable cloud backend simply leaves the
/// Planner local-only.
Future<BackendProfileHealth> _initializeRuntimeAuth([
  PlannerBootstrapSeams seams = const PlannerBootstrapSeams(),
]) async {
  if (SupabaseConfig.isConfigured) {
    // The compile-time developer configuration keeps precedence, so a stored
    // profile can never take over an explicitly configured build.
    await _initializeSupabaseIfConfigured();
    return BackendProfileHealth.ok;
  }
  final read = await seams.readProvisionedBackend();
  final backend = read.backend;
  if (backend == null) {
    await _disposeRuntimeAuthBootstrap();
    return read.health;
  }
  await seams.installProvisionedRuntimeAuth(
    backend,
    seams.appLinkSource ?? AppLinkSource.inert(),
  );
  return read.health;
}

/// Reads the durable connection profile and returns the provisioned backend.
///
/// Returns null when there is no profile, when the profile is not READY, or
/// when it cannot be trusted, so a partial or corrupt profile never produces a
/// runtime client.
Future<ProvisionedBackendRead> _readProvisionedBackend() async {
  final BackendConnectionProfile? profile;
  try {
    profile = await ConnectionProfileStore().read();
  } on ConnectionProfileStoreException catch (error) {
    // An unreadable profile is not a startup blocker: the Planner keeps working
    // locally and the provisioning card stays the repair path. The failure is
    // still reported so the user is told their stored connection needs
    // attention rather than being shown a never-configured Planner.
    return ProvisionedBackendRead(
      health: BackendProfileHealth.fromFailure(error.failure),
    );
  }
  return ProvisionedBackendRead(
    backend: ProvisionedRuntimeBackend.tryFromProfile(profile),
  );
}

/// Builds the runtime Auth connection for a provisioned user-owned project.
///
/// The client comes from the client-safe READY profile only, so no provisioning
/// capability, Management token, or secret key is reachable from this path.
Future<void> _createProvisionedRuntimeAuth(
  ProvisionedRuntimeBackend backend,
  AppLinkSource links,
) async {
  // One secure key-value boundary, shared by this project's session, PKCE
  // verifier, and pending-callback marker namespaces.
  final secureStorage = FlutterSecureKeyValueStore();
  final created = RuntimeSupabaseClientFactory(secureStorage: secureStorage)
      .createWithStorage(backend);
  final client = created.client;
  final runtimeAuthClient = SupabaseRuntimeAuthClient(client);
  final storage = SecureSupabaseLocalStorage(
    storage: secureStorage,
    sessionKey: backend.authNamespaces.sessionKey,
  );
  final flow = ProvisionedAuthCallbackFlow(
    backend: backend,
    storage: secureStorage,
  );
  final repository = AuthRepository(
    runtimeAuthClient,
    sessionStorage: storage,
    provisionedAuthFlow: flow,
  );
  final controller = AuthSessionController(repository);
  storage.onOutcome = controller.recordStorageOutcome;
  // Created together with this runtime's client: a callback can only ever be
  // exchanged by the project that owns this PKCE namespace.
  final router = ProvisionedAuthCallbackRouter(
    backend: backend,
    client: runtimeAuthClient,
    flow: flow,
    // Raw strings, because a delivered link is routed by exact destination and
    // because the shared source already owns the single platform subscription.
    links: links.links,
    onOutcome: (outcome) =>
        controller.recordAuthCallbackOutcome(outcome.notice),
  );
  try {
    // Restores only this project's scoped session. A legacy global session
    // lives under a different key and is never restored into a project.
    await repository.attachScopedSessionStorage();
  } catch (error, stack) {
    // A secure-storage failure must not look like "no session": the Planner
    // would otherwise open the anonymous database while the user believes the
    // cloud account is connected. Surface it as a bootstrap failure with Retry
    // instead of guessing, exactly like the compile-time developer path.
    await router.dispose();
    await _releaseRuntimeAuthResources(
      client: client,
      controller: controller,
      repository: repository,
    );
    Error.throwWithStackTrace(error, stack);
  }
  await controller.start();
  router.start();
  final previous = _runtimeAuthBootstrap;
  _runtimeAuthBootstrap = _RuntimeAuthBootstrap(
    backend: backend,
    repository: repository,
    authController: controller,
    authCallbackRouter: router,
    ownedClient: client,
  );
  await previous?.dispose();
}

Future<void> _releaseRuntimeAuthResources({
  required SupabaseClient client,
  required AuthSessionController controller,
  required AuthRepository repository,
}) async {
  await controller.dispose();
  await repository.dispose();
  try {
    await client.dispose();
  } catch (_) {
    // A client that never finished initializing has nothing left to release.
  }
}

Future<void> _initializeSupabaseIfConfigured() async {
  if (!SupabaseConfig.isConfigured) return;
  final collector = SecureSessionBootstrapCollector();
  final storage = SecureSupabaseLocalStorage(onOutcome: collector.record);
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: FlutterAuthClientOptions(
      autoRefreshToken: true,
      localStorage: storage,
      pkceAsyncStorage: SecureSupabasePkceStorage(),
    ),
  );
  // supabase_flutter catches storage-read failures during recovery. Do not let
  // that caught error look like a valid empty session and open anonymous data.
  if (collector.requiresRetry) {
    try {
      await Supabase.instance.dispose();
    } catch (_) {
      // The retry path below still creates a fresh adapter and collector.
    }
    requireSecureSessionBootstrapReady(collector);
  }
  // The legacy developer path keeps its historical global session namespace and
  // lets supabase_flutter's own singleton wrapper restore and persist it.
  final repository = AuthRepository(
    SupabaseRuntimeAuthClient(Supabase.instance.client),
    sessionStorage: storage,
  );
  final controller = AuthSessionController(repository);
  storage.onOutcome = controller.recordStorageOutcome;
  await controller.start();
  _runtimeAuthBootstrap = _RuntimeAuthBootstrap(
    backend: LegacyStaticRuntimeBackend(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    ),
    repository: repository,
    authController: controller,
  );
}

Future<void> _disposeRuntimeAuthBootstrap() async {
  final resources = _runtimeAuthBootstrap;
  _runtimeAuthBootstrap = null;
  await resources?.dispose();
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.instance.dispose();
    } catch (_) {
      // It is valid for initialization to have failed before a singleton was
      // fully allocated. The next initialization remains authoritative.
    }
  }
}

class _PlannerBootstrap extends StatefulWidget {
  final Object? initialBootstrapError;
  final BackendProfileHealth initialProfileHealth;
  final PlannerBootstrapSeams seams;

  const _PlannerBootstrap({
    this.initialBootstrapError,
    this.initialProfileHealth = BackendProfileHealth.ok,
    this.seams = const PlannerBootstrapSeams(),
  });

  @override
  State<_PlannerBootstrap> createState() => _PlannerBootstrapState();
}

class _PlannerBootstrapState extends State<_PlannerBootstrap>
    with WidgetsBindingObserver {
  AppDatabase? _database;
  ProviderContainer? _container;
  SyncEngine? _syncEngine;
  StreamSubscription<AuthSessionState>? _authSubscription;

  /// The account database/container/local services that are actually open, or
  /// null while nothing is open.
  ///
  /// Written only after [_switchDatabase] has published a container that
  /// matches this target. Auth saying a different scope is desired never
  /// overwrites it, otherwise the drain below could conclude "already open" and
  /// leave the previous account's database active.
  _AccountDatabaseTarget? _openTarget;

  /// The most recent target Auth asked for. It differs from [_openTarget] while
  /// a switch is in flight, after a failed switch, and after a runtime Auth
  /// replacement that still has to be applied.
  _AccountDatabaseTarget? _requestedTarget;

  Future<void>? _databaseSwitch;
  Object? _error;
  Object? _bootstrapError;
  late BackendProfileHealth _profileHealth;

  /// App-lifetime deep-link source of this bootstrap, or an inert one.
  late final AppLinkSource _appLinkSource;
  bool _switching = true;

  @override
  void initState() {
    super.initState();
    _appLinkSource = widget.seams.appLinkSource ?? AppLinkSource.inert();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapError = widget.initialBootstrapError;
    _profileHealth = widget.initialProfileHealth;
    if (_bootstrapError == null) _startDatabaseScope();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _runtimeAuthBootstrap?.authController.recordLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPlannerTimezone());
    }
  }

  Future<void> _refreshPlannerTimezone() async {
    try {
      await initializeTimezone();
      final container = _container;
      if (container != null) {
        final enabled = await container.read(
          reviewReminderEnabledProvider.future,
        );
        final minutes = await container.read(
          reviewReminderMinutesProvider.future,
        );
        final notifications = container.read(notificationServiceProvider);
        if (enabled) {
          await notifications.scheduleDailyReminder(
            hour: minutes ~/ 60,
            minute: minutes % 60,
          );
        } else {
          await notifications.cancelReminder();
        }
      }
      if (mounted) setState(() {});
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
  }

  void _startDatabaseScope() {
    final resources = _runtimeAuthBootstrap;
    if (resources != null) _subscribeToRuntimeAuth(resources);
    // The desired target always comes from live Auth state. Nothing about the
    // currently open database is assumed here: if the target differs, the drain
    // opens it, and [_openTarget] is only replaced once that succeeded.
    _requestDatabaseSwitch(
      _targetFor(resources, resources?.authController.session),
    );
  }

  /// Follows exactly one runtime Auth stack.
  ///
  /// The subscription is bound to the stack instance that created it, so an
  /// event from a replaced stack is dropped before it could be resolved with the
  /// replacement's project identity.
  void _subscribeToRuntimeAuth(_RuntimeAuthBootstrap resources) {
    unawaited(_authSubscription?.cancel());
    _authSubscription = resources.authController.states.listen((state) {
      if (!identical(_runtimeAuthBootstrap, resources)) return;
      _requestDatabaseSwitch(_targetFor(resources, state.session));
    });
  }

  _AccountDatabaseTarget _targetFor(
    _RuntimeAuthBootstrap? resources,
    Session? session,
  ) => _AccountDatabaseTarget(
    runtimeAuth: resources,
    accountScope: _scopeForSession(resources?.backend, session),
  );

  /// Canonical account scope of [backend] for [session].
  ///
  /// A provisioned backend resolves `(projectRef, authUserId)`, so the same
  /// auth user id in two projects selects two different local databases. A
  /// null session is the anonymous local database.
  PlannerAccountScope? _scopeForSession(
    RuntimeBackend? backend,
    Session? session,
  ) {
    if (backend == null || session == null) return null;
    return backend.accountScopeFor(session.user.id);
  }

  void _requestDatabaseSwitch(_AccountDatabaseTarget target) {
    _requestedTarget = target;
    if (_databaseSwitch != null) return;
    final run = _drainDatabaseSwitches();
    _databaseSwitch = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_databaseSwitch, run)) _databaseSwitch = null;
      }),
    );
  }

  Future<void> _drainDatabaseSwitches() async {
    while (mounted &&
        _requestedTarget != null &&
        _openTarget != _requestedTarget) {
      final target = _requestedTarget!;
      final opened = await _switchDatabase(target);
      if (!opened) return;
    }
  }

  Future<void> _retryBootstrap() async {
    if (!mounted || _bootstrapError == null) return;
    setState(() {
      _bootstrapError = null;
      _error = null;
      _switching = true;
    });
    try {
      // Supabase marks its singleton initialized before auth/session recovery
      // finishes. Dispose that failed attempt so Retry can genuinely repeat
      // initialization rather than silently returning a half-ready client.
      unawaited(_authSubscription?.cancel());
      _authSubscription = null;
      await _disposeRuntimeAuthBootstrap();
      _profileHealth = await _initializeRuntimeAuth(widget.seams);
      if (!mounted) return;
      _startDatabaseScope();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      if (!mounted) return;
      setState(() {
        _bootstrapError = error;
        _switching = false;
      });
    }
  }

  void _retryDatabase() {
    if (!mounted) return;
    final target = _requestedTarget;
    if (target == null) return;
    setState(() {
      _error = null;
      _switching = true;
    });
    _requestDatabaseSwitch(target);
  }

  /// Re-reads durable connection state and re-scopes runtime Auth when the
  /// backend changed while the app was running.
  ///
  /// Provisioning finishes inside the running app, so the new user-owned
  /// project has to gain its runtime Auth client without a restart. Static
  /// configuration still wins, and an unchanged backend is a no-op.
  Future<void> _reloadRuntimeBackend() async {
    if (SupabaseConfig.isConfigured) return;
    try {
      final read = await widget.seams.readProvisionedBackend();
      if (!mounted) return;
      _profileHealth = read.health;
      _publishProfileHealth();
      final backend = read.backend;
      if (backend == null) {
        // The stored connection no longer resolves: the user disconnected it,
        // or the durable document became unusable. Leaving the previous runtime
        // Auth stack installed would keep talking to a backend this
        // installation must no longer use, so the app falls back to the local
        // scope instead. Local databases and the outbox are untouched.
        if (_runtimeAuthBootstrap?.backend is ProvisionedRuntimeBackend) {
          // Stop the old stack from driving account scope before it is
          // replaced; the subscription callback also verifies stack identity.
          unawaited(_authSubscription?.cancel());
          _authSubscription = null;
          await _disposeRuntimeAuthBootstrap();
          if (!mounted) return;
          _container
              ?.read(runtimeAuthStackProvider.notifier)
              .replace(const RuntimeAuthStack.localOnly());
          _startDatabaseScope();
        }
        return;
      }
      if (backend == _runtimeAuthBootstrap?.backend) return;
      // Stop the previous runtime Auth generation from driving account scope
      // *before* the replacement becomes visible, so an event queued by a
      // replaced client can never be resolved with the new project's identity.
      // Cancellation removes the listener synchronously; its returned future is
      // not awaited because a slow cancel must never block adopting a backend
      // (the subscription callback also verifies its own stack identity).
      unawaited(_authSubscription?.cancel());
      _authSubscription = null;
      await widget.seams.installProvisionedRuntimeAuth(backend, _appLinkSource);
      if (!mounted) return;
      final container = _container;
      final resources = _runtimeAuthBootstrap;
      if (container != null && resources != null) {
        container
            .read(runtimeAuthStackProvider.notifier)
            .replace(resources.stack);
      }
      // Re-subscribes to the new stack and requests its target; the open
      // database is only replaced when that request is applied.
      _startDatabaseScope();
    } catch (error, stack) {
      // Adoption is best effort: a backend this build cannot adopt leaves the
      // Planner on its current local scope. Nothing is deleted, no stale
      // session is reused, and the richer recovery flow belongs to the
      // lifecycle phase.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      _profileHealth = BackendProfileHealth.unreadable;
      _publishProfileHealth();
      // Whatever stack is still installed stays authoritative.
      if (mounted) _startDatabaseScope();
    }
  }

  /// Republishes the durable profile health to the live provider graph.
  void _publishProfileHealth() {
    final container = _container;
    if (container == null) return;
    container
        .read(backendProfileHealthProvider.notifier)
        .replace(_profileHealth);
  }

  Future<bool> _switchDatabase(_AccountDatabaseTarget target) async {
    if (!mounted) return false;
    setState(() {
      _switching = true;
      _error = null;
    });

    final oldContainer = _container;
    final oldDatabase = _database;
    final oldEngine = _syncEngine;
    _container = null;
    _database = null;
    _syncEngine = null;
    // Nothing is open while the switch is in flight. The open target is
    // published again only after this switch established it.
    _openTarget = null;
    if (oldContainer != null && oldDatabase != null) {
      await widget.seams.shutdownLocalServices(
        oldContainer,
        oldDatabase,
        oldEngine,
        true,
      );
    }

    AppDatabase? database;
    ProviderContainer? container;
    SyncEngine? engine;
    try {
      database = await widget.seams.openDatabase(accountId: target.accountId);
      if (!mounted || _requestedTarget != target) {
        // Superseded while the database was opening. Nothing of this target may
        // reach local services, so no default rows, timer state, or provider
        // container is created for it.
        await _closeDatabase(database);
        return true;
      }
      AndroidForegroundTimer.setAccountScope(target.accountId);
      final openedDatabase = database;
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(openedDatabase),
          openAccountScopeProvider.overrideWithValue(target.accountScope),
          // The container is built for exactly the runtime Auth stack of this
          // target, so it can never serve a replaced client.
          runtimeAuthStackProvider.overrideWith(
            () => RuntimeAuthStackNotifier(
              target.runtimeAuth?.stack ?? const RuntimeAuthStack.localOnly(),
            ),
          ),
          runtimeBackendReloaderProvider.overrideWithValue(
            _BootstrapRuntimeReloader(this),
          ),
          // The app-lifetime deep-link stream, so the provisioning UI observes
          // the same single platform subscription as the Auth callback router.
          appLinkSourceProvider.overrideWithValue(_appLinkSource),
          backendProfileHealthProvider.overrideWith(
            () => BackendProfileHealthNotifier(_profileHealth),
          ),
        ],
      );
      final openedContainer = container;
      engine = await widget.seams.initializeLocalServices(
        openedContainer,
        beforeWindowClose: () =>
            _shutdownForWindowClose(openedContainer, openedDatabase),
      );
      if (!mounted || _requestedTarget != target) {
        await widget.seams.shutdownLocalServices(
          openedContainer,
          openedDatabase,
          engine,
          true,
        );
        return true;
      }
      setState(() {
        _openTarget = target;
        _database = database;
        _container = container;
        _syncEngine = engine;
        _switching = false;
      });
      return true;
    } catch (error, stack) {
      if (container != null && database != null) {
        await widget.seams.shutdownLocalServices(
          container,
          database,
          engine,
          true,
        );
      } else {
        if (database != null) await _closeDatabase(database);
      }
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      if (mounted) {
        setState(() {
          _error = error;
          _switching = false;
        });
      }
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
    unawaited(_disposeRuntimeAuthBootstrap());
    final container = _container;
    final database = _database;
    final engine = _syncEngine;
    _container = null;
    _database = null;
    _syncEngine = null;
    _openTarget = null;
    _requestedTarget = null;
    if (container != null && database != null) {
      unawaited(
        widget.seams
            .shutdownLocalServices(container, database, engine, true)
            .whenComplete(WindowStateService.instance.dispose),
      );
    }
    super.dispose();
  }

  Future<void> _shutdownForWindowClose(
    ProviderContainer container,
    AppDatabase database,
  ) async {
    if (!identical(_container, container)) return;
    // The listener is removed synchronously; see [_reloadRuntimeBackend].
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    _container = null;
    _database = null;
    _syncEngine = null;
    _openTarget = null;
    await widget.seams.shutdownLocalServices(
      container,
      database,
      container.read(syncEngineProvider),
      false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final container = _container;
    if (_bootstrapError != null || _switching || container == null) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month,
                  size: 72,
                  color: Color(0xFF7C5CFC),
                ),
                const SizedBox(height: 16),
                Text(
                  'Personal Planner',
                  style: ThemeData.dark().textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                if (_bootstrapError != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorPanel(
                      message: friendlyErrorMessage(_bootstrapError!),
                      onRetry: _retryBootstrap,
                    ),
                  )
                else if (_error == null)
                  const CircularProgressIndicator()
                else
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorPanel(
                      message: friendlyErrorMessage(_error!),
                      onRetry: _retryDatabase,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return UncontrolledProviderScope(
      container: container,
      child: const PersonalPlannerApp(),
    );
  }
}

/// Lets the cloud-setup card ask the bootstrap to adopt a backend that just
/// finished provisioning. Lifecycle stays in [_PlannerBootstrapState].
class _BootstrapRuntimeReloader implements RuntimeBackendReloader {
  const _BootstrapRuntimeReloader(this._state);

  final _PlannerBootstrapState _state;

  @override
  Future<void> reload() => _state._reloadRuntimeBackend();
}

/// Closes a database that was opened for a target the bootstrap no longer
/// wants. Nothing else was created for it yet, so this is the whole cleanup.
Future<void> _closeDatabase(AppDatabase database) async {
  try {
    await database.close();
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  }
}

/// Seeds the built-in default categories unless a provisioned account's initial
/// synchronization is still unresolved.
///
/// Phase G: a fresh account database must not create local Planner rows before
/// the remote state is known. Uploading bootstrap defaults into an account that
/// already holds Planner data would create duplicate categories and false
/// conflicts, so seeding waits until a safe baseline exists. The coordinator
/// seeds them itself once an account is proven empty on both sides.
Future<void> _seedPlannerDefaults(ProviderContainer container) async {
  final backend = container.read(runtimeBackendProvider);
  if (backend is ProvisionedRuntimeBackend) {
    final record = await InitialSyncStateStore(
      container.read(appDatabaseProvider),
    ).read();
    if (!record.baselineComplete) return;
  }
  await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
}

Future<SyncEngine?> _initializeLocalServices(
  ProviderContainer container, {
  required Future<void> Function() beforeWindowClose,
}) async {
  try {
    await _seedPlannerDefaults(container);
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await initializeTimezone();
    final recurrence = container.read(recurrenceServiceProvider);
    final now = DateTime.now();
    final today = startOfDay(now);
    await recurrence.materializeForDate(today);
    await recurrence.materializeForDate(addDays(today, 1));
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await initializeTimezone();
    final notifications = container.read(notificationServiceProvider);
    await notifications.init(
      onSelect: (payload) {
        appRouter.go(payload ?? NotificationService.reviewRoute);
      },
    );
    final enabled = await container.read(reviewReminderEnabledProvider.future);
    final minutes = await container.read(reviewReminderMinutesProvider.future);
    if (enabled) {
      final armed = await notifications.scheduleDailyReminder(
        hour: minutes ~/ 60,
        minute: minutes % 60,
      );
      if (notifications.schedulingSupported && !armed) {
        await container
            .read(reviewReminderEnabledProvider.notifier)
            .setEnabled(false);
      }
    } else {
      await notifications.cancelReminder();
    }
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await AndroidForegroundTimer().init();
    Future<void> handleTimerAction(PendingForegroundTimerAction pending) async {
      final database = container.read(appDatabaseProvider);
      final owner = await container
          .read(timerRepositoryProvider)
          .localDeviceId();
      final active = pending.sessionId == null
          ? null
          : await database.timerDao.getSessionById(pending.sessionId!);
      if (pending.accountId != AndroidForegroundTimer.accountScope ||
          active == null ||
          active.id != pending.sessionId ||
          active.taskId != pending.taskId ||
          active.ownerDeviceId != owner ||
          active.ownerDeviceId != pending.ownerDeviceId ||
          active.state != 'running' ||
          active.runningSince != pending.expectedRunningSince ||
          active.durationSec != pending.expectedDurationSec ||
          active.revision != pending.expectedStateRevision) {
        // The envelope is stale (account switch, resumed segment, or another
        // notification). Acknowledge it only: clearing by session here could
        // stop a newer segment that intentionally reuses the logical ID.
        await AndroidForegroundTimer().acknowledgePendingAction(
          pending.actionId,
        );
        return;
      }
      final service = container.read(timerServiceProvider);
      TimerTransitionResult result;
      if (pending.action == AndroidForegroundTimer.pauseButtonId) {
        result = await service.pauseSession(
          active.id,
          expectedOwnerDeviceId: owner,
          occurredAt: pending.occurredAt,
          expectedRunningSince: pending.expectedRunningSince,
        );
      } else if (pending.action == AndroidForegroundTimer.stopButtonId) {
        result = await service.stopSession(
          active.id,
          expectedOwnerDeviceId: owner,
          occurredAt: pending.occurredAt,
          expectedRunningSince: pending.expectedRunningSince,
        );
      } else {
        await AndroidForegroundTimer().acknowledgePendingAction(
          pending.actionId,
        );
        return;
      }
      await AndroidForegroundTimer().acknowledgePendingAction(pending.actionId);
      if (result.session != null) {
        await AndroidForegroundTimer().clearSession(result.session!.id);
      }
    }

    AndroidForegroundTimer.onButtonAction = (pending) async {
      try {
        await handleTimerAction(pending);
      } catch (error, stack) {
        // Leave the durable envelope intact. A later app start retries the
        // exact action timestamp instead of pretending the transition won.
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    };
    final pendingAction = await AndroidForegroundTimer.takePendingAction();
    if (pendingAction != null) {
      try {
        await handleTimerAction(pendingAction);
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    }
    // A stale envelope may have been safely acknowledged above. Read the
    // durable store again before deciding whether a newer persisted segment
    // needs its notification restored.
    final stillPending = await AndroidForegroundTimer.takePendingAction();
    if (stillPending == null) {
      final repository = container.read(timerRepositoryProvider);
      final owner = await repository.localDeviceId();
      final running = await container
          .read(appDatabaseProvider)
          .timerDao
          .getRunningForOwner(owner);
      if (running != null && running.runningSince != null) {
        final task = await container
            .read(appDatabaseProvider)
            .taskDao
            .getTaskById(running.taskId);
        if (task != null && task.deletedAt == null) {
          await AndroidForegroundTimer().start(
            taskTitle: task.title,
            taskId: running.taskId,
            sessionId: running.id,
            ownerDeviceId: owner,
            runningSince: running.runningSince!,
            durationSec: running.durationSec,
            stateRevision: running.revision,
          );
        }
      }
    }
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  final engine = container.read(syncEngineProvider);
  try {
    await engine?.start();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    // Phase G: a provisioned account resolves its remote Planner state even if
    // the user never opens Settings → Sync. The subscription keeps the
    // coordinator alive for the lifetime of this account container; it is
    // released when the container is disposed during an account switch.
    container.listen(initialSyncCoordinatorProvider, (previous, next) {});
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await WindowStateService.instance.initialize(
      container.read(appDatabaseProvider),
      beforeClose: beforeWindowClose,
    );
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  return engine;
}

Future<void> _shutdownLocalServices(
  ProviderContainer container,
  AppDatabase database,
  SyncEngine? engine, {
  bool persistWindow = true,
}) async {
  try {
    await AndroidForegroundTimer.detachButtonHandler();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await engine?.stop();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  TimerTransitionResult paused;
  try {
    paused = await container.read(timerServiceProvider).pauseAt(DateTime.now());
  } catch (err, stack) {
    // Do not close this account database after a failed persisted transition:
    // doing so would silently lose the user's recorded running segment.
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    rethrow;
  }
  try {
    if (paused.session != null) {
      await AndroidForegroundTimer().clearSession(paused.session!.id);
    } else {
      await AndroidForegroundTimer().stopService();
    }
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await container.read(notificationServiceProvider).cancelReminder();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    if (persistWindow) {
      await WindowStateService.instance.detachDatabase(database);
    }
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    container.dispose();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await database.close();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
}

/// Positional adapter for [PlannerBootstrapSeams.shutdownLocalServices], so the
/// seam can default to a constant tear-off.
Future<void> _shutdownLocalServicesForSeam(
  ProviderContainer container,
  AppDatabase database,
  SyncEngine? engine,
  bool persistWindow,
) => _shutdownLocalServices(
  container,
  database,
  engine,
  persistWindow: persistWindow,
);
