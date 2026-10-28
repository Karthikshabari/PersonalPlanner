import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';

final selectedTaskIdProvider = StateProvider<String?>((ref) => null);

/// True while the on-demand desktop editor is open. Selection and editing are
/// deliberately separate so the Day timeline can stay full-width by default.
final taskEditorOpenProvider = StateProvider<bool>((ref) => false);

/// How the router asks the open task editor whether Day may be left. The open
/// panel sets [confirmLeave] while it is mounted; it answers true at once when
/// it holds no unsaved edits and otherwise puts up the discard prompt. A plain
/// holder rather than state: nothing watches it.
class TaskEditorLeaveGuard {
  Future<bool> Function()? confirmLeave;
}

final taskEditorLeaveGuardProvider = Provider<TaskEditorLeaveGuard>(
  (ref) => TaskEditorLeaveGuard(),
);

/// Live row for an open editor. A one-shot read would go stale as soon as the
/// task left the viewed day's stream (another day viewed, or deleted).
final selectedTaskByIdProvider = StreamProvider.autoDispose
    .family<Task?, String>((ref, taskId) {
      return ref.watch(taskRepositoryProvider).watchTaskById(taskId);
    });
