// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncLogTable get syncLog => attachedDatabase.syncLog;
  $SyncConflictsTable get syncConflicts => attachedDatabase.syncConflicts;
  $SyncStateTable get syncState => attachedDatabase.syncState;
  $AppSettingsTable get appSettings => attachedDatabase.appSettings;
  SyncDaoManager get managers => SyncDaoManager(this);
}

class SyncDaoManager {
  final _$SyncDaoMixin _db;
  SyncDaoManager(this._db);
  $$SyncLogTableTableManager get syncLog =>
      $$SyncLogTableTableManager(_db.attachedDatabase, _db.syncLog);
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db.attachedDatabase, _db.syncConflicts);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db.attachedDatabase, _db.syncState);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db.attachedDatabase, _db.appSettings);
}
