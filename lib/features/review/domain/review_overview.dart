import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/daily_review.dart';
import '../../../core/models/day_context.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/date_utils.dart';
import '../../day_context/data/day_context_repository.dart';
import '../data/review_repository.dart';
import 'review_mood.dart';
import 'task_outcome.dart';

class ReviewOverviewDay {
  final DateTime date;
  final int totalTasks;
  final int completedTasks;
  final DailyReview? review;
  final DayContext? dayContext;

  const ReviewOverviewDay({
    required this.date,
    required this.totalTasks,
    required this.completedTasks,
    this.review,
    this.dayContext,
  });

  bool get reviewed => review != null;
  int? get mood => review?.mood;
  int? get percent => completionPercent(completedTasks, totalTasks);
}

/// Loads a window of days ending today with one range query per source:
/// tasks, reviews and day contexts. Never returns future days.
class ReviewOverviewService {
  ReviewOverviewService(this._db);

  final AppDatabase _db;

  /// Newest first: index 0 is [today].
  Future<List<ReviewOverviewDay>> window({
    required DateTime today,
    required int dayCount,
  }) async {
    final newest = startOfDay(today);
    final oldest = addDays(newest, -(dayCount - 1));
    final end = addDays(newest, 1);
    final startIso = isoDateString(oldest);
    final endIso = isoDateString(end);
    final tasks = await _db.taskDao.getTasksBetween(oldest, end);
    final reviewRows = await _db.reviewDao.getDailyReviewsBetween(startIso, endIso);
    final contextRows = await (_db.select(_db.dayContexts)
          ..where(
            (row) =>
                row.date.isBiggerOrEqualValue(startIso) &
                row.date.isSmallerThanValue(endIso) &
                row.deletedAt.isNull(),
          ))
        .get();
    final totals = <String, int>{};
    final completed = <String, int>{};
    for (final row in tasks) {
      final start = row.startTime;
      if (start == null || start.isBefore(oldest) || !start.isBefore(end)) {
        continue;
      }
      final key = isoDateString(start);
      totals[key] = (totals[key] ?? 0) + 1;
      if (row.status == TaskStatus.completed.dbValue) {
        completed[key] = (completed[key] ?? 0) + 1;
      }
    }
    final reviews = {
      for (final row in reviewRows) row.date: ReviewRepository.fromRow(row),
    };
    final contexts = {
      for (final row in contextRows) row.date: DayContextRepository.fromRow(row),
    };
    return [
      for (var i = 0; i < dayCount; i++)
        () {
          final date = addDays(newest, -i);
          final key = isoDateString(date);
          return ReviewOverviewDay(
            date: date,
            totalTasks: totals[key] ?? 0,
            completedTasks: completed[key] ?? 0,
            review: reviews[key],
            dayContext: contexts[key],
          );
        }(),
    ];
  }
}

/// `{Wd} {Mon d} · {context} · {Mood | no mood saved} · {pct}% done (c / t)`.
/// The context part is omitted when absent; `No tasks` replaces the last
/// part when the day had no tasks (D21).
String overviewDetailLine(ReviewOverviewDay day) {
  final parts = <String>[
    '${DateFormat('EEE').format(day.date)} ${DateFormat('MMM d').format(day.date)}',
    if (day.dayContext != null) day.dayContext!.displayLabel,
    day.mood == null ? 'no mood saved' : reviewMoodLabel(day.mood!),
    day.percent == null
        ? 'No tasks'
        : '${day.percent}% done (${day.completedTasks} / ${day.totalTasks})',
  ];
  return parts.join(' · ');
}
