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

class ConsistencyDay {
  const ConsistencyDay({
    required this.date,
    required this.plannedMinutes,
    required this.completedPlannedMinutes,
    required this.actualMinutes,
    this.context,
    required this.isFuture,
  });

  final DateTime date;
  final int plannedMinutes;
  final int completedPlannedMinutes;
  final int actualMinutes;
  final DayContextKind? context;
  final bool isFuture;

  bool get excludedByContext =>
      context == DayContextKind.holiday || context == DayContextKind.leave;

  bool get isNeutral => isFuture || excludedByContext || plannedMinutes <= 0;

  double? get followThrough {
    if (isNeutral) return null;
    return (completedPlannedMinutes / plannedMinutes).clamp(0.0, 1.0);
  }

  int? get followThroughPercent =>
      followThrough == null ? null : (followThrough! * 100).round();

  bool get isSuccessful => !isNeutral && followThrough! >= 0.75;

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

  double? get weeklyFollowThrough => plannedMinutes <= 0
      ? null
      : (completedPlannedMinutes / plannedMinutes).clamp(0.0, 1.0);

  int? get weeklyFollowThroughPercent =>
      weeklyFollowThrough == null ? null : (weeklyFollowThrough! * 100).round();

  bool get hasConsistencyHistory =>
      consistencyDays.any((day) => !day.isNeutral);
}
