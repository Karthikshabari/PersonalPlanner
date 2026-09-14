import 'package:drift/drift.dart';

import '../converters.dart';

/// One optional, account-scoped annotation for each planner calendar date.
/// The date is deliberately stored as date-only text rather than an instant.
@DataClassName('DayContextRow')
class DayContexts extends Table {
  TextColumn get id => text()();
  TextColumn get date => text()();
  TextColumn get kind => text()();
  TextColumn get customLabel => text().nullable()();
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
  List<Set<Column>> get uniqueKeys => [
    {date},
  ];

  @override
  List<String> get customConstraints => const [
    "CHECK (length(date) = 10 AND date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(date) = date)",
    "CHECK (kind IN ('office', 'holiday', 'leave', 'travel', 'custom'))",
    "CHECK ((kind = 'custom' AND custom_label IS NOT NULL AND length(trim(custom_label)) BETWEEN 1 AND 80) OR (kind <> 'custom' AND custom_label IS NULL))",
  ];
}
