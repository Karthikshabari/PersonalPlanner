import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import 'review_theme.dart';

/// The note for a week as next week's review shows it: "From last week" at
/// the top of the Review tab, and the preview in the Next week tab.
class WeeklyNoteLine extends StatelessWidget {
  const WeeklyNoteLine({
    super.key,
    required this.heading,
    required this.note,
    this.emptyText = '',
  });

  final String heading;

  /// Trimmed note; empty shows [emptyText].
  final String note;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        border: Border.all(color: tokens.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: reviewMonoStyle(context)),
          const SizedBox(height: 2),
          Text(
            note.isEmpty ? emptyText : '"$note"',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: note.isEmpty ? FontWeight.w400 : FontWeight.w500,
              color: note.isEmpty ? tokens.textMuted : tokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
