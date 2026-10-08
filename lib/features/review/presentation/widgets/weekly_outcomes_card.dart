import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/weekly_review_numbers.dart';
import 'review_theme.dart';
import 'task_outcome_visuals.dart';
import 'task_outcomes_card.dart';

/// "Task outcomes": only Skipped and Rescheduled tasks, one row per task with
/// its plan change inside the row (spec 3.3).
class WeeklyOutcomesCard extends StatelessWidget {
  const WeeklyOutcomesCard({super.key, required this.rows});

  final List<WeeklyOutcomeRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Task outcomes', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Skipped or rescheduled · ${rows.length}',
            key: const ValueKey('weekly-outcomes-count'),
            style: reviewMonoStyle(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (rows.isEmpty)
            Text(
              'Nothing skipped or rescheduled this week.',
              style: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
            )
          else
            for (var i = 0; i < rows.length; i++)
              _WeeklyOutcomeRowView(
                key: ValueKey('weekly-outcome-${rows[i].taskId}'),
                row: rows[i],
                showDivider: i > 0,
              ),
        ],
      ),
    );
  }
}

class _WeeklyOutcomeRowView extends StatelessWidget {
  const _WeeklyOutcomeRowView({
    super.key,
    required this.row,
    required this.showDivider,
  });

  final WeeklyOutcomeRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final meta =
        row.reason ??
        (row.dayReviewed ? 'No reason given' : 'No reason (day not reviewed)');
    final planChange = row.planChange;
    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: tokens.outline)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                DateFormat('EEE').format(row.date),
                style: reviewMonoStyle(context, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (planChange == null)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        row.title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TaskOutcomePill(outcome: row.outcome),
                    ],
                  )
                else ...[
                  PlanChangeBlock(
                    key: ValueKey('weekly-plan-change-${row.taskId}'),
                    change: planChange,
                    reasonSeparator: ' · ',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TaskOutcomePill(outcome: row.outcome),
                ],
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
