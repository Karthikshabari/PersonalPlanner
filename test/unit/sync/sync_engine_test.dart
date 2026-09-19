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
    final engine = SyncEngine(
      db,
      SyncRepository.withGateway(db, _GatedGateway(gate), 'account'),
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
        // The stalled transport is reported as active first…
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(snapshots.last.state, SyncEngineState.syncing);

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

/// A transport that never answers, like a half-open connection.
class _HangingPullGateway extends _NoopGateway {
  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) => Completer<Object?>().future;
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
