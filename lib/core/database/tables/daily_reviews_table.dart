import 'package:drift/drift.dart';

import '../converters.dart';

@DataClassName('DailyReviewRow')
class DailyReviews extends Table {
  TextColumn get id => text()();
  /// Local calendar day as `yyyy-MM-dd`; unique so a date has at most one
  /// review (architecture.md §3 DAILY_REVIEWS).
  TextColumn get date => text()();
  TextColumn get reflection => text().nullable()();
  IntColumn get energyLevel => integer().nullable()();
  IntColumn get productivityRating => integer().nullable()();
  IntColumn get planningAccuracyRating => integer().nullable()();
  TextColumn get winsJson => text().nullable()();
  TextColumn get improvementsJson => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
        'CHECK (energy_level IS NULL OR energy_level BETWEEN 1 AND 5)',
        'CHECK (productivity_rating IS NULL OR productivity_rating BETWEEN 1 AND 5)',
        'CHECK (planning_accuracy_rating IS NULL OR planning_accuracy_rating BETWEEN 1 AND 5)',
      ];
}
