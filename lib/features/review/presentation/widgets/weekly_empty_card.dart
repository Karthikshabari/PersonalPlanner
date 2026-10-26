import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

/// An empty week in place of the glance, reasons and outcomes cards: there is
/// nothing to compare yet, so it points to planning instead.
class WeeklyEmptyCard extends StatelessWidget {
  const WeeklyEmptyCard({super.key, required this.onOpenWeek});

  final VoidCallback onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan some days first', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A weekly review compares what you planned with what happened, '
            'and this week has no tasks yet.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppThemeTokens.of(context).textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: const ValueKey('weekly-open-week'),
            onPressed: onOpenWeek,
            child: const Text('Open Week'),
          ),
        ],
      ),
    );
  }
}
