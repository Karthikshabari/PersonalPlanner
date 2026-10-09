import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/weekly_review.dart';
import '../../../core/utils/date_utils.dart';
import '../data/review_repository.dart';
import 'task_outcome.dart';

/// One past week as the Weekly review needs it: the saved review (if any)
/// and the week's completion (tasks that start in the week, D1).
class WeeklyHistoryWeek {
  const WeeklyHistoryWeek({
    required this.weekStart,
    required this.totalTasks,
    required this.completedTasks,
    this.review,
  });

  final DateTime weekStart;
  final int totalTasks;
  final int completedTasks;
  final WeeklyReview? review;

  /// A saved weekly review record exists for the week.
  bool get reviewed => review != null;
  int? get mood => review?.mood;
  String? get feeling => review?.feeling;

  /// The week's note for the next week (`weekly_reviews.reflection`).
  String? get note => review?.reflection;
  int? get percent => completionPercent(completedTasks, totalTasks);
}

/// Reads past weeks with one range query per source (weekly reviews and
/// tasks). A one-off read: callers invalidate it after a weekly save (WD13).
class WeeklyReviewHistoryService {
  WeeklyReviewHistoryService(this._db);

  final AppDatabase _db;

  /// The [weekCount] weeks before the week of [weekStart], oldest first. The
  /// last entry is the week immediately before [weekStart].
  Future<List<WeeklyHistoryWeek>> load(
    DateTime weekStart, {
    int weekCount = 52,
  }) async {
    final current = startOfWeek(weekStart);
    final oldest = addDays(current, -7 * weekCount);
    final reviews = await ReviewRepository(_db)
        .getWeeklyReviewsBetween(oldest, current);
    final rows = await _db.taskDao.getTasksBetween(oldest, current);
    final totals = <String, int>{};
    final completed = <String, int>{};
    for (final row in rows) {
      final start = row.startTime;
      if (start == null || start.isBefore(oldest) || !start.isBefore(current)) {
        continue;
      }
      final key = isoDateString(startOfWeek(start));
      totals[key] = (totals[key] ?? 0) + 1;
      if (row.status == TaskStatus.completed.dbValue) {
        completed[key] = (completed[key] ?? 0) + 1;
      }
    }
    final byWeek = {
      for (final review in reviews) isoDateString(review.weekStartDate): review,
    };
    return [
      for (var i = 0; i < weekCount; i++)
        () {
          final week = addDays(oldest, 7 * i);
          final key = isoDateString(week);
          return WeeklyHistoryWeek(
            weekStart: week,
            totalTasks: totals[key] ?? 0,
            completedTasks: completed[key] ?? 0,
            review: byWeek[key],
          );
        }(),
    ];
  }

  /// The Overview window: [weekCount] weeks ending with the week of [today],
  /// newest first (index 0 is this week).
  Future<List<WeeklyHistoryWeek>> window({
    required DateTime today,
    required int weekCount,
  }) async {
    final next = addDays(startOfWeek(today), 7);
    final weeks = await load(next, weekCount: weekCount);
    return weeks.reversed.toList(growable: false);
  }
}
