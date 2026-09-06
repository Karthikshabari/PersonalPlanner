import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/inbox_item.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../recurring/presentation/widgets/recurrence_scope_dialog.dart';
import '../../../recurring/domain/recurrence_aggregate_command.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../timer/providers/timer_providers.dart';
import '../../../timer/platform/android_foreground_timer.dart';
import '../../../inbox/domain/inbox_commands.dart';
import '../../../inbox/providers/inbox_provider.dart';
import '../../domain/commands/batch_command.dart';
import '../../domain/commands/move_task_command.dart';
import '../../domain/conflict_detector.dart';
import '../widgets/conflict_resolution_dialog.dart';
import '../../domain/commands/change_status_command.dart';
import '../../domain/commands/delete_task_command.dart';
import '../../domain/commands/duplicate_task_command.dart';
import '../../domain/commands/resize_task_command.dart';
import '../../domain/commands/scheduling_command.dart';
import '../../domain/conflict_resolver.dart';
import '../../domain/snap_to_grid.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/grid_settings_provider.dart';
import '../providers/overlap_flags_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/undo_stack_provider.dart';

/// Shared high-level scheduling actions, invoked from the context menu,
/// keyboard shortcuts and dialogs.
abstract final class TimelineActions {
  /// Schedules/reschedules an Inbox item through the same conflict-aware
  /// command path used by timeline drops.
  static Future<bool> scheduleInboxItem(
    BuildContext context,
    WidgetRef ref,
    InboxItem item,
    DateTime start,
    DateTime end,
  ) async {
    final tasksRepo = ref.read(taskRepositoryProvider);
    final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(start);
    final candidatesStart = start.isBefore(dayStart) ? start : dayStart;
    final candidatesEnd = end.isAfter(dayEnd) ? end : dayEnd;
    final dayTasks = await tasksRepo.getScheduledTasksBetween(
      candidatesStart,
      candidatesEnd,
    );
    final command = item.isOverdue
        ? RescheduleOverdueCommand(
            repository: ref.read(inboxRepositoryProvider),
            originalId: item.task.id,
            start: start,
            end: end,
          )
        : ScheduleInboxItemCommand(
            repository: ref.read(inboxRepositoryProvider),
            taskId: item.task.id,
            start: start,
            end: end,
          );
    final hypothetical = item.task.copyWith(
      id: item.isOverdue ? 'reschedule-preview-${item.task.id}' : item.task.id,
      isInbox: false,
      startTime: start,
      endTime: end,
      actualDurationMin: item.isOverdue ? null : item.task.actualDurationMin,
      status: item.isOverdue ? TaskStatus.planned : item.task.status,
      recurringRuleId: item.task.recurringRuleId,
      rescheduledFromId: item.isOverdue
          ? item.task.id
          : item.task.rescheduledFromId,
      rescheduledToId: null,
      missedAt: null,
    );
    final conflicts = ConflictDetector.detect(hypothetical, dayTasks);
    if (conflicts.isEmpty) {
      await ref.read(undoStackProvider.notifier).execute(command);
      return true;
    }
    if (!context.mounted) return false;
    final choice = await showConflictResolutionDialog(
      context,
      droppedTask: hypothetical,
      conflicts: conflicts,
    );
    if (choice == null) return false;
    if (choice == ConflictResolution.keepOverlap) {
      await ref.read(undoStackProvider.notifier).execute(command);
      return true;
    }
    final plan = choice == ConflictResolution.shiftAllFollowing
        ? ConflictResolver.planShiftAllFollowing(
            moved: hypothetical,
            dayTasks: dayTasks,
          )
        : ConflictResolver.planShiftOnlyOverlapping(
            moved: hypothetical,
            dayTasks: dayTasks,
            maxCascadeDepth: AppConstants.maxCascadeDepth,
          );
    final byId = {for (final task in dayTasks) task.id: task};
    await ref
        .read(undoStackProvider.notifier)
        .execute(
          BatchCommand([
            command,
            for (final shift in plan.shifts)
              if (byId[shift.taskId] != null)
                MoveTaskCommand(
                  repository: tasksRepo,
                  original: byId[shift.taskId]!,
                  newStart: shift.newStart,
                  newEnd: shift.newEnd,
                ),
          ]),
        );
    return true;
  }

