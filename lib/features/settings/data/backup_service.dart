import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/utils/uuid.dart';
import 'backup_codec.dart';
import 'backup_database_applier.dart';
import 'backup_format.dart';
import 'backup_merge_planner.dart';
import 'backup_validator.dart';

export 'backup_format.dart'
    show
        BackupConflict,
        BackupConflictKind,
        BackupImportResult,
        BackupValidationException,
        plannerBackupMaxBytes,
        plannerBackupSchemaVersion,
        portableSettingKeys;

/// Persists a pre-import snapshot without ever replacing an earlier recovery
/// artifact. The caller may retain the returned path for user-facing recovery
/// instructions.
class BackupRecoveryWriter {
  static Future<File> write({
    required String directoryPath,
    required String contents,
  }) async {
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(
      '$directoryPath/personal_planner_pre_import_${timestamp}_${generateUuidV7()}.json',
    );
    await file.create(exclusive: true);
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      await handle.writeString(contents);
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (await file.readAsString() != contents) {
      throw StateError('Recovery backup verification failed.');
    }
    return file;
  }
}

/// Public Settings-facing facade for portable backup operations.
///
/// Codec, validation, merge planning, and transaction application are kept in
/// separate units so a malformed document is rejected before any write and
/// the UI workflow does not own persistence details.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  Future<String> exportJson() async {
    final data = await BackupCodec.exportData(_db);
    return BackupCodec.encodeData(data);
  }

  /// Merges a portable backup without overwriting a differing local row or
  /// setting. The complete comparison and dependency-closure plan is built
  /// inside the transaction before the first write.
  Future<BackupImportResult> importJson(
    String source, {
    bool ownershipConfirmed = false,
  }) async {
    if (!ownershipConfirmed) {
      throw const BackupValidationException(
        'Backup ownership confirmation is required.',
      );
    }
    final data = _decodeAndValidate(source);
    late BackupMergePlan plan;
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      final local = await BackupCodec.exportData(_db);
      plan = BackupMergePlanner().build(incoming: data, local: local);
      await BackupDatabaseApplier(_db).applyMerge(plan);
    });
    return BackupImportResult(
      inserted: plan.insertedCount,
      skipped: plan.skipped,
      conflicts: plan.conflicts,
    );
  }

  /// Replaces all user-domain rows after explicit confirmation and validation
  /// of a recoverable pre-import document. Deletes, imports, derived rebuild,
  /// and integrity checks run in one recoverable transaction.
  Future<void> replaceFromJson(
    String source, {
    required String preImportBackup,
    required bool confirmed,
    bool ownershipConfirmed = false,
  }) async {
    if (!confirmed || !ownershipConfirmed) {
      throw const BackupValidationException(
        'Replace requires explicit confirmation and backup ownership confirmation.',
      );
    }
    _decodeAndValidate(preImportBackup);
    final data = _decodeAndValidate(source);
    // A synced account has server history that a portable backup does not
    // contain. Replacing it locally would either resurrect stale server rows
    // or require an account-wide tombstone protocol. Refuse that ambiguous
    // operation until the user has chosen an explicit sync-aware workflow.
    final syncState = await _db.select(_db.syncState).get();
    if (syncState.isNotEmpty) {
      throw const BackupValidationException(
        'Replace is unavailable for a synchronized account. Use merge or export first.',
      );
    }
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      await BackupDatabaseApplier(_db).applyReplace(data);
    });
  }

  Map<String, dynamic> _decodeAndValidate(String source) {
    final data = BackupCodec.decodeData(source);
    BackupValidator().validate(data);
    // Pre-guide-removal backups may contain this inert preference. Accept the
    // document for compatibility, but do not recreate dead onboarding state.
    (data['settings'] as Map<String, dynamic>).remove(
      legacyOnboardingCompletedSettingKey,
    );
    return data;
  }
}
