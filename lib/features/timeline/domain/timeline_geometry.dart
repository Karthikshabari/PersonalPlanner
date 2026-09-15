import 'dart:math' as math;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/task.dart';
import '../../../../core/utils/planner_day_axis.dart';
import '../../../../core/utils/task_time_metrics.dart';
import 'conflict_detector.dart';

/// Geometry for one visible segment of an original scheduled Task.
///
/// The task's persisted start/end are never replaced with [clippedStart] or
/// [clippedEnd].  Those values are only the intersection with [date]'s
/// planner-local elapsed axis.
final class TimelineTaskGeometry {
  final Task task;
  final DateTime fullStart;
  final DateTime fullEnd;
  final DateTime clippedStart;
  final DateTime clippedEnd;
  final double topPx;
  final double heightPx;
  final int laneIndex;
  final int laneCount;
  final bool hasOverlap;
  final bool continuesBefore;
  final bool continuesAfter;
  final Duration actualCoveredDuration;
  final Duration plannedRemainingDuration;
  final Duration overtimeDuration;
  final List<String> componentTaskIds;

  const TimelineTaskGeometry({
    required this.task,
    required this.fullStart,
    required this.fullEnd,
    required this.clippedStart,
    required this.clippedEnd,
    required this.topPx,
    required this.heightPx,
    required this.laneIndex,
    required this.laneCount,
    required this.hasOverlap,
    required this.continuesBefore,
    required this.continuesAfter,
    required this.actualCoveredDuration,
    required this.plannedRemainingDuration,
    required this.overtimeDuration,
    required this.componentTaskIds,
  });

  Duration get visibleDuration => clippedEnd.difference(clippedStart);

  bool get isScheduledEndSegment => !continuesAfter;

  double get actualCoverageFraction {
    final duration = visibleDuration.inMicroseconds;
    if (duration <= 0) return 0;
    return (actualCoveredDuration.inMicroseconds / duration).clamp(0.0, 1.0);
  }

  double get plannedRemainderFraction {
    final duration = visibleDuration.inMicroseconds;
    if (duration <= 0) return 0;
    return (plannedRemainingDuration.inMicroseconds / duration).clamp(0.0, 1.0);
  }
}

/// Shared Day/Week interval clipping, lanes and actual coverage projection.
abstract final class TimelineGeometry {
  static List<TimelineTaskGeometry> layoutForDay({
    required Iterable<Task> tasks,
    required DateTime date,
    double pixelsPerMinute = AppConstants.pixelsPerMinute,
  }) {
    final axis = PlannerDayAxis(date);
    final visible = tasks.where((task) {
      final start = task.startTime;
      final end = task.endTime;
      return start != null &&
          end != null &&
          end.isAfter(start) &&
          start.isBefore(axis.end) &&
          end.isAfter(axis.start);
    }).toList();
    final lanes = ConflictDetector.componentLaneMetadata(
      visible,
      includeInactive: true,
    );
    visible.sort(_compareTasks);

    return List<TimelineTaskGeometry>.unmodifiable([
      for (final task in visible)
        _forTask(
          task,
          axis: axis,
          pixelsPerMinute: pixelsPerMinute,
          lane: lanes[task.id],
        ),
    ]);
  }

