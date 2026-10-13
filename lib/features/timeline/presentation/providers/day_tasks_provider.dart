import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/plan_counting.dart';
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
/// predecessor remains in the repository as durable history, but while its
/// successor exists that successor is the only active block that should
/// occupy the calendar (`TaskRepository.watchActiveTasksForDay`, which applies
/// the same rule to rows; [liveSuccessors] comes from
/// `TaskDao.liveSuccessorIds`).
bool isActiveTimelineTask(Task task, Set<String> liveSuccessors) =>
    countsAsPlannedTask(
      task.status,
      task.rescheduledToId,
      successorLive: liveSuccessors.contains(task.rescheduledToId),
    );

final activeDayTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final date = ref.watch(selectedDateProvider);
  return ref.watch(taskRepositoryProvider).watchActiveTasksForDay(date);
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
          .watchActiveTasksForDay(normalized);
    });
