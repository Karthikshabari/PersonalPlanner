import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/backend_connection_profile.dart';

/// Upper bound for the persisted profile document.
///
/// The profile holds a handful of identifiers and one publishable key, so it
/// is a few hundred bytes; a larger file therefore means the file is not ours
/// and must not be parsed.
const int plannerBackendProfileMaxBytes = 16 * 1024;

/// Name of the authoritative profile document.
const String plannerBackendProfileFileName =
    'personal_planner_backend_profile.json';

/// Suffix of the temporary file used while replacing the authoritative file.
const String plannerBackendProfileTemporarySuffix = '.tmp';

/// Why a persisted backend profile could not be used.
enum ConnectionProfileStoreFailure {
  /// The file (or the directory it lives in) could not be read.
  unreadable,

  /// The file exists but is not a valid profile document.
  corrupt,

  /// The document declares a format version this build cannot read.
  unsupportedVersion,

  /// The document is larger than [plannerBackendProfileMaxBytes].
  tooLarge,

  /// The document could not be written atomically.
  writeFailed,
}

/// User-visible health of the durable backend profile.
///
/// Bootstrap never blocks the Planner on an unusable profile: the local-first
/// product keeps working, and this is the explicit recoverable state the Sync
/// settings screen surfaces instead of pretending no cloud backend was ever
/// configured (or, worse, silently connecting a different one).
enum BackendProfileHealth {
  /// No failure: either no profile is stored, or it was read successfully.
  ok,

  /// The stored profile document (or its directory) could not be read.
  unreadable,

  /// The stored document is not a valid profile.
  corrupt,

  /// The document declares a format version this build cannot read.
  unsupportedVersion,

  /// The document is larger than this build accepts.
  tooLarge,

  /// A write was rejected by the filesystem.
  writeFailed;

  bool get needsAttention => this != BackendProfileHealth.ok;

  /// True when only an explicit fresh write may replace the document, because
  /// its recorded generation cannot be trusted.
  bool get isReplaceable =>
      this == BackendProfileHealth.corrupt ||
      this == BackendProfileHealth.unsupportedVersion ||
      this == BackendProfileHealth.tooLarge;

  static BackendProfileHealth fromFailure(
    ConnectionProfileStoreFailure failure,
  ) => switch (failure) {
    ConnectionProfileStoreFailure.unreadable => BackendProfileHealth.unreadable,
    ConnectionProfileStoreFailure.corrupt => BackendProfileHealth.corrupt,
    ConnectionProfileStoreFailure.unsupportedVersion =>
      BackendProfileHealth.unsupportedVersion,
    ConnectionProfileStoreFailure.tooLarge => BackendProfileHealth.tooLarge,
    ConnectionProfileStoreFailure.writeFailed => BackendProfileHealth.writeFailed,
  };
}

/// Typed persistence failure.
///
/// The store never reinterprets an unreadable document and never deletes it:
/// callers decide whether to start a fresh connection profile.
class ConnectionProfileStoreException implements Exception {
  const ConnectionProfileStoreException(this.failure, this.message);

  final ConnectionProfileStoreFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a write no longer matches the stored profile generation.
class StaleConnectionProfileException implements Exception {
  const StaleConnectionProfileException({
    required this.expectedGeneration,
    required this.actualGeneration,
  });

  final int? expectedGeneration;
  final int? actualGeneration;

  @override
  String toString() =>
      'Stale backend profile write: expected generation '
      '${expectedGeneration ?? 'none'}, stored generation '
      '${actualGeneration ?? 'none'}.';
}

/// Durable, client-safe storage for [BackendConnectionProfile].
///
/// Why a file instead of SQLite: the profile has to be readable *before* any
/// account database is chosen, so it cannot live inside one account's Drift
/// database.
///
/// Writes replace the authoritative file through a single rename of a
/// flushed temporary file, which is atomic on the supported platforms
/// (Linux/Android). A crash therefore leaves either the previous profile or
/// the complete new one, never a half-written authoritative file. A leftover
/// temporary file is ignored on read.
class ConnectionProfileStore {
  ConnectionProfileStore({
    this.directory,
    this.fileName = plannerBackendProfileFileName,
  });

  /// Directory holding the profile document.
  ///
  /// Null means the platform application support directory, which is what
  /// production uses; tests supply a temporary directory.
  final Directory? directory;
  final String fileName;

