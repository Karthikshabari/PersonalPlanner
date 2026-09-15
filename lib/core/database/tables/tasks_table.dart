import 'package:drift/drift.dart';

import '../converters.dart';
import 'categories_table.dart';
import 'recurring_rules_table.dart';

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().nullable()();
  TextColumn get startTime =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  TextColumn get endTime =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get estimatedDurationMin => integer().nullable()();
  IntColumn get actualDurationMin => integer().nullable()();
  IntColumn get manualDurationAdjustmentMin =>
      integer().withDefault(const Constant(0))();
  BoolColumn get manualActualSet =>
      boolean().withDefault(const Constant(false))();
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get notes => text().nullable()();
  TextColumn get recurringRuleId => text().nullable().references(
    RecurringRules,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Set only while an unfinished deterministic occurrence is tombstoned
  /// because its rule temporarily stopped producing the original slot.
  /// Ordinary user deletion deliberately leaves this null.
  TextColumn get recurrenceRemovalReason => text().nullable().customConstraint(
    "CHECK (recurrence_removal_reason IS NULL OR recurrence_removal_reason = 'rule_excluded')",
  )();
  TextColumn get rescheduledFromId =>
      text().nullable().references(Tasks, #id, onDelete: KeyAction.setNull)();
  TextColumn get rescheduledToId =>
      text().nullable().references(Tasks, #id, onDelete: KeyAction.setNull)();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  IntColumn get inboxContentVersion =>
      integer().withDefault(const Constant(0))();
  TextColumn get dueDate => text().nullable()();
  TextColumn get missedAt => text().nullable()();
  TextColumn get planTitleHistoryJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get displayPlanChangeId => text().nullable()();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  /// Nullable until the row is acknowledged by Supabase.
  IntColumn get serverVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (priority BETWEEN 0 AND 4)',
    "CHECK (status IN ('planned', 'in_progress', 'completed', 'skipped', 'cancelled', 'rescheduled'))",
    'CHECK (estimated_duration_min IS NULL OR estimated_duration_min > 0)',
    'CHECK (actual_duration_min IS NULL OR actual_duration_min >= 0)',
    'CHECK (manual_duration_adjustment_min IS NOT NULL)',
    'CHECK (manual_actual_set IN (0, 1))',
    'CHECK (inbox_content_version IN (0, 1))',
    "CHECK (json_valid(plan_title_history_json) AND json_type(plan_title_history_json) = 'array')",
    "CHECK (due_date IS NULL OR (length(due_date) = 10 AND due_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(due_date) = due_date))",
    'CHECK (end_time IS NULL OR start_time IS NOT NULL)',
    'CHECK (end_time IS NULL OR end_time > start_time)',
  ];
}
