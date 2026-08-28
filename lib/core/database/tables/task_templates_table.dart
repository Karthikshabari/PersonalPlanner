import 'package:drift/drift.dart';

import '../converters.dart';
import 'categories_table.dart';

@DataClassName('TaskTemplateRow')
class TaskTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().nullable()();
  IntColumn get durationMin => integer()();
  TextColumn get categoryId => text()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get tagsJson => text().nullable()();
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
      ];
}
