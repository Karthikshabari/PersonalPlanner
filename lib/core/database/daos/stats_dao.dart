import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/daily_stats_cache_table.dart';

part 'stats_dao.g.dart';

@DriftAccessor(tables: [DailyStatsCache])
class StatsDao extends DatabaseAccessor<AppDatabase> with _$StatsDaoMixin {
  StatsDao(super.db);

  Future<DailyStatsCacheRow?> getStatsForDate(String dateIso) => (select(
    dailyStatsCache,
  )..where((s) => s.date.equals(dateIso))).getSingleOrNull();

  Stream<DailyStatsCacheRow?> watchStatsForDate(String dateIso) {
    return (select(
      dailyStatsCache,
    )..where((s) => s.date.equals(dateIso))).watchSingleOrNull();
  }

  Future<List<DailyStatsCacheRow>> getStatsBetween(
    String startIsoInclusive,
    String endIsoExclusive,
  ) =>
      (select(dailyStatsCache)
            ..where(
              (s) =>
                  s.date.isBiggerOrEqualValue(startIsoInclusive) &
                  s.date.isSmallerThanValue(endIsoExclusive),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.date)]))
          .get();

  /// Full recompute replaces any previous snapshot for the day.
  Future<void> upsertStats(DailyStatsCacheCompanion entry) =>
      into(dailyStatsCache).insertOnConflictUpdate(entry);

  Future<int> invalidateForDate(String dateIso) =>
      (delete(dailyStatsCache)..where((s) => s.date.equals(dateIso))).go();

  Future<int> invalidateAll() => delete(dailyStatsCache).go();
}
