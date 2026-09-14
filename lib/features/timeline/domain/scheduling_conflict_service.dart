import '../../../../core/models/task.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../data/task_repository.dart';
import 'conflict_detector.dart';
import 'conflict_resolver.dart';

/// Shared scheduling conflict boundary used by every way a task can acquire
/// or change a scheduled interval.
///
/// The UI still owns the choice dialog, while this class owns the invariant
/// that candidates cover the complete affected calendar interval and that the
/// same resolution planner is used for every entry point.
abstract final class SchedulingConflictService {
  /// Loads fresh scheduled rows intersecting the whole calendar day(s)
  /// touched by [proposed]. The half-open interval rules remain owned by the
  /// task DAO and [ConflictDetector].
  static Future<List<Task>> loadCandidates(
    TaskRepository repository,
    Task proposed, {
    DateTime? anchorDate,
  }) async {
    final start = proposed.startTime;
    final end = proposed.endTime;
    if (start == null || end == null || !end.isAfter(start)) {
      return const <Task>[];
    }
    final anchor = anchorDate ?? start;
    final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(anchor);
    final queryStart = start.isBefore(dayStart) ? start : dayStart;
    final queryEnd = end.isAfter(dayEnd) ? end : dayEnd;
    return repository.getScheduledTasksBetween(queryStart, queryEnd);
  }

  static List<Task> conflicts(Task proposed, List<Task> candidates) =>
      ConflictDetector.detect(proposed, candidates);

  static ResolutionPlan plan({
    required Task proposed,
    required List<Task> candidates,
    required ConflictResolution resolution,
    int maxCascadeDepth = 10,
  }) {
    switch (resolution) {
      case ConflictResolution.shiftAllFollowing:
        return ConflictResolver.planShiftAllFollowing(
          moved: proposed,
          dayTasks: candidates,
        );
      case ConflictResolution.shiftOnlyOverlapping:
        return ConflictResolver.planShiftOnlyOverlapping(
          moved: proposed,
          dayTasks: candidates,
          maxCascadeDepth: maxCascadeDepth,
        );
      case ConflictResolution.keepOverlap:
        return const ResolutionPlan();
    }
  }
}
