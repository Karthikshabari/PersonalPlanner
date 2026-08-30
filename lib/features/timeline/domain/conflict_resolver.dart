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

  /// **Shift Only Overlapping**: for each conflicting task, computes its
  /// individual overlap with whatever pushed onto it and shifts it forward,
  /// then re-checks for newly created conflicts (cascade). After
  /// [maxCascadeDepth] rounds, remaining conflicts fall back to keep-overlap
  /// (their ids are returned in [ResolutionPlan.keepOverlapIds]).
  static ResolutionPlan planShiftOnlyOverlapping({
    required Task moved,
    required List<Task> dayTasks,
    int maxCascadeDepth = 10,
  }) {
    final initialConflicts = ConflictDetector.detect(moved, dayTasks);
    if (initialConflicts.isEmpty || _spanOf(moved) == null) {
      return const ResolutionPlan();
    }

    // Simulated positions of every active scheduled block, keyed by id.
    final starts = <String, DateTime>{};
    final ends = <String, DateTime>{};
    final originals = <String, Task>{};
    final cumulativeDelta = <String, Duration>{};
    for (final t in _sortedActive(dayTasks)) {
      starts[t.id] = t.startTime!;
      ends[t.id] = t.endTime!;
      originals[t.id] = t;
      cumulativeDelta[t.id] = Duration.zero;
    }
    final movedId = moved.id;
    starts[movedId] = moved.startTime!;
    ends[movedId] = moved.endTime!;
    originals[movedId] = moved;

    // Worklist of (pusherId, victimId) conflicts to resolve.
    var worklist = [
      for (final c in initialConflicts) (pusher: movedId, victim: c.id),
    ];
    final shiftedOnce = <String>{};
    final keepIds = <String>{};
    final shifts = <String, PlannedShift>{};
    var depth = 0;

    while (worklist.isNotEmpty) {
      if (depth >= maxCascadeDepth) {
        // Fall back to keep overlap for everything still unresolved.
        for (final pair in worklist) {
          keepIds.add(pair.victim);
        }
        keepIds.add(movedId);
        break;
      }
      depth++;
      final nextWork = <({String pusher, String victim})>[];
      // Resolve earliest victims first so pushes cascade forward naturally.
      final ordered = [...worklist]
        ..sort((a, b) => starts[a.victim]!.compareTo(starts[b.victim]!));
      for (final pair in ordered) {
        final victimId = pair.victim;
        if (shiftedOnce.contains(victimId)) {
          // Would need a second shift of the same block — keep overlap
          // instead of looping.
          keepIds.add(victimId);
          continue;
        }
        final victimStart = starts[victimId]!;
        final pusherEnd = ends[pair.pusher]!;
        final delta = pusherEnd.difference(victimStart);
        if (delta <= Duration.zero) continue;
        shiftedOnce.add(victimId);

        final original = originals[victimId]!;
        final totalDelta = cumulativeDelta[victimId]! + delta;
        cumulativeDelta[victimId] = totalDelta;
        final newStart = original.startTime!.add(totalDelta);
        final newEnd = original.endTime!.add(totalDelta);
        starts[victimId] = newStart;
        ends[victimId] = newEnd;
        shifts[victimId] = PlannedShift(
          taskId: victimId,
          oldStart: original.startTime!,
          oldEnd: original.endTime!,
          newStart: newStart,
          newEnd: newEnd,
        );

        // Re-check: does the shifted block now collide with anything else?
        for (final entry in starts.entries) {
          final otherId = entry.key;
          if (otherId == victimId || otherId == pair.pusher) continue;
          if (_intervalsOverlap(
            newStart,
            newEnd,
            starts[otherId]!,
            ends[otherId]!,
          )) {
            nextWork.add((pusher: victimId, victim: otherId));
          }
        }
      }
      worklist = nextWork;
    }

    return ResolutionPlan(
      shifts: shifts.values.toList(),
      keepOverlapIds: keepIds,
    );
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
