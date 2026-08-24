import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import 'selected_date_provider.dart';

final dayTasksProvider = StreamProvider<List<Task>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchTasksForDay(date);
});
