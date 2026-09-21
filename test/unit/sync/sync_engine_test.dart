import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/sync_engine.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'engine stop is idempotent and releases connectivity listeners',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity();
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, _NoopGateway(), 'account'),
        connectivity,
      );
      try {
        await engine.start();
        expect(connectivity.activeListeners, 1);
        await engine.stop();
        await engine.stop();
        expect(connectivity.activeListeners, 0);
        await engine.syncNow();
      } finally {
        await engine.stop();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test('stop waits for startup before closing the status stream', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final connectivity = _FakeConnectivity();
    final check = Completer<List<ConnectivityResult>>();
    connectivity.checkResult = check.future;
    final engine = SyncEngine(
      db,
      SyncRepository.withGateway(db, _NoopGateway(), 'account'),
      connectivity,
    );
    try {
      final starting = engine.start();
      final stopping = engine.stop();
      check.complete(const [ConnectivityResult.none]);
      await stopping;
      await starting;
      expect(connectivity.activeListeners, 0);
    } finally {
      await engine.stop();
      await connectivity.close();
      await db.close();
    }
  });

  test(
    'permanent operations remain visible after a successful later cycle',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity();
      connectivity.checkResult = Future.value(const [ConnectivityResult.wifi]);
      final gateway = _NoopGateway();
      final category = await CategoryRepository(db).insertCategory(
        Category(
          id: 'blocked-category',
          name: 'Blocked',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        category.id,
      )).single;
      await db.syncDao.markPermanentError(
        operation.operationId,
        now: DateTime.utc(2026, 1, 1),
        error: 'Needs repair',
      );
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, gateway, 'account'),
        connectivity,
      );
      final states = <SyncEngineState>[];
      final subscription = engine.status.listen(
        (snapshot) => states.add(snapshot.state),
      );
      try {
        await engine.start();
        expect(states, contains(SyncEngineState.permanentFailure));
      } finally {
        await subscription.cancel();
        await engine.stop();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test(
    'expired session pauses sync and asks the SDK for one refresh',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity()
        ..checkResult = Future.value(const [ConnectivityResult.wifi]);
      final source = _FakeAuthRepository(_expiredSession());
      final controller = AuthSessionController(source, clock: _clock);
      final gateway = _CountingGateway();
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, gateway, 'account-a'),
        connectivity,
        authController: controller,
      );
      final states = <SyncEngineState>[];
      final subscription = engine.status.listen(
        (snapshot) => states.add(snapshot.state),
      );
      try {
        await controller.start();
        await engine.start();
        await Future<void>.delayed(Duration.zero);

        expect(source.refreshCalls, 1);
        expect(gateway.pullCalls, 0);
        expect(states, contains(SyncEngineState.refreshPaused));
      } finally {
        await subscription.cancel();
        await engine.stop();
        await controller.dispose();
        await source.dispose();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test(
    'an idle account settles to synced and never announces syncing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity()
        ..checkResult = Future.value(const [ConnectivityResult.wifi]);
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, _NoopGateway(), 'account'),
        connectivity,
      );
      final states = <SyncEngineState>[];
      final subscription = engine.status.listen(
        (snapshot) => states.add(snapshot.state),
      );
      try {
        await engine.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Nothing was pending, so the cycle finished long before the notice
        // delay: the screen never flashes "Syncing…" for a no-op cycle.
        expect(states, isNot(contains(SyncEngineState.syncing)));
        expect(states.last, SyncEngineState.synced);
      } finally {
        await subscription.cancel();
        await engine.stop();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test('real work is announced as syncing while it runs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final connectivity = _FakeConnectivity()
      ..checkResult = Future.value(const [ConnectivityResult.wifi]);
    final gate = Completer<void>();
    final category = await CategoryRepository(db).insertCategory(
      Category(
        id: 'queued-category',
        name: 'Queued',
        colorHex: '#4285F4',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final operation = (await db.syncDao.getActiveOperationsForRecord(
      'categories',
      category.id,
    )).single;
    final engine = SyncEngine(
      db,
      _GatedRepository(db, gate, operation.operationId),
      connectivity,
      syncingNoticeDelay: const Duration(milliseconds: 20),
    );
    final states = <SyncEngineState>[];
    final subscription = engine.status.listen(
      (snapshot) => states.add(snapshot.state),
    );
    try {
      final started = engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(states.last, SyncEngineState.syncing);

      gate.complete();
      await started;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last, SyncEngineState.synced);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await subscription.cancel();
      await engine.stop();
      await connectivity.close();
      await db.close();
    }
  });

  test(
    'only a real successful cycle records the last successful sync',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity()
        ..checkResult = Future.value(const [ConnectivityResult.wifi]);
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, _NoopGateway(), 'account'),
        connectivity,
      );
      try {
        expect(await db.syncDao.getSetting('sync.last_success_at'), null);

        await engine.start();

        final recorded = await db.syncDao.getSetting('sync.last_success_at');
        expect(recorded, isA<String>());
        expect(DateTime.tryParse(recorded!), isA<DateTime>());
      } finally {
        await engine.stop();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test('a failed cycle never moves the last successful sync instant', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final connectivity = _FakeConnectivity()
      ..checkResult = Future.value(const [ConnectivityResult.wifi]);
    final previous = DateTime.utc(2026, 9, 19, 18, 12);
    await db.syncDao.setSetting(
      'sync.last_success_at',
      previous.toIso8601String(),
    );
    final engine = SyncEngine(
      db,
      SyncRepository.withGateway(db, _FailingPullGateway(), 'account'),
      connectivity,
    );
    final snapshots = <SyncStatusSnapshot>[];
    final subscription = engine.status.listen(snapshots.add);
    try {
      await engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        await db.syncDao.getSetting('sync.last_success_at'),
        previous.toIso8601String(),
      );
      expect(snapshots.last.lastSuccessfulSync, previous);
      expect(snapshots.last.state, SyncEngineState.backendUnavailable);
      expect(snapshots.last.state, isNot(SyncEngineState.synced));
    } finally {
      await subscription.cancel();
      await engine.stop();
      await connectivity.close();
      await db.close();
    }
  });

  test(
    'no-op checks and status refreshes never move an existing instant',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity()
        ..checkResult = Future.value(const [ConnectivityResult.wifi]);
      final previous = DateTime.utc(2026, 9, 19, 18, 12);
      await db.syncDao.setSetting(
        'sync.last_success_at',
        previous.toIso8601String(),
      );
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, _NoopGateway(), 'account'),
        connectivity,
      );
      try {
        await engine.start();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Startup performed a successful but empty remote check. That is useful
        // reachability evidence, not new synchronized data.
        final recordedAfterStart = await db.syncDao.getSetting(
          'sync.last_success_at',
        );
        connectivity.emit(const [ConnectivityResult.none]);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          await db.syncDao.getSetting('sync.last_success_at'),
          recordedAfterStart,
        );
        expect(recordedAfterStart, previous.toIso8601String());
      } finally {
        await engine.stop();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test(
    'queued work waiting on retry backoff is not a successful sync',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity()
        ..checkResult = Future.value(const [ConnectivityResult.wifi]);
      final category = await CategoryRepository(db).insertCategory(
        Category(
          id: 'queued-category',
          name: 'Queued',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        category.id,
      )).single;
      await db.syncDao.markRetryableError(
        operation.operationId,
        now: DateTime.now().toUtc(),
        nextAttemptAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        error: 'Network unavailable; retry scheduled.',
      );
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, _NoopGateway(), 'account'),
        connectivity,
      );
      try {
        await engine.start();

        // Push skipped the ineligible operation while the pull round-tripped.
        // The change is still unsynchronized, so no fresh instant may be
        // recorded for it.
        expect(await db.syncDao.getSetting('sync.last_success_at'), null);
      } finally {
        await engine.stop();
        await connectivity.close();
        await db.close();
      }
    },
  );

  test('a skipped repository cycle is never a successful sync', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gate = Completer<void>();
    final repository = SyncRepository.withGateway(
      db,
      _GatedGateway(gate),
      'account',
    );
    try {
      final first = repository.sync();
      final second = await repository.sync();
      expect(second.skipped, isTrue);
      expect(second.succeeded, isFalse);
      expect(second.firstFailure, null);
      gate.complete();
      expect((await first).succeeded, isTrue);
    } finally {
      await db.close();
    }
  });

  test('an out-of-band unreachable verdict never moves the instant', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final connectivity = _FakeConnectivity()
      ..checkResult = Future.value(const [ConnectivityResult.none]);
    final previous = DateTime.utc(2026, 9, 19, 18, 12);
    await db.syncDao.setSetting(
      'sync.last_success_at',
      previous.toIso8601String(),
    );
    final engine = SyncEngine(
      db,
      SyncRepository.withGateway(db, _NoopGateway(), 'account'),
      connectivity,
    );
    final snapshots = <SyncStatusSnapshot>[];
    final subscription = engine.status.listen(snapshots.add);
    try {
      await engine.start();
      engine.noteBackendUnreachable();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        await db.syncDao.getSetting('sync.last_success_at'),
        previous.toIso8601String(),
      );
      expect(snapshots.last.state, SyncEngineState.offline);
      expect(snapshots.last.lastSuccessfulSync, previous);
    } finally {
      await subscription.cancel();
      await engine.stop();
      await connectivity.close();
      await db.close();
    }
  });

  test('transient backend failure recovers on connectivity restoration without duplicate states', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final connectivity = _FakeConnectivity()
      ..checkResult = Future.value(const [ConnectivityResult.wifi]);
    final gateway = _RecoveringGateway()..fail = true;
    final engine = SyncEngine(
      db,
      SyncRepository.withGateway(db, gateway, 'account'),
      connectivity,
    );
    final states = <SyncEngineState>[];
    final subscription = engine.status.listen(
      (snapshot) => states.add(snapshot.state),
    );
    try {
      await engine.start();
      expect(states.last, SyncEngineState.backendUnavailable);
      states.clear();

      gateway.fail = false;
      connectivity.emit(const [ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      connectivity.emit(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.last, SyncEngineState.synced);
      expect(
        states.where((state) => state == SyncEngineState.synced).length,
        1,
      );
      expect(gateway.pullCalls, 2);
    } finally {
      await subscription.cancel();
      await engine.stop();
      await connectivity.close();
      await db.close();
    }
  });

  test(
    'a request that never returns cannot pin the engine in syncing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final connectivity = _FakeConnectivity()
        ..checkResult = Future.value(const [ConnectivityResult.wifi]);
      final engine = SyncEngine(
        db,
        SyncRepository.withGateway(db, _HangingPullGateway(), 'account'),
        connectivity,
        syncingNoticeDelay: const Duration(milliseconds: 10),
        cycleTimeout: const Duration(milliseconds: 120),
      );
      final snapshots = <SyncStatusSnapshot>[];
      final subscription = engine.status.listen(snapshots.add);
      try {
        unawaited(engine.start());
        // An empty feed check is not shown as active merely because the
        // transport stalls.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(snapshots.last.state, SyncEngineState.pending);

        // …and the bounded cycle then releases the engine instead of leaving
        // the UI on a spinner forever.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(snapshots.last.state, SyncEngineState.error);
        expect(snapshots.last.message, syncCycleStalledMessage);
        // A second attempt is not blocked by the abandoned cycle.
        await engine.syncNow().timeout(const Duration(seconds: 2));
      } finally {
        await subscription.cancel();
        // Shutdown must not hang on the request that never returned.
        await engine.stop().timeout(const Duration(seconds: 2));
        await connectivity.close();
        await db.close();
      }
    },
  );
}

