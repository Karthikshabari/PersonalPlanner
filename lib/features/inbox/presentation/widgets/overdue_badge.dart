import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/inbox_item.dart';
import '../../../../core/theme/app_colors.dart';

/// Amber badge for overdue items (planner.md Chunk 3 #15): shows the original
/// date, e.g. "Jul 21", or "Missed Jul 21 14:00" when `missed_at` is set.
class OverdueBadge extends StatelessWidget {
  final InboxItem item;

  const OverdueBadge({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    String label;
    if (task.missedAt != null) {
      // missed_at format: YYYY-MM-DDTHH:mm
      final parts = task.missedAt!.split('T');
      final date = DateTime.tryParse(parts[0]);
      final dayMonth =
          date == null ? parts[0] : DateFormat('MMM d').format(date);
      label = 'Missed $dayMonth ${parts.length > 1 ? parts[1] : ''}'.trim();
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
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.warning, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.warning),
      ),
    );
  }
}
