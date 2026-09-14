import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'retryable stream error retains the account and later refresh recovers',
    () async {
      final source = _FakeAuthRepository(_session('account-a'));
      final controller = AuthSessionController(source, clock: _clock);
      final observed = <AuthSessionState>[];
      final subscription = controller.states.listen(observed.add);
      try {
        await controller.start();
        source.events.addError(const _RetryableNetworkError());
        await _flush();

        expect(controller.session?.user.id, 'account-a');
        expect(controller.current.health, AuthSessionHealth.retryingRefresh);
        final generation = controller.current.generation;

        source.session = _session('account-a', expiresInMinutes: 60);
        source.events.add(
          AuthState(AuthChangeEvent.tokenRefreshed, source.session),
        );
        await _flush();

        expect(controller.session?.user.id, 'account-a');
        expect(controller.current.health, AuthSessionHealth.ready);
        expect(controller.current.generation, generation);
        expect(observed, isNotEmpty);
      } finally {
        await subscription.cancel();
        await controller.dispose();
        await source.dispose();
      }
    },
  );

  test(
    'a terminal sign-out clears scope and ignores a delayed old refresh',
    () async {
      final source = _FakeAuthRepository(
        _session('account-a', expiresInMinutes: -1),
      );
      final controller = AuthSessionController(source, clock: _clock);
      final delayedRefresh = Completer<void>();
      source.onRefresh = () => delayedRefresh.future;
      try {
        await controller.start();
        final refresh = controller.requestRefreshIfNeeded();
        expect(source.refreshCalls, 1);
        source.events.add(
          const AuthState(
            AuthChangeEvent.signedOut,
            null,
            signOutReason: SignOutReason.sessionExpired,
          ),
        );
        source.session = _session('account-b');
        source.events.add(AuthState(AuthChangeEvent.signedIn, source.session));
        // A response from A must not move B's local database back to A.
        source.events.add(
          AuthState(AuthChangeEvent.tokenRefreshed, _session('account-a')),
        );
        delayedRefresh.complete();
        await refresh;
        await _flush();

        expect(controller.session?.user.id, 'account-b');
        expect(controller.current.health, AuthSessionHealth.ready);
        expect(
          controller.diagnostics.map((entry) => entry.event),
          contains('tokenRefreshed_ignored_stale_account'),
        );
      } finally {
        await controller.dispose();
        await source.dispose();
      }
    },
  );

  test('expired access requests one SDK refresh and retains local scope on failure', () async {
    final source = _FakeAuthRepository(
      _session('account-a', expiresInMinutes: -1),
    );
    final controller = AuthSessionController(source, clock: _clock);
    final refresh = Completer<void>();
    source.onRefresh = () => refresh.future;
    try {
      await controller.start();
      final first = controller.requestRefreshIfNeeded();
      final second = controller.requestRefreshIfNeeded();

      expect(identical(first, second), isTrue);
      expect(source.refreshCalls, 1);
      expect(controller.session?.user.id, 'account-a');
      expect(controller.current.health, AuthSessionHealth.retryingRefresh);

      refresh.completeError(const _RetryableNetworkError());
      await first;
      expect(controller.session?.user.id, 'account-a');
      expect(controller.current.health, AuthSessionHealth.retryingRefresh);
    } finally {
      await controller.dispose();
      await source.dispose();
    }
  });

  test('storage failures are recoverable and diagnostics never contain credentials', () async {
    final source = _FakeAuthRepository(_session('account-a'));
    final controller = AuthSessionController(source, clock: _clock);
    try {
      await controller.start();
      controller.recordStorageOutcome(
        const SecureSessionStorageOutcome(
          operation: SecureSessionStorageOperation.accessToken,
          succeeded: false,
          errorType: 'KeyringException',
        ),
      );

      expect(controller.session?.user.id, 'account-a');
      expect(controller.current.health, AuthSessionHealth.storageError);
      final rendered = jsonEncode(
        controller.diagnostics.map((entry) => entry.toJson()).toList(),
      );
      expect(rendered, isNot(contains('access-secret')));
      expect(rendered, isNot(contains('refresh-secret')));
      expect(rendered, isNot(contains('person@example.test')));

      controller.recordStorageOutcome(
        const SecureSessionStorageOutcome(
          operation: SecureSessionStorageOperation.accessToken,
          succeeded: true,
        ),
      );
      expect(controller.current.health, AuthSessionHealth.ready);
    } finally {
      await controller.dispose();
      await source.dispose();
    }
  });

  test('diagnostics are bounded to one hundred entries', () async {
    final source = _FakeAuthRepository(_session('account-a'));
    final controller = AuthSessionController(source, clock: _clock);
    try {
      await controller.start();
      for (var index = 0; index < 120; index++) {
        controller.recordLifecycle(AppLifecycleState.resumed);
      }
      expect(
        controller.diagnostics,
        hasLength(AuthSessionController.maxDiagnostics),
      );
    } finally {
      await controller.dispose();
      await source.dispose();
    }
  });
}

class _FakeAuthRepository implements AuthSessionRepository {
  _FakeAuthRepository(this.session);

  final events = StreamController<AuthState>.broadcast();
  Session? session;
  Future<void> Function()? onRefresh;
  int refreshCalls = 0;

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get authStateChanges => events.stream;

  @override
  Future<void> refreshSession() {
    refreshCalls++;
    return onRefresh?.call() ?? Future<void>.value();
  }

  Future<void> dispose() => events.close();
}

class _RetryableNetworkError implements Exception {
  const _RetryableNetworkError();
}

DateTime _clock() => DateTime.utc(2026, 9, 12, 12);

Session _session(String accountId, {int expiresInMinutes = 60}) {
  final expiry = _clock().add(Duration(minutes: expiresInMinutes));
  final payload = base64Url
      .encode(
        utf8.encode(jsonEncode({'exp': expiry.millisecondsSinceEpoch ~/ 1000})),
      )
      .replaceAll('=', '');
  return Session(
    accessToken: 'header.$payload.access-secret',
    refreshToken: 'refresh-secret',
    tokenType: 'bearer',
    user: User(
      id: accountId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
      email: 'person@example.test',
    ),
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
