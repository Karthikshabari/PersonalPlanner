import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../domain/commands/create_task_command.dart';
import '../../domain/commands/delete_task_command.dart';
import '../../domain/conflict_resolver.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/undo_stack_provider.dart';

/// Shared high-level scheduling actions, invoked from the context menu,
/// keyboard shortcuts and dialogs.
abstract final class TimelineActions {
  /// Duplicates [task] into the next available slot after the original.
  /// All fields are copied except id / created_at / updated_at.
  static Future<void> duplicateTask(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    if (task.startTime == null || task.endTime == null) {
      showAppToast(context, 'Only scheduled tasks can be duplicated');
      return;
    }
    final history = ref.read(undoStackProvider.notifier);
    final tasks = ref.read(dayTasksProvider).value ?? const <Task>[];
    final durationMin = task.scheduledDuration!.inMinutes;
    final originalStartMin = minutesSinceMidnight(task.startTime!);

    final slot = ConflictResolver.findNextAvailableSlot(
      durationMinutes: durationMin,
      dayTasks: tasks,
      searchFromMinutes: originalStartMin + durationMin,
    );
    if (slot == null) {
      showAppToast(context, 'No room left on this day for the copy');
      return;
    }
    final day = ref.read(selectedDateProvider);
    final start = day.add(Duration(minutes: slot));
    final end = start.add(Duration(minutes: durationMin));
    final now = DateTime.now();
    final copy = task.copyWith(
      id: '',
      startTime: start,
      endTime: end,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    await history.execute(
      CreateTaskCommand(ref.read(taskRepositoryProvider), copy),
    );
    if (!context.mounted) return;
    showAppToast(context, 'Duplicated "${task.title}"');
  }

  /// Asks for confirmation, then soft-deletes via [DeleteTaskCommand].
  static Future<void> deleteWithConfirmation(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete task?',
      message: '"${task.title}" will be removed from the timeline.\n'
          'You can undo this with Ctrl+Z.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    final command = DeleteTaskCommand(
      repository: ref.read(taskRepositoryProvider),
      original: task,
    );
    await ref.read(undoStackProvider.notifier).execute(command);
  }

  /// Direct status update (not part of the reversible scheduling commands).
  static Future<void> setStatus(WidgetRef ref, Task task, TaskStatus status) {
    return ref
        .read(taskRepositoryProvider)
        .updateTask(task.copyWith(status: status));
  }
}

/// Grid fallback used when the setting has not finished loading yet; mirrors
/// [AppConstants.defaultGridMinutes].

