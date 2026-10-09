import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show InsightsProgressBar, formatMinutes;
import '../../domain/experiment_progress.dart';

/// The experiment's bar: the filled part is what is done, the thin tick marks
/// what was expected by now, and the whole bar is the whole window. The legend
/// sits underneath.
class ExperimentProgressBar extends StatelessWidget {
  const ExperimentProgressBar({
    super.key,
    required this.experimentId,
    required this.progress,
  });

  final String experimentId;
  final ExperimentProgress progress;

  static const _barHeight = 10.0;
  static const _tickWidth = 2.0;
  static const _tickHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final mutedStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: tokens.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final tickLeft =
                (progress.tickFraction * constraints.maxWidth - _tickWidth / 2)
                    .clamp(0.0, constraints.maxWidth - _tickWidth);
            return SizedBox(
              height: _tickHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  InsightsProgressBar(
                    key: ValueKey('experiment-bar-$experimentId'),
                    fraction: progress.fillFraction,
                    color: tokens.success,
                    height: _barHeight,
                  ),
                  if (progress.expectedMin > 0)
                    Positioned(
                      left: tickLeft,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        key: ValueKey('experiment-tick-$experimentId'),
                        width: _tickWidth,
                        child: ColoredBox(color: primary),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LegendItem(color: tokens.success, label: 'Done'),
            _LegendItem(color: primary, label: 'Expected by now', tick: true),
            Text(
              'Full bar = the whole window, '
              '${formatMinutes(progress.totalMin)}',
              style: mutedStyle,
            ),
          ],
        ),
        if (progress.showExtraLegendLine) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Today's target only counts against you once the day is over.",
            style: mutedStyle,
          ),
        ],
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.tick = false,
  });

  final Color color;
  final String label;
  final bool tick;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppThemeTokens.of(context).textMuted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: tick ? 2 : 10,
          height: tick ? 14 : 10,
          child: ColoredBox(color: color),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}
