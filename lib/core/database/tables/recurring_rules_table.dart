import 'package:drift/drift.dart';

import '../converters.dart';
import 'categories_table.dart';

@DataClassName('RecurringRuleRow')
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get rrule => text().withLength(min: 1, max: 500)();
  TextColumn get taskTitle => text().withLength(min: 1, max: 500)();
  TextColumn get taskDescription => text().nullable()();
  IntColumn get durationMin => integer()();
  TextColumn get categoryId => text()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get tagsJson => text().nullable()();
  TextColumn get startTimeOfDay => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get exceptionsJson => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt => text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
        'CHECK (duration_min > 0)',
        'CHECK (priority BETWEEN 0 AND 4)',
        "CHECK (start_time_of_day GLOB '[01][0-9]:[0-5][0-9]' OR start_time_of_day GLOB '2[0-3]:[0-5][0-9]')",
      ];
}
