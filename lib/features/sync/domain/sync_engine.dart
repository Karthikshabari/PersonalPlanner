import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../../core/database/app_database.dart';
import '../data/sync_repository.dart';
import 'auth_session_controller.dart';
import 'sync_models.dart';

/// Shortest time a cycle must be running before the UI is told it is syncing.
///
/// A quick no-op cycle (nothing pending, one empty pull page) finishes in well
/// under this, so an idle account never flashes "Syncing…". A cycle that really
/// transfers something outlives it and is reported as active.
const Duration syncSyncingNoticeDelay = Duration(milliseconds: 400);

/// Upper bound on one synchronization cycle.
///
/// The transport can hand back a request that never completes (a half-open
/// connection, a stalled TLS read, an SDK refresh that never settles). Without
/// a bound, that single request would keep the engine's "cycle in progress"
/// flag set forever, so every later status computation would keep reporting
/// `syncing` and the UI would spin indefinitely with no way back. The bound
/// only decides when the *engine* stops claiming to be running; a late
/// completion still updates the durable state normally.
const Duration syncCycleTimeout = Duration(minutes: 1);

/// User-facing message for a cycle that outlived [syncCycleTimeout].
const String syncCycleStalledMessage =
    'Sync is taking longer than expected. Your changes are safe on this '
    'device.';

/// Serializes automatic and manual sync attempts and owns all lifecycle
/// triggers. Connectivity is treated as a transport hint only; the actual
/// repository request remains the reachability check.
class SyncEngine with WidgetsBindingObserver {
  SyncEngine(
    this._db,
    this._repository,
    this._connectivity, {
    this.authController,
    this.syncingNoticeDelay = syncSyncingNoticeDelay,
    this.cycleTimeout = syncCycleTimeout,
  });

  final AppDatabase _db;
  final SyncRepository _repository;
  final SyncConnectivityMonitor _connectivity;
  final AuthSessionController? authController;

  /// How long real work must run before the UI is told it is syncing.
  final Duration syncingNoticeDelay;

