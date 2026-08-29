import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../providers/timer_providers.dart';
import '../../platform/android_foreground_timer.dart';
import '../timer_actions.dart';

/// Start / Pause / Stop controls embedded in the task editor — used by the
/// desktop side panel and the mobile bottom sheet (planner.md Chunk 6 #9).
class TimerControls extends ConsumerWidget {
  final Task task;

  const TimerControls({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTimerProvider).value;
    final isHere = active?.session.taskId == task.id;
    final elapsed =
        formatTimerClock(ref.watch(activeTimerElapsedProvider(task.id)).value ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Timer', style: Theme.of(context).textTheme.titleSmall),
        if (!AndroidForegroundTimer.supported)
          Text(
            'Foreground timer notifications are unavailable on this platform.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: AppSpacing.sm),
        if (isHere) ...[
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 14, color: AppColors.inProgress),
              const SizedBox(width: AppSpacing.xs),
              Text(
                key: const ValueKey('editor-timer-elapsed'),
                elapsed,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inProgress,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('timer-pause-button'),
                  icon: const Icon(Icons.pause, size: 16),
                  label: const Text('Pause'),
                  onPressed: () => TimerActions.pause(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('timer-stop-button'),
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop'),
                  onPressed: () => TimerActions.stopWithPrompt(context, ref),
                ),
              ),
            ],
          ),
        ] else ...[
          if (active != null)
            Row(
              children: [
                Icon(Icons.timer_off_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Running on "${active.taskTitle}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          FilledButton.icon(
            key: const ValueKey('timer-start-button'),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: Text(active == null ? 'Start timer' : 'Switch timer'),
            onPressed: () => TimerActions.start(context, ref, task),
          ),
        ],
        if (task.actualDurationMin != null && !isHere)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Tracked so far: ${task.actualDurationMin} min',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
