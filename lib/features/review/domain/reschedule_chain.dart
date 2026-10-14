import 'package:intl/intl.dart';

import '../../../core/utils/clock_format.dart';
import '../../../core/utils/planner_time_zone.dart';

/// One task row of a reschedule chain (`TaskDao.getRescheduleRelatives`).
typedef RescheduleLink = ({
  String id,
  DateTime? start,
  DateTime? end,
  String? rescheduledToId,
  bool deleted,
});

/// Where a moved block was planned and where its task is planned now. Display
/// only: it never changes a count, minute, percent or streak.
typedef RescheduleMove = ({
  DateTime fromStart,
  DateTime fromEnd,
  DateTime toStart,
  DateTime toEnd,

  /// Moves along the whole chain (1 = moved once).
  int pushes,
});

/// The move of the block [id], or null when it is not moved to a live block.
/// Follows `rescheduled_to_id` forward to where the task is now and back to
/// its first planned slot; deleted rows are walked through but not counted.
/// A visited set and a step cap make a broken or cyclic chain terminate.
RescheduleMove? rescheduleMoveOf(
  String id,
  Map<String, RescheduleLink> rowsById,
) {
  final fromOf = <String, String>{};
  for (final row
      in rowsById.values.toList()..sort((a, b) => a.id.compareTo(b.id))) {
    final to = row.rescheduledToId;
    if (to != null) fromOf.putIfAbsent(to, () => row.id);
  }
  final own = rowsById[id];
  if (own == null || own.start == null || own.end == null) return null;
  final seen = <String>{id};
  var earlier = 0;
  for (var at = fromOf[id]; at != null && seen.add(at); at = fromOf[at]) {
    if (rowsById[at]?.deleted == false) earlier++;
  }
  RescheduleLink? now;
  var later = 0;
  for (
    var at = own.rescheduledToId;
    at != null && seen.add(at) && seen.length < 200;
    at = rowsById[at]?.rescheduledToId
  ) {
    final row = rowsById[at];
    if (row == null) break;
    if (row.deleted || row.start == null || row.end == null) continue;
    now = row;
    later++;
  }
  if (now == null) return null;
  return (
    fromStart: own.start!,
    fromEnd: own.end!,
    toStart: now.start!,
    toEnd: now.end!,
    pushes: earlier + later,
  );
}

/// Daily row: `Moved to Thu Oct 1, 14:00`.
String movedToText(RescheduleMove move) {
  final to = PlannerTimeZone.toPlannerLocal(move.toStart);
  return 'Moved to ${DateFormat('EEE MMM d').format(to)}, ${formatClock24(to)}';
}

/// Weekly row: `Planned Mon 09:00–10:00 → now Thu 14:00–15:00 · pushed 2
/// times`.
String plannedNowText(RescheduleMove move) {
  String slot(DateTime start, DateTime end) {
    final from = PlannerTimeZone.toPlannerLocal(start);
    final to = PlannerTimeZone.toPlannerLocal(end);
    return '${DateFormat('EEE').format(from)} ${formatClock24(from)}–'
        '${formatClock24(to)}';
  }

  return 'Planned ${slot(move.fromStart, move.fromEnd)} → now '
      '${slot(move.toStart, move.toEnd)}'
      '${move.pushes >= 2 ? ' · pushed ${move.pushes} times' : ''}';
}

/// Editor line: `Originally planned Mon Sep 7, 09:00–10:00 - moved 2 times`.
String originallyPlannedText(RescheduleMove move) {
  final from = PlannerTimeZone.toPlannerLocal(move.fromStart);
  final to = PlannerTimeZone.toPlannerLocal(move.fromEnd);
  return 'Originally planned ${DateFormat('EEE MMM d').format(from)}, '
      '${formatClock24(from)}–${formatClock24(to)} - moved ${move.pushes} '
      '${move.pushes == 1 ? 'time' : 'times'}';
}