  /// Upper bound on one cycle; see [syncCycleTimeout].
  final Duration cycleTimeout;
  final _status = StreamController<SyncStatusSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _writeDebounce;
  Timer? _periodic;
  Timer? _syncingNotice;
  bool _started = false;
  bool _stopping = false;
  bool _disposed = false;
  bool _running = false;
  bool _syncingVisible = false;
  bool _transportAvailable = false;
  String? _lastError;
  SyncEngineState? _failureState;
  DateTime? _lastSuccessfulSync;
  Future<void>? _startFuture;
  Future<void>? _activeCycle;
  Future<void>? _stopFuture;
  Stream<SyncStatusSnapshot> get status => _status.stream;

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_started || _stopping || _disposed) return;
    _started = true;
    final lastSuccess = await _db.syncDao.getSetting('sync.last_success_at');
    if (_stopping || _disposed) return;
    _lastSuccessfulSync = DateTime.tryParse(lastSuccess ?? '')?.toUtc();
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(_connectivity.changes.listen(_onConnectivityChanged));
    _subscriptions.add(
      _db.syncDao.watchPendingOperations().listen((_) {
        _scheduleStatus();
        _scheduleWriteSync();
      }),
    );
    _subscriptions.add(
      _db.syncDao.watchConflicts().listen((_) => _scheduleStatus()),
    );
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_transportAvailable) unawaited(syncNow());
    });
    _transportAvailable = _hasTransport(await _connectivity.check());
    await _refreshStatus();
    if (_transportAvailable && !_stopping) await syncNow();
  }

  Future<void> syncNow() {
    if (_stopping || _disposed) return Future.value();
    final active = _activeCycle;
    if (active != null) return active;
    final cycle = _runSync();
    _activeCycle = cycle;
    return cycle.whenComplete(() {
      if (identical(_activeCycle, cycle)) _activeCycle = null;
    });
  }

  Future<void> _runSync() async {
    _running = true;
    _syncingVisible = false;
    _lastError = null;
    _failureState = null;
    _scheduleSyncingNotice();
    try {
      final authController = this.authController;
      if (authController != null && !authController.hasUsableAccessToken()) {
        unawaited(authController.requestRefreshIfNeeded());
        _lastError = 'Session refresh is pending; local work is safe.';
        _failureState = SyncEngineState.refreshPaused;
        return;
      }
      final SyncCycleResult result;
      try {
        // Bounded: the transport can hand back a request that never completes,
        // and an unbounded await would keep `_running` set forever — leaving
        // every later status computation on "Syncing…" with no way back.
        // Abandoning the wait never changes durable state: the outbox keeps
        // every queued operation, so a later cycle still delivers it.
        result = await _repository.sync().timeout(cycleTimeout);
      } on TimeoutException {
        _lastError = syncCycleStalledMessage;
        _failureState = SyncEngineState.error;
        return;
      }
      if (result.succeeded) {
        _lastSuccessfulSync = DateTime.now().toUtc();
        await _db.syncDao.setSetting(
          'sync.last_success_at',
          _lastSuccessfulSync!.toIso8601String(),
        );
      } else {
        final failure = result.firstFailure!;
        _lastError = failure.message;
        _failureState = _failureStateFor(result);
      }
      if (!_stopping) await _refreshStatus();
    } catch (error) {
      _lastError = safeSyncError(error);
      _failureState = SyncEngineState.error;
      if (!_stopping) await _refreshStatus();
    } finally {
      _syncingNotice?.cancel();
      _syncingVisible = false;
      _running = false;
      if (!_stopping) await _refreshStatus();
    }
  }

  /// Announces real work only once it has lasted long enough to be true.
  void _scheduleSyncingNotice() {
    _syncingNotice?.cancel();
    _syncingNotice = Timer(syncingNoticeDelay, () {
      if (!_running || _stopping || _disposed) return;
      _syncingVisible = true;
      _scheduleStatus();
    });
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_stopping || _disposed) return;
    final wasAvailable = _transportAvailable;
    _transportAvailable = _hasTransport(results);
    _scheduleStatus();
    if (!wasAvailable && _transportAvailable) unawaited(syncNow());
  }

  void _scheduleWriteSync() {
    if (_stopping || _disposed) return;
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(seconds: 2), () {
      if (_transportAvailable) unawaited(syncNow());
    });
  }

  void _scheduleStatus() {
    if (_stopping || _disposed) return;
    unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    if (_stopping || _disposed) return;
    final pending = await _db.syncDao.pendingCount();
    final permanent = await _db.syncDao.firstPermanentOperation();
    final conflicts = await _countConflicts();
    // Only a cycle that has been running long enough to be user-visible counts
    // as "syncing"; the engine's internal in-flight flag alone must never pin
    // the screen on a spinner.
    final state = _syncingVisible
        ? SyncEngineState.syncing
        : conflicts > 0
        ? SyncEngineState.conflict
        : _failureState == SyncEngineState.refreshPaused
        ? SyncEngineState.refreshPaused
        : !_transportAvailable
        ? SyncEngineState.offline
        : _failureState != null
        ? _failureState!
        : permanent != null
        ? SyncEngineState.permanentFailure
        : pending > 0
        ? SyncEngineState.pending
        : SyncEngineState.synced;
    await _emit(
      SyncStatusSnapshot(
        state: state,
        pendingOperations: pending,
        conflictCount: conflicts,
        lastSuccessfulSync: _lastSuccessfulSync,
        message: _lastError ?? permanent?.lastError,
      ),
    );
  }

  SyncEngineState _failureStateFor(SyncCycleResult result) {
    final failure = result.firstFailure!;
    if (failure.kind == SyncFailureKind.authentication) {
      return SyncEngineState.authFailure;
    }
    if (failure.kind == SyncFailureKind.invalidData) {
      return SyncEngineState.invalidData;
    }
    if (failure.kind == SyncFailureKind.backendUnavailable) {
      // Only reachable while the platform reports an available transport: a
      // genuinely offline device reports `offline` instead.
      return SyncEngineState.backendUnavailable;
    }
    if (failure.kind == SyncFailureKind.permanent) {
      return SyncEngineState.permanentFailure;
    }
    if ((result.pushFailure == null) != (result.pullFailure == null)) {
      return SyncEngineState.partialSuccess;
    }
    return SyncEngineState.error;
  }

  Future<int> _countConflicts() async {
    var count = 0;
    await for (final rows in _db.syncDao.watchConflicts().take(1)) {
      count = rows.length;
    }
    return count;
  }

  Future<void> _emit(SyncStatusSnapshot value) async {
    if (_stopping || _disposed) return;
    if (!_status.isClosed) _status.add(value);
  }

  static bool _hasTransport(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_stopping || _disposed) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_recheckAndSync());
    } else if (state == AppLifecycleState.paused) {
      // Best effort only. The durable outbox and cursor provide correctness.
      unawaited(syncNow());
    }
  }

  Future<void> _recheckAndSync() async {
    _transportAvailable = _hasTransport(await _connectivity.check());
    if (_stopping || _disposed) return;
    await _refreshStatus();
    if (_transportAvailable) await syncNow();
  }

  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    if (_disposed) return;
    _stopping = true;
    WidgetsBinding.instance.removeObserver(this);
    _writeDebounce?.cancel();
    _periodic?.cancel();
    _syncingNotice?.cancel();
    _syncingVisible = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await _startFuture;
    } catch (_) {
      // Shutdown must still release the observer, subscriptions, and status
      // stream when startup failed after allocating any of them.
    }
    try {
      // A wedged request must not be able to hang application shutdown.
      await _activeCycle?.timeout(cycleTimeout);
    } on TimeoutException {
      // The durable outbox and cursor keep correctness; the process can exit.
    } catch (_) {
      // The active cycle already records transport failures. Do not let one
      // failed request prevent the database scope from closing.
    }
    _disposed = true;
    await _status.close();
  }

  Future<void> dispose() => stop();
}

abstract interface class SyncConnectivityMonitor {
  Stream<List<ConnectivityResult>> get changes;

  Future<List<ConnectivityResult>> check();
}

class PlatformSyncConnectivityMonitor implements SyncConnectivityMonitor {
  PlatformSyncConnectivityMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;

  @override
  Future<List<ConnectivityResult>> check() => _connectivity.checkConnectivity();
}
