import 'dart:math' as math;

/// Pure time calculations shared by persistence, editors, analytics and the
/// timeline.  A task's UTC interval is the only source of planned duration;
/// the stored estimate is only a compatibility projection of that interval.
abstract final class TaskTimeMetrics {
  /// Returns the exact elapsed duration for a valid scheduled interval.
  static Duration? scheduledDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null || !end.isAfter(start)) return null;
    return end.difference(start);
  }

  /// Returns the compatibility minute projection.  Positive sub-minute
  /// schedules remain visible as one minute, while seconds are never rounded
  /// away from the persisted start/end instants.
  static int? plannedMinutes(DateTime? start, DateTime? end) {
    final duration = scheduledDuration(start, end);
    if (duration == null) return null;
    return math.max(1, duration.inMinutes);
  }

  /// The cumulative planned portion covered by committed actual minutes.
  /// This is deliberately a projection from the beginning of the original
  /// interval, not a claim that work happened at those clock times.
  static DateTime? coveredEnd(
    DateTime? start,
    DateTime? end,
    int? actualMinutes,
  ) {
    final duration = scheduledDuration(start, end);
    if (duration == null || start == null || actualMinutes == null) return null;
    final plannedSeconds =
        duration.inMicroseconds ~/ Duration.microsecondsPerSecond;
    final actualSeconds = (actualMinutes.clamp(0, 1 << 31) * 60).toInt();
    return start.add(
      Duration(seconds: math.min(plannedSeconds, actualSeconds)),
    );
  }

  /// Intersects the cumulative coverage interval with a visible segment.
  /// The returned pair is (strongly covered, remaining planned) duration.
  static ({Duration strong, Duration light}) coverageForSegment({
    required DateTime taskStart,
    required DateTime taskEnd,
    required int actualMinutes,
    required DateTime segmentStart,
    required DateTime segmentEnd,
  }) {
    final planned = scheduledDuration(taskStart, taskEnd);
    if (planned == null || !segmentEnd.isAfter(segmentStart)) {
      return (strong: Duration.zero, light: Duration.zero);
    }
    final covered = taskStart.add(
      Duration(
        seconds: math.min(
          planned.inMicroseconds ~/ Duration.microsecondsPerSecond,
          (actualMinutes.clamp(0, 1 << 31) * 60).toInt(),
        ),
      ),
    );
    final visibleStart = segmentStart.isAfter(taskStart)
        ? segmentStart
        : taskStart;
    final visibleEnd = segmentEnd.isBefore(taskEnd) ? segmentEnd : taskEnd;
    if (!visibleEnd.isAfter(visibleStart)) {
      return (strong: Duration.zero, light: Duration.zero);
    }
    final strongEnd = covered.isBefore(visibleEnd) ? covered : visibleEnd;
    final strong = strongEnd.isAfter(visibleStart)
        ? strongEnd.difference(visibleStart)
        : Duration.zero;
    final lightStart = strongEnd.isAfter(visibleStart)
        ? strongEnd
        : visibleStart;
    final light = visibleEnd.isAfter(lightStart)
        ? visibleEnd.difference(lightStart)
        : Duration.zero;
    return (strong: strong, light: light);
  }
}
