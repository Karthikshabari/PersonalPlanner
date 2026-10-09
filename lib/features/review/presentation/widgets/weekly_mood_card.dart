import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import 'review_equal_grid.dart';
import 'review_header_body.dart';
import 'review_mood_tile.dart';
import 'weekly_review_style.dart';

/// "How was the week?": four faces the user picks from (never detected).
/// Radio semantics, 44 dp minimum targets, a 240 ms face pop and a light
/// haptic on Android when a face is picked (spec 3.5).
class WeeklyMoodCard extends StatelessWidget {
  const WeeklyMoodCard({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    this.lastWeekHint,
  });

  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// `Last week: Great`, or null.
  final String? lastWeekHint;

  /// Room one tile needs for the longest label (semibold, as when selected)
  /// plus the tile's own padding and border.
  static double _minTileWidth(BuildContext context) =>
      measureWidestText(
        context,
        reviewMoodLabels,
        Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ) +
      2 * 2 + // tile horizontal padding
      2; // border

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: ReviewHeaderBody(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How was the week?', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
        // Centred in whatever height the row gives this card.
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'Mood of the week',
              container: true,
              child: ReviewEqualGrid(
                minCellWidth: _minTileWidth(context),
                spacing: WeeklyStyle.space2,
                children: [
                  for (var level = 1; level <= 4; level++)
                    ReviewMoodTile(
                      keyPrefix: 'weekly-mood',
                      level: level,
                      selected: selected == level,
                      enabled: enabled,
                      onChanged: onChanged,
                    ),
                ],
              ),
            ),
            if (lastWeekHint != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                lastWeekHint!,
                key: const ValueKey('weekly-last-mood'),
                style: textTheme.bodySmall?.copyWith(
                  color: AppThemeTokens.of(context).textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
