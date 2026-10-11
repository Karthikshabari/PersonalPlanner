import 'date_utils.dart';

/// One scheduled block as a half-open instant interval `[start, end)`.
typedef PlannedSpan = ({DateTime start, DateTime end});

/// Clock-time rules for planned blocks, shared by Review, Insights and Week.
///
/// Planned time is clock time: the length of the union of the blocks after
/// clipping each one to the range, so an overlap is counted once (REV-001).
/// A block that crosses midnight is one task, counted on the day it starts,
/// while its minutes stay split across the days it touches (DAY-006).
abstract final class PlannedClockTime {
  /// Whole minutes covered by the union of [spans] clipped to
  /// `[rangeStart, rangeEnd)`.
  static int unionMinutes(
    Iterable<PlannedSpan> spans,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final clipped = _clip(spans, rangeStart, rangeEnd)
      ..sort((a, b) => a.start.compareTo(b.start));
    var total = Duration.zero;
    DateTime? runStart;
    DateTime? runEnd;
    for (final span in clipped) {
      if (runEnd != null && !span.start.isAfter(runEnd)) {
        if (span.end.isAfter(runEnd)) runEnd = span.end;
        continue;
      }
      if (runStart != null) total += runEnd!.difference(runStart);
      runStart = span.start;
      runEnd = span.end;
    }
    if (runStart != null) total += runEnd!.difference(runStart);
    return total.inMinutes;
  }

  /// Whole minutes of [spans] clipped to `[rangeStart, rangeEnd)`, added up
  /// block by block (an overlap counts once per block).
  static int clippedSumMinutes(
    Iterable<PlannedSpan> spans,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) => _clip(spans, rangeStart, rangeEnd)
      .fold(Duration.zero, (sum, span) => sum + span.end.difference(span.start))
      .inMinutes;

  /// Minutes counted more than once by [clippedSumMinutes]: the overlap that
  /// [unionMinutes] removes.
  static int overlapMinutes(
    Iterable<PlannedSpan> spans,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) =>
      clippedSumMinutes(spans, rangeStart, rangeEnd) -
      unionMinutes(spans, rangeStart, rangeEnd);

  /// Clock minutes of the planner day [day] that belong to blocks which
  /// started on an earlier day ("+30m from yesterday").
  static int spillInMinutes(Iterable<PlannedSpan> spans, DateTime day) {
    final dayStart = startOfDay(day);
    return unionMinutes(
      spans.where((span) => span.start.isBefore(dayStart)),
      dayStart,
      addDays(dayStart, 1),
    );
  }

  /// A block belongs to the planner day its start falls on. Task counts use
  /// this everywhere, so a block crossing midnight is counted once.
  static bool startsOnDay(DateTime? start, DateTime day) {
    if (start == null) return false;
    final dayStart = startOfDay(day);
    return !start.isBefore(dayStart) && start.isBefore(addDays(dayStart, 1));
  }

  static List<PlannedSpan> _clip(
    Iterable<PlannedSpan> spans,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) => [
    for (final span in spans)
      if (span.end.isAfter(span.start) &&
          span.end.isAfter(rangeStart) &&
          span.start.isBefore(rangeEnd))
        (
          start: span.start.isAfter(rangeStart) ? span.start : rangeStart,
          end: span.end.isBefore(rangeEnd) ? span.end : rangeEnd,
        ),
  ];
}
