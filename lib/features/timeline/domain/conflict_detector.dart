import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';

/// Interval-overlap conflict detection per architecture.md Section 8:
/// two intervals [a1, a2) and [b1, b2) overlap iff a1 < b2 AND a2 > b1.
abstract final class ConflictDetector {
  /// Returns the day tasks that overlap [task], excluding itself and
  /// cancelled/rescheduled blocks, sorted by start time.
  static List<Task> detect(Task task, List<Task> dayTasks) {
    return dayTasks.where((other) => overlaps(task, other)).toList()
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
          ids
            ..add(dayTasks[i].id)
            ..add(dayTasks[j].id);
        }
      }
    }
    return ids;
  }

  /// Assigns deterministic lanes within each connected overlap component.
  /// Equal-start intervals cannot share a lane; unrelated components restart
  /// at lane zero.
  static Map<String, int> overlapLanes(List<Task> dayTasks) {
    final metadata = componentLaneMetadata(dayTasks, includeInactive: false);
    return {
      for (final entry in metadata.entries) entry.key: entry.value.laneIndex,
    };
  }

  /// Returns deterministic lane and connected-component metadata for visual
  /// timeline layout. Unlike scheduling conflicts, visual components can
  /// include cancelled/rescheduled history so those rows cannot conceal a
  /// live block. Set [includeInactive] to false for the old active-only
  /// conflict behavior.
  static Map<String, OverlapLaneMetadata> componentLaneMetadata(
    List<Task> dayTasks, {
    bool includeInactive = true,
  }) {
    final scheduled = dayTasks
        .where(
          (task) =>
              task.startTime != null &&
              task.endTime != null &&
              task.endTime!.isAfter(task.startTime!) &&
              (includeInactive || !_isInactive(task)),
        )
        .toList();
    final remaining = {for (final task in scheduled) task.id: task};
    final result = <String, OverlapLaneMetadata>{};
    while (remaining.isNotEmpty) {
      final seed = remaining.values.reduce(
        (a, b) => _compareStart(a, b) <= 0 ? a : b,
      );
      final component = <Task>[seed];
      remaining.remove(seed.id);
      for (var index = 0; index < component.length; index++) {
        final current = component[index];
        final connected = remaining.values
            .where(
              (task) =>
                  _intervalsOverlap(current, task) &&
                  (includeInactive ||
                      (!_isInactive(current) && !_isInactive(task))),
            )
            .toList();
        for (final task in connected) {
          remaining.remove(task.id);
          component.add(task);
        }
      }
      component.sort(_compareStart);
      final laneEnd = <DateTime>[];
      final componentIds = List<String>.unmodifiable(
        component.map((task) => task.id),
      );
      for (final task in component) {
        var lane = 0;
        while (lane < laneEnd.length &&
            task.startTime!.isBefore(laneEnd[lane])) {
          lane++;
        }
        if (lane == laneEnd.length) {
          laneEnd.add(task.endTime!);
        } else {
          laneEnd[lane] = task.endTime!;
        }
        result[task.id] = OverlapLaneMetadata(
          laneIndex: lane,
          laneCount: 0,
          hasOverlap: component.length > 1,
          componentTaskIds: componentIds,
        );
      }
      final laneCount = laneEnd.length;
      for (final task in component) {
        final current = result[task.id]!;
        result[task.id] = current.copyWith(laneCount: laneCount);
      }
    }
    return result;
  }

  /// Alias for callers that describe these assignments as visual lanes.
  static Map<String, OverlapLaneMetadata> visualLaneMetadata(
    List<Task> dayTasks,
  ) => componentLaneMetadata(dayTasks);

  static bool _intervalsOverlap(Task a, Task b) {
    final aStart = a.startTime;
    final aEnd = a.endTime;
    final bStart = b.startTime;
    final bEnd = b.endTime;
    if (aStart == null || aEnd == null || bStart == null || bEnd == null) {
      return false;
    }
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  static int _compareStart(Task a, Task b) {
    final byStart = a.startTime!.compareTo(b.startTime!);
    return byStart == 0 ? a.id.compareTo(b.id) : byStart;
  }

  static bool _isInactive(Task t) =>
      t.status == TaskStatus.cancelled || t.status == TaskStatus.rescheduled;
}

/// Stable visual-lane assignment for one task in an overlap component.
final class OverlapLaneMetadata {
  final int laneIndex;
  final int laneCount;
  final bool hasOverlap;
  final List<String> componentTaskIds;

  const OverlapLaneMetadata({
    required this.laneIndex,
    required this.laneCount,
    required this.hasOverlap,
    required this.componentTaskIds,
  });

  OverlapLaneMetadata copyWith({int? laneCount}) => OverlapLaneMetadata(
    laneIndex: laneIndex,
    laneCount: laneCount ?? this.laneCount,
    hasOverlap: hasOverlap,
    componentTaskIds: componentTaskIds,
  );
}