  /// Reads the stored profile, or null when none has been written.
  ///
  /// Throws [ConnectionProfileStoreException] when the document exists but
  /// cannot be trusted. Callers must treat that as "no usable cloud
  /// configuration" and surface a repair path; it is never safe to guess.
  Future<BackendConnectionProfile?> read() async {
    final file = await _profileFile();
    if (!await _exists(file)) return null;

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.unreadable,
        'The stored backend profile could not be read.',
      );
    }
    if (bytes.length > plannerBackendProfileMaxBytes) {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.tooLarge,
        'The stored backend profile is larger than this build accepts.',
      );
    }

    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.corrupt,
        'The stored backend profile is not valid UTF-8 text.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.corrupt,
        'The stored backend profile is not valid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.corrupt,
        'The stored backend profile is not a JSON object.',
      );
    }

    try {
      return BackendConnectionProfile.fromJson(decoded);
    } on UnsupportedBackendProfileFormatException catch (error) {
      throw ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.unsupportedVersion,
        error.toString(),
      );
    } on BackendProfileValidationException catch (error) {
      throw ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.corrupt,
        error.message,
      );
    }
  }

  /// Atomically persists [profile].
  ///
  /// [expectedGeneration] is the generation the caller believes is stored:
  /// pass null to create the first profile and the stored generation to update
  /// it. A mismatch throws [StaleConnectionProfileException] and leaves the
  /// stored profile untouched, so a slow asynchronous operation cannot
  /// overwrite newer provisioning progress.
  ///
  /// A corrupt, unsupported, or oversized document can only be replaced by an
  /// explicit fresh write (`expectedGeneration == null`), because its
  /// generation cannot be trusted.
  Future<BackendConnectionProfile> save(
    BackendConnectionProfile profile, {
    int? expectedGeneration,
  }) async {
    final existing = await _readForWrite(
      expectedGeneration: expectedGeneration,
    );
    if (existing != null) {
      if (expectedGeneration == null ||
          expectedGeneration != existing.generation) {
        throw StaleConnectionProfileException(
          expectedGeneration: expectedGeneration,
          actualGeneration: existing.generation,
        );
      }
      existing.validateReplacement(profile);
    } else if (expectedGeneration != null) {
      throw StaleConnectionProfileException(
        expectedGeneration: expectedGeneration,
        actualGeneration: null,
      );
    }

    final bytes = utf8.encode(jsonEncode(profile.toJson()));
    if (bytes.length > plannerBackendProfileMaxBytes) {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.tooLarge,
        'The backend profile is larger than this build accepts.',
      );
    }

    final target = await _profileFile();
    final temporary = File(
      '${target.path}$plannerBackendProfileTemporarySuffix',
    );
    try {
      await target.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } on FileSystemException {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Leaving a temporary file behind is harmless: it is never read.
      }
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.writeFailed,
        'The backend profile could not be saved.',
      );
    }
    return profile;
  }

  /// Returns the stored profile for the generation check in [save].
  ///
  /// Propagates every failure from [read] except a corrupt, unsupported, or
  /// oversized document when the caller is not claiming a generation: that
  /// combination is an explicit fresh write, which is how an unusable
  /// document is replaced.
  Future<BackendConnectionProfile?> _readForWrite({
    required int? expectedGeneration,
  }) async {
    try {
      return await read();
    } on ConnectionProfileStoreException catch (error) {
      final replaceable =
          error.failure == ConnectionProfileStoreFailure.corrupt ||
          error.failure == ConnectionProfileStoreFailure.unsupportedVersion ||
          error.failure == ConnectionProfileStoreFailure.tooLarge;
      if (expectedGeneration != null || !replaceable) rethrow;
      return null;
    }
  }

  Future<File> _profileFile() async {
    final Directory resolved;
    try {
      resolved = directory ?? await getApplicationSupportDirectory();
    } on Exception {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.unreadable,
        'The application support directory is unavailable.',
      );
    }
    return File(p.join(resolved.path, fileName));
  }

  Future<bool> _exists(File file) async {
    try {
      return await file.exists();
    } on FileSystemException {
      throw const ConnectionProfileStoreException(
        ConnectionProfileStoreFailure.unreadable,
        'The stored backend profile could not be read.',
      );
    }
  }
}
