import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../providers/timer_providers.dart';
import '../timer_actions.dart';

/// Small floating widget in the bottom-right corner of the Day View,
/// visible whenever a timer is running (planner.md Chunk 6 #8, desktop).
class TimerOverlay extends ConsumerWidget {
  const TimerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTimerProvider).value;
    if (active == null) return const SizedBox.shrink();

    final elapsed = formatTimerClock(
        ref.watch(activeTimerElapsedProvider(active.session.taskId)).value ??
            0);

    return Card(
      key: const ValueKey('timer-overlay'),
      elevation: 6,
      color: AppColors.surfaceVariantDark,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: AppColors.inProgress),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                active.taskTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              key: const ValueKey('overlay-timer-elapsed'),
              elapsed,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.inProgress,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              key: const ValueKey('overlay-pause-button'),
              tooltip: 'Pause',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.pause, size: 18),
              onPressed: () => TimerActions.pause(context, ref),
            ),
            IconButton(
              key: const ValueKey('overlay-stop-button'),
              tooltip: 'Stop',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.stop, size: 18),
              onPressed: () => TimerActions.stopWithPrompt(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
