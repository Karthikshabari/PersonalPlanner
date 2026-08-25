DateTime startOfDay(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime addDays(DateTime dateTime, int days) =>
    startOfDay(dateTime).add(Duration(days: days));

int minutesSinceMidnight(DateTime dateTime) =>
    dateTime.hour * 60 + dateTime.minute;

/// Formats the local calendar date as `yyyy-MM-dd`.
String isoDateString(DateTime dateTime) =>
    '${dateTime.year.toString().padLeft(4, '0')}-'
    '${dateTime.month.toString().padLeft(2, '0')}-'
    '${dateTime.day.toString().padLeft(2, '0')}';

/// Parses a `yyyy-MM-dd` string into local midnight.
DateTime parseIsoDate(String value) {
  final parts = value.split('-');
  return DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// Local midnight of the Monday of the week containing [dateTime]
/// (Mon–Sun weeks, planner.md Chunk 5 #6).
DateTime startOfWeek(DateTime dateTime) =>
    startOfDay(dateTime).add(Duration(days: -(dateTime.weekday - 1)));
