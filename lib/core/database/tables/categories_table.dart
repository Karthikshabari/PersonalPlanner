import 'package:drift/drift.dart';

import '../converters.dart';

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get colorHex => text().withLength(min: 7, max: 7)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isFocus => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text().map(const DateTimeUtcConverter())();
  TextColumn get updatedAt => text().map(const DateTimeUtcConverter())();
  TextColumn get deletedAt => text().nullable().map(const NullableDateTimeUtcConverter())();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
        "CHECK (color_hex GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]')",
        'CHECK (sort_order >= 0)',
      ];
}