  /// Duplicates [task] into the next available slot after the original.
  /// All fields are copied except id / created_at / updated_at.
  static Future<void> duplicateTask(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    if (task.startTime == null || task.endTime == null) {
      showAppToast(context, 'Only scheduled tasks can be duplicated');
      return;
    }
    final history = ref.read(undoStackProvider.notifier);
    final tasks = ref.read(dayTasksProvider).value ?? const <Task>[];
    final durationMin = task.scheduledDuration!.inMinutes;
    final day = ref.read(selectedDateProvider);
    final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(day);
    final searchFrom = task.endTime!.isAfter(dayEnd)
        ? minutesPerDay
        : task.endTime!.isBefore(dayStart)
        ? 0
        : minutesSinceMidnight(task.endTime!);

    final slot = ConflictResolver.findNextAvailableSlot(
      durationMinutes: durationMin,
      dayTasks: tasks,
      searchFromMinutes: searchFrom,
      day: day,
    );
    if (slot == null) {
      showAppToast(context, 'No room left on this day for the copy');
      return;
    }
    final localDay = PlannerTimeZone.toPlannerLocal(day);
    final start = PlannerTimeZone.calendarDate(
      localDay.year,
      localDay.month,
      localDay.day,
      minute: slot,
    );
    final end = start.add(Duration(minutes: durationMin));
    await history.execute(
      DuplicateTaskCommand(
        repository: ref.read(taskRepositoryProvider),
        source: task,
        newStart: start,
        newEnd: end,
      ),
    );
    if (!context.mounted) return;
    showAppToast(context, 'Duplicated "${task.title}"');
  }

  /// Asks for confirmation, then soft-deletes via [DeleteTaskCommand].
  /// Recurring instances get an extra scope question (planner.md Chunk 4 #8):
  /// "This occurrence only" adds an exception date; "All future occurrences"
  /// ends the rule the day before this instance.
  static Future<void> deleteWithConfirmation(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    // Capture before any await so post-dialog work never touches a stale
    // provider graph.
    final viewedDate = ref.read(selectedDateProvider);
    final repository = ref.read(taskRepositoryProvider);
    final activeBefore = ref.read(activeTimerProvider).value;
    final wasTiming = activeBefore?.session.taskId == task.id;
    final deletedSessionId = wasTiming ? activeBefore?.session.id : null;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete task?',
      message:
          '"${task.title}" will be removed from the timeline.\n'
          'You can undo this with Ctrl+Z.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    if (task.recurringRuleId != null) {
      final scope = await showRecurrenceScopeDialog(
        context,
        title: 'Delete recurring task',
        message:
            '"${task.title}" is generated by a recurring rule.\nWhat should be deleted?',
        thisOccurrenceLabel: 'This occurrence only',
        allFutureLabel: 'All future occurrences',
      );
      if (scope == null) return;

      final rulesRepo = ref.read(recurringRepositoryProvider);
      final ruleId = task.recurringRuleId!;
      final boundary = startOfDay(task.startTime ?? viewedDate);
      final command = RecurrenceAggregateCommand(
        database: repository.database,
        ruleId: ruleId,
        description: scope == RecurrenceScope.thisOccurrence
            ? 'Delete recurring occurrence'
            : 'End recurring series',
        mutation: () async {
          await repository.deleteTask(task.id);
          if (scope == RecurrenceScope.thisOccurrence) {
            await rulesRepo.addException(ruleId, boundary);
          } else {
            await rulesRepo.setEndDate(ruleId, addDays(boundary, -1));
            await rulesRepo.deactivateRule(ruleId);
            await ref
                .read(recurrenceServiceProvider)
                .deleteMaterializedFuture(
                  ruleId,
                  boundary,
                  keepTaskId: task.id,
                );
          }
        },
      );
      await ref.read(undoStackProvider.notifier).execute(command);
      if (!context.mounted) return;
      showAppToast(
        context,
        scope == RecurrenceScope.thisOccurrence
            ? 'Occurrence deleted'
            : 'Recurring series ended',
      );
      ref.invalidate(dayMaterializationProvider(viewedDate));
    } else {
      final command = DeleteTaskCommand(repository: repository, original: task);
      await ref.read(undoStackProvider.notifier).execute(command);
    }

