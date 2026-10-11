import '../../../core/models/category.dart';
import '../../../core/models/day_context.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';

/// One half-open calendar range. Insights uses this consistently for planned
/// overlap, timer allocation, week comparisons, and database reads.
class InsightDateRange {
  InsightDateRange(DateTime start, DateTime endExclusive)
    : start = startOfDay(start),
      endExclusive = startOfDay(endExclusive) {
    if (!this.start.isBefore(this.endExclusive)) {
      throw ArgumentError('Insight ranges must have a positive length.');
    }
  }

  final DateTime start;
  final DateTime endExclusive;

  int get dayCount {
    final first = PlannerTimeZone.toPlannerLocal(start);
    final last = PlannerTimeZone.toPlannerLocal(endExclusive);
    return DateTime.utc(
      last.year,
      last.month,
      last.day,
    ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
  }

  bool contains(DateTime date) {
    final day = startOfDay(date);
    return !day.isBefore(start) && day.isBefore(endExclusive);
  }
}

/// The rolling one-year window for the contribution calendar.
///
/// The range contains the latest 365 calendar dates, including [generatedFor].
/// Padding week columns may extend beyond this half-open range, but labels and
/// statistics never treat those padding dates as another displayed month.
InsightDateRange consistencyCalendarRange(
  DateTime generatedFor, {
  // Kept for call-site compatibility. Insights intentionally shows the full
  // year on both desktop and mobile; the mobile grid scrolls horizontally.
  bool compact = false,
}) {
  final today = startOfDay(generatedFor);
  return InsightDateRange(addDays(today, -364), addDays(today, 1));
}

enum ConsistencyIntensity { neutral, low, medium, high, strong }

/// The Settings "Follow-through target" choices, as fractions.
const List<double> followThroughTargetChoices = [0.5, 0.6, 0.7, 0.8];
const double defaultFollowThroughTarget = 0.6;

/// What one day counts as for the streak and the heatmap (INS-003).
enum DayResult {
  /// Time done is at or above the target.
  success,

  /// Below the target, but at least one planned block was completed.
  started,

  /// Planned time, nothing completed, and the day is over.
  missed,

  /// Nothing planned, or a Holiday / Leave day.
  empty,
}

/// The one rule that classifies a day. Returns null while the day is not
/// decided yet: a future day, or today before it is a Success (today only
/// becomes Started or Missed once it is over).
DayResult? classifyDay(ConsistencyDay day, {required double target}) {
  if (day.excludedByContext || day.plannedMinutes <= 0) return DayResult.empty;
  if (day.isFuture) return null;
  if (day.followThrough! >= target) return DayResult.success;
  if (day.isToday) return null;
  return day.completedPlannedMinutes > 0 ? DayResult.started : DayResult.missed;
}

class ConsistencyDay {
  const ConsistencyDay({
    required this.date,
    required this.plannedMinutes,
    required this.completedPlannedMinutes,
    required this.actualMinutes,
    this.context,
    required this.isFuture,
    this.isToday = false,
  });

  final DateTime date;
  /// Clock time: the union of the day's blocks, so an overlap counts once.
  final int plannedMinutes;

  /// Clock time of the completed blocks (same union rule), never more than
  /// [plannedMinutes].
  final int completedPlannedMinutes;
  final int actualMinutes;
  final DayContextKind? context;
  final bool isFuture;

  /// The day is today: not over yet, so it is only decided once a Success.
  final bool isToday;

  bool get excludedByContext =>
      context == DayContextKind.holiday || context == DayContextKind.leave;

  bool get isNeutral => isFuture || excludedByContext || plannedMinutes <= 0;

  double? get followThrough {
    if (isNeutral) return null;
    return (completedPlannedMinutes / plannedMinutes).clamp(0.0, 1.0);
  }

  int? get followThroughPercent =>
      followThrough == null ? null : (followThrough! * 100).round();

  ConsistencyIntensity get intensity {
    final value = followThrough;
    if (value == null) return ConsistencyIntensity.neutral;
    if (value < 0.25) return ConsistencyIntensity.low;
    if (value < 0.50) return ConsistencyIntensity.medium;
    if (value < 0.75) return ConsistencyIntensity.high;
    return ConsistencyIntensity.strong;
  }
}

class StreakSummary {
  const StreakSummary({required this.current, required this.best});

  final int current;
  final int best;
}

class CategoryTime {
  const CategoryTime({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.actualMinutes,
  });

