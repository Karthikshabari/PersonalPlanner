import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import '../models/task.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/duration_utils.dart';
import '../../features/task_editor/providers/subtask_providers.dart';
import '../../features/timer/providers/timer_providers.dart';
import 'status_badge.dart';

class TaskBlockWidget extends ConsumerWidget {
  final Task task;
  final Category? category;
  final bool selected;

  /// Runtime-only flag: this block participates in an overlap that was
  /// allowed ("Keep Overlap"). Renders a striped texture, amber outline and
  /// warning icon; never persisted.
  final bool hasOverlap;
  final VoidCallback? onTap;
  final VoidCallback? onStatusTap;

  const TaskBlockWidget({
    super.key,
    required this.task,
    this.category,
    this.selected = false,
    this.hasOverlap = false,
    this.onTap,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryColor =
        category == null ? null : AppColors.parseHex(category!.colorHex);
    final duration = task.scheduledDuration;
    // "2/4" completion count; only rendered when the task has subtasks.
    final subtasksAsync = ref.watch(subtasksForTaskProvider(task.id));
    final subtaskCount = subtasksAsync.maybeWhen(
      data: (subtasks) => subtasks.isEmpty
          ? null
          : '${subtasks.where((s) => s.isCompleted).length}/${subtasks.length}',
      orElse: () => null,
    );
    // Live timer display (Chunk 6 #7): ticks every second while THIS block's
    // timer runs. The tick stream is only listened to when relevant.
    final activeTimer = ref.watch(activeTimerProvider).value;
    final isTimingHere = activeTimer?.session.taskId == task.id;
    final timerLabel = isTimingHere
        ? formatTimerClock(
            ref.watch(activeTimerElapsedProvider(task.id)).value ?? 0)
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariantDark.withValues(alpha: 0.92),
            // A non-uniform Border cannot have a borderRadius (paint-time
            // crash), so overlap blocks use square corners.
            borderRadius: hasOverlap ? null : BorderRadius.circular(8),
            border: hasOverlap
                ? Border(
                    left: BorderSide(
                      color: categoryColor ?? AppColors.primary,
                      width: 4,
                    ),
                    top: const BorderSide(color: AppColors.warning, width: 1.5),
                    right:
                        const BorderSide(color: AppColors.warning, width: 1.5),
                    bottom:
                        const BorderSide(color: AppColors.warning, width: 1.5),
                  )
                : Border(
                    left: BorderSide(
                      color: categoryColor ?? AppColors.primary,
                      width: 4,
                    ),
                  ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? AppColors.selectionHighlight
                    : Colors.black.withValues(alpha: 0.3),
                blurRadius: selected ? 0 : 4,
                spreadRadius: selected ? 1.5 : 0,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            // Short blocks (15-min grid slots, live shrink-resize) only fit
            // the title; showing the badge row there overflows the Column.
            final compact = constraints.maxHeight < 38;
            if (constraints.maxHeight < 24) {
              return ClipRect(
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              );
            }
            return Stack(
              children: [
                if (hasOverlap)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child:
                            CustomPaint(painter: _StripesPainter()),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          StatusBadge(status: task.status, onTap: onStatusTap),
                          const Spacer(),
                          if (duration != null)
                            Text(
                              duration.shortLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondaryDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (hasOverlap)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 13,
                      color: AppColors.warning,
                    ),
                  ),
                // Recurring-series marker (Chunk 4 #14): small ↻ in the
                // corner; the overlap warning wins when both apply.
                if (task.recurringRuleId != null && !hasOverlap)
                  Positioned(
                    top: 0,
                    right: 2,
                    child: Icon(
                      key: const ValueKey('recurring-indicator'),
                      Icons.refresh,
                      size: 13,
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                if (timerLabel != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Row(
                      key: const ValueKey('block-timer-chip'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 10, color: AppColors.inProgress),
                        const SizedBox(width: 2),
                        Text(
                          timerLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inProgress,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (subtaskCount != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Text(
                      subtaskCount,
                      key: const ValueKey('subtask-count'),
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondaryDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  static final Paint _paint = Paint()
    ..strokeWidth = 3
    ..color = AppColors.warning.withValues(alpha: 0.14);

  @override
  void paint(Canvas canvas, Size size) {
    for (double x = -size.height; x < size.width + size.height; x += 10) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StripesPainter oldDelegate) => false;
}
