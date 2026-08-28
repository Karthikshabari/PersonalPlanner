import 'package:drift/drift.dart';

import '../converters.dart';
import 'categories_table.dart';
import 'recurring_rules_table.dart';

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().nullable()();
  TextColumn get startTime => text().nullable().map(const NullableDateTimeUtcConverter())();
  TextColumn get endTime => text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get estimatedDurationMin => integer().nullable()();
  IntColumn get actualDurationMin => integer().nullable()();
  IntColumn get manualDurationAdjustmentMin =>
      integer().withDefault(const Constant(0))();
  TextColumn get categoryId => text()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get notes => text().nullable()();
  TextColumn get recurringRuleId => text()
      .nullable()
      .references(RecurringRules, #id, onDelete: KeyAction.setNull)();
  TextColumn get rescheduledFromId => text()
      .nullable()
      .references(Tasks, #id, onDelete: KeyAction.setNull)();
  TextColumn get rescheduledToId => text()
      .nullable()
      .references(Tasks, #id, onDelete: KeyAction.setNull)();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  TextColumn get missedAt => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt => text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
        'CHECK (priority BETWEEN 0 AND 4)',
        "CHECK (status IN ('planned', 'in_progress', 'completed', 'skipped', 'cancelled', 'rescheduled'))",
        'CHECK (estimated_duration_min IS NULL OR estimated_duration_min > 0)',
        'CHECK (actual_duration_min IS NULL OR actual_duration_min >= 0)',
        'CHECK (manual_duration_adjustment_min IS NOT NULL)',
        'CHECK (end_time IS NULL OR start_time IS NOT NULL)',
        'CHECK (end_time IS NULL OR end_time > start_time)',
      ];
}
