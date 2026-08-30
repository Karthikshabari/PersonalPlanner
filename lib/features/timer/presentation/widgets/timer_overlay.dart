import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/timer_providers.dart';
import '../timer_actions.dart';

/// Small floating widget in the bottom-right corner of the Day View,
/// visible whenever a timer is running (planner.md Chunk 6 #8, desktop).
class TimerOverlay extends ConsumerWidget {
  const TimerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final activeAsync = ref.watch(activeTimerProvider);
    if (activeAsync.hasError) {
      return SizedBox(
        width: 320,
        child: ErrorPanel(
          message: friendlyErrorMessage(activeAsync.error!),
          onRetry: () => ref.invalidate(activeTimerProvider),
          compact: true,
        ),
      );
    }
    if (!activeAsync.hasValue) {
      return const SizedBox(
        width: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final active = activeAsync.requireValue;
    if (active == null) return const SizedBox.shrink();

    final elapsedAsync = ref.watch(
      activeTimerElapsedProvider(active.session.taskId),
    );
    final elapsedSeconds = elapsedAsync.hasValue
        ? elapsedAsync.requireValue
        : 0;
    final elapsed = formatTimerClock(elapsedSeconds);

    return Card(
      key: const ValueKey('timer-overlay'),
      elevation: 6,
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        side: BorderSide(color: tokens.outlineStrong),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: elapsedSeconds.isEven ? 1.05 : 1,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              child: Icon(
                Icons.timer_outlined,
                size: 16,
                color: tokens.pending,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                active.taskTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (elapsedAsync.hasError)
              IconButton(
                tooltip: friendlyErrorMessage(elapsedAsync.error!),
                icon: const Icon(Icons.error_outline),
                color: tokens.error,
                onPressed: () => ref.invalidate(
                  activeTimerElapsedProvider(active.session.taskId),
                ),
              )
            else if (!elapsedAsync.hasValue)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                key: const ValueKey('overlay-timer-elapsed'),
                elapsed,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: tokens.pending,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              key: const ValueKey('overlay-pause-button'),
              tooltip: 'Pause',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.pause, size: 18),
              onPressed: () => _runTimerAction(
                context,
                () => TimerActions.pause(context, ref),
              ),
            ),
            IconButton(
              key: const ValueKey('overlay-stop-button'),
              tooltip: 'Stop',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.stop, size: 18),
              onPressed: () => _runTimerAction(
                context,
                () => TimerActions.stopWithPrompt(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _runTimerAction(
  BuildContext context,
  Future<Object?> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}
