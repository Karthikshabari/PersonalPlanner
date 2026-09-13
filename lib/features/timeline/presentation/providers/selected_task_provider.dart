import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';

final selectedTaskIdProvider = StateProvider<String?>((ref) => null);

/// True while the on-demand desktop editor is open. Selection and editing are
/// deliberately separate so the Day timeline can stay full-width by default.
final taskEditorOpenProvider = StateProvider<bool>((ref) => false);

final selectedTaskByIdProvider = FutureProvider.autoDispose
    .family<Task?, String>((ref, taskId) {
      return ref.watch(taskRepositoryProvider).getTaskById(taskId);
    });
