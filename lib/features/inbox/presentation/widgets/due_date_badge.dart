import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';

class DueDateBadge extends StatelessWidget {
  final String dueDate;
  final DateTime today;

  const DueDateBadge({
    super.key,
    required this.dueDate,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final due = parseIsoDate(dueDate);
    final todayDate = parseIsoDate(isoDateString(today));
    final overdue = due.isBefore(todayDate);
    final label = isSameDay(due, today)
        ? 'Due today'
        : overdue
        ? 'Overdue · ${DateFormat('MMM d').format(due)}'
        : 'Due ${DateFormat('EEE, MMM d').format(due)}';
    final color = overdue ? tokens.warning : tokens.info;
    return Container(
      key: const ValueKey('due-date-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
