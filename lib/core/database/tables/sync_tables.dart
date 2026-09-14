import 'package:drift/drift.dart';

import '../converters.dart';

/// Durable local outbox for one logical client mutation.
///
/// The table is local-only. Its payload is a validated JSON snapshot or
/// tombstone and must never contain credentials or session data.
@DataClassName('SyncLogRow')
class SyncLog extends Table {
  TextColumn get operationId => text()();
  TextColumn get entityTableName => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get operation => text()();
  IntColumn get expectedServerVersion => integer().nullable()();
  TextColumn get payload => text()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get nextAttemptAt =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  TextColumn get lastError => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => const [
    "CHECK (operation IN ('insert', 'update', 'delete'))",
    "CHECK (state IN ('pending', 'in_flight', 'acknowledged', 'conflict', 'error'))",
    'CHECK (attempt_count >= 0)',
  ];
}

/// Both snapshots are retained until the user explicitly resolves a conflict.
@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  TextColumn get id => text()();
  TextColumn get operationId => text()();
  TextColumn get entityTableName => text().named('table_name')();
  TextColumn get recordId => text()();
  IntColumn get expectedServerVersion => integer().nullable()();
  IntColumn get actualServerVersion => integer().nullable()();
  TextColumn get localSnapshot => text()();
  TextColumn get remoteSnapshot => text()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// One durable pull cursor per authenticated account/database.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get accountId => text()();
  IntColumn get lastChangeId => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();

  @override
  Set<Column> get primaryKey => {accountId};
}