    // Task deletion finalizes its own active session inside the same database
    // transaction. Stop the native service only when that service still
    // represents the deleted session; a timer started for another task while
    // the confirmation dialog was open must remain untouched.
    if (wasTiming) {
      final activeAfter = await repository.database.timerDao.getActiveTimer();
      if (activeAfter == null || activeAfter.id == deletedSessionId) {
        await AndroidForegroundTimer().stop();
      }
    }
  }

  static Future<void> setStatus(WidgetRef ref, Task task, TaskStatus status) {
    return ref
        .read(undoStackProvider.notifier)
        .execute(
          ChangeStatusCommand(
            repository: ref.read(taskRepositoryProvider),
            taskId: task.id,
            newStatus: status,
          ),
        );
  }

  /// Moves a selected task by one configured grid interval. The same conflict
  /// dialog and command history used by pointer dragging are used here too.
  static Future<bool> moveByGrid(
    BuildContext context,
    WidgetRef ref,
    Task task,
    int direction,
  ) async {
    final start = task.startTime;
    final end = task.endTime;
    if (start == null || end == null) return false;
    final grid =
        ref.read(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;
    final duration = end.difference(start).inMinutes;
    final originalMinutes = minutesSinceMidnight(start);
    final newMinutes = (originalMinutes + direction * grid)
        .clamp(0, minutesPerDay - grid)
        .toInt();
    if (newMinutes == originalMinutes) return false;
    final local = PlannerTimeZone.toPlannerLocal(start);
    final newStart = PlannerTimeZone.calendarDate(
      local.year,
      local.month,
      local.day,
      minute: newMinutes,
    );
    final newEnd = newStart.add(Duration(minutes: duration));
    return _commitConflictAware(
      context,
      ref,
      MoveTaskCommand(
        repository: ref.read(taskRepositoryProvider),
        original: task,
        newStart: newStart,
        newEnd: newEnd,
      ),
      task.copyWith(startTime: newStart, endTime: newEnd),
    );
  }

  /// Resizes a selected task by one configured grid interval through the
  /// existing [ResizeTaskCommand] and conflict-resolution path.
  static Future<bool> resizeByGrid(
    BuildContext context,
    WidgetRef ref,
    Task task,
    int direction,
  ) async {
    final start = task.startTime;
    final end = task.endTime;
    if (start == null || end == null) return false;
    final grid =
        ref.read(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;
    final originalDuration = end.difference(start).inMinutes;
    final newDuration = snapDuration(
      originalDuration + direction * grid,
      grid,
    ).clamp(grid, 10000).toInt();
    if (newDuration == originalDuration) return false;
    final newEnd = start.add(Duration(minutes: newDuration));
    return _commitConflictAware(
      context,
      ref,
      ResizeTaskCommand(
        repository: ref.read(taskRepositoryProvider),
        original: task,
        newEnd: newEnd,
      ),
      task.copyWith(endTime: newEnd),
    );
  }

  static Future<bool> _commitConflictAware(
    BuildContext context,
    WidgetRef ref,
    SchedulingCommand primary,
    Task hypothetical,
  ) async {
    final tasks = ref.read(dayTasksProvider).value ?? const <Task>[];
    final conflicts = ConflictDetector.detect(hypothetical, tasks);
    final history = ref.read(undoStackProvider.notifier);
    ref.read(keepOverlapIdsProvider.notifier).state = const <String>{};
    if (conflicts.isEmpty) {
      await history.execute(primary);
      return true;
    }
    if (!context.mounted) return false;
    final choice = await showConflictResolutionDialog(
      context,
      droppedTask: hypothetical,
      conflicts: conflicts,
    );
    if (choice == null) return false;
    if (choice == ConflictResolution.keepOverlap) {
      await history.execute(primary);
      ref.read(keepOverlapIdsProvider.notifier).state = {
        hypothetical.id,
        for (final conflict in conflicts) conflict.id,
      };
      return true;
    }
    final plan = choice == ConflictResolution.shiftAllFollowing
        ? ConflictResolver.planShiftAllFollowing(
            moved: hypothetical,
            dayTasks: tasks,
          )
        : ConflictResolver.planShiftOnlyOverlapping(
            moved: hypothetical,
            dayTasks: tasks,
            maxCascadeDepth: AppConstants.maxCascadeDepth,
          );
    final byId = {for (final item in tasks) item.id: item};
    await history.execute(
      BatchCommand([
        primary,
        for (final shift in plan.shifts)
          if (byId[shift.taskId] != null)
            MoveTaskCommand(
              repository: ref.read(taskRepositoryProvider),
              original: byId[shift.taskId]!,
              newStart: shift.newStart,
              newEnd: shift.newEnd,
            ),
      ]),
    );
    if (plan.keepOverlapIds.isNotEmpty) {
      ref.read(keepOverlapIdsProvider.notifier).state = {
        ...plan.keepOverlapIds,
        hypothetical.id,
      };
    }
    return true;
  }
}

/// Grid fallback used when the setting has not finished loading yet; mirrors
/// [AppConstants.defaultGridMinutes].
