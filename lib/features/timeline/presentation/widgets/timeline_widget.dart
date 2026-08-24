import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/category.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/task_block_widget.dart';
import '../../../categories/providers/category_providers.dart';
import '../../domain/commands/create_task_command.dart';
import '../../domain/commands/batch_command.dart';
import '../../domain/commands/move_task_command.dart';
import '../../domain/commands/resize_task_command.dart';
import '../../domain/commands/scheduling_command.dart';
import '../../domain/conflict_detector.dart';
import '../../domain/conflict_resolver.dart';
import '../../domain/snap_to_grid.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/grid_settings_provider.dart';
import '../providers/overlap_flags_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../providers/undo_stack_provider.dart';
import 'conflict_resolution_dialog.dart';
import 'current_time_indicator.dart';
import 'draggable_task_block.dart';
import 'ghost_preview.dart';
import 'resizable_handle.dart';
import 'task_context_menu.dart';
import 'task_quick_create.dart';

/// Live interaction previews held while a gesture is in progress.
class _DragPreview {
  final Task task;
  final int origStartMinutes;
  final int durationMinutes;
  double deltaPx;

  _DragPreview({
    required this.task,
    required this.origStartMinutes,
    required this.durationMinutes,
    required this.deltaPx,
  });
}

class _ResizePreview {
  final Task task;
  final int origStartMinutes;
  final int origDurationMinutes;
  double deltaPx;

  _ResizePreview({
    required this.task,
    required this.origStartMinutes,
    required this.origDurationMinutes,
    required this.deltaPx,
  });
}

class TimelineWidget extends ConsumerStatefulWidget {
  final void Function(Task task)? onTaskTap;

  const TimelineWidget({super.key, this.onTaskTap});

