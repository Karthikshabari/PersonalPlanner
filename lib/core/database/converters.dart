import 'package:drift/drift.dart';

class DateTimeUtcConverter extends TypeConverter<DateTime, String> {
  const DateTimeUtcConverter();

  @override
  DateTime fromSql(String fromDb) => DateTime.parse(fromDb).toLocal();

  @override
  String toSql(DateTime value) => value.toUtc().toIso8601String();
}

class NullableDateTimeUtcConverter
    extends TypeConverter<DateTime?, String?> {
  const NullableDateTimeUtcConverter();

  @override
  DateTime? fromSql(String? fromDb) =>
      fromDb == null ? null : DateTime.parse(fromDb).toLocal();

  @override
  String? toSql(DateTime? value) => value?.toUtc().toIso8601String();
}
