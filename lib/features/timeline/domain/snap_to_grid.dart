import '../../../core/utils/planner_time_zone.dart';

/// Minutes in a full day.
const int minutesPerDay = 24 * 60;

/// Rounds [dateTime] to the nearest [gridMinutes] boundary of its day,
/// following architecture.md Section 8. Seconds and milliseconds are dropped.
///
/// The result never crosses midnight: the latest possible start is
/// `1440 - gridMinutes` minutes after midnight so a full final slot fits.
DateTime snapToGrid(DateTime dateTime, int gridMinutes) {
  final local = PlannerTimeZone.toPlannerLocal(dateTime);
  return PlannerTimeZone.calendarDate(
    local.year,
    local.month,
    local.day,
    minute: snapSlotStart(local.hour * 60 + local.minute, gridMinutes),
  );
}

/// Snaps a raw minute-of-day value to the nearest grid slot, clamped to the
/// last full slot of the day.
int snapSlotStart(int rawMinutes, int gridMinutes) {
  final snapped = (rawMinutes / gridMinutes).round() * gridMinutes;
  return snapped.clamp(0, minutesPerDay - gridMinutes);
}

/// Snaps a duration (in minutes) to whole grid slots, enforcing a minimum of
/// one grid slot.
int snapDuration(int rawMinutes, int gridMinutes) {
  if (rawMinutes <= gridMinutes) return gridMinutes;
  return (rawMinutes / gridMinutes).round() * gridMinutes;
}