  @override
  ConsumerState<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends ConsumerState<TimelineWidget> {
  late final ScrollController _scrollController;
  int? _quickCreateSlot;
  _DragPreview? _drag;
  _ResizePreview? _resize;

  double get _pixelsPerMinute =>
      AppConstants.hourRowHeight / Duration.minutesPerHour;

  double get _totalHeight =>
      AppConstants.hourRowHeight * Duration.hoursPerDay + AppSpacing.huge;

  int get _gridMinutes => ref.watch(gridIntervalProvider).value ??
      AppConstants.defaultGridMinutes;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _initialOffset(),
    );
  }

  double _initialOffset() {
    final selectedDate = ref.read(selectedDateProvider);
    final now = DateTime.now();
    final anchorMinutes = isSameDay(selectedDate, now)
        ? (minutesSinceMidnight(now) - 90).toDouble()
        : (7 * Duration.minutesPerHour).toDouble();
    return _anchorOffset(anchorMinutes).clamp(0.0, _maxScrollExtent());
  }

  double _anchorOffset(double minutes) =>
      minutes * _pixelsPerMinute - AppConstants.hourRowHeight * 1.5;

  double _maxScrollExtent() => _totalHeight - AppConstants.hourRowHeight * 6;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Task> _currentTasks() =>
      ref.read(dayTasksProvider).value ?? const <Task>[];

  // ------------------------------------------------------------------
  // Quick create (routed through the command history for undo support)
  // ------------------------------------------------------------------

  void _createQuickTask(String title) {
    final slot = _quickCreateSlot;
    if (slot == null) return;
    setState(() => _quickCreateSlot = null);
    final day = ref.read(selectedDateProvider);
    final start = day.add(Duration(minutes: slot));
    final end = start.add(Duration(minutes: _gridMinutes));
    final now = DateTime.now();
    ref.read(undoStackProvider.notifier).execute(
          CreateTaskCommand(
            ref.read(taskRepositoryProvider),
            Task(
              id: '',
              title: title,
              startTime: start,
              endTime: end,
              estimatedDurationMin: _gridMinutes,
              status: TaskStatus.planned,
              isInbox: false,
              createdAt: now,
              updatedAt: now,
            ),
          ),
        );
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_quickCreateSlot != null || _drag != null || _resize != null) return;
    final tasks = _currentTasks();
    // The gesture detector wraps the scroll viewport, so the tapped content
    // position is the local y plus the current scroll offset.
    final contentY = details.localPosition.dy + _scrollController.offset;
    final rawMinutes = contentY / _pixelsPerMinute;
    final snapped = snapSlotStart(rawMinutes.round(), _gridMinutes);
    final slotEnd = snapped + _gridMinutes;
    for (final task in tasks) {
      final s = task.startTime == null
          ? 0
          : minutesSinceMidnight(task.startTime!);
      final e = s + (task.scheduledDuration?.inMinutes ?? _gridMinutes);
      if (snapped < e && slotEnd > s) return;
    }
    setState(() => _quickCreateSlot = snapped);
  }

  // ------------------------------------------------------------------
  // Move drag
  // ------------------------------------------------------------------

  void _startDrag(Task task) {
    if (_drag != null || _resize != null || task.startTime == null) return;
    setState(() {
      _drag = _DragPreview(
        task: task,
        origStartMinutes: minutesSinceMidnight(task.startTime!),
        durationMinutes:
            task.scheduledDuration?.inMinutes ?? _gridMinutes,
        deltaPx: 0,
      );
    });
  }

  void _updateDrag(double dyPx) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => drag.deltaPx = dyPx);
  }

  Future<void> _endDrag() async {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);

    final grid = _gridMinutes;
    final deltaMinutes = (drag.deltaPx / _pixelsPerMinute).round();
    final remaining = minutesPerDay - drag.durationMinutes;
    var newStartMin =
        snapSlotStart(drag.origStartMinutes + deltaMinutes, grid);
    newStartMin = newStartMin.clamp(0, remaining > 0 ? remaining : 0);
    if (newStartMin == drag.origStartMinutes) return; // no effective change

    final day = ref.read(selectedDateProvider);
    final newStart = day.add(Duration(minutes: newStartMin));
    final newEnd = newStart.add(Duration(minutes: drag.durationMinutes));
    final primary = MoveTaskCommand(
      repository: ref.read(taskRepositoryProvider),
      original: drag.task,
      newStart: newStart,
      newEnd: newEnd,
    );
    final hypothetical =
        drag.task.copyWith(startTime: newStart, endTime: newEnd);
    await _resolveConflictsAndCommit(primary, hypothetical);
  }

  // ------------------------------------------------------------------
  // Resize
  // ------------------------------------------------------------------

  void _startResize(Task task) {
    if (_drag != null ||
        _resize != null ||
        task.startTime == null ||
        task.endTime == null) {
      return;
    }
    setState(() {
      _resize = _ResizePreview(
        task: task,
        origStartMinutes: minutesSinceMidnight(task.startTime!),
        origDurationMinutes:
            task.scheduledDuration?.inMinutes ?? _gridMinutes,
        deltaPx: 0,
      );
    });
  }

  void _updateResize(double dyPx) {
    final resize = _resize;
    if (resize == null) return;
    setState(() => resize.deltaPx = dyPx);
  }

  Future<void> _endResize() async {
    final resize = _resize;
    if (resize == null) return;
    setState(() => _resize = null);

    final grid = _gridMinutes;
    final deltaMinutes = (resize.deltaPx / _pixelsPerMinute).round();
    final maxDur = minutesPerDay - resize.origStartMinutes;
    final newDuration =
        snapDuration(resize.origDurationMinutes + deltaMinutes, grid)
            .clamp(grid, maxDur > 0 ? maxDur : grid);
    if (newDuration == resize.origDurationMinutes) return; // no change

    final day = ref.read(selectedDateProvider);
    final newStart = day.add(Duration(minutes: resize.origStartMinutes));
    final newEnd = newStart.add(Duration(minutes: newDuration));
    final primary = ResizeTaskCommand(
      repository: ref.read(taskRepositoryProvider),
      original: resize.task,
      newEnd: newEnd,
    );
    final hypothetical = resize.task.copyWith(endTime: newEnd);
    await _resolveConflictsAndCommit(primary, hypothetical);
  }

  void _cancelDrag() {
    if (_drag == null) return;
    setState(() => _drag = null);
  }

  void _cancelResize() {
    if (_resize == null) return;
    setState(() => _resize = null);
  }

  /// Live duration (in minutes) of the block being resized — for rendering.
  double get _liveResizeMinutes {
    final resize = _resize!;
    final raw = resize.origDurationMinutes + resize.deltaPx / _pixelsPerMinute;
    return raw.clamp(8.0, double.infinity);
  }

  // ------------------------------------------------------------------
  // Conflict detection + resolution
  // ------------------------------------------------------------------

  /// Runs conflict detection for the hypothetical result of [primary] and
  /// either commits directly or asks the user how to resolve overlaps.
  /// Returns true when a command was committed to history.
  Future<bool> _resolveConflictsAndCommit(
    SchedulingCommand primary,
    Task hypothetical,
  ) async {
    final tasks = _currentTasks();
    final conflicts = ConflictDetector.detect(hypothetical, tasks);
    final historyNotifier = ref.read(undoStackProvider.notifier);

    void clearOverlapFlags() {
      ref.read(keepOverlapIdsProvider.notifier).state = const <String>{};
    }

    if (conflicts.isEmpty) {
      clearOverlapFlags();
      await historyNotifier.execute(primary);
      return true;
    }

    if (!mounted) return false;
    final choice = await showConflictResolutionDialog(
      context,
      droppedTask: hypothetical,
      conflicts: conflicts,
    );
    if (choice == null) return false; // Cancel — discard the operation.

    switch (choice) {
      case ConflictResolution.keepOverlap:
        clearOverlapFlags();
        await historyNotifier.execute(primary);
        if (!mounted) return true;
        ref.read(keepOverlapIdsProvider.notifier).state = {
          hypothetical.id,
          for (final c in conflicts) c.id,
        };
        return true;

      case ConflictResolution.shiftAllFollowing:
        final plan = ConflictResolver.planShiftAllFollowing(
          moved: hypothetical,
          dayTasks: tasks,
        );
        clearOverlapFlags();
        await historyNotifier.execute(BatchCommand([
          primary,
          ..._shiftCommands(plan.shifts, tasks),
        ]));
        return true;

      case ConflictResolution.shiftOnlyOverlapping:
        final plan = ConflictResolver.planShiftOnlyOverlapping(
          moved: hypothetical,
          dayTasks: tasks,
          maxCascadeDepth: AppConstants.maxCascadeDepth,
        );
        clearOverlapFlags();
        await historyNotifier.execute(BatchCommand([
          primary,
          ..._shiftCommands(plan.shifts, tasks),
        ]));
        if (plan.keepOverlapIds.isNotEmpty && mounted) {
          ref.read(keepOverlapIdsProvider.notifier).state = {
            ...plan.keepOverlapIds,
            hypothetical.id,
          };
        }
        return true;
    }
  }

  List<SchedulingCommand> _shiftCommands(
    List<PlannedShift> shifts,
    List<Task> tasks,
  ) {
    final byId = {for (final t in tasks) t.id: t};
    final commands = <SchedulingCommand>[];
    for (final shift in shifts) {
      final original = byId[shift.taskId];
      if (original == null) continue;
      commands.add(MoveTaskCommand(
        repository: ref.read(taskRepositoryProvider),
        original: original,
        newStart: shift.newStart,
        newEnd: shift.newEnd,
      ));
    }
    return commands;
  }

  // ------------------------------------------------------------------
  // Status cycling
  // ------------------------------------------------------------------

  void _cycleStatus(Task task) {
    final next = StatusBadge.nextStatus(task.status);
    ref.read(taskRepositoryProvider).updateTask(task.copyWith(status: next));
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final tasksAsync = ref.watch(dayTasksProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedTaskId = ref.watch(selectedTaskIdProvider);
    final keepFlags = ref.watch(keepOverlapIdsProvider);
    final grid = _gridMinutes;
    final now = DateTime.now();
    final showNowLine = isSameDay(selectedDate, now);

    final tasks =
        tasksAsync.maybeWhen(data: (t) => t, orElse: () => const <Task>[]);
    final categories = categoriesAsync.maybeWhen(
        data: (c) => c, orElse: () => const <Category>[]);

    Category? categoryFor(Task task) {
      for (final c in categories) {
        if (c.id == task.categoryId) return c;
      }
      return null;
    }

    // Data-driven overlap ids merged with runtime keep-overlap flags.
    final overlapIds = {
      ...ConflictDetector.overlappingIdSet(tasks),
      ...keepFlags,
    };
    // Offset index per overlapping block: how many other overlapped blocks
    // start at-or-before it. Drives the slight horizontal offset.
    final overlapIndex = <String, int>{};
    for (final task in tasks) {
      if (!overlapIds.contains(task.id)) continue;
      var idx = 0;
      for (final other in tasks) {
        if (other.id == task.id || !overlapIds.contains(other.id)) continue;
        if (_startsAtOrBefore(other, task)) idx++;
      }
      overlapIndex[task.id] = idx;
    }

    final dragTaskId = _drag?.task.id;
    final resizeTaskId = _resize?.task.id;

    return GestureDetector(
      key: const ValueKey('timeline-gestures'),
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: () {},
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: SizedBox(
              height: _totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildHourGrid(context, grid),
                  for (final task in tasks)
                    _buildPositionedBlock(
                      context,
                      task,
                      categoryFor(task),
                      selectedTaskId == task.id,
                      overlapIndex: overlapIndex[task.id] ?? 0,
                      hasOverlap: overlapIds.contains(task.id),
                      // While being dragged the SAME subtree stays mounted
                      // (the gesture must survive); only its opacity drops.
                      dimmed: task.id == dragTaskId,
                      overrideHeightMinutes:
                          task.id == resizeTaskId ? _liveResizeMinutes : null,
                    ),
                  if (_drag != null)
                    GhostPreview(
                      title: _drag!.task.title,
                      topPx: (_drag!.origStartMinutes * _pixelsPerMinute +
                              _drag!.deltaPx)
                          .clamp(
                              0.0,
                              _totalHeight -
                                  _drag!.durationMinutes *
                                      _pixelsPerMinute),
                      heightPx:
                          _drag!.durationMinutes * _pixelsPerMinute,
                      left: AppConstants.hourLabelWidth + 8,
                      right: AppSpacing.md,
                      accentColor: _accentColor(categoryFor(_drag!.task)),
                      durationMinutes: _drag!.durationMinutes,
                    ),
                  if (showNowLine)
                    CurrentTimeIndicator(pixelsPerMinute: _pixelsPerMinute),
                  if (_quickCreateSlot != null)
                    TaskQuickCreate(
                      slotMinutes: _quickCreateSlot!,
                      onSubmit: _createQuickTask,
                      onCancel: () => setState(() => _quickCreateSlot = null),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _startsAtOrBefore(Task a, Task b) =>
      a.startTime != null &&
      b.startTime != null &&
      !a.startTime!.isAfter(b.startTime!);

  Color _accentColor(Category? category) => category == null
      ? AppColors.primary
      : AppColors.parseHex(category.colorHex);

  Widget _buildHourGrid(BuildContext context, int gridMinutes) {
    final lineColor = Theme.of(context).dividerColor;
    final labelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      children: [
        for (var hour = 0; hour < Duration.hoursPerDay; hour++)
          SizedBox(
            height: AppConstants.hourRowHeight,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: AppConstants.hourLabelWidth,
                  right: 0,
                  child: Divider(height: 1, thickness: 1, color: lineColor),
                ),
                // Minor grid lines when the interval is finer than one hour.
                for (var m = gridMinutes; m < 60; m += gridMinutes)
                  Positioned(
                    top: AppConstants.hourRowHeight * m / 60,
                    left: AppConstants.hourLabelWidth,
                    right: 0,
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: lineColor.withValues(alpha: 0.45),
                    ),
                  ),
                Positioned(
                  top: 2,
                  left: AppSpacing.sm,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPositionedBlock(
    BuildContext context,
    Task task,
    Category? category,
    bool selected, {
    required int overlapIndex,
    required bool hasOverlap,
    required bool dimmed,
    double? overrideHeightMinutes,
  }) {
    final startMinutes =
        task.startTime == null ? 0 : minutesSinceMidnight(task.startTime!);
    final durationMinutes = overrideHeightMinutes ??
        (task.scheduledDuration?.inMinutes.toDouble() ??
            task.estimatedDurationMin?.toDouble() ??
            AppConstants.defaultGridMinutes.toDouble());
    const minHeight = 30.0;
    final height = (durationMinutes * _pixelsPerMinute)
        .clamp(minHeight, _totalHeight - startMinutes * _pixelsPerMinute);
    final leftOffset = overlapIndex * AppConstants.overlapOffsetPerIndex;

    final block = Stack(
      fit: StackFit.expand,
      children: [
        TaskBlockWidget(
          task: task,
          category: category,
          selected: selected,
          hasOverlap: hasOverlap,
          onTap: () {
            ref.read(selectedTaskIdProvider.notifier).state = task.id;
            widget.onTaskTap?.call(task);
          },
          onStatusTap: () => _cycleStatus(task),
        ),
        // Bottom-edge resize handle overlays the block content.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: AppConstants.resizeHandleHeight,
          child: ResizableHandle(
            onResizeStart: () => _startResize(task),
            onResizeUpdate: _updateResize,
            onResizeEnd: _endResize,
            onResizeCancel: _cancelResize,
          ),
        ),
      ],
    );

    return Positioned(
      key: ValueKey('task-block-${task.id}'),
      top: startMinutes * _pixelsPerMinute + 1,
      left: AppConstants.hourLabelWidth + 8 + leftOffset,
      right: AppSpacing.md,
      height: height - 2,
      child: DraggableTaskBlock(
        onDragStart: () => _startDrag(task),
        onDragUpdate: _updateDrag,
        onDragEnd: _endDrag,
        onDragCancel: _cancelDrag,
        onContextMenuRequested: (position) =>
            showTaskContextMenu(context, ref, task, position),
        child: dimmed ? Opacity(opacity: 0.35, child: block) : block,
      ),
    );
  }
}
