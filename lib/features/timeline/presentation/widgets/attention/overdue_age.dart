import 'package:intl/intl.dart';

import '../../../../../core/models/task.dart';
import '../../../../../core/utils/missed_at.dart';
import '../../../../../core/utils/planner_time_zone.dart';

/// The instant an overdue task is measured from: the moment it was marked
/// missed when known, otherwise its planned start (as `OverdueBadge` does).
DateTime? overdueInstant(Task task) =>
    MissedAtCodec.parse(task.missedAt) ?? task.startTime;

/// How long ago [instant] was, relative to [now]: "Just now", "5 min ago",
/// "3 hours ago", "Yesterday", "6 days ago", "3 weeks ago", then "Mar 10".
///
/// Pure: [now] is passed in (the widget takes it from `inboxClockProvider`).
/// "Yesterday" and the day and week counts use planner-local calendar days.
String formatOverdueAge(DateTime instant, DateTime now) {
  final elapsed = now.difference(instant);
  if (elapsed < const Duration(minutes: 1)) return 'Just now';
  if (elapsed < const Duration(hours: 1)) return '${elapsed.inMinutes} min ago';

  final days = _calendarDaysBetween(instant, now);
  if (days <= 0) {
    // Same planner day (or a clock that is behind): hours.
    final hours = elapsed.inHours;
    return hours == 1 ? '1 hour ago' : '$hours hours ago';
  }
  if (days == 1) return 'Yesterday';
  if (days < 14) return '$days days ago';
  if (days < 56) {
    final weeks = days ~/ 7;
    return '$weeks weeks ago';
  }
  return DateFormat('MMM d').format(PlannerTimeZone.toPlannerLocal(instant));
}

/// The exact time shown in tooltips and read by screen readers:
/// `EEE, MMM d · HH:mm` in the planner time zone. Empty when the task has no
/// time to show.
String formatOverdueExact(Task task) {
  final instant = overdueInstant(task);
  if (instant == null) return '';
  return formatExactInstant(instant);
}

/// `EEE, MMM d · HH:mm` for [instant] in the planner time zone.
String formatExactInstant(DateTime instant) =>
    DateFormat('EEE, MMM d · HH:mm')
        .format(PlannerTimeZone.toPlannerLocal(instant));

/// Whole planner-local calendar days from [from] to [to] (negative when [to]
/// is the earlier day).
int _calendarDaysBetween(DateTime from, DateTime to) {
  final a = PlannerTimeZone.toPlannerLocal(from);
  final b = PlannerTimeZone.toPlannerLocal(to);
  return DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}
