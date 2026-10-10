import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../domain/kept_copy.dart';
import '../../domain/kept_experiment.dart';
import 'experiment_ui.dart';

/// "How this is counted": the seven days of this week and the arithmetic
/// behind the chip.
class KeptExplainPanel extends StatelessWidget {
  const KeptExplainPanel({super.key, required this.view});

  final KeptExperimentView view;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final id = view.experimentId;
    final pace = view.paceMin;
    final paceColor = pace >= 0 ? styles.done : styles.caution;
    return Column(
      key: ValueKey('kept-explain-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < view.days.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _DayColumn(id: id, day: view.days[i]),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _MathRow(
          label: keptMathMinimum(
            weekdayCount: view.weekdayCount,
            weekdayMin: view.weekdayTargetMin,
            weekendCount: view.weekendCount,
            weekendMin: view.weekendTargetMin,
          ),
          value: formatMinutes(view.targetMin),
        ),
        const SizedBox(height: 6),
        _MathRow(
          label: keptMathDone(view.name),
          value: formatMinutes(view.doneMin),
        ),
        const SizedBox(height: 6),
        _MathRow(label: keptMathPlanned, value: formatMinutes(view.plannedMin)),
        const SizedBox(height: 6),
        _MathRow(
          label: keptMathExpected,
          value: formatMinutes(view.expectedMin),
        ),
        const SizedBox(height: AppSpacing.sm),
        const ExperimentHairline(),
        const SizedBox(height: AppSpacing.sm),
        _MathRow(
          label: keptMathPace,
          value: keptPaceText(pace, formatMinutes),
          labelColor: styles.scheme.onSurface,
          valueColor: paceColor,
          bold: true,
        ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.id, required this.day});

  final String id;
  final KeptDayColumn day;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return Column(
      key: ValueKey('kept-day-$id-${day.date}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: styles.barTrack,
              borderRadius: BorderRadius.circular(4),
              border: day.isToday ? Border.all(color: styles.accent) : null,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: day.fillFraction,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: styles.done,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day.dayName,
          style: styles.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          day.valueLabel,
          textAlign: TextAlign.center,
          style: styles.caption.copyWith(
            color: day.dim ? styles.muted : styles.scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _MathRow extends StatelessWidget {
  const _MathRow({
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? labelColor;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final weight = bold ? FontWeight.w600 : FontWeight.w400;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: AppSpacing.md,
      runSpacing: 2,
      children: [
        Text(
          label,
          style: styles.secondary.copyWith(
            color: labelColor ?? styles.muted,
            fontWeight: weight,
          ),
        ),
        Text(
          value,
          style: styles.secondary.copyWith(
            color: valueColor ?? styles.scheme.onSurface,
            fontWeight: weight,
          ),
        ),
      ],
    );
  }
}
