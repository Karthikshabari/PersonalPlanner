import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../domain/experiment_progress.dart';
import 'experiment_ui.dart';

/// The experiment's bar: the filled part is what is done, the thin tick marks
/// what was expected by now, and the whole bar is the whole window. One
/// caption line sits underneath.
///
/// With [concluded] true there is no expected tick: the bar is the final
/// result against the whole window.
class ExperimentProgressBar extends StatelessWidget {
  const ExperimentProgressBar({
    super.key,
    required this.experimentId,
    required this.progress,
    this.concluded = false,
  });

  final String experimentId;
  final ExperimentProgress progress;
  final bool concluded;

  static const _barHeight = 8.0;
  static const _tickWidth = 2.0;
  static const _tickHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final tickLeft = (progress.tickFraction * width - _tickWidth / 2)
                .clamp(0.0, width - _tickWidth);
            final fill = progress.fillFraction.isFinite
                ? progress.fillFraction.clamp(0.0, 1.0)
                : 0.0;
            return SizedBox(
              height: _tickHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(_barHeight / 2),
                    child: SizedBox(
                      key: ValueKey('experiment-bar-$experimentId'),
                      height: _barHeight,
                      width: width,
                      child: ColoredBox(
                        color: styles.scheme.surfaceContainerHighest,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: fill,
                            child: SizedBox.expand(
                              child: ColoredBox(color: styles.done),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!concluded && progress.expectedMin > 0)
                    Positioned(
                      left: tickLeft,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        key: ValueKey('experiment-tick-$experimentId'),
                        width: _tickWidth,
                        child: ColoredBox(color: styles.accent),
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
            _LegendItem(color: styles.done, label: 'Done'),
            if (!concluded)
              _LegendItem(
                color: styles.accent,
                label: 'Expected by now',
                tick: true,
              ),
            Text(
              'Full bar = the whole window, '
              '${formatMinutes(progress.totalMin)}',
              style: styles.caption,
            ),
          ],
        ),
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
    final styles = ExperimentStyles.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: tick ? 2 : 8,
          height: tick ? 12 : 8,
          child: DecoratedBox(
            decoration: tick
                ? BoxDecoration(color: color)
                : ShapeDecoration(color: color, shape: const CircleBorder()),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label, style: styles.caption)),
      ],
    );
  }
}
