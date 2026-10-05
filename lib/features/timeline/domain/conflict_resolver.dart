import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import 'conflict_detector.dart';
import 'snap_to_grid.dart';

/// User-selectable strategies shown in the conflict resolution dialog.
enum ConflictResolution { shiftAllFollowing, shiftOnlyOverlapping, keepOverlap }

/// A planned time shift for one task, produced by a resolution strategy.
/// Pure data — executing it is the caller's job (via a [MoveTaskCommand]).
class PlannedShift {
  final String taskId;
  final DateTime oldStart;
  final DateTime oldEnd;
  final DateTime newStart;
  final DateTime newEnd;

  const PlannedShift({
    required this.taskId,
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
  });
}

/// Outcome of planning a resolution: the shifts to apply plus any tasks that
/// were deliberately left overlapping (cascade depth exceeded / keep overlap).
class ResolutionPlan {
  final List<PlannedShift> shifts;
  final Set<String> keepOverlapIds;

  const ResolutionPlan({
    this.shifts = const [],
    this.keepOverlapIds = const {},
  });

  bool get isEmpty => shifts.isEmpty && keepOverlapIds.isEmpty;
}

/// Pure conflict-resolution planners per architecture.md Section 8.
abstract final class ConflictResolver {
  /// **Shift All Following**: computes
  /// `overlapDuration = dropped.end - firstConflict.start` and shifts every
  /// active scheduled task starting at/after `firstConflict.start` forward by
  /// that amount (the dropped task itself is excluded — the caller moves it).
  static ResolutionPlan planShiftAllFollowing({
    required Task moved,
    required List<Task> dayTasks,
  }) {
    final conflicts = ConflictDetector.detect(moved, dayTasks);
    if (conflicts.isEmpty || _spanOf(moved) == null) {
      return const ResolutionPlan();
    }
    final first = conflicts.first;
    final movedEnd = moved.endTime!;
    final overlapDuration = movedEnd.difference(first.startTime!);
    if (overlapDuration <= Duration.zero) return const ResolutionPlan();

    final shifts = <PlannedShift>[];
    for (final task in _sortedActive(dayTasks)) {
      if (task.id == moved.id) continue;
      final start = task.startTime!;
      if (start.isBefore(first.startTime!)) continue;
      final end = task.endTime!;
      shifts.add(
        PlannedShift(
          taskId: task.id,
          oldStart: start,
          oldEnd: end,
          newStart: start.add(overlapDuration),
          newEnd: end.add(overlapDuration),
        ),
      );
    }
    return ResolutionPlan(shifts: shifts);
  }

