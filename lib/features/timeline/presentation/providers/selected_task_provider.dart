import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';

final selectedTaskIdProvider = StateProvider<String?>((ref) => null);

final selectedTaskByIdProvider =
    FutureProvider.autoDispose.family<Task?, String>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).getTaskById(taskId);
});
