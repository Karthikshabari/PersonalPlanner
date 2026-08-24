import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';

/// Interval-overlap conflict detection per architecture.md Section 8:
/// two intervals [a1, a2) and [b1, b2) overlap iff a1 < b2 AND a2 > b1.
abstract final class ConflictDetector {
  /// Returns the day tasks that overlap [task], excluding itself and
  /// cancelled/rescheduled blocks, sorted by start time.
  static List<Task> detect(Task task, List<Task> dayTasks) {
    return dayTasks
        .where((other) => overlaps(task, other))
        .toList()
      ..sort((a, b) => a.startTime!.compareTo(b.startTime!));
  }

  /// True when [a] and [b] are distinct active scheduled blocks that overlap.
  static bool overlaps(Task a, Task b) {
    if (identical(a, b) || a.id == b.id) return false;
    if (_isInactive(a) || _isInactive(b)) return false;
    final aStart = a.startTime;
    final aEnd = a.endTime;
    final bStart = b.startTime;
    final bEnd = b.endTime;
    if (aStart == null || aEnd == null || bStart == null || bEnd == null) {
      return false;
    }
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  /// Ids of all active scheduled blocks involved in at least one overlap.
  /// Used for the visual overlap indicator on the timeline.
  static Set<String> overlappingIdSet(List<Task> dayTasks) {
    final ids = <String>{};
    for (var i = 0; i < dayTasks.length; i++) {
      for (var j = i + 1; j < dayTasks.length; j++) {
        if (overlaps(dayTasks[i], dayTasks[j])) {
          ids..add(dayTasks[i].id)..add(dayTasks[j].id);
        }
      }
    }
    return ids;
  }

  static bool _isInactive(Task t) =>
      t.status == TaskStatus.cancelled || t.status == TaskStatus.rescheduled;
}
