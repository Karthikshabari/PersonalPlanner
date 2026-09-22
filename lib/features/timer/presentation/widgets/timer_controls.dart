import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/models/timer_session.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/timer_providers.dart';
import '../timer_actions.dart';

/// Start / Pause / Stop controls embedded in the task editor — used by the
/// desktop side panel and the mobile bottom sheet (planner.md Chunk 6 #9).
class TimerControls extends ConsumerWidget {
  final Task task;

  const TimerControls({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final unfinishedAsync = ref.watch(unfinishedTimerForTaskProvider(task.id));
    final recoverableAsync = ref.watch(
      recoverableTimerForTaskProvider(task.id),
    );
    final foreignAsync = ref.watch(foreignTimerForTaskProvider(task.id));
    if (unfinishedAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(unfinishedAsync.error!),
        onRetry: () => ref.invalidate(unfinishedTimerForTaskProvider(task.id)),
        compact: true,
      );
    }
    if (!unfinishedAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final session = unfinishedAsync.requireValue;
    final recoverable = recoverableAsync.value;
    final foreign = foreignAsync.value;
    final busyScope = session?.id ?? task.id;
    final busy = ref.watch(timerActionBusyProvider(busyScope));
    final activeAsync = ref.watch(activeTimerProvider);
    final active = activeAsync.value;
    final isHere = session != null;
    final elapsedAsync = session != null
        ? ref.watch(timerSessionElapsedProvider(session))
        : const AsyncValue<int>.data(0);

    final displayedElapsed = elapsedAsync.value ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Timer', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (isHere) ...[
          if (elapsedAsync.hasError)
            ErrorPanel(
              message: friendlyErrorMessage(elapsedAsync.error!),
              onRetry: () =>
                  ref.invalidate(activeTimerElapsedProvider(task.id)),
              compact: true,
            )
          else if (!elapsedAsync.hasValue)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: tokens.pending),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  key: const ValueKey('editor-timer-elapsed'),
                  formatTimerClock(displayedElapsed),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.pending,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          _buildTimerActions(context, ref, session, busy),
        ] else if (recoverable != null) ...[
          Text(
            'This imported timer is paused until you recover it on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('timer-recover-button'),
            icon: const Icon(Icons.settings_backup_restore_outlined, size: 16),
            label: const Text('Recover timer'),
            onPressed: busy
                ? null
                : () => _runTimerAction(
                    context,
                    ref,
                    busyScope,
                    () => TimerActions.recover(
                      context,
                      ref,
                      task,
                      recoverable.id,
                    ),
                  ),
          ),
        ] else if (foreign != null) ...[
          Text(
            foreign.state == TimerSessionState.running
                ? 'Timer running on another device.'
                : 'Timer paused on another device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else ...[
          if (active != null)
            Row(
              children: [
                Icon(
                  Icons.timer_off_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
            onPressed: busy
                ? null
                : () => _runTimerAction(
                    context,
                    ref,
                    busyScope,
                    () => TimerActions.start(context, ref, task),
                  ),
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

Widget _buildTimerActions(
  BuildContext context,
  WidgetRef ref,
  TimerSession session,
  bool busy,
) => LayoutBuilder(
  builder: (context, constraints) {
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    double buttonWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      // Material's themed icon button gap and horizontal padding, plus a
      // small safety allowance for localized/icon-font metrics.
      return painter.width + 16 + 8 + 36 + 12;
    }

    final requiredWidth =
        buttonWidth('Pause') + buttonWidth('Stop') + AppSpacing.sm;
    final stack =
        !constraints.hasBoundedWidth || constraints.maxWidth < requiredWidth;
    final paused = session.state == TimerSessionState.paused;
    final pause = OutlinedButton.icon(
      key: ValueKey(paused ? 'timer-resume-button' : 'timer-pause-button'),
      icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 16),
      label: Text(paused ? 'Resume' : 'Pause'),
      onPressed: busy
          ? null
          : () => _runTimerAction(
              context,
              ref,
              session.id,
              () => paused
                  ? TimerActions.resume(context, ref, session.id)
                  : TimerActions.pause(context, ref, session.id),
            ),
    );
    final stop = FilledButton.tonalIcon(
      key: const ValueKey('timer-stop-button'),
      icon: const Icon(Icons.stop, size: 16),
      label: const Text('Stop'),
      onPressed: busy
          ? null
          : () => _runTimerAction(
              context,
              ref,
              session.id,
              () => TimerActions.stopWithPrompt(context, ref, session.id),
            ),
    );
    if (stack) {
      return Column(
        key: const ValueKey('timer-actions-stacked'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pause,
          const SizedBox(height: AppSpacing.sm),
          stop,
        ],
      );
    }
    return Row(
      key: const ValueKey('timer-actions-row'),
      children: [
        Expanded(child: pause),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: stop),
      ],
    );
  },
);

Future<void> _runTimerAction(
  BuildContext context,
  WidgetRef ref,
  String actionScope,
  Future<Object?> Function() action,
) async {
  final busy = ref.read(timerActionBusyProvider(actionScope).notifier);
  if (busy.isBusy) return;
  busy.setBusy(true);
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  } finally {
    busy.setBusy(false);
  }
}
