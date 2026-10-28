import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import '../models/enums/task_status.dart';
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
import '../../features/timeline/presentation/widgets/day_style.dart';
import '../../features/timeline/presentation/widgets/resizable_handle.dart';
import 'status_badge.dart';

class TaskBlockWidget extends ConsumerWidget {
  /// A normal card needs room for its title, subtask count, status and
  /// duration. Below this height the card switches to its one-line layout.
  static const double compactHeightThreshold = 54;

  /// Rendering-only minimum used by the day view for cards that would
  /// otherwise be shorter than a readable title. It never changes geometry
  /// or the task's persisted start/end values.
  static const double compactMinHeight = 28;

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
  final VoidCallback? onDoubleTap;
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
    this.onDoubleTap,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = AppThemeTokens.of(context);
    final taskFillForeground = geometry == null ? null : tokens.onTaskFill;
    final categoryColor = category == null
        ? null
        : AppColors.categoryColor(category!.colorHex, colorScheme.brightness);
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
      if (renderedSubtaskCount != null) 'subtasks done $renderedSubtaskCount',
      'actual $actualMinutes minutes',
      if (geometry != null && geometry!.overtimeDuration > Duration.zero)
        'overtime ${geometry!.overtimeDuration.inMinutes} minutes',
      if (category != null) 'category ${category!.name}',
      if (hasOverlap) 'overlapping task',
    ].join(', ');
    return Semantics(
      button: onTap != null,
      label: contextLabel,
      hint: onTap == null
          ? null
          : 'Select task; double tap or use Edit to open the editor',
      onTap: onTap,
      // One stop per block: the label says everything the title, duration and
      // badge show, and the badge's tap is this action.
      excludeSemantics: true,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Change status'): ?onStatusTap,
      },
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, outer) {
            // Blocks at least 48 px tall get the card radius, shorter ones the
            // small radius.
            final blockHeight = outer.hasBoundedHeight
                ? outer.maxHeight
                : (geometry?.heightPx ?? 0);
            final radius = BorderRadius.circular(
              blockHeight >= 48
                  ? DayStyle.medium(context)
                  : DayStyle.small(context),
            );
            // A lane too narrow for the status row falls back to the one-line
            // layout, with the tighter side padding of a compact card so the
            // title keeps some room.
            final lanePadding = compact ? AppSpacing.xs : AppSpacing.md;
            // 4 is the width of the category bar on the left edge.
            final narrowLane = outer.maxWidth - 2 * lanePadding - 4 < 64;
            final baseFill = selected
                ? Color.alphaBlend(tokens.selected, tokens.surfaceRaised)
                : tokens.surfaceRaised;
            return InkWell(
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              mouseCursor: onTap == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              hoverColor: Colors.transparent,
              focusColor: tokens.focus.withValues(alpha: 0.12),
              splashColor: tokens.selected,
              borderRadius: radius,
              child: _HoverFill(
                builder: (context, hovered, child) => Container(
                  decoration: BoxDecoration(
                    // The ink of an InkWell paints under this opaque fill, so
                    // the hover tint is blended into the fill itself.
                    color: hovered
                        ? Color.alphaBlend(tokens.hover, baseFill)
                        : baseFill,
                    // A non-uniform Border with several visible colours cannot
                    // have a borderRadius (paint-time crash), so overlap blocks
                    // use square corners. The selection ring is a separate
                    // uniform foreground border and keeps the corners round.
                    borderRadius: hasOverlap ? null : radius,
                    border: hasOverlap
                        ? Border(
                            left: BorderSide(
                              color: categoryColor ?? AppColors.primary,
                              width: 4,
                            ),
                            top: BorderSide(color: tokens.warning, width: 1.5),
                            right: BorderSide(
                              color: tokens.warning,
                              width: 1.5,
                            ),
                            bottom: BorderSide(
                              color: tokens.warning,
                              width: 1.5,
                            ),
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
                            ? tokens.focus.withValues(alpha: 0.38)
                            : colorScheme.shadow.withValues(alpha: 0.24),
                        blurRadius: selected ? 8 : 4,
                        spreadRadius: selected ? 1 : 0,
                      ),
                    ],
                  ),
                  foregroundDecoration: selected
                      ? BoxDecoration(
                          borderRadius: hasOverlap ? null : radius,
                          border: Border.all(color: tokens.focus, width: 2),
                        )
                      : null,
                  child: child,
                ),
                child: Stack(
                  children: [
                    if (geometry != null)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: radius,
                          child: TaskProgressBackground(geometry: geometry!),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact || narrowLane
                            ? AppSpacing.xs
                            : AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final shortBlock =
                              compact ||
                              (geometry == null
                                  ? constraints.maxHeight <
                                        compactHeightThreshold
                                  : geometry!.heightPx <
                                        compactHeightThreshold);
                          final showPriorTitle =
                              planChange != null &&
                              (compact
                                  ? geometry != null
                                        ? geometry!.heightPx >=
                                              compactHeightThreshold
                                        : constraints.maxHeight >= 48
                                  : constraints.maxHeight >= 58);
                          final compactBlock = shortBlock || narrowLane;
                          final dimTitle =
                              task.status == TaskStatus.skipped ||
                              task.status == TaskStatus.cancelled;
                          final titleStyle = Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: taskFillForeground,
                              );
                          // Compact cards drop the status badge, so Skipped and
                          // Cancelled are shown by dimming and striking the title.
                          final titleTextStyle = compactBlock && dimTitle
                              ? titleStyle?.copyWith(
                                  color:
                                      (titleStyle.color ??
                                              colorScheme.onSurface)
                                          .withValues(alpha: 0.6),
                                  decoration: TextDecoration.lineThrough,
                                )
                              : titleStyle;
                          final statusGlyph =
                              compactBlock &&
                                  !narrowLane &&
                                  constraints.maxWidth >= 96 &&
                                  task.status != TaskStatus.planned &&
                                  !dimTitle
                              ? _StatusGlyph(
                                  status: task.status,
                                  onTap: onStatusTap,
                                )
                              : null;
                          final title = Tooltip(
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
                                    style: titleTextStyle,
                                  ),
                                ),
                                if (planChange != null &&
                                    !showPriorTitle &&
                                    (!compactBlock ||
                                        renderedSubtaskCount == null))
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
                          );
                          final durationLabel = duration == null
                              ? null
                              : Text(
                                  duration.shortLabel,
                                  key: const ValueKey('task-duration-label'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: geometry == null
                                        ? colorScheme.onSurfaceVariant
                                        : tokens.onTaskFill.withValues(
                                            alpha: 0.82,
                                          ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                          final subtaskLabel = renderedSubtaskCount == null
                              ? null
                              : Text(
                                  renderedSubtaskCount,
                                  key: const ValueKey('subtask-count'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
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
                              if (compactBlock && showPriorTitle)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (statusGlyph != null)
                                      const SizedBox(width: _StatusGlyph.width),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            planChange.previousTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: titleStyle?.copyWith(
                                              fontWeight: FontWeight.w400,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                          title,
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              else if (compactBlock)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (statusGlyph != null)
                                      const SizedBox(width: _StatusGlyph.width),
                                    Expanded(child: title),
                                    if (subtaskLabel != null) ...[
                                      const SizedBox(width: AppSpacing.xs),
                                      subtaskLabel,
                                    ],
                                  ],
                                )
                              else
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showPriorTitle)
                                      Text(
                                        planChange.previousTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: titleStyle?.copyWith(
                                          fontWeight: FontWeight.w400,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    // The count shares the title line so the
                                    // 12sp meta text still fits a 54 px card.
                                    if (subtaskLabel == null)
                                      title
                                    else
                                      Row(
                                        children: [
                                          Expanded(child: title),
                                          const SizedBox(width: AppSpacing.xs),
                                          subtaskLabel,
                                        ],
                                      ),
                                    if (subtaskLookupLoading &&
                                        !subtaskLookupError)
                                      const Align(
                                        alignment: Alignment.centerRight,
                                        child: SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                          ),
                                        ),
                                      ),
                                    if (lookupError != null)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Tooltip(
                                          message: lookupError,
                                          child: Icon(
                                            Icons.error_outline,
                                            size: 12,
                                            color: colorScheme.error,
                                          ),
                                        ),
                                      ),
                                    // Hidden when the card (at this text size) has no
                                    // room left for it.
                                    Flexible(
                                      // On touch the badge's tap area is 48 dp
                                      // high, or the height left under the title
                                      // when the block has less room.
                                      child: LayoutBuilder(
                                        builder: (context, room) =>
                                            _HideIfClipped(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: StatusBadge(
                                                      status: task.status,
                                                      onTap: onStatusTap,
                                                      tapHeight:
                                                          ResizableHandle
                                                              .isTouchPlatform
                                                          ? math.min(
                                                              StatusBadge
                                                                  .minTapSize,
                                                              room.maxHeight,
                                                            )
                                                          : 0,
                                                    ),
                                                  ),
                                                  // The duration is dropped when the
                                                  // lane is too narrow to hold both.
                                                  if (durationLabel != null &&
                                                      constraints.maxWidth >=
                                                          128)
                                                    durationLabel,
                                                ],
                                              ),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Added after the title so a tap near the glyph
                              // reaches it before the title beside it.
                              if (statusGlyph != null)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: _StatusGlyph.width,
                                  child: statusGlyph,
                                ),
                              // Narrow lanes drop the icon: the stripes and amber
                              // outline still mark the overlap and the icon would
                              // cover the end of the title.
                              if (hasOverlap && !narrowLane)
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
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Hover state for one block, kept in its own small State so a pointer
/// entering or leaving rebuilds only the fill, never the timeline.
class _HoverFill extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered, Widget child)
  builder;
  final Widget child;

  const _HoverFill({required this.builder, required this.child});

  @override
  State<_HoverFill> createState() => _HoverFillState();
}

