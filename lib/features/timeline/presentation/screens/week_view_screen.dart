import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/category.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/selected_date_provider.dart';
import '../../../../features/review/providers/review_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';

/// Seven-day overview (planner.md Chunk 5 #7): one Mon–Sun column per day,
/// compact title-only blocks color-coded by category. Tapping a column opens
/// that day in the Day View.
class WeekViewScreen extends ConsumerWidget {
  const WeekViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(selectedWeekStartProvider);
    final days = List.generate(7, (i) => addDays(weekStart, i));

    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, ref, weekStart),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = isDesktopWidth(constraints.maxWidth);
                final columns = [
                  for (final day in days) _WeekDayColumn(date: day),
                ];
                final grid = Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (isDesktop)
                        Expanded(child: columns[i])
                      else
                        SizedBox(width: 180, child: columns[i]),
                      if (i < columns.length - 1)
                        const VerticalDivider(width: 1),
                    ],
                  ],
                );
                // Give the shared vertical viewport a finite child height;
                // otherwise the Row's stretch axis becomes infinite and
                // each day column receives invalid constraints.
                final gridHeight = 24 * 60 * AppConstants.pixelsPerMinute + 64;
                final horizontallyScrollable = isDesktop
                    ? grid
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: 7 * 180, child: grid),
                      );
                return ColoredBox(
                  color: tokens.canvas,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: gridHeight,
                      child: horizontallyScrollable,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, DateTime weekStart) {
    final notifier = ref.read(selectedWeekStartProvider.notifier);
    final fmt = DateFormat('MMM d');
    final tokens = AppThemeTokens.of(context);
    return Container(
      color: tokens.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WEEK OVERVIEW',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.textMuted, letterSpacing: 1.4),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              IconButton(
                key: const ValueKey('weekview-prev'),
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => notifier.state = addDays(weekStart, -7),
              ),
              Text(
                '${fmt.format(weekStart)} – ${DateFormat('MMM d, yyyy').format(addDays(weekStart, 6))}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                key: const ValueKey('weekview-next'),
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => notifier.state = addDays(weekStart, 7),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                key: const ValueKey('weekview-this-week'),
                onPressed: () => notifier.state = startOfWeek(DateTime.now()),
                child: const Text('This Week'),
              ),
              SegmentedButton<String>(
                key: const ValueKey('day-week-switcher'),
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Day')),
                  ButtonSegment(value: 'week', label: Text('Week')),
                ],
                selected: const {'week'},
                onSelectionChanged: (selection) {
                  if (selection.contains('day')) context.go('/day');
                },
              ),
              const SyncStatusAction(),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekDayColumn extends ConsumerWidget {
  final DateTime date;

  const _WeekDayColumn({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Materialize recurring rules for this day so the week reflects them
    // (same trigger semantics as the Day View).
    final materializationAsync = ref.watch(dayMaterializationProvider(date));
    final tasksAsync = ref.watch(dayTasksForDateProvider(date));
    final categoriesAsync = ref.watch(categoriesProvider);

    final tasks = tasksAsync.value ?? const <Task>[];
    final categories = categoriesAsync.value ?? const <Category>[];

    Category? categoryFor(Task task) {
      for (final c in categories) {
        if (c.id == task.categoryId) return c;
      }
      return null;
    }

    final completed = tasks
        .where((t) => t.status == TaskStatus.completed)
        .length;
    final isToday = isSameDay(date, DateTime.now());
    final totalHeight = 24 * 60 * AppConstants.pixelsPerMinute;

    return InkWell(
      key: ValueKey('week-column-${isoDateString(date)}'),
      onTap: () {
        ref.read(selectedDateProvider.notifier).state = date;
        context.go('/day');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isToday
                  ? AppThemeTokens.of(context).selected
                  : AppThemeTokens.of(context).surface,
              border: Border(
                bottom: BorderSide(
                  color: isToday
                      ? AppColors.primary
                      : Theme.of(context).dividerColor,
                  width: isToday ? 2 : 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    DateFormat('EEE d').format(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (tasksAsync.hasValue && tasks.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '$completed/${tasks.length}',
                    key: ValueKey('day-count-${isoDateString(date)}'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isToday)
            Container(
              key: const ValueKey('week-today-marker'),
              height: 3,
              color: AppColors.primary,
            ),
          if (materializationAsync.hasError)
            ErrorPanel(
              message: friendlyErrorMessage(materializationAsync.error!),
              onRetry: () => ref.invalidate(dayMaterializationProvider(date)),
              compact: true,
            )
          else if (tasksAsync.hasError)
            ErrorPanel(
              message: friendlyErrorMessage(tasksAsync.error!),
              onRetry: () => ref.invalidate(dayTasksForDateProvider(date)),
              compact: true,
            )
          else if (categoriesAsync.hasError)
            ErrorPanel(
              message: friendlyErrorMessage(categoriesAsync.error!),
              onRetry: () => ref.invalidate(categoriesProvider),
              compact: true,
            )
          else if (!materializationAsync.hasValue ||
              !tasksAsync.hasValue ||
              !categoriesAsync.hasValue)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SizedBox(
              height: totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final task in tasks)
                    _buildBlock(context, task, categoryFor(task)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, Task task, Category? category) {
    final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(date);
    final clippedStart = task.startTime!.isBefore(dayStart)
        ? dayStart
        : task.startTime!;
    final clippedEnd = task.endTime!.isAfter(dayEnd) ? dayEnd : task.endTime!;
    if (!clippedEnd.isAfter(clippedStart)) return const SizedBox.shrink();
    final startMinutes = minutesSinceMidnight(clippedStart);
    final durationMinutes = clippedEnd
        .difference(clippedStart)
        .inMinutes
        .toDouble();
    final height = durationMinutes * AppConstants.pixelsPerMinute;
    final accent = category == null
        ? AppColors.primary
        : AppColors.parseHex(category.colorHex);
    return Positioned(
      key: ValueKey('week-block-${task.id}'),
      top: startMinutes * AppConstants.pixelsPerMinute + 1,
      left: 2,
      right: 2,
      height: height - 2,
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Icon(
              _statusIcon(task.status),
              size: 10,
              color: AppThemeTokens.of(context).textSecondary,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(TaskStatus status) => switch (status) {
    TaskStatus.completed => Icons.check_circle,
    TaskStatus.inProgress => Icons.play_circle,
    TaskStatus.skipped => Icons.skip_next,
    TaskStatus.cancelled => Icons.cancel_outlined,
    TaskStatus.rescheduled => Icons.schedule,
    TaskStatus.planned => Icons.radio_button_unchecked,
  };
}
