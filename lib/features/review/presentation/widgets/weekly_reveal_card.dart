import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/weekly_review_numbers.dart';
import 'dashed_outline.dart';
import 'review_theme.dart';

/// "Your week". Until W5 it always shows its "before" state: a dashed face,
/// the invitation to save, and the eight-week dots.
class WeeklyRevealCard extends StatelessWidget {
  const WeeklyRevealCard({super.key, required this.dots});

  final List<WeeklyDot> dots;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your week', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: SizedBox.square(
              dimension: 72,
              child: CustomPaint(
                painter: DashedOutlinePainter(
                  color: tokens.textMuted,
                  strokeWidth: 1.5,
                  circle: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Save your review to reveal your week.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          WeeklyDotsRow(
            dots: dots,
            currentFill: 0,
            reviewedCount: weeklyReviewedDotCount(dots, currentSaved: false),
          ),
        ],
      ),
    );
  }
}

/// Eight dots, oldest first, and `{n} of 8 weeks reviewed` (spec 3.10).
class WeeklyDotsRow extends StatelessWidget {
  const WeeklyDotsRow({
    super.key,
    required this.dots,
    required this.currentFill,
    required this.reviewedCount,
  });

  final List<WeeklyDot> dots;

  /// 0 = the current week's dot is dashed; 1 = filled with the accent.
  final double currentFill;
  final int reviewedCount;

  static const double size = 12;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final colors = ReviewColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    Widget dot(WeeklyDot value) {
      switch (value.kind) {
        case WeeklyDotKind.gap:
          return CustomPaint(
            painter: DashedOutlinePainter(
              color: tokens.textMuted.withValues(alpha: 0.6),
              strokeWidth: 1.5,
              dash: 2.6,
              gap: 2.6,
              circle: true,
            ),
          );
        case WeeklyDotKind.reviewed:
          final mood = value.mood;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mood == null ? tokens.textMuted : colors.mood(mood),
            ),
          );
        case WeeklyDotKind.current:
          return Stack(
            fit: StackFit.expand,
            children: [
              if (currentFill < 1)
                CustomPaint(
                  painter: DashedOutlinePainter(
                    color: accent,
                    strokeWidth: 1.5,
                    dash: 2.6,
                    gap: 2.6,
                    circle: true,
                  ),
                ),
              if (currentFill > 0)
                Opacity(
                  opacity: currentFill,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                  ),
                ),
            ],
          );
      }
    }

    return Column(
      children: [
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < dots.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: SizedBox.square(
                    key: ValueKey('weekly-dot-$i'),
                    dimension: size,
                    child: dot(dots[i]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          weeksReviewedLabel(reviewedCount),
          key: const ValueKey('weekly-dots-text'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
