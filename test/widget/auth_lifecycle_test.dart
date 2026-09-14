import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'auth session mapping stays live through refresh error and A to B transition',
    (tester) async {
      final source = _FakeAuthRepository(_session('account-a'));
      final controller = AuthSessionController(source, clock: _clock);
      addTearDown(() async {
        await controller.dispose();
        await source.dispose();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(home: _AuthSessionProbe()),
        ),
      );
      await tester.pump();
      expect(find.text('account-a'), findsOneWidget);

      source.events.addError(const _RetryableNetworkError());
      await tester.pump();
      expect(find.text('account-a'), findsOneWidget);
      expect(find.text('stream-error'), findsNothing);

      source.events.add(const AuthState(AuthChangeEvent.signedOut, null));
      await tester.pump();
      expect(find.text('anonymous'), findsOneWidget);

      source.session = _session('account-b');
      source.events.add(AuthState(AuthChangeEvent.signedIn, source.session));
      await tester.pump();
      await tester.pump();
      expect(find.text('account-b'), findsOneWidget);
    },
  );
}

class _AuthSessionProbe extends ConsumerWidget {
  const _AuthSessionProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return Scaffold(
      body: Text(
        session.when(
          data: (value) => value?.user.id ?? 'anonymous',
          loading: () => 'loading',
          error: (_, _) => 'stream-error',
        ),
      ),
    );
  }
}

class _FakeAuthRepository implements AuthSessionRepository {
  _FakeAuthRepository(this.session);

  final events = StreamController<AuthState>.broadcast();
  Session? session;

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get authStateChanges => events.stream;

  @override
  Future<void> refreshSession() => Future<void>.value();

  Future<void> dispose() => events.close();
}

class _RetryableNetworkError implements Exception {
  const _RetryableNetworkError();
}

DateTime _clock() => DateTime.utc(2026, 9, 12, 12);

Session _session(String accountId) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp':
                _clock().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                1000,
          }),
        ),
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
    ),
  );
}
