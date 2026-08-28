import 'package:drift/drift.dart';

import '../converters.dart';

@DataClassName('WeeklyReviewRow')
class WeeklyReviews extends Table {
  TextColumn get id => text()();
  /// Monday of the reviewed week as `yyyy-MM-dd`; unique per week
  /// (architecture.md §3 WEEKLY_REVIEWS).
  TextColumn get weekStartDate => text()();
  TextColumn get reflection => text().nullable()();
  IntColumn get overallRating => integer().nullable()();
  TextColumn get goalsMetJson => text().nullable()();
  TextColumn get goalsMissedJson => text().nullable()();
  TextColumn get nextWeekFocusJson => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
        'CHECK (overall_rating IS NULL OR overall_rating BETWEEN 1 AND 5)',
      ];
}