class _HoverFillState extends State<_HoverFill> {
  bool _hovered = false;

  void _set(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: widget.builder(context, _hovered, widget.child),
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

/// The status mark of a compact card, which has no room for the badge: a
/// check for Completed, a play mark for In Progress, a clock for Rescheduled.
/// It is also the tap-to-cycle control, with a 48 dp tap area where the card
/// is large enough to pass taps through.
class _StatusGlyph extends StatelessWidget {
  static const double width = 24;

  final TaskStatus status;
  final VoidCallback? onTap;

  const _StatusGlyph({required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = StatusBadge.colorFor(AppThemeTokens.of(context), status);
    final glyph = SizedBox(
      key: ValueKey('compact-status-${status.name}'),
      width: width,
      child: Center(
        child: Icon(StatusBadge.iconFor(status), size: 16, color: color),
      ),
    );
    if (onTap == null) {
      return Semantics(
        label: 'Status: ${status.label}',
        excludeSemantics: true,
        child: glyph,
      );
    }
    return MinTapTarget(
      child: Semantics(
        button: true,
        label: 'Status: ${status.label}',
        hint: 'Change status',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: glyph,
        ),
      ),
    );
  }
}

/// Shows [child] only when it fits the height it is offered, and otherwise
/// takes no space and paints nothing. Used for the status row of a card, which
/// must give way to the title at large text sizes.
class _HideIfClipped extends SingleChildRenderObjectWidget {
  const _HideIfClipped({required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHideIfClipped();
}

class _RenderHideIfClipped extends RenderProxyBox {
  bool _fits = true;

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(
      constraints.copyWith(maxHeight: double.infinity),
      parentUsesSize: true,
    );
    _fits =
        !constraints.hasBoundedHeight ||
        child.size.height <= constraints.maxHeight + 0.01;
    size = constraints.constrain(
      _fits ? child.size : Size(child.size.width, 0),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child!.getDryLayout(
      constraints.copyWith(maxHeight: double.infinity),
    );
    final fits =
        !constraints.hasBoundedHeight ||
        childSize.height <= constraints.maxHeight + 0.01;
    return constraints.constrain(fits ? childSize : Size(childSize.width, 0));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_fits) super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _fits && super.hitTestChildren(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_fits) super.visitChildrenForSemantics(visitor);
  }
}
