import 'package:drift/drift.dart';

import '../converters.dart';

/// Pre-aggregated per-day statistics (architecture.md §10 "Computation
/// Strategy"). Local-only — never synced (§9 "Tables NOT synced").
@DataClassName('DailyStatsCacheRow')
class DailyStatsCache extends Table {
  /// Local calendar day as `yyyy-MM-dd` (primary key).
  TextColumn get date => text()();
  IntColumn get totalTasks => integer().withDefault(const Constant(0))();
  IntColumn get completedTasks => integer().withDefault(const Constant(0))();
  IntColumn get plannedTasks => integer().withDefault(const Constant(0))();
  IntColumn get inProgressTasks => integer().withDefault(const Constant(0))();
  IntColumn get missedTasks => integer().withDefault(const Constant(0))();
  IntColumn get skippedTasks => integer().withDefault(const Constant(0))();
  IntColumn get cancelledTasks => integer().withDefault(const Constant(0))();
  IntColumn get rescheduledTasks => integer().withDefault(const Constant(0))();
  IntColumn get plannedDurationMin =>
      integer().withDefault(const Constant(0))();
  IntColumn get actualDurationMin => integer().withDefault(const Constant(0))();
  IntColumn get focusDurationMin => integer().withDefault(const Constant(0))();
  IntColumn get energyLevel => integer().nullable()();
  IntColumn get productivityRating => integer().nullable()();
  RealColumn get planningAccuracyPct => real().nullable()();
  TextColumn get computedAt => text().map(const DateTimeUtcConverter())();

  @override
  Set<Column> get primaryKey => {date};
}
