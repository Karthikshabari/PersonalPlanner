import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/tag.dart';
import '../../task_editor/data/tag_repository.dart';
import '../../../core/providers/database_provider.dart';

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository(ref.watch(appDatabaseProvider));
});

/// All active tags (for the picker and settings management).
final tagsProvider = StreamProvider.autoDispose<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAllTags();
});

/// Tags currently attached to one task.
final tagsForTaskProvider =
    StreamProvider.autoDispose.family<List<Tag>, String>((ref, taskId) {
  return ref.watch(tagRepositoryProvider).watchTagsForTask(taskId);
});
