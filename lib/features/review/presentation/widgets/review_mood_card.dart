import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import 'review_equal_grid.dart';
import 'review_header_body.dart';
import 'review_mood_tile.dart';
import 'weekly_review_style.dart';

/// "How was the day?": four faces the user picks from, in Weekly's tile look.
/// Four in a row, or 2 x 2 when the card is too narrow for the longest label;
/// the row is centred in the free height of an equal-height pair.
class ReviewMoodCard extends StatelessWidget {
  final int selected;

  /// False while [selected] is only the default (Good), shown as a suggestion.
  final bool chosen;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const ReviewMoodCard({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    this.chosen = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: ReviewHeaderBody(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReviewMoodTitle(
              title: 'How was the day?',
              suggestion: chosen
                  ? null
                  : '${reviewMoodLabel(selected)} is suggested',
            ),
            const SizedBox(height: WeeklyStyle.titleGap),
          ],
        ),
        body: Semantics(
          label: 'Mood of the day',
          container: true,
          child: ReviewEqualGrid(
            minCellWidth: ReviewMoodTile.minWidth(context),
            spacing: AppSpacing.sm,
            children: [
              for (var level = 1; level <= reviewMoodLabels.length; level++)
                ReviewMoodTile(
                  keyPrefix: 'review-mood',
                  level: level,
                  selected: chosen && selected == level,
                  suggested: !chosen && selected == level,
                  enabled: enabled,
                  onChanged: onChanged,
                  selectedScale: WeeklyStyle.selectedScale,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
