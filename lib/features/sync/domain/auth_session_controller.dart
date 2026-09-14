import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../data/secure_session_storage.dart';

enum AuthSessionHealth {
  ready,
  retryingRefresh,
  reauthenticationRequired,
  storageError,
}

class AuthSessionState {
  const AuthSessionState({
    required this.session,
    required this.health,
    required this.generation,
    this.issueCode,
  });

  final Session? session;
  final AuthSessionHealth health;
  final String? issueCode;

  /// Changes only when the selected account scope changes, not on rotation.
  final int generation;
}

/// Sanitized, memory-only support breadcrumb. It intentionally cannot carry a
/// session object, token, user profile, HTTP payload, or storage value.
class AuthSessionDiagnostic {
  const AuthSessionDiagnostic({
    required this.recordedAt,
    required this.event,
    required this.lifecycle,
    required this.sessionPresent,
    required this.expiryDelta,
    required this.accountGenerationChanged,
    this.signOutReason,
    this.issueCode,
    this.storageOutcome,
  });

  final DateTime recordedAt;
  final String event;
  final String lifecycle;
  final bool sessionPresent;
  final String expiryDelta;
  final bool accountGenerationChanged;
  final String? signOutReason;
  final String? issueCode;
  final String? storageOutcome;

  Map<String, Object?> toJson() => {
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'event': event,
    'lifecycle': lifecycle,
    'session_present': sessionPresent,
    'expiry_delta': expiryDelta,
    'account_generation_changed': accountGenerationChanged,
    if (signOutReason != null) 'sign_out_reason': signOutReason,
    if (issueCode != null) 'issue_code': issueCode,
    if (storageOutcome != null) 'storage_outcome': storageOutcome,
  };
}

/// One non-terminating reducer for SDK auth events. It does not refresh tokens
/// itself; it only asks [AuthSessionRepository] to let the SDK do so once when
/// a sync attempt discovers expiry.
class AuthSessionController {
  AuthSessionController(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const maxDiagnostics = 100;

  final AuthSessionRepository _repository;
  final DateTime Function() _clock;
  final _states = StreamController<AuthSessionState>.broadcast();
  final List<AuthSessionDiagnostic> _diagnostics = [];
  StreamSubscription<AuthState>? _subscription;
  Future<void>? _refreshing;
  bool _started = false;
  bool _disposed = false;
  String _lifecycle = 'unknown';
  AuthSessionState _current = const AuthSessionState(
    session: null,
    health: AuthSessionHealth.ready,
    generation: 0,
  );

  AuthSessionState get current => _current;

  Session? get session => _current.session;

  Stream<AuthSessionState> get states => _states.stream;

  List<AuthSessionDiagnostic> get diagnostics =>
      List.unmodifiable(_diagnostics);

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subscription = _repository.authStateChanges.listen(
      _onAuthState,
      onError: _onAuthStreamError,
      cancelOnError: false,
    );
    // Supabase has already restored its authoritative currentSession by the
    // time bootstrap constructs this controller. Never invent a remembered
    // account identifier when that session is null.
    _publish(
      session: _repository.currentSession,
      health: AuthSessionHealth.ready,
      event: 'seed',
    );
  }

  void _onAuthState(AuthState event) {
    if (_disposed) return;
    final incoming = event.session;
    switch (event.event) {
      case AuthChangeEvent.signedOut:
      // ignore: deprecated_member_use
      case AuthChangeEvent.userDeleted:
        _publish(
          session: null,
          health: AuthSessionHealth.reauthenticationRequired,
          issueCode: _signOutIssue(event.signOutReason),
          event: event.event.name,
          signOutReason: event.signOutReason?.name,
        );
        return;
      case AuthChangeEvent.signedIn:
        if (incoming != null) {
          _publish(
            session: incoming,
            health: AuthSessionHealth.ready,
            event: event.event.name,
          );
        }
        return;
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        if (incoming != null && _canAcceptNonSignIn(incoming)) {
          _publish(
            session: incoming,
            health: AuthSessionHealth.ready,
            event: event.event.name,
          );
        } else if (incoming != null) {
          _record(
            event: '${event.event.name}_ignored_stale_account',
            issueCode: 'stale_account_event',
          );
        }
        return;
      case AuthChangeEvent.initialSession:
        // A null initial event means anonymous mode only when bootstrap did
        // not restore a known account. It must not clear one after a retry.
        if (incoming != null && _current.session == null) {
          _publish(
            session: incoming,
            health: AuthSessionHealth.ready,
            event: event.event.name,
          );
        } else if (incoming == null && _current.session == null) {
          _publish(
            session: null,
            health: AuthSessionHealth.ready,
            event: event.event.name,
          );
        } else {
          _record(event: '${event.event.name}_ignored_null');
        }
        return;
      case AuthChangeEvent.passwordRecovery:
      case AuthChangeEvent.mfaChallengeVerified:
        if (incoming != null && _canAcceptNonSignIn(incoming)) {
          _publish(
            session: incoming,
            health: AuthSessionHealth.ready,
            event: event.event.name,
          );
        } else {
          _record(event: '${event.event.name}_ignored');
        }
        return;
    }
  }

