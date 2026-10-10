import 'package:drift/drift.dart';

import '../converters.dart';
import 'tags_table.dart';

/// A time-boxed trial linked to exactly one tag. Dates are date-only text
/// (`yyyy-MM-dd`); the id is deterministic: `experiment:<tagId>`.
@DataClassName('ExperimentRow')
class Experiments extends Table {
  TextColumn get id => text()();
  TextColumn get tagId => text().references(Tags, #id)();
  TextColumn get purpose => text().nullable()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  IntColumn get weekdayTargetMin => integer()();
  IntColumn get weekendTargetMin => integer()();
  IntColumn get checkInEveryDays => integer()();
  TextColumn get status => text().withDefault(const Constant('running'))();

  /// JSON array of `{reason, previous_end_date, new_end_date, made_on}`.
  TextColumn get extensionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get outcome => text().nullable()();
  TextColumn get conclusionNote => text().nullable()();
  TextColumn get concludedOn => text().nullable()();

  /// When a kept experiment was retired (UTC). Null while kept and for every
  /// experiment that was never kept.
  TextColumn get retiredAt =>
      text().nullable().map(const NullableDateTimeUtcConverter())();

  /// What was learned, written when retiring. At most 4000 code points.
  TextColumn get retireNote => text().nullable().customConstraint(
    'CHECK (retire_note IS NULL OR length(retire_note) <= 4000)',
  )();

  /// JSON array of `{effective_week_start, weekday_target_min,
  /// weekend_target_min, made_on}`, ascending, at most one entry per week.
  TextColumn get targetChangesJson =>
      text().withDefault(const Constant('[]'))();
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
    "CHECK (length(start_date) = 10 AND start_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(start_date) = start_date)",
    "CHECK (length(end_date) = 10 AND end_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(end_date) = end_date)",
    "CHECK (concluded_on IS NULL OR (length(concluded_on) = 10 AND concluded_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(concluded_on) = concluded_on))",
    'CHECK (end_date >= start_date)',
    'CHECK (weekday_target_min BETWEEN 0 AND 9999)',
    'CHECK (weekend_target_min BETWEEN 0 AND 9999)',
    'CHECK (check_in_every_days IN (1, 3, 7, 10, 15))',
    "CHECK (status IN ('running', 'concluded'))",
    "CHECK (outcome IS NULL OR outcome IN ('continue_habit', 'drop'))",
    "CHECK (json_valid(extensions_json) AND json_type(extensions_json) = 'array')",
    'CHECK (purpose IS NULL OR length(purpose) <= 1000)',
    'CHECK (conclusion_note IS NULL OR length(conclusion_note) <= 4000)',
    "CHECK ((status = 'running' AND outcome IS NULL AND conclusion_note IS NULL AND concluded_on IS NULL) OR (status = 'concluded' AND outcome IS NOT NULL AND concluded_on IS NOT NULL))",
  ];
}

/// One written note per experiment and slot date. The id is deterministic:
/// `experiment-check-in:<experimentId>:<yyyy-MM-dd>`.
@DataClassName('ExperimentCheckInRow')
class ExperimentCheckIns extends Table {
  TextColumn get id => text()();
  TextColumn get experimentId => text().references(Experiments, #id)();
  TextColumn get slotDate => text()();
  TextColumn get note => text()();
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
    "CHECK (length(slot_date) = 10 AND slot_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(slot_date) = slot_date)",
    'CHECK (length(trim(note)) BETWEEN 1 AND 4000)',
  ];
}
