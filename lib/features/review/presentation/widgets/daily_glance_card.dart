import 'package:flutter/material.dart';

import '../../../../core/models/daily_stats.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_insights.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// "Day at a glance": the completion line, a slim progress bar and the
/// planned / moved / skipped / cancelled facts as one wrapping caption.
/// A day without tasks says so instead of showing `0 / 0`.
class DailyGlanceCard extends StatelessWidget {
  const DailyGlanceCard({
    super.key,
    required this.stats,
    required this.insights,
    required this.future,
    required this.isToday,
  });

  final DailyStats stats;
  final ReviewInsights insights;

  /// The viewed day is after today.
  final bool future;

  /// The viewed day is today: a small "Today" pill sits next to the title.
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final completed = stats.completedTasks;
    final total = stats.totalTasks;
    final tracked = stats.actualDurationMin;
    final planned = Duration(minutes: stats.plannedDurationMin).shortLabel;
    final noTasks = !future && total == 0;
    final headline = future
        ? '$total planned'
        : noTasks
        ? 'No tasks planned'
        : '$completed / $total completed';
    final facts = <String>[
      if (tracked > 0)
        '$planned planned · ${Duration(minutes: tracked).shortLabel} tracked'
      else if (stats.plannedDurationMin > 0)
        '$planned planned'
      else
        'No planned time',
      if (!future && insights.movedCount > 0) '${insights.movedCount} moved',
      if (!future && stats.skippedTasks > 0) '${stats.skippedTasks} skipped',
      if (!future && stats.cancelledTasks > 0)
        '${stats.cancelledTasks} cancelled',
    ];
    return AppSurface(
      key: const ValueKey('review-day-glance'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Day at a glance', style: textTheme.titleMedium),
              if (isToday) const _TodayPill(),
            ],
          ),
          const SizedBox(height: WeeklyStyle.titleGap),
          Text(
            headline,
            key: const ValueKey('review-glance-headline'),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (!future && total > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                key: const ValueKey('review-glance-progress'),
                value: (completed / total).clamp(0.0, 1.0),
                minHeight: 4,
                color: ReviewColors.of(context).success,
                backgroundColor: tokens.outline,
                semanticsLabel: '$completed of $total tasks completed',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            facts.join(' · '),
            key: const ValueKey('review-glance-facts'),
            style: weeklyCaptionStyle(context),
          ),
        ],
      ),
    );
  }
}

/// Small "Today" marker next to a card title: a tonal pill, accent text.
class _TodayPill extends StatelessWidget {
  const _TodayPill();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      key: const ValueKey('review-glance-today'),
      decoration: BoxDecoration(
        color: WeeklyStyle.inset(context),
        borderRadius: BorderRadius.circular(WeeklyStyle.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        child: Text(
          'Today',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: accent, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
