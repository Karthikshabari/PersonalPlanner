import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/daily_stats.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_insights.dart';

class ReviewSummarySection extends StatelessWidget {
  final DailyStats stats;
  final ReviewInsights insights;
  final bool future;
  final String heading;
  final String emptyLabel;

  const ReviewSummarySection({
    super.key,
    required this.stats,
    required this.insights,
    required this.future,
    required this.heading,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final completed = stats.completedTasks;
    final total = stats.totalTasks;
    final tracked = stats.actualDurationMin;
    final statusSummary = <String>[
      if (stats.skippedTasks > 0) '${stats.skippedTasks} skipped',
      if (stats.cancelledTasks > 0) '${stats.cancelledTasks} cancelled',
    ];
    final planned = Duration(minutes: stats.plannedDurationMin).shortLabel;
    final time = tracked > 0
        ? '$planned planned · ${Duration(minutes: tracked).shortLabel} tracked'
        : stats.plannedDurationMin > 0
        ? '$planned planned'
        : 'No planned time';
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          if (!future && total == 0)
            Text(emptyLabel, style: Theme.of(context).textTheme.bodyMedium)
          else
            Text(
              future ? '$total planned' : '$completed / $total completed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(time, style: Theme.of(context).textTheme.bodyMedium),
          if (!future &&
              (insights.movedCount > 0 || statusSummary.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (insights.movedCount > 0) '${insights.movedCount} moved',
                ...statusSummary,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class ReviewChangesSection extends StatelessWidget {
  final ReviewInsights insights;
  final bool future;
  final String heading;

  const ReviewChangesSection({
    super.key,
    required this.insights,
    required this.future,
    this.heading = 'What changed',
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (future)
            const Text('This period has not happened yet.')
          else if (insights.changes.isEmpty)
            const Text('Your plan stayed mostly as planned.'),
          if (!future)
            for (final change in insights.changes) _ChangeRow(change: change),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final ReviewChange change;

  const _ChangeRow({required this.change});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 17, color: tokens.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.taskTitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  change.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon => switch (change.kind) {
    ReviewChangeKind.moved => Icons.swap_horiz,
    ReviewChangeKind.added => Icons.add_circle_outline,
    ReviewChangeKind.status => Icons.remove_circle_outline,
    ReviewChangeKind.duration => Icons.timer_outlined,
  };
}

class ReviewCarryoverSection extends StatelessWidget {
  final List<ReviewCarryover> items;
  final String heading;

  const ReviewCarryoverSection({
    super.key,
    required this.items,
    required this.heading,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            const Text('Nothing carried forward.')
          else ...[
            Text(
              '${items.length} item${items.length == 1 ? '' : 's'} carried forward',
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(item.title)),
                    Text(
                      item.startTime == null
                          ? 'Unscheduled'
                          : DateFormat('h:mm a').format(
                              PlannerTimeZone.toPlannerLocal(item.startTime!),
                            ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
