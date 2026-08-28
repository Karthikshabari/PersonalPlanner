import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import 'selected_date_provider.dart';

final dayTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchTasksForDay(date);
});

/// Tasks for an explicit date, independent of [selectedDateProvider] — used
/// by surfaces that show other days (Week View columns, Daily Review
/// mini-timeline).
final dayTasksForDateProvider =
    StreamProvider.autoDispose.family<List<Task>, DateTime>((ref, date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return ref.watch(taskRepositoryProvider).watchTasksForDay(normalized);
});
