// Portable backup format constants and result types.

/// The version of the portable Personal Planner backup document.
const int plannerBackupSchemaVersion = 2;

/// Inputs larger than this are rejected before JSON parsing. This keeps the
/// Settings workflow responsive and prevents an accidental giant file from
/// becoming an unbounded memory allocation.
const int plannerBackupMaxBytes = 20 * 1024 * 1024;

/// Settings that are safe and useful to carry between local databases. Sync
/// cursors, outbox entries, conflict snapshots, auth material, and account
/// identifiers are intentionally excluded.
const Set<String> portableSettingKeys = {
  'grid_interval_minutes',
  'theme_mode',
  'review_reminder_enabled',
  'review_reminder_time',
  'onboarding.completed',
};

enum BackupConflictKind { differing, blocked }

class BackupValidationException implements Exception {
  final String message;

  const BackupValidationException(this.message);

  @override
  String toString() => message;
}

class BackupConflict {
  final String table;
  final String id;
  final BackupConflictKind kind;

  const BackupConflict({
    required this.table,
    required this.id,
    this.kind = BackupConflictKind.differing,
  });

  bool get isBlocked => kind == BackupConflictKind.blocked;

  @override
  String toString() => '$table/$id${isBlocked ? ' (blocked)' : ''}';
}

class BackupImportResult {
  final int inserted;
  final int skipped;
  final List<BackupConflict> conflicts;

  const BackupImportResult({
    required this.inserted,
    required this.skipped,
    required this.conflicts,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}
