import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import 'secure_session_storage.dart';

/// Thrown when the secure store backing the in-flight Management authorization
/// could not be read or written. The message never contains a stored value.
class SecureManagementAttemptStoreException implements Exception {
  const SecureManagementAttemptStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One device-initiated Management authorization that is still in flight.
///
/// The pairing of a provisioning transaction with its short-lived capability
/// exists only so the Worker can accept the project check that follows the
/// browser consent. Nothing here is a Supabase credential and nothing here is
/// Management material: the Worker holds the OAuth tokens.
@immutable
class ManagementAttempt {
  const ManagementAttempt({
    required this.transactionId,
    required this.capability,
    required this.projectRef,
  });

  final String transactionId;
  final String capability;
  final String projectRef;

  @override
  String toString() =>
      'ManagementAttempt(projectRef: $projectRef, transactionId: '
      '$transactionId)';
}

/// Secure storage for the single in-flight Management authorization.
///
/// The record is deleted as soon as its outcome is read (or when the user
/// disconnects), so a device never keeps a control-plane credential for a
/// Management operation that already finished.
class ManagementAttemptStore {
  ManagementAttemptStore({required this._storage});

  static const String storageKey =
      'personal_planner.supabase.management_attempt';

  static final RegExp _transactionIdPattern = RegExp(r'^[a-f0-9]{32}$');
  static final RegExp _capabilityPattern = RegExp(r'^[A-Za-z0-9_-]{32,256}$');
  static final RegExp _projectRefPattern = RegExp(r'^[a-z]{20}$');

  final SecureKeyValueStore _storage;

  /// The in-flight attempt, or null when there is none.
  Future<ManagementAttempt?> read() async {
    final String? value;
    try {
      value = await _storage.read(key: storageKey);
    } on Object {
      throw const SecureManagementAttemptStoreException(
        'Secure storage could not be read.',
      );
    }
    if (value == null || value.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      await clear();
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      await clear();
      return null;
    }
    final transactionId = decoded['transactionId'];
    final capability = decoded['capability'];
    final projectRef = decoded['projectRef'];
    if (transactionId is! String ||
        capability is! String ||
        projectRef is! String ||
        !_transactionIdPattern.hasMatch(transactionId) ||
        !_capabilityPattern.hasMatch(capability) ||
        !_projectRefPattern.hasMatch(projectRef)) {
      await clear();
      return null;
    }
    return ManagementAttempt(
      transactionId: transactionId,
      capability: capability,
      projectRef: projectRef,
    );
  }

  /// Replaces any previous attempt with [attempt].
  Future<void> write(ManagementAttempt attempt) async {
    try {
      await _storage.write(
        key: storageKey,
        value: jsonEncode(<String, String>{
          'transactionId': attempt.transactionId,
          'capability': attempt.capability,
          'projectRef': attempt.projectRef,
        }),
      );
    } on Object {
      throw const SecureManagementAttemptStoreException(
        'Secure storage could not be written.',
      );
    }
  }

  /// Forgets the in-flight attempt and its credential.
  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
    } on Object {
      throw const SecureManagementAttemptStoreException(
        'Secure storage could not be updated.',
      );
    }
  }
}
