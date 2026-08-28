// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats_dao.dart';

// ignore_for_file: type=lint
mixin _$StatsDaoMixin on DatabaseAccessor<AppDatabase> {
  $DailyStatsCacheTable get dailyStatsCache => attachedDatabase.dailyStatsCache;
  StatsDaoManager get managers => StatsDaoManager(this);
}

class StatsDaoManager {
  final _$StatsDaoMixin _db;
  StatsDaoManager(this._db);
  $$DailyStatsCacheTableTableManager get dailyStatsCache =>
      $$DailyStatsCacheTableTableManager(
        _db.attachedDatabase,
        _db.dailyStatsCache,
      );
}
