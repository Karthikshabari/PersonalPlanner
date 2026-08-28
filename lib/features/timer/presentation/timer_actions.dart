import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../platform/android_foreground_timer.dart';
import '../providers/timer_providers.dart';

/// High-level timer actions shared by the editor controls and the desktop
/// overlay, including the "Mark as Completed?" prompt on stop
/// (planner.md Chunk 6 #11/#12).
abstract final class TimerActions {
  /// Starts (or resumes) the timer for [task]; auto-pauses any other
  /// running session first.
  static Future<void> start(
      BuildContext context, WidgetRef ref, Task task) async {
    final service = ref.read(timerServiceProvider);
    await service.start(task.id);
    final foregroundStarted =
        await AndroidForegroundTimer().start(taskTitle: task.title);
    if (AndroidForegroundTimer.supported && !foregroundStarted) {
      await service.pause();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Background timer support failed to start')),
        );
      }
    }
  }

  static Future<void> pause(BuildContext context, WidgetRef ref) async {
    await ref.read(timerServiceProvider).pause();
    await AndroidForegroundTimer().stop();
  }

  /// Stops the running session and asks whether the task should be marked
  /// completed. Returns true when a session was actually stopped.
  static Future<bool> stopWithPrompt(BuildContext context, WidgetRef ref) async {
    final active = ref.read(activeTimerProvider).value;
    if (active == null) return false;
    await ref.read(timerServiceProvider).stop();
    await AndroidForegroundTimer().stop();

    final repo = ref.read(taskRepositoryProvider);
    var task = await repo.getTaskById(active.session.taskId);
    if (task == null) return true;

    if (context.mounted && task.status != TaskStatus.completed) {
      final markCompleted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mark as Completed?'),
          content: Text('"${task.title}" was stopped.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              key: const ValueKey('mark-completed-yes'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (markCompleted == true) {
        final refreshed = await repo.getTaskById(task.id) ?? task;
        if (refreshed.status != TaskStatus.completed) {
          await repo.updateTask(
              refreshed.copyWith(status: TaskStatus.completed));
        }
      }
    }
    return true;
  }

  /// Accent color for timer chrome.
  static Color get accent => AppColors.inProgress;
}
