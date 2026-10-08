import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/day_context.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../day_context/data/day_context_repository.dart';
import '../../timeline/data/task_repository.dart';
import '../data/review_repository.dart';
import 'review_plan_change.dart';
import 'task_outcome.dart';
import 'weekly_review_numbers.dart';

/// Loads the seven days of one week with one range query per source: tasks,
/// daily reviews and day contexts. A task belongs to the day its start time
/// falls on (D1), exactly as in the Daily review.
class WeeklyReviewService {
  WeeklyReviewService(this._db);

  final AppDatabase _db;

  Future<List<WeeklyDayInput>> loadWeek(DateTime weekStart) async {
    final start = startOfWeek(weekStart);
    final end = addDays(start, 7);
    final startIso = isoDateString(start);
    final endIso = isoDateString(end);
    final taskRows = await _db.taskDao.getTasksBetween(start, end);
    final reviews = await ReviewRepository(_db)
        .getDailyReviewsBetween(start, end);
    final contextRows =
        await (_db.select(_db.dayContexts)..where(
              (row) =>
                  row.date.isBiggerOrEqualValue(startIso) &
                  row.date.isSmallerThanValue(endIso) &
                  row.deletedAt.isNull(),
            ))
            .get();
    final reviewByDate = {
      for (final review in reviews) isoDateString(review.date): review,
    };
    final contextByDate = {
      for (final row in contextRows)
        row.date: DayContextRepository.fromRow(row),
    };
    final tasksByDate = <String, List<Task>>{};
    for (final row in taskRows) {
      final task = TaskRepository.fromRow(row);
      final taskStart = task.startTime;
      if (taskStart == null ||
          taskStart.isBefore(start) ||
          !taskStart.isBefore(end)) {
        continue;
      }
      tasksByDate.putIfAbsent(isoDateString(taskStart), () => []).add(task);
    }
    return [
      for (var i = 0; i < 7; i++)
        () {
          final date = addDays(start, i);
          final key = isoDateString(date);
          final review = reviewByDate[key];
          final dayTasks = [...?tasksByDate[key]]..sort(_byStartThenId);
          return WeeklyDayInput(
            date: date,
            reviewed: review != null,
            mood: review?.mood,
            contextLabel: contextByDate[key]?.displayLabel,
            tasks: [
              for (final task in dayTasks)
                () {
                  final tracked = clampTrackedMinutes(task.actualDurationMin);
                  final reason = review?.taskReasons[task.id]?.trim();
                  return WeeklyTaskInput(
                    taskId: task.id,
                    title: task.title,
                    outcome: resolveTaskOutcome(
                      task.status,
                      trackedMinutes: tracked,
                    ),
                    reason: reason == null || reason.isEmpty ? null : reason,
                    planChange: ReviewPlanChange.forTask(task),
                  );
                }(),
            ],
          );
        }(),
    ];
  }

  static int _byStartThenId(Task a, Task b) {
    final byStart = a.startTime!.compareTo(b.startTime!);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  }
}
