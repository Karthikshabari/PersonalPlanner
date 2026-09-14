import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Single timezone boundary used by planner calendar calculations.
///
/// The application stores instants in UTC, but calendar dates and recurrence
/// boundaries are wall-clock concepts. `TZDateTime(year, month, day + n)` is
/// used for calendar arithmetic so a DST transition never turns a day into a
/// fixed 24-hour offset.
abstract final class PlannerTimeZone {
  static bool _initialized = false;

  static void initialize({String? identifier}) {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    if (identifier != null) {
      try {
        tz.setLocalLocation(tz.getLocation(identifier));
      } on Object {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
    }
  }

  static tz.Location get location {
    initialize();
    return tz.local;
  }

  static DateTime toPlannerLocal(DateTime instant) =>
      tz.TZDateTime.from(instant.toUtc(), location);

  static DateTime startOfDay(DateTime date) {
    final local = toPlannerLocal(date);
    return tz.TZDateTime(location, local.year, local.month, local.day);
  }

  /// Constructs a wall-clock date in the planner timezone.
  ///
  /// Date-only values must not be created as host-timezone instants first,
  /// because that can shift the calendar date before conversion.
  static DateTime calendarDate(
    int year,
    int month,
    int day, {
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    int microsecond = 0,
  }) => tz.TZDateTime(
    location,
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
    microsecond,
  );

  static DateTime addDays(DateTime date, int days) {
    final local = toPlannerLocal(date);
    return tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day + days,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  static (DateTime start, DateTime end) dayBounds(DateTime date) {
    final start = startOfDay(date);
    return (start, addDays(start, 1));
  }
}
