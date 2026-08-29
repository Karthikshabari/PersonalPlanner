import 'package:flutter/material.dart';

import '../../../../core/models/category.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/status_badge.dart';

/// Read-only miniature timeline for the Daily Review screen: every block of
/// the day at its scheduled position with its final status (planner.md
/// Chunk 5 #5). No gestures — nothing here mutates data.
class DaySummaryTimeline extends StatelessWidget {
  final List<Task> tasks;
  final List<Category> categories;
  final DateTime date;

  /// Vertical pixels per minute; the whole day is scrollable.
  final double pixelsPerMinute;

  const DaySummaryTimeline({
    super.key,
    required this.tasks,
    required this.categories,
    required this.date,
    this.pixelsPerMinute = 0.6,
  });

  double get _totalHeight => 24 * 60 * pixelsPerMinute;

  Category? _categoryFor(Task task) {
    for (final c in categories) {
      if (c.id == task.categoryId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: Text('No blocks scheduled this day.')),
      );
    }
    final lineColor = Theme.of(context).dividerColor;
    return SizedBox(
      key: const ValueKey('review-mini-timeline'),
      height: 320,
      child: SingleChildScrollView(
        child: SizedBox(
          height: _totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Hour grid + labels every other hour to stay compact.
              for (var hour = 0; hour < 24; hour += 2)
                Positioned(
                  top: hour * 60 * pixelsPerMinute,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${hour.toString().padLeft(2, '0')}:00',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                            height: 1, thickness: 0.5, color: lineColor),
                      ),
                    ],
                  ),
                ),
              for (final task in tasks) _buildBlock(context, task),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(BuildContext context, Task task) {
    final startMinutes = task.startTime == null
        ? 0
        : minutesSinceMidnight(task.startTime!);
    final durationMinutes =
        task.scheduledDuration?.inMinutes.toDouble() ?? 60.0;
    final height = (durationMinutes * pixelsPerMinute).clamp(22.0, 200.0);
    final category = _categoryFor(task);
    final accent = category == null
        ? AppColors.primary
        : AppColors.parseHex(category.colorHex);
    return Positioned(
      key: ValueKey('review-block-${task.id}'),
      top: startMinutes * pixelsPerMinute + 1,
      left: 44,
      right: AppSpacing.sm,
      height: height - 2,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: accent, width: 3),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(status: task.status),
          ],
        ),
      ),
    );
  }
}
