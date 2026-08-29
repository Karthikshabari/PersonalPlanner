import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/subtask.dart';
import '../../task_editor/data/subtask_repository.dart';
import '../../../core/providers/database_provider.dart';

final subtaskRepositoryProvider = Provider<SubtaskRepository>((ref) {
  return SubtaskRepository(ref.watch(appDatabaseProvider));
});

/// Stream of a task's subtasks ordered by sort order.
final subtasksForTaskProvider = StreamProvider.autoDispose
    .family<List<Subtask>, String>((ref, taskId) {
      return ref.watch(subtaskRepositoryProvider).watchSubtasksForTask(taskId);
    });

/// One grouped query for timeline subtask badges.
final subtaskCountsProvider = StreamProvider.autoDispose<Map<String, String>>((
  ref,
) {
  return ref.watch(subtaskRepositoryProvider).watchSubtaskCounts();
});