class _FakeConnectivity implements SyncConnectivityMonitor {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  Future<List<ConnectivityResult>> checkResult = Future.value(const [
    ConnectivityResult.none,
  ]);

  @override
  Stream<List<ConnectivityResult>> get changes => _controller.stream;

  @override
  Future<List<ConnectivityResult>> check() => checkResult;

  int get activeListeners => _controller.hasListener ? 1 : 0;

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  Future<void> close() => _controller.close();
}

class _NoopGateway implements SyncRemoteGateway {
  @override
  Future<Object?> getCapabilities() => Future.value(const <String, Object?>{
    'protocol_version': 2,
    'payload_versions': [1, 2],
    'inbox_content_version': true,
    'due_date': true,
    'manual_actual_source': true,
    'timer_state_machine': true,
  });

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
    String? baselineToken,
  }) => Future.value(const <String, Object?>{});

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) => Future.value(const <Object>[]);
}

class _CountingGateway extends _NoopGateway {
  int pullCalls = 0;

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) {
    pullCalls++;
    return super.pullChanges(afterChangeId: afterChangeId, limit: limit);
  }
}

/// A gateway whose pull only completes when the test releases it.
class _GatedGateway extends _NoopGateway {
  _GatedGateway(this._gate);

  final Completer<void> _gate;

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async {
    await _gate.future;
    return const <Object>[];
  }
}

