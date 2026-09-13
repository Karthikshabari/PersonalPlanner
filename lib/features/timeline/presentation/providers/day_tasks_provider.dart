import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/utils/date_utils.dart';
import 'selected_date_provider.dart';

final dayTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchTasksForDay(date);
});

/// The active calendar projection used by timeline surfaces. A rescheduled
/// predecessor remains in the repository as durable history, but its linked
/// successor is the only active block that should occupy the calendar.
bool isActiveTimelineTask(Task task) =>
    !(task.status == TaskStatus.rescheduled && task.rescheduledToId != null);

final activeDayTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final date = ref.watch(selectedDateProvider);
  return ref
      .watch(taskRepositoryProvider)
      .watchTasksForDay(date)
      .map(
        (tasks) => tasks.where(isActiveTimelineTask).toList(growable: false),
      );
});

/// Tasks for an explicit date, independent of [selectedDateProvider] — used
/// by surfaces that show other days (Week View columns, Daily Review
/// mini-timeline).
final dayTasksForDateProvider = StreamProvider.autoDispose
    .family<List<Task>, DateTime>((ref, date) {
      final normalized = startOfDay(date);
      return ref.watch(taskRepositoryProvider).watchTasksForDay(normalized);
    });

final activeDayTasksForDateProvider = StreamProvider.autoDispose
    .family<List<Task>, DateTime>((ref, date) {
      final normalized = startOfDay(date);
      return ref
          .watch(taskRepositoryProvider)
          .watchTasksForDay(normalized)
          .map(
            (tasks) =>
                tasks.where(isActiveTimelineTask).toList(growable: false),
          );
    });
