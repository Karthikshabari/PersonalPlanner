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
