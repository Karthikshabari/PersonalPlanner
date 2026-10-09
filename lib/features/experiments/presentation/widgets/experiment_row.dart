import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/models/experiment.dart';
import '../../domain/experiment_dashboard.dart';
import '../../domain/experiment_progress.dart';
import 'experiment_chart.dart';
import 'experiment_check_in_box.dart';
import 'experiment_end_panel.dart';
import 'experiment_past_check_ins.dart';
import 'experiment_progress_bar.dart';

/// One experiment on the Experiments card. (Named `ExperimentRowView` so it
/// does not clash with the Drift row class `ExperimentRow`.)
class ExperimentRowView extends StatelessWidget {
  const ExperimentRowView({super.key, required this.view});

  final ExperimentView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final experiment = view.experiment;
    final progress = view.progress;
    final id = experiment.id;
    final purpose = experiment.purpose;
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );

    return AppSurface(
      key: ValueKey('experiment-$id'),
      color: tokens.surfaceSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(experiment.tagName, style: theme.textTheme.titleMedium),
              _StatusChip(text: progress.statusChip),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(experimentDatesLine(experiment), style: mutedStyle),
          if (view.extensionLine != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              view.extensionLine!,
              key: ValueKey('experiment-extension-$id'),
              style: mutedStyle,
            ),
          ],
          if (purpose != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(purpose, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            progress.headline,
            key: ValueKey('experiment-headline-$id'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ExperimentProgressBar(experimentId: id, progress: progress),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.sm,
            children: [
              _Stat(
                key: ValueKey('experiment-pace-$id'),
                label: 'Pace',
                value: progress.paceLabel,
              ),
              _Stat(
                key: ValueKey('experiment-days-at-target-$id'),
                label: 'Days at your target',
                value: progress.daysAtTargetLabel,
              ),
              _Stat(
                key: ValueKey('experiment-check-ins-$id'),
                label: 'Check-ins',
                value: view.checkInStatistic,
              ),
            ],
          ),
          if (progress.hasTodayLine) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              progress.todayLine,
              key: ValueKey('experiment-today-$id'),
              style: theme.textTheme.bodyMedium,
            ),
            if (progress.shortfallHint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(progress.shortfallHint!, style: mutedStyle),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          ExperimentChart(view: view),
          if (experiment.status == ExperimentStatus.concluded) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Outcome: ${experiment.outcome?.label ?? ''}',
              key: ValueKey('experiment-outcome-$id'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              experiment.conclusionNote ?? 'No note added.',
              key: ValueKey('experiment-conclusion-note-$id'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (view.showsEndPanel) ...[
            const SizedBox(height: AppSpacing.lg),
            ExperimentEndPanel(experiment: experiment),
          ],
          if (view.pendingDates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            ExperimentCheckInBox(
              experimentId: id,
              pendingDates: view.pendingDates,
              missedCount: view.missedCount,
              dueToday: view.dueToday,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          ExperimentPastCheckIns(experimentId: id, checkIns: view.checkIns),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppThemeTokens.of(context).textMuted,
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
