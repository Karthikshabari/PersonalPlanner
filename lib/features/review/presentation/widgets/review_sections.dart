import 'package:flutter/material.dart';

import '../../../../core/models/daily_stats.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/duration_utils.dart';
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