  /// Allocates temporary horizontal lanes only when rendering minimum heights
  /// would make otherwise adjacent cards overlap. The returned lanes affect
  /// painting only; scheduling geometry and conflict detection stay unchanged.
  static Map<String, ({int index, int count})> visualLanesForMinimumHeight({
    required Iterable<TimelineTaskGeometry> geometries,
    required double thresholdPx,
    required double minimumHeightPx,
  }) {
    final intervals =
        geometries.where((geometry) => geometry.laneCount == 1).map((geometry) {
          final needsMinimum = geometry.heightPx < thresholdPx;
          final renderedHeight = needsMinimum
              ? math.max(minimumHeightPx, geometry.heightPx)
              : geometry.heightPx;
          final extra = needsMinimum
              ? (renderedHeight - geometry.heightPx) / 2
              : 0.0;
          return _VisualInterval(
            taskId: geometry.task.id,
            start: geometry.topPx - extra,
            end: geometry.topPx + geometry.heightPx + extra,
          );
        }).toList()..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart == 0 ? a.end.compareTo(b.end) : byStart;
        });

    final lanes = <String, ({int index, int count})>{};
    var component = <_VisualInterval>[];
    var componentEnd = double.negativeInfinity;

    void allocateComponent(List<_VisualInterval> intervals) {
      if (intervals.length < 2) return;
      final active = <_ActiveVisualLane>[];
      final assigned = <String, int>{};
      var laneCount = 0;
      for (final interval in intervals) {
        active.removeWhere((entry) => entry.end <= interval.start);
        var lane = 0;
        while (active.any((entry) => entry.lane == lane)) {
          lane++;
        }
        active.add(_ActiveVisualLane(end: interval.end, lane: lane));
        assigned[interval.taskId] = lane;
        laneCount = math.max(laneCount, lane + 1);
      }
      for (final entry in assigned.entries) {
        lanes[entry.key] = (index: entry.value, count: laneCount);
      }
    }

    for (final interval in intervals) {
      if (component.isNotEmpty && interval.start >= componentEnd) {
        allocateComponent(component);
        component = <_VisualInterval>[];
        componentEnd = double.negativeInfinity;
      }
      component.add(interval);
      componentEnd = math.max(componentEnd, interval.end);
    }
    allocateComponent(component);
    return lanes;
  }

  static TimelineTaskGeometry _forTask(
    Task task, {
    required PlannerDayAxis axis,
    required double pixelsPerMinute,
    required OverlapLaneMetadata? lane,
  }) {
    final fullStart = task.startTime!;
    final fullEnd = task.endTime!;
    final clippedStart = fullStart.isBefore(axis.start)
        ? axis.start
        : fullStart;
    final clippedEnd = fullEnd.isAfter(axis.end) ? axis.end : fullEnd;
    final visibleMicros = clippedEnd.difference(clippedStart).inMicroseconds;
    final visibleMinutes = visibleMicros / Duration.microsecondsPerMinute;
    final coverage = TaskTimeMetrics.coverageForSegment(
      taskStart: fullStart,
      taskEnd: fullEnd,
      actualMinutes: math.max(0, task.actualDurationMin ?? 0),
      segmentStart: clippedStart,
      segmentEnd: clippedEnd,
    );
    final planned = TaskTimeMetrics.scheduledDuration(fullStart, fullEnd)!;
    final actualMinutes = math.max(0, task.actualDurationMin ?? 0);
    final overtime = Duration(
      seconds: math.max(
        0,
        actualMinutes * 60 -
            planned.inMicroseconds ~/ Duration.microsecondsPerSecond,
      ),
    );
    return TimelineTaskGeometry(
      task: task,
      fullStart: fullStart,
      fullEnd: fullEnd,
      clippedStart: clippedStart,
      clippedEnd: clippedEnd,
      topPx: axis.elapsedMinutes(clippedStart) * pixelsPerMinute,
      heightPx: visibleMinutes * pixelsPerMinute,
      laneIndex: lane?.laneIndex ?? 0,
      laneCount: lane?.laneCount ?? 1,
      hasOverlap: lane?.hasOverlap ?? false,
      continuesBefore: fullStart.isBefore(axis.start),
      continuesAfter: fullEnd.isAfter(axis.end),
      actualCoveredDuration: coverage.strong,
      plannedRemainingDuration: coverage.light,
      overtimeDuration: overtime,
      componentTaskIds: lane?.componentTaskIds ?? <String>[task.id],
    );
  }

  static int _compareTasks(Task a, Task b) {
    final byStart = a.startTime!.compareTo(b.startTime!);
    return byStart == 0 ? a.id.compareTo(b.id) : byStart;
  }
}

final class _VisualInterval {
  final String taskId;
  final double start;
  final double end;

  const _VisualInterval({
    required this.taskId,
    required this.start,
    required this.end,
  });
}

final class _ActiveVisualLane {
  final double end;
  final int lane;

  const _ActiveVisualLane({required this.end, required this.lane});
}
