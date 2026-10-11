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

/// First day of the planner week, chosen in Settings.
enum WeekStartDay {
  monday,
  sunday;

  static WeekStartDay parse(String? value) =>
      value == 'sunday' ? WeekStartDay.sunday : WeekStartDay.monday;
}

/// The week start every week boundary in the app reads. Set only by the
/// week-start setting provider; Monday until it loads.
WeekStartDay plannerWeekStartDay = WeekStartDay.monday;

/// Local midnight of the first day of the week containing [dateTime] under
/// [weekStart].
DateTime startOfWeekFor(DateTime dateTime, WeekStartDay weekStart) {
  final local = PlannerTimeZone.toPlannerLocal(dateTime);
  final offset = switch (weekStart) {
    WeekStartDay.monday => local.weekday - DateTime.monday,
    WeekStartDay.sunday => local.weekday % 7,
  };
  return addDays(
    PlannerTimeZone.calendarDate(local.year, local.month, local.day),
    -offset,
  );
}

/// Local midnight of the first day of the week containing [dateTime], per the
/// week-start setting (Monday by default).
DateTime startOfWeek(DateTime dateTime) =>
    startOfWeekFor(dateTime, plannerWeekStartDay);

/// 1-based position of [dateTime]'s day inside its planner week (1 = first
/// day of the week per the setting, 7 = last).
int dayOfPlannerWeek(DateTime dateTime) {
  final local = PlannerTimeZone.toPlannerLocal(dateTime);
  return switch (plannerWeekStartDay) {
    WeekStartDay.monday => local.weekday,
    WeekStartDay.sunday => local.weekday % 7 + 1,
  };
}

/// Local midnight of the Monday of the week containing [dateTime], whatever
/// the week-start setting. For rules that are defined on ISO weeks.
DateTime startOfIsoWeek(DateTime dateTime) =>
    startOfWeekFor(dateTime, WeekStartDay.monday);

/// The canonical Monday under which the weekly review of the week containing
/// [dateTime] is stored. Saved reviews keep this Monday key whatever the
/// week-start setting, so switching it never orphans or moves a review: a
/// Sunday-start week is keyed by the Monday that falls inside it.
DateTime weeklyReviewKey(DateTime dateTime) {
  final start = startOfWeek(dateTime);
  return plannerWeekStartDay == WeekStartDay.sunday ? addDays(start, 1) : start;
}
