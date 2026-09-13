import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/database/app_database.dart';
import 'core/providers/database_provider.dart';
import 'core/router/app_router.dart';
import 'core/utils/date_utils.dart';
import 'core/widgets/error_panel.dart';
import 'features/recurring/providers/recurring_providers.dart';
import 'features/settings/providers/notification_settings_providers.dart';
import 'features/sync/data/auth_repository.dart';
import 'features/sync/data/secure_session_storage.dart';
import 'features/sync/domain/auth_session_controller.dart';
import 'features/sync/domain/sync_engine.dart';
import 'features/sync/providers/sync_providers.dart';
import 'features/timer/domain/notification_service.dart';
import 'features/timer/domain/timer_service.dart';
import 'features/timer/platform/android_foreground_timer.dart';
import 'features/timer/providers/timer_providers.dart';
import 'platform/desktop/window_manager.dart';

_SupabaseBootstrapResources? _supabaseBootstrap;

class _SupabaseBootstrapResources {
  const _SupabaseBootstrapResources({
    required this.authRepository,
    required this.authController,
  });

  final AuthRepository authRepository;
  final AuthSessionController authController;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.demangleStackTrace = _demangleStackTrace;
  ErrorWidget.builder = (_) => const ErrorPanel(
    message: 'This screen could not be displayed. Please retry.',
  );
  Object? bootstrapError;
  try {
    await _initializeSupabaseIfConfigured();
  } catch (error, stack) {
    bootstrapError = error;
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  }
  runApp(_PlannerBootstrap(initialBootstrapError: bootstrapError));
}

/// Drift and other async libraries can propagate package:stack_trace objects.
/// Flutter's error presenter expects VM-format traces on desktop platforms.
StackTrace _demangleStackTrace(StackTrace stack) {
  if (stack is Trace) return stack.vmTrace;
  if (stack is Chain) return stack.toTrace().vmTrace;
  return stack;
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
  final repository = AuthRepository(
    Supabase.instance.client,
    sessionStorage: storage,
  );
  final controller = AuthSessionController(repository);
  storage.onOutcome = controller.recordStorageOutcome;
  await controller.start();
  _supabaseBootstrap = _SupabaseBootstrapResources(
    authRepository: repository,
    authController: controller,
  );
}

Future<void> _disposeSupabaseBootstrapResources() async {
  final resources = _supabaseBootstrap;
  _supabaseBootstrap = null;
  await resources?.authController.dispose();
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

  const _PlannerBootstrap({this.initialBootstrapError});

  @override
  State<_PlannerBootstrap> createState() => _PlannerBootstrapState();
}

class _PlannerBootstrapState extends State<_PlannerBootstrap>
    with WidgetsBindingObserver {
  AppDatabase? _database;
  ProviderContainer? _container;
  SyncEngine? _syncEngine;
  StreamSubscription<AuthSessionState>? _authSubscription;
  String? _accountId;
  String? _requestedAccountId;
  Future<void>? _databaseSwitch;
  Object? _error;
  Object? _bootstrapError;
  bool _switching = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapError = widget.initialBootstrapError;
    if (_bootstrapError == null) _startDatabaseScope();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _supabaseBootstrap?.authController.recordLifecycle(state);
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
    if (SupabaseConfig.isConfigured) {
      final resources = _supabaseBootstrap;
      if (resources == null) {
        setState(() {
          _bootstrapError = const SecureSessionBootstrapException(
            'initialization_missing',
          );
          _switching = false;
        });
        return;
      }
      unawaited(_authSubscription?.cancel());
      _authSubscription = resources.authController.states.listen((state) {
        _requestDatabaseSwitch(state.session?.user.id);
      });
      _accountId = resources.authController.session?.user.id;
    }
    _requestedAccountId = _accountId;
    _requestDatabaseSwitch(_accountId);
  }

  void _requestDatabaseSwitch(String? accountId) {
    _requestedAccountId = accountId;
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
        (_database == null || _accountId != _requestedAccountId)) {
      final target = _requestedAccountId;
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
      if (SupabaseConfig.isConfigured) {
        await _authSubscription?.cancel();
        _authSubscription = null;
        await _disposeSupabaseBootstrapResources();
        await _initializeSupabaseIfConfigured();
      }
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
    setState(() {
      _error = null;
      _switching = true;
    });
    _requestDatabaseSwitch(_accountId);
  }

  Future<bool> _switchDatabase(String? accountId) async {
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
    if (oldContainer != null && oldDatabase != null) {
      await _shutdownLocalServices(oldContainer, oldDatabase, oldEngine);
    }

    AppDatabase? database;
    ProviderContainer? container;
    SyncEngine? engine;
    try {
      database = await AppDatabase.open(accountId: accountId);
      AndroidForegroundTimer.setAccountScope(accountId);
      final openedDatabase = database;
      final resources = _supabaseBootstrap;
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(openedDatabase),
          openAccountIdProvider.overrideWithValue(accountId),
          if (resources != null) ...[
            authRepositoryProvider.overrideWithValue(resources.authRepository),
            authSessionControllerProvider.overrideWithValue(
              resources.authController,
            ),
          ],
        ],
      );
      final openedContainer = container;
      engine = await _initializeLocalServices(
        openedContainer,
        beforeWindowClose: () =>
            _shutdownForWindowClose(openedContainer, openedDatabase),
      );
      if (!mounted || _requestedAccountId != accountId) {
        await _shutdownLocalServices(openedContainer, openedDatabase, engine);
        return true;
      }
      setState(() {
        _accountId = accountId;
        _database = database;
        _container = container;
        _syncEngine = engine;
        _switching = false;
      });
      return true;
    } catch (error, stack) {
      if (container != null && database != null) {
        await _shutdownLocalServices(container, database, engine);
      } else {
        try {
          await database?.close();
        } catch (cleanupError, cleanupStack) {
          FlutterError.reportError(
            FlutterErrorDetails(exception: cleanupError, stack: cleanupStack),
          );
        }
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
    unawaited(_disposeSupabaseBootstrapResources());
    final container = _container;
    final database = _database;
    final engine = _syncEngine;
    _container = null;
    _database = null;
    _syncEngine = null;
    if (container != null && database != null) {
      unawaited(
        _shutdownLocalServices(
          container,
          database,
          engine,
        ).whenComplete(WindowStateService.instance.dispose),
      );
    }
    super.dispose();
  }

  Future<void> _shutdownForWindowClose(
    ProviderContainer container,
    AppDatabase database,
  ) async {
    if (!identical(_container, container)) return;
    await _authSubscription?.cancel();
    _authSubscription = null;
    _container = null;
    _database = null;
    _syncEngine = null;
    await _shutdownLocalServices(
      container,
      database,
      container.read(syncEngineProvider),
      persistWindow: false,
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

Future<SyncEngine?> _initializeLocalServices(
  ProviderContainer container, {
  required Future<void> Function() beforeWindowClose,
}) async {
  try {
    await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
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
