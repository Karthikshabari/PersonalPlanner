import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/category.dart';
import '../../../../core/models/inbox_item.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_day_axis.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/utils/uuid.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/task_block_widget.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../task_editor/providers/subtask_providers.dart';
import '../../../sync/providers/sync_providers.dart';
import '../../domain/commands/move_task_command.dart';
import '../../domain/commands/resize_task_command.dart';
import '../../domain/commands/scheduling_command.dart';
import '../../domain/conflict_detector.dart';
import '../../domain/scheduled_task_draft.dart';
import '../../domain/snap_to_grid.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/day_view_controller.dart';
import '../providers/grid_settings_provider.dart';
import '../providers/overlap_flags_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../providers/timeline_action_provider.dart';
import 'current_time_indicator.dart';
import 'draggable_task_block.dart';
import 'ghost_preview.dart';
import 'resizable_handle.dart';
import 'task_context_menu.dart';
import 'task_block_motion.dart';
import 'task_quick_create.dart';
import 'timeline_hour_grid.dart';
import 'timeline_overlap_action.dart';
import '../../domain/timeline_geometry.dart';

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
  final void Function(Task task)? onEditTask;

  const TimelineWidget({super.key, this.onTaskTap, this.onEditTask});

  @override
  ConsumerState<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends ConsumerState<TimelineWidget> {
  late final ScrollController _scrollController;
  int? _quickCreateSlot;
  _DragPreview? _drag;
  _ResizePreview? _resize;
  final _removedTasks = <String, Task>{};
  final _removalTimers = <String, Timer>{};
  bool _quickCreateOpening = false;

  double get _pixelsPerMinute => AppConstants.pixelsPerMinute;

  PlannerDayAxis get _dayAxis => PlannerDayAxis(ref.read(selectedDateProvider));

  double get _totalHeight =>
      _dayAxis.durationMinutes * _pixelsPerMinute + AppSpacing.huge;

  int get _gridMinutes =>
      ref.watch(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _initialOffset());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrentTime();
    });
  }

  double _initialOffset() {
    final selectedDate = ref.read(selectedDateProvider);
    final now = DateTime.now();
    final anchorMinutes = isSameDay(selectedDate, now)
        ? (_dayAxis.elapsedMinutes(now) - 90).toDouble()
        : (7 * Duration.minutesPerHour).toDouble();
    return _anchorOffset(anchorMinutes).clamp(0.0, _maxScrollExtent());
  }

  double _anchorOffset(double minutes) =>
      minutes * _pixelsPerMinute - AppConstants.hourRowHeight * 1.5;

  double _maxScrollExtent() => _totalHeight - AppConstants.hourRowHeight * 6;

  @override
  void dispose() {
    for (final timer in _removalTimers.values) {
      timer.cancel();
    }
    _removalTimers.clear();
    _scrollController.dispose();
    super.dispose();
  }

  List<Task> _currentTasks() =>
      ref.read(activeDayTasksProvider).value ?? const <Task>[];

  void _scrollToCurrentTime() {
    final selectedDate = ref.read(selectedDateProvider);
    final now = DateTime.now();
    if (!_scrollController.hasClients || !isSameDay(selectedDate, now)) {
      return;
    }
    _scrollToMinutes((_dayAxis.elapsedMinutes(now) - 90).round());
  }

  void _scrollToMinutes(int minutes) {
    if (!_scrollController.hasClients) return;
    final target = _anchorOffset(minutes.toDouble())
        .clamp(0.0, _maxScrollExtent())
        .toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  // ------------------------------------------------------------------
  // Quick create (routed through the command history for undo support)
  // ------------------------------------------------------------------

  Future<void> _showQuickCreate(int slot) async {
    if (_quickCreateOpening || !mounted) return;
    _quickCreateOpening = true;
    final grid = _gridMinutes;
    final start = _dayAxis.instantAt(slot.toDouble());
    final end = start.add(Duration(minutes: grid));
    final taskId = generateUuidV7();
    final desktop =
        MediaQuery.sizeOf(context).width >= AppConstants.desktopBreakpoint;
    Future<bool> submit(ScheduledTaskDraft draft) async {
      final saved = await TimelineActions.createScheduledTask(
        context,
        ref,
        draft,
      );
      if (saved == null || !mounted) return false;
      ref.read(selectedDateProvider.notifier).state = startOfDay(
        saved.startTime!,
      );
      ref.read(selectedTaskIdProvider.notifier).state = saved.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToMinutes(slot);
      });
      return true;
    }

    try {
      final route = desktop
          ? showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: TaskQuickCreate(
                    taskId: taskId,
                    initialStart: start,
                    initialEnd: end,
                    onSubmit: submit,
                    onCancel: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            )
          : showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              isDismissible: false,
              enableDrag: false,
              useSafeArea: true,
              builder: (sheetContext) => Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: TaskQuickCreate(
                  taskId: taskId,
                  initialStart: start,
                  initialEnd: end,
                  onSubmit: submit,
                  onCancel: () => Navigator.of(sheetContext).pop(),
                ),
              ),
            );
      await route;
    } finally {
      _quickCreateOpening = false;
    }
  }

  void _requestQuickCreateAtCurrentTime() {
    final grid = _gridMinutes;
    final date = ref.read(selectedDateProvider);
    final now = DateTime.now();
    final raw = isSameDay(date, now)
        ? _dayAxis.elapsedMinutes(now).round()
        : 9 * Duration.minutesPerHour;
    setState(
      () => _quickCreateSlot = snapSlotStart(
        raw,
        grid,
      ).clamp(0, _dayAxis.durationMinutes - grid),
    );
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_quickCreateSlot != null || _drag != null || _resize != null) return;
    final tasks = _currentTasks();
    // The gesture detector wraps the scroll viewport, so the tapped content
    // position is the local y plus the current scroll offset.
    final contentY = details.localPosition.dy + _scrollController.offset;
    final rawMinutes = contentY / _pixelsPerMinute;
    final snapped = snapSlotStart(
      rawMinutes.round(),
      _gridMinutes,
    ).clamp(0, _dayAxis.durationMinutes - _gridMinutes);
    final slotEnd = snapped + _gridMinutes;
    for (final task in tasks) {
      final visibleTask = _clipTaskToSelectedDay(task);
      final s = visibleTask.startTime == null
          ? 0.0
          : _dayAxis.elapsedMinutes(visibleTask.startTime!);
      final e = visibleTask.endTime == null
          ? s + _gridMinutes
          : _dayAxis.elapsedMinutes(visibleTask.endTime!);
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
        // Keep the original interval in the selected day's coordinate
        // system. A continuation segment therefore starts before 00:00
        // instead of being mistaken for a midnight-origin task.
        origStartMinutes: _minutesFromSelectedDay(task.startTime!),
        durationMinutes: _elapsedDurationMinutes(task),
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
    var newStartMin = snapSlotStart(drag.origStartMinutes + deltaMinutes, grid);
    final earliestStart = drag.durationMinutes >= _dayAxis.durationMinutes
        ? -(drag.durationMinutes - grid)
        : 0;
    final latestStart = drag.durationMinutes < _dayAxis.durationMinutes
        ? _dayAxis.durationMinutes - drag.durationMinutes
        : _dayAxis.durationMinutes - grid;
    newStartMin = newStartMin.clamp(
      earliestStart,
      latestStart > earliestStart ? latestStart : earliestStart,
    );
    if (newStartMin == drag.origStartMinutes) return; // no effective change

    final newStart = _dayAxis.instantAt(newStartMin.toDouble());
    final newEnd = newStart.add(Duration(minutes: drag.durationMinutes));
    final primary = MoveTaskCommand(
      repository: ref.read(taskRepositoryProvider),
      original: drag.task,
      newStart: newStart,
      newEnd: newEnd,
    );
    final hypothetical = drag.task.copyWith(
      startTime: newStart,
      endTime: newEnd,
    );
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
        origStartMinutes: _minutesFromSelectedDay(task.startTime!),
        origDurationMinutes: _elapsedDurationMinutes(task),
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
    final newDuration = snapDuration(
      resize.origDurationMinutes + deltaMinutes,
      grid,
    ).clamp(grid, 10000);
    if (newDuration == resize.origDurationMinutes) return; // no change

    final newStart = resize.task.startTime!;
    final newEnd = newStart.add(Duration(minutes: newDuration));
    final primary = ResizeTaskCommand(
      repository: ref.read(taskRepositoryProvider),
      original: resize.task,
      newEnd: newEnd,
    );
    final hypothetical = resize.task.copyWith(endTime: newEnd);
    await _resolveConflictsAndCommit(primary, hypothetical);
  }

  void _resizeBySemantic(Task task, int deltaMinutes) {
    if (task.startTime == null || task.endTime == null) return;
    final newEnd = task.endTime!.add(Duration(minutes: deltaMinutes));
    if (!newEnd.isAfter(task.startTime!)) return;
    final primary = ResizeTaskCommand(
      repository: ref.read(taskRepositoryProvider),
      original: task,
      newEnd: newEnd,
    );
    unawaited(
      _resolveConflictsAndCommit(primary, task.copyWith(endTime: newEnd)),
    );
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
  ) => TimelineActions.commitScheduledChange(
    context,
    ref,
    primary: primary,
    hypothetical: hypothetical,
    anchorDate: ref.read(selectedDateProvider),
  );

  // ------------------------------------------------------------------
  // Status cycling
  // ------------------------------------------------------------------

  void _cycleStatus(Task task) {
    final next = StatusBadge.nextStatus(task.status);
    if (next == task.status) return;
    TimelineActions.setStatus(ref, task, next);
  }

  void _finishTaskRemoval(String taskId) {
    _removalTimers.remove(taskId)?.cancel();
    if (!mounted) return;
    setState(() => _removedTasks.remove(taskId));
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Task>>>(activeDayTasksProvider, (
      previous,
      next,
    ) {
      final previousTasks = previous?.maybeWhen(
        data: (value) => value,
        orElse: () => null,
      );
      if (next.hasValue && previousTasks != null) {
        final liveIds = next.value!.map((task) => task.id).toSet();
        final removed = previousTasks.where(
          (task) => !liveIds.contains(task.id),
        );
        for (final task in removed) {
          _removalTimers.remove(task.id)?.cancel();
          _removedTasks[task.id] = task;
          _removalTimers[task.id] = Timer(
            const Duration(milliseconds: 220),
            () => _finishTaskRemoval(task.id),
          );
        }
        for (final task in next.value!) {
          _removalTimers.remove(task.id)?.cancel();
          _removedTasks.remove(task.id);
        }
        if (removed.isNotEmpty && mounted) setState(() {});
      }
    });
    ref.listen<int?>(timelineQuickCreateSlotProvider, (_, next) {
      if (next == null || !mounted) return;
      setState(() => _quickCreateSlot = next);
      ref.read(timelineQuickCreateSlotProvider.notifier).state = null;
    });
    ref.listen<int>(timelineCancelRequestProvider, (_, _) {
      if (!mounted) return;
      _cancelDrag();
      _cancelResize();
    });
    ref.listen<DateTime>(selectedDateProvider, (_, _) {
      for (final timer in _removalTimers.values) {
        timer.cancel();
      }
      _removalTimers.clear();
      _removedTasks.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentTime();
      });
    });
    final selectedDate = ref.watch(selectedDateProvider);
    final gridAsync = ref.watch(gridIntervalProvider);
    // Keep the canonical day stream alive for command/history consumers as
    // well as the active calendar projection. The latter intentionally
    // filters rescheduled predecessors, while repositories and tests still
    // observe the complete persisted day list.
    ref.watch(dayTasksProvider);
    final tasksAsync = ref.watch(activeDayTasksProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final subtaskCountsAsync = ref.watch(subtaskCountsProvider);
    if (gridAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(gridAsync.error!),
        onRetry: () => ref.invalidate(gridIntervalProvider),
      );
    }
    if (!gridAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tasksAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(tasksAsync.error!),
        onRetry: () => ref.invalidate(activeDayTasksProvider),
      );
    }
    if (!tasksAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (categoriesAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(categoriesAsync.error!),
        onRetry: () => ref.invalidate(categoriesProvider),
      );
    }
    if (!categoriesAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (subtaskCountsAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(subtaskCountsAsync.error!),
        onRetry: () => ref.invalidate(subtaskCountsProvider),
      );
    }
    if (!subtaskCountsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final subtaskCounts = subtaskCountsAsync.requireValue;
    final selectedTaskId = ref.watch(selectedTaskIdProvider);
    final keepFlags = ref.watch(keepOverlapIdsProvider);
    final grid = _gridMinutes;
    final now = DateTime.now();
    final showNowLine = isSameDay(selectedDate, now);

    final liveTasks = tasksAsync.requireValue;
    final liveIds = liveTasks.map((task) => task.id).toSet();
    final tasks = [
      ...liveTasks,
      for (final task in _removedTasks.values)
        if (!liveIds.contains(task.id)) task,
    ];
    final categories = categoriesAsync.requireValue;

    Category? categoryFor(Task task) {
      for (final c in categories) {
        if (c.id == task.categoryId) return c;
      }
      return null;
    }

    // Data-driven overlap ids merged with runtime keep-overlap flags.
    final overlapIds = {
      ...ConflictDetector.overlappingIdSet(liveTasks),
      ...keepFlags,
    };
    final overlapIndex = ConflictDetector.overlapLanes(liveTasks);
    final geometryById = {
      for (final geometry in TimelineGeometry.layoutForDay(
        tasks: tasks,
        date: selectedDate,
        pixelsPerMinute: _pixelsPerMinute,
      ))
        geometry.task.id: geometry,
    };

    final dragTaskId = _drag?.task.id;
    final resizeTaskId = _resize?.task.id;

    final requestedQuickCreate = ref.watch(timelineQuickCreateSlotProvider);
    if (requestedQuickCreate != null &&
        _quickCreateSlot != requestedQuickCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _quickCreateSlot == requestedQuickCreate) return;
        setState(() => _quickCreateSlot = requestedQuickCreate);
        ref.read(timelineQuickCreateSlotProvider.notifier).state = null;
      });
    }
    if (_quickCreateSlot != null && !_quickCreateOpening) {
      final slot = _quickCreateSlot!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _quickCreateSlot != slot || _quickCreateOpening) {
          return;
        }
        setState(() => _quickCreateSlot = null);
        unawaited(_showQuickCreate(slot));
      });
    }

    Future<void> refreshSync() async {
      final engine = ref.read(syncEngineProvider);
      if (engine == null) return;
      await engine.syncNow();
    }

    return DragTarget<InboxItem>(
      onWillAcceptWithDetails: (_) {
        return true;
      },
      onAcceptWithDetails: (details) =>
          _handleInboxDrop(details.data, details.offset),
      builder: (context, candidateItems, rejectedItems) => GestureDetector(
        key: const ValueKey('timeline-gestures'),
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: () {},
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: refreshSync,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: ColoredBox(
                  color: AppThemeTokens.of(context).canvas,
                  child: SizedBox(
                    height: _totalHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final laneWidth =
                            (constraints.maxWidth -
                                    AppConstants.hourLabelWidth -
                                    8 -
                                    AppSpacing.md)
                                .clamp(1.0, double.infinity)
                                .toDouble();
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildHourGrid(context, grid),
                            for (final task in tasks)
                              _buildPositionedBlock(
                                context,
                                task,
                                categoryFor(task),
                                selectedTaskId == task.id,
                                geometry: geometryById[task.id],
                                allTasks: tasks,
                                availableLaneWidth: laneWidth,
                                overlapIndex: overlapIndex[task.id] ?? 0,
                                hasOverlap:
                                    overlapIds.contains(task.id) ||
                                    (geometryById[task.id]?.hasOverlap ??
                                        false),
                                groupedSubtaskCount: subtaskCountsAsync.hasValue
                                    ? subtaskCounts[task.id] ?? ''
                                    : '',
                                // While being dragged the SAME subtree stays mounted
                                // (the gesture must survive); only its opacity drops.
                                dimmed: task.id == dragTaskId,
                                removing: !liveIds.contains(task.id),
                                overrideHeightMinutes: task.id == resizeTaskId
                                    ? _liveResizeMinutes
                                    : null,
                              ),
                            if (_drag != null)
                              GhostPreview(
                                title: _drag!.task.title,
                                topPx:
                                    (_drag!.origStartMinutes *
                                                _pixelsPerMinute +
                                            _drag!.deltaPx)
                                        .clamp(
                                          -(_drag!.durationMinutes -
                                                      _gridMinutes)
                                                  .clamp(
                                                    0,
                                                    _dayAxis.durationMinutes,
                                                  ) *
                                              _pixelsPerMinute,
                                          _totalHeight -
                                              _gridMinutes * _pixelsPerMinute,
                                        ),
                                heightPx:
                                    _drag!.durationMinutes * _pixelsPerMinute,
                                left: AppConstants.hourLabelWidth + 8,
                                right: AppSpacing.md,
                                accentColor: _accentColor(
                                  categoryFor(_drag!.task),
                                ),
                                durationMinutes: _drag!.durationMinutes,
                              ),
                            if (showNowLine)
                              CurrentTimeIndicator(
                                pixelsPerMinute: _pixelsPerMinute,
                                day: ref.read(selectedDateProvider),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (liveTasks.isEmpty && _quickCreateSlot == null)
              Positioned.fill(
                child: _EmptyDayState(onAdd: _requestQuickCreateAtCurrentTime),
              ),
          ],
        ),
      ),
    );
  }

  /// Handles a drop from the Inbox (Flows 5 & 6): explicit items are
  /// scheduled at the snapped drop position; overdue items are rescheduled
  /// (original → rescheduled, linked copy created).
  Future<void> _handleInboxDrop(InboxItem item, Offset globalPosition) async {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final grid = _gridMinutes;
    final contentY = (local.dy + _scrollController.offset).clamp(
      0.0,
      _totalHeight,
    );
    var minutes = (contentY / _pixelsPerMinute).round();
    minutes = ((minutes / grid).round()) * grid;
    minutes = minutes.clamp(0, _dayAxis.durationMinutes - grid);

    final date = ref.read(selectedDateProvider);
    final start = _dayAxis.instantAt(minutes.toDouble());
    if (!isSameDay(start, date)) return;
    final end = start.add(Duration(minutes: grid));

    final committed = await TimelineActions.showInboxSchedulingForm(
      context,
      ref,
      item,
      start,
      end,
    );
    if (!committed || !mounted) return;
    if (item.isOverdue) {
      showAppToast(
        context,
        'Rescheduled to ${start.hour}:${start.minute.toString().padLeft(2, '0')}',
      );
    } else {
      showAppToast(context, 'Scheduled');
    }
  }

  Color _accentColor(Category? category) => category == null
      ? AppColors.primary
      : AppColors.parseHex(category.colorHex);

  Widget _buildHourGrid(BuildContext context, int gridMinutes) {
    return TimelineHourGrid(
      date: ref.read(selectedDateProvider),
      gridMinutes: gridMinutes,
      pixelsPerMinute: _pixelsPerMinute,
      rulerWidth: AppConstants.hourLabelWidth,
    );
  }

  Widget _buildPositionedBlock(
    BuildContext context,
    Task task,
    Category? category,
    bool selected, {
    TimelineTaskGeometry? geometry,
    required List<Task> allTasks,
    required double availableLaneWidth,
    required int overlapIndex,
    required bool hasOverlap,
    required bool dimmed,
    required String groupedSubtaskCount,
    required bool removing,
    double? overrideHeightMinutes,
  }) {
    final previewTask = overrideHeightMinutes == null || task.startTime == null
        ? task
        : task.copyWith(
            endTime: task.startTime!.add(
              Duration(minutes: overrideHeightMinutes.round()),
            ),
          );
    final displayGeometry = overrideHeightMinutes == null
        ? geometry
        : TimelineGeometry.layoutForDay(
            tasks: [previewTask],
            date: ref.read(selectedDateProvider),
            pixelsPerMinute: _pixelsPerMinute,
          ).firstOrNull;
    if (displayGeometry == null) return const SizedBox.shrink();
    final startMinutes = displayGeometry.topPx / _pixelsPerMinute;
    final height = displayGeometry.heightPx.clamp(
      1.0,
      _totalHeight - displayGeometry.topPx,
    );
    final visualHeight = height.toDouble();
    final renderedHeight = ResizableHandle.isTouchPlatform
        ? visualHeight
              .clamp(ResizableHandle.touchTargetHeight, double.infinity)
              .toDouble()
        : visualHeight;
    final outerTop = ResizableHandle.isTouchPlatform
        ? (startMinutes * _pixelsPerMinute -
                  (renderedHeight - visualHeight) / 2)
              .clamp(0.0, double.infinity)
              .toDouble()
        : startMinutes * _pixelsPerMinute;
    final visualTop = startMinutes * _pixelsPerMinute - outerTop;
    final laneCount = displayGeometry.laneCount;
    final laneIndex = displayGeometry.laneIndex;
    final laneWidth = availableLaneWidth / laneCount;
    final dense =
        displayGeometry.hasOverlap &&
        laneWidth < 84 * MediaQuery.textScalerOf(context).scale(1);

    final block = Stack(
      fit: StackFit.expand,
      children: [
        TaskBlockWidget(
          task: task,
          geometry: displayGeometry,
          category: category,
          selected: selected,
          hasOverlap: hasOverlap,
          groupedSubtaskCount: groupedSubtaskCount,
          onTap: () {
            ref.read(selectedTaskIdProvider.notifier).state = task.id;
            widget.onTaskTap?.call(task);
          },
          onStatusTap: () => _cycleStatus(task),
        ),
        // Bottom-edge resize handle overlays the block content.
        if (!ResizableHandle.isTouchPlatform || selected)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: ResizableHandle.isTouchPlatform
                ? ResizableHandle.touchTargetHeight
                      .clamp(12, visualHeight)
                      .toDouble()
                : AppConstants.resizeHandleHeight,
            child: ResizableHandle(
              onResizeStart: () => _startResize(task),
              onResizeUpdate: _updateResize,
              onResizeEnd: _endResize,
              onResizeCancel: _cancelResize,
              onIncrease: () => _resizeBySemantic(task, _gridMinutes),
              onDecrease: () => _resizeBySemantic(task, -_gridMinutes),
            ),
          ),
        if (dense && laneIndex == 0)
          Positioned.fill(
            child: TimelineOverlapAction(
              geometry: displayGeometry,
              tasks: allTasks,
              date: ref.read(selectedDateProvider),
              onOpen: (openedTask) {
                ref.read(selectedTaskIdProvider.notifier).state = openedTask.id;
                widget.onTaskTap?.call(openedTask);
              },
            ),
          ),
      ],
    );

    void selectTask() {
      ref.read(selectedTaskIdProvider.notifier).state = task.id;
      widget.onTaskTap?.call(task);
    }

    final dragChild = ResizableHandle.isTouchPlatform
        ? Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: selectTask,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: visualTop,
                left: 0,
                right: 0,
                height: visualHeight,
                child: block,
              ),
            ],
          )
        : block;

    final interactiveBlock = IgnorePointer(
      ignoring: removing,
      child: DraggableTaskBlock(
        onDragStart: () => _startDrag(task),
        onDragUpdate: _updateDrag,
        onDragEnd: _endDrag,
        onDragCancel: _cancelDrag,
        onContextMenuRequested: (position) => showTaskContextMenu(
          context,
          ref,
          task,
          position,
          onEdit: () => widget.onEditTask?.call(task),
        ),
        child: dimmed ? Opacity(opacity: 0.35, child: dragChild) : dragChild,
      ),
    );

    return Positioned(
      key: ValueKey('task-block-${task.id}'),
      top: outerTop + 1,
      left: AppConstants.hourLabelWidth + 8 + laneWidth * laneIndex + 2,
      width: (laneWidth - 4).clamp(2.0, double.infinity).toDouble(),
      height: renderedHeight,
      child: TaskBlockMotion(
        isDragging: !removing && task.id == _drag?.task.id,
        isRemoving: removing,
        onRemoved: () => _finishTaskRemoval(task.id),
        child: interactiveBlock,
      ),
    );
  }

  /// A task may span midnight, but each day view paints only the portion that
  /// intersects the selected local calendar day. The original task remains
  /// attached to command callbacks so persistence and scheduling semantics do
  /// not change.
  Task _clipTaskToSelectedDay(Task task) {
    final start = task.startTime;
    final end = task.endTime;
    if (start == null || end == null) return task;
    final dayStart = startOfDay(ref.read(selectedDateProvider));
    final dayEnd = addDays(dayStart, 1);
    final clippedStart = start.isBefore(dayStart) ? dayStart : start;
    final clippedEnd = end.isAfter(dayEnd) ? dayEnd : end;
    if (clippedStart == start && clippedEnd == end) return task;
    return task.copyWith(startTime: clippedStart, endTime: clippedEnd);
  }

  int _minutesFromSelectedDay(DateTime instant) {
    final selected = PlannerTimeZone.toPlannerLocal(
      ref.read(selectedDateProvider),
    );
    final local = PlannerTimeZone.toPlannerLocal(instant);
    final selectedDate = DateTime.utc(
      selected.year,
      selected.month,
      selected.day,
    );
    final taskDate = DateTime.utc(local.year, local.month, local.day);
    final dayDelta = taskDate.difference(selectedDate).inDays;
    if (dayDelta == 0) return _dayAxis.elapsedMinutes(instant).round();
    return dayDelta * minutesPerDay +
        local.hour * Duration.minutesPerHour +
        local.minute;
  }

  int _elapsedDurationMinutes(Task task) {
    if (task.startTime == null || task.endTime == null) {
      return task.scheduledDuration?.inMinutes ?? _gridMinutes;
    }
    return task.endTime!.difference(task.startTime!).inMinutes;
  }
}

class _EmptyDayState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyDayState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Center(
        child: TextButton.icon(
          key: const ValueKey('empty-day-add'),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add block'),
        ),
      ),
    );
  }
}
