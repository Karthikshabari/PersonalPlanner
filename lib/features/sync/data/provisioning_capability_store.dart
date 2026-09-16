import 'secure_session_storage.dart';

/// Why a provisioning capability could not be stored or read.
enum ProvisioningCapabilityFailure {
  /// The OS-backed store is unavailable.
  unavailable,

  /// The value is not a usable provisioning capability (or is not bound to a
  /// valid transaction id).
  malformed,
}

class ProvisioningCapabilityStoreException implements Exception {
  const ProvisioningCapabilityStoreException(this.failure, this.message);

  final ProvisioningCapabilityFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Secure storage for the short-lived provisioning capability.
///
/// The capability authorizes exactly one provisioning transaction. It is not a
/// Supabase credential and has a different lifetime from Planner sessions, so
/// it lives in its own namespace and class: never inside
/// `BackendConnectionProfile`, never in the profile/JSON store, never in Drift
/// or shared preferences, and never next to Supabase Auth session material.
abstract interface class ProvisioningCapabilityStore {
  Future<void> write({
    required String transactionId,
    required String capability,
  });

  Future<String?> read({required String transactionId});

  Future<void> delete({required String transactionId});
}

/// OS-backed implementation built on the existing secure key/value boundary.
class SecureProvisioningCapabilityStore implements ProvisioningCapabilityStore {
  SecureProvisioningCapabilityStore({SecureKeyValueStore? storage})
    : _storage = storage ?? FlutterSecureKeyValueStore();

  /// Namespace that keeps provisioning capabilities apart from session
  /// material (`personal_planner.supabase.*`).
  static const keyPrefix = 'personal_planner.provisioning.capability.';

  static final RegExp _transactionIdPattern = RegExp(r'^[a-f0-9]{32}$');
  static final RegExp _capabilityPattern = RegExp(r'^[A-Za-z0-9_-]{32,256}$');

  /// Defense in depth: a Supabase key must never end up stored in place of a
  /// provisioning capability.
  static const _forbiddenPrefixes = <String>[
    'sb_secret_',
    'sb_publishable_',
    'sbp_',
    'sba_',
    'service_role',
  ];

  final SecureKeyValueStore _storage;

  @override
  Future<void> write({
    required String transactionId,
    required String capability,
  }) async {
    _requireTransactionId(transactionId);
    if (!_capabilityPattern.hasMatch(capability) ||
        _forbiddenPrefixes.any(capability.startsWith)) {
      throw const ProvisioningCapabilityStoreException(
        ProvisioningCapabilityFailure.malformed,
        'The provisioning capability is malformed and was not stored.',
      );
    }
    try {
      await _storage.write(key: _key(transactionId), value: capability);
    } catch (error) {
      throw _unavailable(error);
    }
  }

  @override
  Future<String?> read({required String transactionId}) async {
    _requireTransactionId(transactionId);
    final String? value;
    try {
      value = await _storage.read(key: _key(transactionId));
    } catch (error) {
      throw _unavailable(error);
    }
    if (value == null) return null;
    if (!_capabilityPattern.hasMatch(value)) {
      throw const ProvisioningCapabilityStoreException(
        ProvisioningCapabilityFailure.malformed,
        'The stored provisioning capability is malformed.',
      );
    }
    return value;
  }

  @override
  Future<void> delete({required String transactionId}) async {
    _requireTransactionId(transactionId);
    try {
      await _storage.delete(key: _key(transactionId));
    } catch (error) {
      throw _unavailable(error);
    }
  }

  /// Keys are derived only from a validated transaction id, so one transaction
  /// can never address another transaction's capability.
  String _key(String transactionId) => '$keyPrefix$transactionId';

  void _requireTransactionId(String transactionId) {
    if (!_transactionIdPattern.hasMatch(transactionId)) {
      throw const ProvisioningCapabilityStoreException(
        ProvisioningCapabilityFailure.malformed,
        'A provisioning capability must be bound to a valid transaction id.',
      );
    }
  }

  ProvisioningCapabilityStoreException _unavailable(Object error) =>
      ProvisioningCapabilityStoreException(
        ProvisioningCapabilityFailure.unavailable,
        'Secure storage is unavailable (${error.runtimeType}).',
      );
}
