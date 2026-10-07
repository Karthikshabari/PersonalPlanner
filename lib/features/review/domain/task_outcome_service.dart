import '../../../core/database/app_database.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../timeline/data/task_repository.dart';
import 'review_plan_change.dart';
import 'task_outcome.dart';

/// One row per task that starts on the review day (D1), never two rows for
/// the same task.
class TaskOutcomeService {
  TaskOutcomeService(this._db);

  final AppDatabase _db;

  Future<List<TaskOutcomeRow>> forDay(DateTime date) async {
    final day = startOfDay(date);
    final end = addDays(day, 1);
    final rows = await _db.taskDao.getTasksBetween(day, end);
    final result = <TaskOutcomeRow>[];
    for (final row in rows) {
      final task = TaskRepository.fromRow(row);
      final start = task.startTime;
      if (start == null || start.isBefore(day) || !start.isBefore(end)) {
        continue;
      }
      final tracked = clampTrackedMinutes(task.actualDurationMin);
      result.add(
        TaskOutcomeRow(
          taskId: task.id,
          title: task.title,
          startTime: start,
          plannedMinutes: task.plannedDurationMinutes ?? 0,
          trackedMinutes: tracked,
          outcome: resolveTaskOutcome(task.status, trackedMinutes: tracked),
          planChange: ReviewPlanChange.forTask(task),
        ),
      );
    }
    result.sort(compareTaskOutcomeRows);
    return result;
  }
}