  bool _canAcceptNonSignIn(Session incoming) {
    final current = _current.session;
    if (current == null) {
      return _current.health != AuthSessionHealth.reauthenticationRequired;
    }
    return current.user.id == incoming.user.id;
  }

  void _onAuthStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    // SDK retryable refresh failures retain currentSession. Stream errors are
    // therefore health information, never implicit evidence of sign-out.
    _publish(
      session: _current.session,
      health: AuthSessionHealth.retryingRefresh,
      issueCode: _safeStreamIssue(error),
      event: 'stream_error',
    );
  }

  /// True only when a captured token is still safe to send to the server.
  bool hasUsableAccessToken([Session? candidate]) {
    final value = candidate ?? _current.session;
    final expiresAt = value?.expiresAt;
    if (value == null || value.accessToken.isEmpty || expiresAt == null) {
      return false;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
      isUtc: true,
    ).isAfter(_clock().toUtc());
  }

  /// Coalesces expiry-triggered requests. The SDK retains ownership of refresh
  /// token rotation, retry policy, and terminal signed-out events.
  Future<void> requestRefreshIfNeeded() {
    if (_disposed || _current.session == null || hasUsableAccessToken()) {
      return Future<void>.value();
    }
    final active = _refreshing;
    if (active != null) return active;
    _publish(
      session: _current.session,
      health: AuthSessionHealth.retryingRefresh,
      issueCode: 'access_token_expired',
      event: 'refresh_requested',
    );
    late final Future<void> request;
    request = _runRefresh().whenComplete(() {
      if (identical(_refreshing, request)) _refreshing = null;
    });
    _refreshing = request;
    return request;
  }

  Future<void> _runRefresh() async {
    try {
      await _repository.refreshSession();
    } catch (error, stackTrace) {
      _onAuthStreamError(error, stackTrace);
    }
  }

  void recordStorageOutcome(SecureSessionStorageOutcome outcome) {
    if (_disposed) return;
    if (!outcome.succeeded) {
      _publish(
        session: _current.session,
        health: AuthSessionHealth.storageError,
        issueCode: outcome.code,
        event: 'secure_storage_error',
        storageOutcome: outcome.code,
      );
      return;
    }
    if (_current.health == AuthSessionHealth.storageError) {
      _publish(
        session: _current.session,
        health: AuthSessionHealth.ready,
        event: 'secure_storage_recovered',
        storageOutcome: outcome.code,
      );
    } else {
      _record(event: 'secure_storage', storageOutcome: outcome.code);
    }
  }

  void recordLifecycle(AppLifecycleState state) {
    if (_disposed) return;
    _lifecycle = state.name;
    _record(event: 'lifecycle');
  }

  void _publish({
    required Session? session,
    required AuthSessionHealth health,
    required String event,
    String? issueCode,
    String? signOutReason,
    String? storageOutcome,
  }) {
    final oldAccount = _current.session?.user.id;
    final nextAccount = session?.user.id;
    final accountChanged = oldAccount != nextAccount;
    _current = AuthSessionState(
      session: session,
      health: health,
      issueCode: issueCode,
      generation: accountChanged
          ? _current.generation + 1
          : _current.generation,
    );
    _record(
      event: event,
      signOutReason: signOutReason,
      issueCode: issueCode,
      storageOutcome: storageOutcome,
      accountGenerationChanged: accountChanged,
    );
    if (!_states.isClosed) _states.add(_current);
  }

  void _record({
    required String event,
    String? signOutReason,
    String? issueCode,
    String? storageOutcome,
    bool accountGenerationChanged = false,
  }) {
    if (_diagnostics.length == maxDiagnostics) _diagnostics.removeAt(0);
    _diagnostics.add(
      AuthSessionDiagnostic(
        recordedAt: _clock().toUtc(),
        event: event,
        lifecycle: _lifecycle,
        sessionPresent: _current.session != null,
        expiryDelta: _expiryDelta(),
        accountGenerationChanged: accountGenerationChanged,
        signOutReason: signOutReason,
        issueCode: issueCode,
        storageOutcome: storageOutcome,
      ),
    );
  }

  String _expiryDelta() {
    final expiresAt = _current.session?.expiresAt;
    if (expiresAt == null) return 'unknown';
    final delta = DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
      isUtc: true,
    ).difference(_clock().toUtc());
    if (delta.isNegative) return 'expired';
    if (delta <= const Duration(minutes: 1)) return 'under_1m';
    if (delta <= const Duration(minutes: 15)) return 'under_15m';
    if (delta <= const Duration(hours: 1)) return 'under_1h';
    return 'over_1h';
  }

  static String _safeStreamIssue(Object error) {
    final type = error.runtimeType.toString().toLowerCase();
    if (type.contains('network') || type.contains('socket')) {
      return 'network_error';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('timeout') ||
        text.contains('connection') ||
        text.contains('dns')) {
      return 'network_error';
    }
    return 'auth_stream_error';
  }

  static String _signOutIssue(SignOutReason? reason) => switch (reason) {
    SignOutReason.userInitiated => 'signed_out_by_user',
    SignOutReason.sessionExpired => 'refresh_session_expired',
    SignOutReason.sessionMissing => 'refresh_session_missing',
    null => 'signed_out',
  };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _states.close();
  }
}
