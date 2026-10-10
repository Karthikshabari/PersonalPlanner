import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../domain/kept_copy.dart';
import '../../domain/kept_experiment.dart';
import 'experiment_ui.dart';

/// Up to nine weekly bars (full height = that week's target), with the
/// selected week's numbers underneath. Plain widgets; no painter.
class KeptWeeklyBars extends StatelessWidget {
  const KeptWeeklyBars({
    super.key,
    required this.view,
    required this.selectedWeekStart,
    required this.onSelect,
  });

  final KeptExperimentView view;
  final String selectedWeekStart;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final id = view.experimentId;
    final bars = view.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    final selected = bars.firstWhere(
      (bar) => bar.weekStart == selectedWeekStart,
      orElse: () => bars.last,
    );
    final targetThen = keptTargetThenText(selected, formatMinutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: 2,
          children: [
            Text(
              keptWeeklyTotals,
              style: styles.label.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(keptFullHeight, style: styles.caption),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                for (var i = 0; i < bars.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Bar(
                      key: ValueKey('kept-bar-$id-${bars[i].weekStart}'),
                      bar: bars[i],
                      selected: bars[i].weekStart == selected.weekStart,
                      onTap: () => onSelect(bars[i].weekStart),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(view.axisStartLabel, style: styles.caption),
            Text(keptThisWeekAxis, style: styles.caption),
          ],
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          key: ValueKey('kept-detail-$id'),
          constraints: const BoxConstraints(minHeight: 42),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: styles.strip,
              borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      selected.label,
                      style: styles.secondary.copyWith(
                        color: styles.scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      keptBarDetailText(selected, formatMinutes),
                      style: styles.secondary.copyWith(
                        color: styles.scheme.onSurface,
                      ),
                    ),
                    if (targetThen != null)
                      Text(targetThen, style: styles.note),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.bar,
    required this.selected,
    required this.onTap,
  });

  final KeptWeekBar bar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: bar.semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: bar.isCurrent
                    ? styles.tint(styles.accent)
                    : styles.barTrack,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: bar.heightPercent / 100,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: styles.done,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned(
                left: -4,
                top: -4,
                right: -4,
                bottom: -4,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: styles.accent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