class _GatedRepository extends SyncRepository {
  _GatedRepository(this._db, this._gate, this._operationId)
    : super.withGateway(_db, _NoopGateway(), 'account');

  final AppDatabase _db;
  final Completer<void> _gate;
  final String _operationId;

  @override
  Future<SyncCycleResult> sync() async {
    await _gate.future;
    await _db.syncDao.markAcknowledged(_operationId, DateTime.utc(2026, 1, 1));
    return const SyncCycleResult();
  }
}

class _RecoveringGateway extends _NoopGateway {
  bool fail = false;
  int pullCalls = 0;

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) {
    pullCalls += 1;
    if (fail) {
      return Future<Object?>.error(
        Exception(
          "ClientException with SocketException: Failed host lookup: "
          "'project.supabase.co'",
        ),
      );
    }
    return Future<Object?>.value(const <Object>[]);
  }
}

/// A transport that never answers, like a half-open connection.
class _HangingPullGateway extends _NoopGateway {
  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) => Completer<Object?>().future;
}

/// A transport that reports the account's own project host as unreachable.
class _FailingPullGateway extends _NoopGateway {
  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) => Future<Object?>.error(
    Exception(
      "ClientException with SocketException: Failed host lookup: "
      "'project.supabase.co'",
    ),
  );
}

class _FakeAuthRepository implements AuthSessionRepository {
  _FakeAuthRepository(this.session);

  final events = StreamController<AuthState>.broadcast();
  Session? session;
  int refreshCalls = 0;

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get authStateChanges => events.stream;

  @override
  Future<void> refreshSession() {
    refreshCalls++;
    return Future<void>.error(StateError('network unavailable'));
  }

  Future<void> dispose() => events.close();
}

DateTime _clock() => DateTime.utc(2026, 9, 12, 12);

Session _expiredSession() {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp':
                _clock()
                    .subtract(const Duration(minutes: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return Session(
    accessToken: 'header.$payload.signature',
    refreshToken: 'refresh-secret',
    tokenType: 'bearer',
    user: const User(
      id: 'account-a',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
    ),
  );
}
