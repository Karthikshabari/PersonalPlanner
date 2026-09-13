import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import '../models/task.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/duration_utils.dart';
import '../utils/planner_time_zone.dart';
import 'error_panel.dart';
import 'task_progress_background.dart';
import '../../features/task_editor/providers/subtask_providers.dart';
import '../../features/timeline/domain/timeline_geometry.dart';
import 'status_badge.dart';

class TaskBlockWidget extends ConsumerWidget {
  final Task task;
  final Category? category;
  final bool selected;
  final TimelineTaskGeometry? geometry;
  final bool compact;

  /// Runtime-only flag: this block participates in an overlap that was
  /// allowed ("Keep Overlap"). Renders a striped texture, amber outline and
  /// warning icon; never persisted.
  final bool hasOverlap;

  /// When supplied, the parent has already loaded the `completed/total` label
  /// in a grouped query. A null value preserves the standalone fallback.
  final String? groupedSubtaskCount;
  final VoidCallback? onTap;
  final VoidCallback? onStatusTap;

  const TaskBlockWidget({
    super.key,
    required this.task,
    this.category,
    this.selected = false,
    this.geometry,
    this.compact = false,
    this.hasOverlap = false,
    this.groupedSubtaskCount,
    this.onTap,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = AppThemeTokens.of(context);
    final taskFillForeground = geometry == null ? null : tokens.onTaskFill;
    final categoryColor = category == null
        ? null
        : AppColors.parseHex(category!.colorHex);
    final duration = task.scheduledDuration;
    final actualMinutes = task.actualDurationMin ?? 0;
    final planChange = task.displayPlanChange;
    // "2/4" completion count; only rendered when the task has subtasks.
    final subtasksAsync = groupedSubtaskCount == null
        ? ref.watch(subtasksForTaskProvider(task.id))
        : null;
    final subtaskLookupError = subtasksAsync?.hasError == true;
    final subtaskLookupLoading =
        subtasksAsync != null && !subtasksAsync.hasValue;
    final renderedSubtaskCount = groupedSubtaskCount == null
        ? subtasksAsync?.hasValue == true
              ? (() {
                  final subtasks = subtasksAsync!.requireValue;
                  return subtasks.isEmpty
                      ? null
                      : '${subtasks.where((s) => s.isCompleted).length}/${subtasks.length}';
                })()
              : null
        : groupedSubtaskCount!.isEmpty
        ? null
        : groupedSubtaskCount;
    final lookupError = subtaskLookupError
        ? friendlyErrorMessage(subtasksAsync!.error!)
        : null;
    final start = task.startTime == null
        ? null
        : PlannerTimeZone.toPlannerLocal(task.startTime!);
    final end = task.endTime == null
        ? null
        : PlannerTimeZone.toPlannerLocal(task.endTime!);
    String timeLabel(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    final interval = start == null || end == null
        ? 'unscheduled'
        : '${timeLabel(start)} to ${timeLabel(end)}';
    final contextLabel = [
      'Task ${task.title}',
      if (planChange != null)
        'plan changed from ${planChange.previousTitle} to ${task.title}',
      interval,
      task.status.label,
      if (duration != null) 'planned ${duration.inMinutes} minutes',
      'actual $actualMinutes minutes',
      if (geometry != null && geometry!.overtimeDuration > Duration.zero)
        'overtime ${geometry!.overtimeDuration.inMinutes} minutes',
      if (category != null) 'category ${category!.name}',
      if (hasOverlap) 'overlapping task',
    ].join(', ');
    return Semantics(
      button: onTap != null,
      label: contextLabel,
      hint: onTap == null ? null : 'Open task; long press to move',
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          hoverColor: tokens.hover,
          focusColor: tokens.focus.withValues(alpha: 0.12),
          splashColor: tokens.selected,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(tokens.selected, tokens.surfaceRaised)
                  : tokens.surfaceRaised,
              // A non-uniform Border cannot have a borderRadius (paint-time
              // crash), so overlap blocks use square corners.
              borderRadius: hasOverlap || selected
                  ? null
                  : BorderRadius.circular(tokens.radiusSmall),
              border: hasOverlap
                  ? Border(
                      left: BorderSide(
                        color: categoryColor ?? AppColors.primary,
                        width: 4,
                      ),
                      top: BorderSide(color: tokens.warning, width: 1.5),
                      right: BorderSide(color: tokens.warning, width: 1.5),
                      bottom: BorderSide(color: tokens.warning, width: 1.5),
                    )
                  : Border(
                      left: BorderSide(
                        color: categoryColor ?? AppColors.primary,
                        width: 4,
                      ),
                      top: selected
                          ? BorderSide(color: tokens.focus, width: 1.5)
                          : BorderSide.none,
                      right: selected
                          ? BorderSide(color: tokens.focus, width: 1.5)
                          : BorderSide.none,
                      bottom: selected
                          ? BorderSide(color: tokens.focus, width: 1.5)
                          : BorderSide.none,
                    ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? tokens.focus.withValues(alpha: 0.38)
                      : colorScheme.shadow.withValues(alpha: 0.24),
                  blurRadius: selected ? 8 : 4,
                  spreadRadius: selected ? 1 : 0,
                ),
              ],
            ),
            child: Stack(
              children: [
                if (geometry != null)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(tokens.radiusSmall),
                      child: TaskProgressBackground(geometry: geometry!),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? AppSpacing.xs : AppSpacing.md,
                    vertical: compact ? AppSpacing.xs : AppSpacing.sm,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Short blocks (15-min grid slots, live shrink-resize) only fit
                      // the title; showing the badge row there overflows the Column.
                      final compactBlock =
                          compact || constraints.maxHeight < 38;
                      if (constraints.maxHeight < 24) {
                        return ClipRect(
                          child: SizedBox(
                            height: constraints.maxHeight,
                            child: Tooltip(
                              message: planChange == null
                                  ? task.title
                                  : '${planChange.previousTitle} → ${task.title}',
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      task.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: taskFillForeground,
                                          ),
                                    ),
                                  ),
                                  if (planChange != null)
                                    Icon(
                                      Icons.history,
                                      key: const ValueKey(
                                        'plan-change-indicator',
                                      ),
                                      size: 12,
                                      color: taskFillForeground,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final showPriorTitle =
                          planChange != null &&
                          constraints.maxHeight >= (compact ? 54 : 58);
                      final titleStyle = Theme.of(context).textTheme.titleSmall
                          ?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: taskFillForeground,
                          );
                      return Stack(
                        children: [
                          if (hasOverlap)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CustomPaint(
                                    painter: _StripesPainter(),
                                  ),
                                ),
                              ),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showPriorTitle)
                                Text(
                                  planChange.previousTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle?.copyWith(
                                    fontWeight: FontWeight.w400,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              Tooltip(
                                message: planChange == null
                                    ? task.title
                                    : '${planChange.previousTitle} → ${task.title}',
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        task.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: titleStyle,
                                      ),
                                    ),
                                    if (planChange != null && !showPriorTitle)
                                      Icon(
                                        Icons.history,
                                        key: const ValueKey(
                                          'plan-change-indicator',
                                        ),
                                        size: 12,
                                        color: taskFillForeground,
                                      ),
                                  ],
                                ),
                              ),
                              if (!compactBlock) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    StatusBadge(
                                      status: task.status,
                                      onTap: onStatusTap,
                                    ),
                                    const Spacer(),
                                    if (duration != null)
                                      Text(
                                        duration.shortLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: geometry == null
                                              ? colorScheme.onSurfaceVariant
                                              : tokens.onTaskFill.withValues(
                                                  alpha: 0.82,
                                                ),
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
                                color: tokens.warning,
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
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (renderedSubtaskCount != null)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Text(
                                renderedSubtaskCount,
                                key: const ValueKey('subtask-count'),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (subtaskLookupLoading && !subtaskLookupError)
                            const Positioned(
                              bottom: 0,
                              right: 0,
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ),
                          if (lookupError != null)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Tooltip(
                                message: lookupError,
                                child: Icon(
                                  Icons.error_outline,
                                  size: 12,
                                  color: colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
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
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripesPainter oldDelegate) => false;
}
