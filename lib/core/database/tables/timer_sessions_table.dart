import 'package:drift/drift.dart';

import '../converters.dart';
import 'tasks_table.dart';

@DataClassName('TimerSessionRow')
class TimerSessions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get startedAt => text().map(const DateTimeUtcConverter())();
  /// Null while the timer is running (architecture.md §3 TIMER_SESSIONS).
  TextColumn get endedAt =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get durationSec => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('finished'))();
  TextColumn get runningSince =>
      text().nullable().map(const NullableDateTimeUtcConverter())();
  TextColumn get workIntervalsJson => text().withDefault(const Constant('[]'))();
  TextColumn get ownerDeviceId => text().nullable()();
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
        'CHECK (duration_sec >= 0)',
        'CHECK (ended_at IS NULL OR ended_at >= started_at)',
        "CHECK (state IN ('running', 'paused', 'finished'))",
        "CHECK ((state = 'running' AND running_since IS NOT NULL AND ended_at IS NULL) OR (state = 'paused' AND running_since IS NULL AND ended_at IS NULL) OR (state = 'finished' AND running_since IS NULL AND ended_at IS NOT NULL))",
      ];
}
