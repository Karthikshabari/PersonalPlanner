import 'planner_time_zone.dart';

DateTime startOfDay(DateTime dateTime) => PlannerTimeZone.startOfDay(dateTime);

bool isSameDay(DateTime a, DateTime b) {
  final left = PlannerTimeZone.toPlannerLocal(a);
  final right = PlannerTimeZone.toPlannerLocal(b);
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

DateTime addDays(DateTime dateTime, int days) =>
    PlannerTimeZone.addDays(startOfDay(dateTime), days);

int minutesSinceMidnight(DateTime dateTime) {
  final local = PlannerTimeZone.toPlannerLocal(dateTime);
  return local.hour * 60 + local.minute;
}

/// Formats the local calendar date as `yyyy-MM-dd`.
String isoDateString(DateTime dateTime) {
  final local = PlannerTimeZone.toPlannerLocal(dateTime);
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Parses a `yyyy-MM-dd` string into local midnight.
DateTime parseIsoDate(String value) {
  final parts = value.split('-');
  return PlannerTimeZone.calendarDate(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Returns true only for a real, zero-padded calendar date. Date-only values
/// must not be interpreted as UTC instants because that can shift the date.
bool isValidIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return false;
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  return parsed != null &&
      parsed.year == year &&
      parsed.month == month &&
      parsed.day == day;
}

/// Local midnight of the Monday of the week containing [dateTime]
/// (Mon–Sun weeks, planner.md Chunk 5 #6).
DateTime startOfWeek(DateTime dateTime) {
  final local = PlannerTimeZone.toPlannerLocal(dateTime);
  return addDays(
    PlannerTimeZone.calendarDate(local.year, local.month, local.day),
    -(local.weekday - 1),
  );
}
