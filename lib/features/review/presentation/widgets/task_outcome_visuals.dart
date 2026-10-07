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
  const TaskOutcomePill({super.key, required this.outcome});

  final TaskOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final color = taskOutcomeColor(context, outcome);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: color)),
      ),
      child: Text(
        outcome.label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
