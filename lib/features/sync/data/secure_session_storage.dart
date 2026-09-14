import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Testable minimum of secure key-value storage. Session values are kept in
/// this boundary only; callbacks deliberately contain no values or messages.
abstract interface class SecureKeyValueStore {
  Future<bool> containsKey({required String key});

  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

enum SecureSessionStorageOperation {
  initialize,
  hasAccessToken,
  accessToken,
  persistSession,
  removePersistedSession,
}

class SecureSessionStorageOutcome {
  const SecureSessionStorageOutcome({
    required this.operation,
    required this.succeeded,
    this.errorType,
  });

  final SecureSessionStorageOperation operation;
  final bool succeeded;
  final String? errorType;

  /// A code only: secure-storage error messages can include platform details.
  String get code => succeeded
      ? '${operation.name}_ok'
      : '${operation.name}_${errorType ?? 'error'}';
}

/// Collects initialization read failures that Supabase itself may catch and
/// log. Bootstrap must consult it before choosing the anonymous database.
class SecureSessionBootstrapCollector {
  SecureSessionStorageOutcome? _readFailure;

  SecureSessionStorageOutcome? get readFailure => _readFailure;

  bool get requiresRetry => _readFailure != null;

  void record(SecureSessionStorageOutcome outcome) {
    if (outcome.succeeded || _readFailure != null) return;
    switch (outcome.operation) {
      case SecureSessionStorageOperation.hasAccessToken:
      case SecureSessionStorageOperation.accessToken:
        _readFailure = outcome;
      case SecureSessionStorageOperation.initialize:
      case SecureSessionStorageOperation.persistSession:
      case SecureSessionStorageOperation.removePersistedSession:
        break;
    }
  }
}

class SecureSessionBootstrapException implements Exception {
  const SecureSessionBootstrapException(this.code);

  final String code;

  @override
  String toString() => 'Secure session storage is unavailable ($code).';
}

/// Bootstrap calls this after Supabase initialization, whose recovery layer
/// intentionally catches adapter read errors. Keeping the barrier here makes
/// the no-anonymous-fallback contract independently testable.
void requireSecureSessionBootstrapReady(
  SecureSessionBootstrapCollector collector,
) {
  final failure = collector.readFailure;
  if (failure != null) throw SecureSessionBootstrapException(failure.code);
}

/// Secure session storage for Supabase Auth. Tokens never enter SQLite,
/// app_settings, logs, exports, or error messages.
class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage({SecureKeyValueStore? storage, this.onOutcome})
    : _storage = storage ?? FlutterSecureKeyValueStore();

  static const sessionKey = 'personal_planner.supabase.session';
  final SecureKeyValueStore _storage;
  void Function(SecureSessionStorageOutcome outcome)? onOutcome;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> initialize() =>
      _enqueue(SecureSessionStorageOperation.initialize, () async {});

  @override
  Future<bool> hasAccessToken() => _enqueue(
    SecureSessionStorageOperation.hasAccessToken,
    () => _storage.containsKey(key: sessionKey),
  );

  @override
  Future<String?> accessToken() => _enqueue(
    SecureSessionStorageOperation.accessToken,
    () => _storage.read(key: sessionKey),
  );

  @override
  Future<void> removePersistedSession() => _enqueue(
    SecureSessionStorageOperation.removePersistedSession,
    () => _storage.delete(key: sessionKey),
  );

  @override
  Future<void> persistSession(String persistSessionString) => _enqueue(
    SecureSessionStorageOperation.persistSession,
    () => _storage.write(key: sessionKey, value: persistSessionString),
  );

  /// Waits for queued reads/writes/deletes without exposing session material.
  Future<void> settle() => _tail;

  Future<T> _enqueue<T>(
    SecureSessionStorageOperation operation,
    Future<T> Function() action,
  ) {
    final result = _tail.then((_) => action());
    // Every queued operation advances the tail even when it fails; one failed
    // keyring write must not permanently poison later refresh/sign-out work.
    _tail = result.then<void>(
      (_) => _report(
        SecureSessionStorageOutcome(operation: operation, succeeded: true),
      ),
      onError: (Object error, StackTrace stack) {
        _report(
          SecureSessionStorageOutcome(
            operation: operation,
            succeeded: false,
            errorType: error.runtimeType.toString(),
          ),
        );
      },
    );
    return result;
  }

  void _report(SecureSessionStorageOutcome outcome) {
    try {
      onOutcome?.call(outcome);
    } catch (_) {
      // Storage correctness must never depend on a diagnostics observer.
    }
  }
}

/// Secure PKCE verifier storage. The verifier is short-lived but still
/// credential material and must not use shared preferences.
class SecureSupabasePkceStorage extends GotrueAsyncStorage {
  SecureSupabasePkceStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String key) => 'personal_planner.supabase.pkce.$key';

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: _key(key));

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: _key(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: _key(key), value: value);
}
