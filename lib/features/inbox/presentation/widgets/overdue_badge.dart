import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/inbox_item.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/missed_at.dart';
import '../../../../core/utils/planner_time_zone.dart';

/// Amber badge for overdue items (planner.md Chunk 3 #15): shows the original
/// date, e.g. "Jul 21", or "Missed Jul 21 14:00" when `missed_at` is set.
class OverdueBadge extends StatelessWidget {
  final InboxItem item;

  const OverdueBadge({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final task = item.task;
    String label;
    if (task.missedAt != null) {
      final instant = MissedAtCodec.parse(task.missedAt);
      if (instant == null) {
        label = 'Missed ${task.missedAt}';
      } else {
        final local = PlannerTimeZone.toPlannerLocal(instant);
        label = 'Missed ${DateFormat('MMM d HH:mm').format(local)}';
      }
    } else {
      final start = task.startTime;
      label = start == null
          ? TaskStatus.rescheduled.label
          : DateFormat('MMM d').format(start);
    }
    return Container(
      key: const ValueKey('overdue-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.warning, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: tokens.warning,
        ),
      ),
    );
  }
}