  final String id;
  final String name;
  final String colorHex;
  final int actualMinutes;
}

enum NotableInsightKind { categoryChange, planningGap }

class NotableInsight {
  const NotableInsight({required this.kind, required this.message});

  final NotableInsightKind kind;
  final String message;
}

/// A canonical actual-time allocation already split onto a planner day.
/// [taskId] retains the category relationship without reinterpreting time.
class ActualTimeSlice {
  const ActualTimeSlice({
    required this.taskId,
    required this.date,
    required this.minutes,
  });

  final String taskId;
  final DateTime date;
  final int minutes;
}

/// Source rows loaded in bounded passes before entering the pure calculator.
class InsightsSourceData {
  const InsightsSourceData({
    required this.plannedTasks,
    required this.actualTasks,
    required this.actualSlices,
    required this.categories,
    required this.dayContexts,
  });

  final List<Task> plannedTasks;
  final List<Task> actualTasks;
  final List<ActualTimeSlice> actualSlices;
  final List<Category> categories;
  final List<DayContext> dayContexts;
}

class InsightsSnapshot {
  const InsightsSnapshot({
    required this.generatedFor,
    required this.consistencyStart,
    required this.consistencyDays,
    required this.streaks,
    required this.weekStart,
    required this.weekEndExclusive,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.completedPlannedMinutes,
    required this.categories,
    required this.notable,
    this.followThroughTarget = defaultFollowThroughTarget,
  });

  final DateTime generatedFor;
  final DateTime consistencyStart;
  final List<ConsistencyDay> consistencyDays;
  final StreakSummary streaks;
  final DateTime weekStart;
  final DateTime weekEndExclusive;
  final int plannedMinutes;
  final int actualMinutes;
  final int completedPlannedMinutes;
  final List<CategoryTime> categories;
  final List<NotableInsight> notable;

  /// The Settings target the streaks and heatmap results were computed with.
  final double followThroughTarget;

  double? get weeklyFollowThrough => plannedMinutes <= 0
      ? null
      : (completedPlannedMinutes / plannedMinutes).clamp(0.0, 1.0);

  int? get weeklyFollowThroughPercent =>
      weeklyFollowThrough == null ? null : (weeklyFollowThrough! * 100).round();

  bool get hasConsistencyHistory =>
      consistencyDays.any((day) => !day.isNeutral);
}

/// True when [a] and [b] show exactly the same thing, field by field. Used so a
/// recalculation that produced the same snapshot (a sync acknowledgement, a
/// task edit that changes no total) does not rebuild the Insights screen.
/// When a field is added to the snapshot or the types it holds, add it here.
bool sameInsightsSnapshot(InsightsSnapshot a, InsightsSnapshot b) {
  if (identical(a, b)) return true;
  // The screen only uses the planner day of `generatedFor`, not the instant.
  if (startOfDay(a.generatedFor) != startOfDay(b.generatedFor) ||
      a.consistencyStart != b.consistencyStart ||
      a.followThroughTarget != b.followThroughTarget ||
      a.streaks.current != b.streaks.current ||
      a.streaks.best != b.streaks.best ||
      a.weekStart != b.weekStart ||
      a.weekEndExclusive != b.weekEndExclusive ||
      a.plannedMinutes != b.plannedMinutes ||
      a.actualMinutes != b.actualMinutes ||
      a.completedPlannedMinutes != b.completedPlannedMinutes ||
      a.consistencyDays.length != b.consistencyDays.length ||
      a.categories.length != b.categories.length ||
      a.notable.length != b.notable.length) {
    return false;
  }
  for (var i = 0; i < a.consistencyDays.length; i++) {
    final x = a.consistencyDays[i];
    final y = b.consistencyDays[i];
    if (x.date != y.date ||
        x.plannedMinutes != y.plannedMinutes ||
        x.completedPlannedMinutes != y.completedPlannedMinutes ||
        x.actualMinutes != y.actualMinutes ||
        x.context != y.context ||
        x.isFuture != y.isFuture ||
        x.isToday != y.isToday) {
      return false;
    }
  }
  for (var i = 0; i < a.categories.length; i++) {
    final x = a.categories[i];
    final y = b.categories[i];
    if (x.id != y.id ||
        x.name != y.name ||
        x.colorHex != y.colorHex ||
        x.actualMinutes != y.actualMinutes) {
      return false;
    }
  }
  for (var i = 0; i < a.notable.length; i++) {
    if (a.notable[i].kind != b.notable[i].kind ||
        a.notable[i].message != b.notable[i].message) {
      return false;
    }
  }
  return true;
}
