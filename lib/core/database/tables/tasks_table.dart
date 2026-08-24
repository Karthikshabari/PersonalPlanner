import 'package:drift/drift.dart';

import '../converters.dart';

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().nullable()();
  TextColumn get startTime => text().nullable().map(const NullableDateTimeUtcConverter())();
  TextColumn get endTime => text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get estimatedDurationMin => integer().nullable()();
  IntColumn get actualDurationMin => integer().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get notes => text().nullable()();
  TextColumn get recurringRuleId => text().nullable()();
  TextColumn get rescheduledFromId => text().nullable()();
  TextColumn get rescheduledToId => text().nullable()();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  TextColumn get missedAt => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt => text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}
