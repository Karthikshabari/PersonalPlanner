import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/models/timer_session.dart';
import '../../platform/android_foreground_timer.dart';
import '../../providers/timer_providers.dart';
import '../timer_actions.dart';

/// Small floating widget in the bottom-right corner of the Day View,
/// visible whenever a timer is running (planner.md Chunk 6 #8, desktop).
class TimerOverlay extends ConsumerWidget {
  /// Maximum width supplied by the parent timeline viewport. Loading and
  /// error states use the same bound so state changes cannot resize over an
  /// editor or produce a new narrow-layout overflow.
  final double? maxWidth;

  const TimerOverlay({super.key, this.maxWidth});

  double _widthFor(BoxConstraints constraints) {
    final available = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : 360.0;
    final requested = maxWidth ?? available;
    return math.max(1, math.min(requested, available));
  }

  Widget _bounded(BuildContext context, Widget child) => LayoutBuilder(
    builder: (context, constraints) =>
        SizedBox(width: _widthFor(constraints), child: child),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final activeAsync = ref.watch(activeTimerProvider);
    final pausedAsync = ref.watch(latestPausedTimerProvider);
    if (activeAsync.hasError) {
      return _bounded(
        context,
        ErrorPanel(
          message: friendlyErrorMessage(activeAsync.error!),
          onRetry: () => ref.invalidate(activeTimerProvider),
          compact: true,
        ),
      );
    }
    if (!activeAsync.hasValue) {
      return _bounded(
        context,
        const Center(child: CircularProgressIndicator()),
      );
    }
    final active = activeAsync.requireValue;
    final displayed = active ?? pausedAsync.value;
    if (displayed == null) return const SizedBox.shrink();

    final elapsedAsync = ref.watch(
      timerSessionElapsedProvider(displayed.session),
    );
    final elapsedSeconds = elapsedAsync.hasValue
        ? elapsedAsync.requireValue
        : 0;
    return ValueListenableBuilder<PendingForegroundTimerAction?>(
      valueListenable: AndroidForegroundTimer.pendingAction,
      builder: (context, pending, _) {
        final pendingForSession =
            displayed.session.state == TimerSessionState.running &&
            pending?.sessionId == displayed.session.id;
        final displayedSeconds = pendingForSession
            ? elapsedSecondsForSession(displayed.session, pending!.occurredAt)
            : elapsedSeconds;
        final elapsed = formatTimerClock(displayedSeconds);
        return _bounded(
          context,
          Card(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScaler = MediaQuery.textScalerOf(context);
                  final titlePainter = TextPainter(
                    text: TextSpan(
                      text: displayed.taskTitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    textDirection: TextDirection.ltr,
                    textScaler: textScaler,
                  )..layout();
                  final oneRowWidth =
                      16 +
                      AppSpacing.sm +
                      math.min(titlePainter.width, 180) +
                      AppSpacing.sm +
                      76 +
                      AppSpacing.sm +
                      96;
                  final wrap = constraints.maxWidth < oneRowWidth;
                  final title = Flexible(
                    child: Text(
                      displayed.taskTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  );
                  final clock = _clock(
                    context,
                    ref,
                    elapsedAsync,
                    elapsed,
                    elapsedSeconds,
                  );
                  final actions = _actions(context, ref, displayed.session);
                  final titleRow = Row(
                    children: [
                      AnimatedScale(
                        scale: displayedSeconds.isEven ? 1.05 : 1,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: tokens.pending,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      title,
                    ],
                  );
                  if (wrap) {
                    return Column(
                      key: const ValueKey('timer-overlay-wrapped'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        titleRow,
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [clock, actions],
                        ),
                      ],
                    );
                  }
                  return Row(
                    key: const ValueKey('timer-overlay-row'),
                    children: [
                      Expanded(child: titleRow),
                      const SizedBox(width: AppSpacing.sm),
                      clock,
                      actions,
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _clock(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<int> elapsedAsync,
    String elapsed,
    int elapsedSeconds,
  ) {
    final tokens = AppThemeTokens.of(context);
    if (elapsedAsync.hasError) {
      return IconButton(
        tooltip: friendlyErrorMessage(elapsedAsync.error!),
        icon: const Icon(Icons.error_outline),
        color: tokens.error,
        onPressed: () => ref.invalidate(timerSessionElapsedProvider),
      );
    }
    if (!elapsedAsync.hasValue) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Text(
      key: const ValueKey('overlay-timer-elapsed'),
      elapsed,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: tokens.pending,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, TimerSession session) {
    final busy = ref.watch(timerActionBusyProvider(session.id));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey(
            session.state == TimerSessionState.paused
                ? 'overlay-resume-button'
                : 'overlay-pause-button',
          ),
          tooltip: session.state == TimerSessionState.paused
              ? 'Resume'
              : 'Pause',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            session.state == TimerSessionState.paused
                ? Icons.play_arrow
                : Icons.pause,
            size: 18,
          ),
          onPressed: busy
              ? null
              : () => _runTimerAction(
                  context,
                  ref,
                  session.id,
                  () => session.state == TimerSessionState.paused
                      ? TimerActions.resume(context, ref, session.id)
                      : TimerActions.pause(context, ref, session.id),
                ),
        ),
        IconButton(
          key: const ValueKey('overlay-stop-button'),
          tooltip: 'Stop',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.stop, size: 18),
          onPressed: busy
              ? null
              : () => _runTimerAction(
                  context,
                  ref,
                  session.id,
                  () => TimerActions.stopWithPrompt(context, ref, session.id),
                ),
        ),
      ],
    );
  }
}

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
