import 'package:flutter/foundation.dart';

import '../../../core/models/enums/task_status.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../timeline/domain/scheduling_conflict_service.dart';
import 'inbox_status.dart';

/// How many planner days (today included) a session can be planned on.
const inboxWindowDays = 14;

/// The session lengths the dates panel offers, in minutes.
const inboxSlotLengths = <int>[30, 60, 90, 120];

const inboxDefaultStartHour = 9;
const inboxDefaultLengthMin = 60;

/// The next whole planner hour after [now], or null when none is left today.
int? inboxNextWholeHour(DateTime now) {
  final hour = PlannerTimeZone.toPlannerLocal(now).hour + 1;
  return hour < 24 ? hour : null;
}

/// The hour 'Time for all' starts at: 09:00, or the next whole hour once
/// 09:00 has passed so that Today can still be picked. Back to 09:00 when no
/// hour is left today.
int inboxDefaultHour(DateTime now) {
  final next = inboxNextWholeHour(now);
  return next == null || next <= inboxDefaultStartHour
      ? inboxDefaultStartHour
      : next;
}

/// What the dates panel holds for one idea while it is closed: the picked
/// dates with their minute of the day, the time and length for the rest, and
/// the length each existing session keeps.
@immutable
class InboxDatesDraft {
  const InboxDatesDraft({
    required this.pickedMinutes,
    required this.allMinutes,
    required this.length,
    required this.ownLengths,
  });

  final Map<String, int> pickedMinutes;
  final int allMinutes;
  final int length;
  final Map<String, int> ownLengths;
}

/// One session the user picked: a start instant and a length. Its date is the
/// planner date of the start.
@immutable
class InboxSlot {
  const InboxSlot({required this.start, required this.lengthMin});

  final DateTime start;
  final int lengthMin;

  DateTime get end => start.add(Duration(minutes: lengthMin));

  /// Planner date (`yyyy-MM-dd`) the slot belongs to.
  String get date => isoDateString(start);

  @override
  bool operator ==(Object other) =>
      other is InboxSlot &&
      other.start.isAtSameMomentAs(start) &&
      other.lengthMin == lengthMin;

  @override
  int get hashCode => Object.hash(start.microsecondsSinceEpoch, lengthMin);

  @override
  String toString() => 'InboxSlot($start, ${lengthMin}m)';
}

/// The 14 planner dates from today, as `yyyy-MM-dd`. Built with calendar
/// arithmetic so a DST change or a month end never shifts a date.
List<String> inboxWindowDates(DateTime now) {
  final today = PlannerTimeZone.toPlannerLocal(now);
  return [
    for (var i = 0; i < inboxWindowDays; i++)
      isoDateString(
        PlannerTimeZone.calendarDate(today.year, today.month, today.day + i),
      ),
  ];
}

/// The wall-clock start of [isoDate] at [hour]:[minute] in the planner zone.
DateTime inboxSlotStart(
  String isoDate, {
  int hour = inboxDefaultStartHour,
  int minute = 0,
}) {
  final parts = isoDate.split('-');
  return PlannerTimeZone.calendarDate(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
    hour: hour,
    minute: minute,
  );
}

enum InboxQuickPick { tomorrow, nextThreeDays, nextFiveWeekdays, clear }

/// The dates a quick pick selects. Tomorrow = today+1; next 3 days =
/// today+1..today+3; next 5 weekdays = the next five Monday to Friday dates
/// counted from tomorrow; clear = none.
List<String> inboxQuickPickDates(InboxQuickPick pick, DateTime now) {
  final window = inboxWindowDates(now);
  switch (pick) {
    case InboxQuickPick.clear:
      return const <String>[];
    case InboxQuickPick.tomorrow:
      return [window[1]];
    case InboxQuickPick.nextThreeDays:
      return window.sublist(1, 4);
    case InboxQuickPick.nextFiveWeekdays:
      return [
        for (final date in window.skip(1))
          if (parseIsoDate(date).weekday <= DateTime.friday) date,
      ].take(5).toList(growable: false);
  }
}

/// Why [slot] cannot be saved at [now], or null when it can.
String? inboxSlotError(InboxSlot slot, DateTime now) {
  if (!inboxSlotLengths.contains(slot.lengthMin)) {
    return 'Length must be 30, 60, 90 or 120 minutes.';
  }
  if (!slot.start.isAfter(now)) {
    return 'Pick a time that has not passed yet.';
  }
  if (!inboxWindowDates(now).contains(slot.date)) {
    return 'You can plan up to 2 weeks ahead.';
  }
  return null;
}

/// Throws [ArgumentError] with a readable message unless every slot is valid,
/// there are at most 14, and no two share a planner date.
void validateInboxSlots(Iterable<InboxSlot> slots, DateTime now) {
  final list = slots.toList(growable: false);
  if (list.length > inboxWindowDays) {
    throw ArgumentError('Pick at most $inboxWindowDays dates.');
  }
  final seen = <String>{};
  for (final slot in list) {
    final error = inboxSlotError(slot, now);
    if (error != null) throw ArgumentError(error);
    if (!seen.add(slot.date)) {
      throw ArgumentError('Pick each date only once.');
    }
  }
}

/// The sessions Save dates may move or drop, soonest first: not deleted, still
/// `planned`, starting after [now] and inside the 14-day window. Started,
/// in-progress, done, skipped, carried and after-window sessions are never
/// touched.
List<InboxSessionFacts> replaceableInboxSessions(
  Iterable<InboxSessionFacts> sessions,
  DateTime now,
) {
  final window = inboxWindowDates(now).toSet();
  return [
    for (final session in sessions)
      if (session.deletedAt == null &&
          session.status == TaskStatus.planned &&
          session.start != null &&
          session.start!.isAfter(now) &&
          window.contains(isoDateString(session.start!)))
        session,
  ]..sort((a, b) {
    final byStart = a.start!.compareTo(b.start!);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  });
}

/// Upcoming sessions that start after the 14-day window. They stay as planned
/// in Day and Save never touches them.
List<InboxSessionFacts> inboxAfterWindowSessions(
  Iterable<InboxSessionFacts> sessions,
  DateTime now,
) {
  final last = inboxWindowDates(now).last;
  return [
    for (final session in sessions)
      if (sessionStatusOf(session, now) == InboxSessionStatus.upcoming &&
          isoDateString(session.start!).compareTo(last) > 0)
        session,
  ];
}

/// For each picked slot, the Day blocks it overlaps, keyed by slot date.
/// [windowTasks] is Day's candidate read for the window; the item's own
/// replaceable sessions ([replaceableIds]) are left out because Save moves or
/// drops them. Cancelled and rescheduled blocks never conflict
/// (`ConflictDetector`). Slots with no overlap are absent from the result.
Map<String, List<Task>> inboxSlotOverlaps({
  required Iterable<InboxSlot> slots,
  required List<Task> windowTasks,
  Set<String> replaceableIds = const <String>{},
}) {
  final candidates = [
    for (final task in windowTasks)
      if (!replaceableIds.contains(task.id)) task,
  ];
  final result = <String, List<Task>>{};
  for (final slot in slots) {
    final probe = Task(
      id: 'inbox-slot-${slot.date}',
      title: '',
      startTime: slot.start,
      endTime: slot.end,
      createdAt: slot.start,
      updatedAt: slot.start,
    );
    final conflicts = SchedulingConflictService.conflicts(probe, candidates);
    if (conflicts.isNotEmpty) result[slot.date] = conflicts;
  }
  return result;
}
