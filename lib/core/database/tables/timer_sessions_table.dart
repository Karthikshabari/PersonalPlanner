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
        'CHECK (duration_sec >= 0)',
        'CHECK (ended_at IS NULL OR ended_at >= started_at)',
      ];
}
