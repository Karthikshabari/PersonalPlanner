import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../../features/categories/data/category_repository.dart';
import '../../features/timeline/data/task_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
      'appDatabaseProvider must be overridden at bootstrap');
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(appDatabaseProvider));
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(appDatabaseProvider));
});
