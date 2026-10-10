import '../../../core/models/daily_stats.dart';
import 'review_insights.dart';
import 'review_overview.dart';
import 'review_plan_change.dart';
import 'task_outcome.dart';
import 'weekly_review_numbers.dart';

/// Field-by-field equality of the values the review streams emit, so a
/// recalculation that produced the same result (a sync acknowledgement, a task
/// on another day) does not notify listeners and rebuild the screen.
///
/// Every comparison covers every field the model has. When a field is added to
/// one of these models, add it here too, or a change to it will not show.

/// [DailyStats.computedAt] is the instant of the calculation, not data.
bool sameDailyStats(DailyStats a, DailyStats b) =>
    a == b.copyWith(computedAt: a.computedAt);

bool sameReviewInsights(ReviewInsights a, ReviewInsights b) =>
    _sameList(a.changes, b.changes, _sameChange) &&
    _sameList(a.carryover, b.carryover, _sameCarryover);

bool sameTaskOutcomes(List<TaskOutcomeRow> a, List<TaskOutcomeRow> b) =>
    _sameList(a, b, _sameOutcomeRow);

bool sameWeeklyDays(List<WeeklyDayInput> a, List<WeeklyDayInput> b) =>
    _sameList(a, b, _sameWeeklyDay);

bool sameOverviewDays(List<ReviewOverviewDay> a, List<ReviewOverviewDay> b) =>
    _sameList(a, b, _sameOverviewDay);

bool _sameList<T>(List<T> a, List<T> b, bool Function(T, T) same) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!same(a[i], b[i])) return false;
  }
  return true;
}

bool _sameChange(ReviewChange a, ReviewChange b) =>
    a.taskTitle == b.taskTitle && a.detail == b.detail && a.kind == b.kind;

bool _sameCarryover(ReviewCarryover a, ReviewCarryover b) =>
    a.title == b.title && a.startTime == b.startTime;

bool _samePlanChange(ReviewPlanChange? a, ReviewPlanChange? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.kind == b.kind &&
      a.oldValue == b.oldValue &&
      a.newValue == b.newValue &&
      a.reason == b.reason;
}

bool _sameOutcomeRow(TaskOutcomeRow a, TaskOutcomeRow b) =>
    a.taskId == b.taskId &&
    a.title == b.title &&
    a.startTime == b.startTime &&
    a.plannedMinutes == b.plannedMinutes &&
    a.trackedMinutes == b.trackedMinutes &&
    a.outcome == b.outcome &&
    _samePlanChange(a.planChange, b.planChange);

bool _sameWeeklyTask(WeeklyTaskInput a, WeeklyTaskInput b) =>
    a.taskId == b.taskId &&
    a.title == b.title &&
    a.outcome == b.outcome &&
    a.reason == b.reason &&
    _samePlanChange(a.planChange, b.planChange);

bool _sameWeeklyDay(WeeklyDayInput a, WeeklyDayInput b) =>
    a.date == b.date &&
    a.reviewed == b.reviewed &&
    a.mood == b.mood &&
    a.contextLabel == b.contextLabel &&
    _sameList(a.tasks, b.tasks, _sameWeeklyTask);

// `DailyReview` and `DayContext` are Freezed value classes: `==` covers all
// their fields.
bool _sameOverviewDay(ReviewOverviewDay a, ReviewOverviewDay b) =>
    a.date == b.date &&
    a.totalTasks == b.totalTasks &&
    a.completedTasks == b.completedTasks &&
    a.review == b.review &&
    a.dayContext == b.dayContext;