  /// **Shift Only Overlapping**: the moved block stays where it was dropped
  /// and every block it overlaps is pushed forward just far enough to clear
  /// it, cascading into blocks that a pushed block lands on.
  ///
  /// Victims are placed one at a time in original start order: each starts
  /// at its original start and is moved past every already placed block it
  /// overlaps (the moved block, earlier victims, blocks left in place), so
  /// several victims of one pusher stack one after another instead of
  /// landing on the same slot. Untouched blocks that a placed victim now
  /// overlaps join the queue one cascade generation deeper.
  ///
  /// A victim is left in place, and its id returned in
  /// [ResolutionPlan.keepOverlapIds] together with the moved block, when its
  /// generation exceeds [maxCascadeDepth] or when the push would carry its
  /// end past the end of the planner day it starts on (rows on the next day
  /// are not part of the candidate set, so they cannot be checked).
  static ResolutionPlan planShiftOnlyOverlapping({
    required Task moved,
    required List<Task> dayTasks,
    int maxCascadeDepth = 10,
  }) {
    final initialConflicts = ConflictDetector.detect(moved, dayTasks);
    if (initialConflicts.isEmpty || _spanOf(moved) == null) {
      return const ResolutionPlan();
    }

    final movedId = moved.id;
    final untouched = {
      for (final t in _sortedActive(dayTasks))
        if (t.id != movedId) t.id: t,
    };
    // Blocks whose final position is decided: the moved block, shifted
    // victims and victims left in place.
    final placed = <({DateTime start, DateTime end})>[
      (start: moved.startTime!, end: moved.endTime!),
    ];
    final queue = <({Task task, int depth})>[];
    for (final c in initialConflicts) {
      if (untouched.remove(c.id) != null) queue.add((task: c, depth: 1));
    }
    final keepIds = <String>{};
    final shifts = <PlannedShift>[];

    while (queue.isNotEmpty) {
      queue.sort((a, b) {
        final byStart = a.task.startTime!.compareTo(b.task.startTime!);
        return byStart != 0 ? byStart : a.task.id.compareTo(b.task.id);
      });
      final (:task, :depth) = queue.removeAt(0);
      final oldStart = task.startTime!;
      final oldEnd = task.endTime!;
      final duration = oldEnd.difference(oldStart);

      var newStart = oldStart;
      var progressed = true;
      while (progressed) {
        progressed = false;
        for (final p in placed) {
          if (_intervalsOverlap(
            newStart,
            newStart.add(duration),
            p.start,
            p.end,
          )) {
            newStart = p.end;
            progressed = true;
          }
        }
      }
      final newEnd = newStart.add(duration);
      final (_, dayEnd) = PlannerTimeZone.dayBounds(oldStart);

      if (depth > maxCascadeDepth || newEnd.isAfter(dayEnd)) {
        keepIds.add(task.id);
        placed.add((start: oldStart, end: oldEnd));
        continue;
      }
      placed.add((start: newStart, end: newEnd));
      if (newStart != oldStart) {
        shifts.add(
          PlannedShift(
            taskId: task.id,
            oldStart: oldStart,
            oldEnd: oldEnd,
            newStart: newStart,
            newEnd: newEnd,
          ),
        );
      }

      // Cascade: untouched blocks the shifted block now lands on.
      final hit = [
        for (final other in untouched.values)
          if (_intervalsOverlap(
            newStart,
            newEnd,
            other.startTime!,
            other.endTime!,
          ))
            other,
      ];
      for (final other in hit) {
        untouched.remove(other.id);
        queue.add((task: other, depth: depth + 1));
      }
    }

    if (keepIds.isNotEmpty) keepIds.add(movedId);
    return ResolutionPlan(shifts: shifts, keepOverlapIds: keepIds);
  }

  /// Finds the next slot (minute-of-day on the viewed day) at/after
  /// [searchFromMinutes] that fits [durationMinutes] without overlapping any
  /// active scheduled block. Returns null when nothing fits before midnight.
  static int? findNextAvailableSlot({
    required int durationMinutes,
    required List<Task> dayTasks,
    required int searchFromMinutes,
    DateTime? day,
  }) {
    if (durationMinutes <= 0 ||
        durationMinutes > minutesPerDay ||
        searchFromMinutes > minutesPerDay - durationMinutes) {
      return null;
    }
    var cursor = searchFromMinutes;
    final active = _sortedActive(dayTasks)
        .map((t) {
          if (day == null) {
            return (
              start: t.startTime!.hour * 60 + t.startTime!.minute,
              end: t.endTime!.hour * 60 + t.endTime!.minute,
            );
          }
          final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(day);
          if (!t.endTime!.isAfter(dayStart) || !t.startTime!.isBefore(dayEnd)) {
            return null;
          }
          final start = t.startTime!.isBefore(dayStart)
              ? dayStart
              : t.startTime!;
          final end = t.endTime!.isAfter(dayEnd) ? dayEnd : t.endTime!;
          return (
            start: minutesSinceMidnight(start),
            end: end == dayEnd ? minutesPerDay : minutesSinceMidnight(end),
          );
        })
        .whereType<({int start, int end})>()
        .toList();
    var progressed = true;
    while (progressed) {
      progressed = false;
      for (final slot in active) {
        if (cursor < slot.end && cursor + durationMinutes > slot.start) {
          cursor = slot.end;
          progressed = true;
        }
      }
      if (cursor > minutesPerDay - durationMinutes) return null;
    }
    return cursor;
  }

  static ({DateTime start, DateTime end})? _spanOf(Task t) =>
      t.startTime != null && t.endTime != null
      ? (start: t.startTime!, end: t.endTime!)
      : null;

  static bool _intervalsOverlap(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) => aStart.isBefore(bEnd) && aEnd.isAfter(bStart);

  static List<Task> _sortedActive(List<Task> dayTasks) =>
      dayTasks
          .where(
            (t) =>
                t.startTime != null &&
                t.endTime != null &&
                t.status != TaskStatus.cancelled &&
                t.status != TaskStatus.rescheduled,
          )
          .toList()
        ..sort((a, b) => a.startTime!.compareTo(b.startTime!));
}
