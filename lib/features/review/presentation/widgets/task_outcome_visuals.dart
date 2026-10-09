import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/task_outcome.dart';
import 'review_theme.dart';

IconData taskOutcomeIcon(TaskOutcome o) => switch (o) {
  TaskOutcome.completed => Icons.check_circle_outline_rounded,
  TaskOutcome.partlyDone => Icons.timelapse_rounded,
  TaskOutcome.notStarted => Icons.radio_button_unchecked_rounded,
  TaskOutcome.skipped => Icons.skip_next_rounded,
  TaskOutcome.rescheduled => Icons.event_repeat_rounded,
};

const IconData planChangedIcon = Icons.edit_note_rounded;

Color taskOutcomeColor(BuildContext context, TaskOutcome o) {
  final colors = ReviewColors.of(context);
  return switch (o) {
    TaskOutcome.completed => colors.success,
    TaskOutcome.partlyDone => colors.amber,
    TaskOutcome.rescheduled => colors.blue,
    TaskOutcome.notStarted ||
    TaskOutcome.skipped => AppThemeTokens.of(context).textMuted,
  };
}

class TaskOutcomePill extends StatelessWidget {
  const TaskOutcomePill({super.key, required this.outcome, this.roomy = false});

  final TaskOutcome outcome;

  /// A slightly larger pill (12 px text, 24 dp tall) for the Daily rows.
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final color = taskOutcomeColor(context, outcome);
    final textTheme = Theme.of(context).textTheme;
    final label = Text(
      outcome.label,
      style: (roomy ? textTheme.labelMedium : textTheme.labelSmall)?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      constraints: BoxConstraints(minHeight: roomy ? 24 : 0),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: roomy ? 2 : 1),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: color)),
      ),
      child: roomy ? Center(widthFactor: 1, child: label) : label,
    );
  }
}
