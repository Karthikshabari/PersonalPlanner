import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/category.dart';
import '../../../../core/models/enums/task_status.dart';
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
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/task_block_widget.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../inbox/domain/inbox_commands.dart';
import '../../../inbox/providers/inbox_provider.dart';
import '../../../task_editor/providers/subtask_providers.dart';
import '../../../sync/providers/sync_providers.dart';
import '../../domain/commands/create_task_command.dart';
import '../../domain/commands/batch_command.dart';
import '../../domain/commands/move_task_command.dart';
import '../../domain/commands/resize_task_command.dart';
import '../../domain/commands/scheduling_command.dart';
import '../../domain/conflict_detector.dart';
import '../../domain/conflict_resolver.dart';
import '../../domain/scheduling_conflict_service.dart';
import '../../domain/snap_to_grid.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/day_view_controller.dart';
import '../providers/grid_settings_provider.dart';
import '../providers/overlap_flags_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../providers/timeline_action_provider.dart';
import '../providers/undo_stack_provider.dart';
import 'conflict_resolution_dialog.dart';
import 'current_time_indicator.dart';
import 'draggable_task_block.dart';
import 'ghost_preview.dart';
import 'resizable_handle.dart';
import 'task_context_menu.dart';
import 'task_block_motion.dart';
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
  final _removedTasks = <String, Task>{};
  final _removalTimers = <String, Timer>{};

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
      ref.read(dayTasksProvider).value ?? const <Task>[];

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

  Future<void> _createQuickTask(String title) async {
    final slot = _quickCreateSlot;
    if (slot == null) return;
    setState(() => _quickCreateSlot = null);
    final start = _dayAxis.instantAt(slot.toDouble());
    final end = start.add(Duration(minutes: _gridMinutes));
    final now = DateTime.now();
    final task = Task(
      id: generateUuidV7(),
      title: title,
      startTime: start,
      endTime: end,
      estimatedDurationMin: _gridMinutes,
      status: TaskStatus.planned,
      isInbox: false,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _resolveConflictsAndCommit(
        CreateTaskCommand(ref.read(taskRepositoryProvider), task),
        task,
      );
      if (mounted) _scrollToMinutes(slot);
    } catch (error) {
      if (mounted) showAppToast(context, friendlyErrorMessage(error));
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
  ) async {
    final tasks = hypothetical.startTime != null && hypothetical.endTime != null
        ? await _loadSchedulingCandidates(hypothetical)
        : _currentTasks();
    final conflicts = SchedulingConflictService.conflicts(hypothetical, tasks);
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
        final plan = SchedulingConflictService.plan(
          proposed: hypothetical,
          candidates: tasks,
          resolution: choice,
          maxCascadeDepth: AppConstants.maxCascadeDepth,
        );
        clearOverlapFlags();
        await historyNotifier.execute(
          BatchCommand([primary, ..._shiftCommands(plan.shifts, tasks)]),
        );
        return true;

      case ConflictResolution.shiftOnlyOverlapping:
        final plan = SchedulingConflictService.plan(
          proposed: hypothetical,
          candidates: tasks,
          resolution: choice,
          maxCascadeDepth: AppConstants.maxCascadeDepth,
        );
        clearOverlapFlags();
        await historyNotifier.execute(
          BatchCommand([primary, ..._shiftCommands(plan.shifts, tasks)]),
        );
        if (plan.keepOverlapIds.isNotEmpty && mounted) {
          ref.read(keepOverlapIdsProvider.notifier).state = {
            ...plan.keepOverlapIds,
            hypothetical.id,
          };
        }
        return true;
    }
  }

  Future<List<Task>> _loadSchedulingCandidates(Task hypothetical) {
    return SchedulingConflictService.loadCandidates(
      ref.read(taskRepositoryProvider),
      hypothetical,
      anchorDate: ref.read(selectedDateProvider),
    );
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
      commands.add(
        MoveTaskCommand(
          repository: ref.read(taskRepositoryProvider),
          original: original,
          newStart: shift.newStart,
          newEnd: shift.newEnd,
        ),
      );
    }
    return commands;
  }

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
    ref.listen<AsyncValue<List<Task>>>(dayTasksProvider, (previous, next) {
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
      final selectedId = ref.read(selectedTaskIdProvider);
      if (selectedId == null || !next.hasValue) return;
      final stillVisible = next.value!.any(
        (task) => task.id == selectedId && task.deletedAt == null,
      );
      if (!stillVisible) {
        ref.read(selectedTaskIdProvider.notifier).state = null;
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
    final tasksAsync = ref.watch(dayTasksProvider);
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
        onRetry: () => ref.invalidate(dayTasksProvider),
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

    Future<void> refreshSync() async {
      final engine = ref.read(syncEngineProvider);
      if (engine == null) return;
      await engine.syncNow();
    }

    return DragTarget<InboxItem>(
      onWillAcceptWithDetails: (_) => true,
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
                                (_drag!.origStartMinutes * _pixelsPerMinute +
                                        _drag!.deltaPx)
                                    .clamp(
                                      -(_drag!.durationMinutes - _gridMinutes)
                                              .clamp(
                                                0,
                                                _dayAxis.durationMinutes,
                                              ) *
                                          _pixelsPerMinute,
                                      _totalHeight -
                                          _gridMinutes * _pixelsPerMinute,
                                    ),
                            heightPx: _drag!.durationMinutes * _pixelsPerMinute,
                            left: AppConstants.hourLabelWidth + 8,
                            right: AppSpacing.md,
                            accentColor: _accentColor(categoryFor(_drag!.task)),
                            durationMinutes: _drag!.durationMinutes,
                          ),
                        if (showNowLine)
                          CurrentTimeIndicator(
                            pixelsPerMinute: _pixelsPerMinute,
                            day: ref.read(selectedDateProvider),
                          ),
                        if (_quickCreateSlot != null)
                          TaskQuickCreate(
                            slotMinutes: _quickCreateSlot!,
                            onSubmit: (title) {
                              unawaited(_createQuickTask(title));
                            },
                            onCancel: () =>
                                setState(() => _quickCreateSlot = null),
                          ),
                      ],
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

    final repo = ref.read(inboxRepositoryProvider);
    late final SchedulingCommand command;
    late final Task hypothetical;
    if (item.isOverdue) {
      command = RescheduleOverdueCommand(
        repository: repo,
        originalId: item.task.id,
        start: start,
        end: end,
      );
      hypothetical = item.task.copyWith(
        id: 'reschedule-preview-${item.task.id}',
        startTime: start,
        endTime: end,
        actualDurationMin: null,
        status: TaskStatus.planned,
        recurringRuleId: item.task.recurringRuleId,
        rescheduledFromId: item.task.id,
        rescheduledToId: null,
        missedAt: null,
      );
    } else {
      command = ScheduleInboxItemCommand(
        repository: repo,
        taskId: item.task.id,
        start: start,
        end: end,
      );
      hypothetical = item.task.copyWith(
        isInbox: false,
        startTime: start,
        endTime: end,
      );
    }
    final committed = await _resolveConflictsAndCommit(command, hypothetical);
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
    final tokens = AppThemeTokens.of(context);
    final lineColor = tokens.outline.withValues(alpha: 0.58);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final markers = _dayAxis.hourMarkers;
    return Column(
      children: [
        for (var index = 0; index < markers.length - 1; index++)
          Builder(
            builder: (context) {
              final marker = markers[index];
              final rowMinutes =
                  markers[index + 1].elapsedMinutes - marker.elapsedMinutes;
              return SizedBox(
                height: rowMinutes * _pixelsPerMinute,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: AppConstants.hourLabelWidth - 1,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: tokens.outline.withValues(alpha: 0.34),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: AppConstants.hourLabelWidth,
                      right: 0,
                      child: Divider(height: 1, thickness: 1, color: lineColor),
                    ),
                    for (
                      var m = gridMinutes;
                      m < 60 && m < rowMinutes;
                      m += gridMinutes
                    )
                      Positioned(
                        top: rowMinutes * _pixelsPerMinute * m / 60,
                        left: AppConstants.hourLabelWidth,
                        right: 0,
                        child: Divider(
                          height: 1,
                          thickness: 0.5,
                          color: lineColor.withValues(alpha: 0.42),
                        ),
                      ),
                    Positioned(
                      top: 2,
                      left: AppSpacing.sm,
                      child: Text(marker.label, style: labelStyle),
                    ),
                  ],
                ),
              );
            },
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
    final displayTask = _clipTaskToSelectedDay(previewTask);
    final startMinutes = displayTask.startTime == null
        ? 0.0
        : _dayAxis.elapsedMinutes(displayTask.startTime!);
    final durationMinutes =
        displayTask.startTime == null || displayTask.endTime == null
        ? displayTask.estimatedDurationMin?.toDouble() ??
              AppConstants.defaultGridMinutes.toDouble()
        : (_dayAxis.elapsedMinutes(displayTask.endTime!) - startMinutes)
              .clamp(0, _dayAxis.durationMinutes)
              .toDouble();
    final height = (durationMinutes * _pixelsPerMinute).clamp(
      1.0,
      _totalHeight - startMinutes * _pixelsPerMinute,
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
    final leftOffset = overlapIndex * AppConstants.overlapOffsetPerIndex;

    final block = Stack(
      fit: StackFit.expand,
      children: [
        TaskBlockWidget(
          task: displayTask,
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
        onContextMenuRequested: (position) =>
            showTaskContextMenu(context, ref, task, position),
        child: dimmed ? Opacity(opacity: 0.35, child: dragChild) : dragChild,
      ),
    );

    return Positioned(
      key: ValueKey('task-block-${task.id}'),
      top: outerTop + 1,
      left: AppConstants.hourLabelWidth + 8 + leftOffset,
      right: AppSpacing.md,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppSurface(
            padding: const EdgeInsets.all(AppSpacing.xl),
            color: AppThemeTokens.of(context).surfaceRaised,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No tasks planned for this day',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tap + to add your first block',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey('empty-day-add'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add block'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
