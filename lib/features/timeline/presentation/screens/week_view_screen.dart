import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/category.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_day_axis.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../../core/widgets/task_block_widget.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../day_context/presentation/day_context_editor.dart';
import '../../../day_context/providers/day_context_providers.dart';
import '../../../inbox/providers/inbox_provider.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../review/providers/review_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/timeline_geometry.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/grid_settings_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../widgets/current_time_indicator.dart';
import '../widgets/timeline_hour_grid.dart';
import '../widgets/timeline_overlap_action.dart';

/// A responsive seven-date timeline. Horizontal paging changes only the
/// visible date group; each page owns a distinct vertical controller so a
/// PageView never attaches one ScrollController to multiple children.
class WeekViewScreen extends ConsumerStatefulWidget {
  const WeekViewScreen({super.key});

  @override
  ConsumerState<WeekViewScreen> createState() => _WeekViewScreenState();
}

class _WeekViewScreenState extends ConsumerState<WeekViewScreen> {
  PageController? _pageController;
  final _pageScrollControllers = <int, ScrollController>{};
  final _positionedPages = <int>{};
  int? _capacity;
  double? _verticalOffset;

  @override
  void dispose() {
    _pageController?.dispose();
    for (final controller in _pageScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<DateTime> _days(DateTime weekStart) => [
    for (var i = 0; i < 7; i++) addDays(weekStart, i),
  ];

  int _selectedDayIndex(DateTime weekStart, DateTime selectedDate) {
    final days = _days(weekStart);
    for (var i = 0; i < days.length; i++) {
      if (isSameDay(days[i], selectedDate)) return i;
    }
    return 0;
  }

  ScrollController _scrollControllerFor(int page) =>
      _pageScrollControllers.putIfAbsent(page, ScrollController.new);

  void _ensurePageController(int page, int capacity) {
    if (_pageController == null) {
      _pageController = PageController(initialPage: page);
      _capacity = capacity;
      return;
    }
    if (_capacity == capacity) return;
    _capacity = capacity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController!.hasClients) return;
      final selected = ref.read(selectedDateProvider);
      final weekStart = ref.read(selectedWeekStartProvider);
      final target = _selectedDayIndex(weekStart, selected) ~/ capacity;
      _pageController!.jumpToPage(target);
    });
  }

  void _recordScroll(double offset) {
    _verticalOffset = offset;
  }

  double _initialScrollOffset(List<DateTime> days) {
    final now = DateTime.now();
    final weekStart = days.first;
    final weekEnd = addDays(weekStart, 7);
    final todayInWeek = !now.isBefore(weekStart) && now.isBefore(weekEnd);
    final anchor = todayInWeek
        ? PlannerDayAxis(now).elapsedMinutes(now) - 90
        : 9 * Duration.minutesPerHour.toDouble();
    return math.max(0, anchor * AppConstants.pixelsPerMinute - 96);
  }

  void _positionPage(int page, List<DateTime> days) {
    if (!_positionedPages.add(page)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _scrollControllerFor(page);
      if (!controller.hasClients) return;
      final target = (_verticalOffset ?? _initialScrollOffset(days)).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(target.toDouble());
    });
  }

  void _selectDate(DateTime date, {bool navigate = true}) {
    final weekStart = ref.read(selectedWeekStartProvider);
    ref.read(selectedDateProvider.notifier).state = date;
    if (!navigate || _pageController == null || !_pageController!.hasClients) {
      return;
    }
    final page = _selectedDayIndex(weekStart, date) ~/ (_capacity ?? 1);
    _pageController!.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _navigateWeek(int delta) {
    final weekStart = ref.read(selectedWeekStartProvider);
    final offset = _selectedDayIndex(weekStart, ref.read(selectedDateProvider));
    final next = addDays(weekStart, delta * 7);
    ref.read(selectedWeekStartProvider.notifier).state = next;
    ref.read(selectedDateProvider.notifier).state = addDays(next, offset);
    _positionedPages.clear();
  }

  void _goToToday() {
    final today = startOfDay(DateTime.now());
    ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(today);
    ref.read(selectedDateProvider.notifier).state = today;
    _positionedPages.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pageController == null || !_pageController!.hasClients) {
        return;
      }
      _pageController!.animateToPage(
        _selectedDayIndex(startOfWeek(today), today) ~/ (_capacity ?? 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollToNow() {
    final today = startOfDay(DateTime.now());
    final weekStart = ref.read(selectedWeekStartProvider);
    if (!isSameDay(startOfWeek(today), weekStart)) {
      _goToToday();
      return;
    }
    _selectDate(today);
    final page = _selectedDayIndex(weekStart, today) ~/ (_capacity ?? 1);
    final controller = _scrollControllerFor(page);
    final axis = PlannerDayAxis(today);
    final target =
        axis.elapsedMinutes(DateTime.now()) * AppConstants.pixelsPerMinute -
        90 * AppConstants.pixelsPerMinute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.animateTo(
        target.clamp(0.0, controller.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = ref.watch(selectedWeekStartProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final now = ref.watch(inboxClockProvider).value ?? DateTime.now();
    final days = _days(weekStart);
    final gridMinutes =
        ref.watch(gridIntervalProvider).value ??
        AppConstants.defaultGridMinutes;

    // PageView temporarily pauses off-screen Consumer elements. Keep each
    // visible week's shared sources subscribed at the screen level so an
    // off-screen page cannot lose an auto-disposed subscription while it is
    // being activated or deactivated during Day/Week navigation.
    ref.watch(categoriesProvider);
    for (final day in days) {
      ref.watch(dayMaterializationProvider(day));
      ref.watch(activeDayTasksForDateProvider(day));
      ref.watch(dayContextForDateProvider(day));
    }

    // Keyboard navigation can enter Week without going through DayHeader.
    // Align a stale week selection with the date being viewed once.
    if (_selectedDayIndex(weekStart, selectedDate) == 0 &&
        !isSameDay(weekStart, selectedDate)) {
      final selectedLocal = PlannerTimeZone.toPlannerLocal(selectedDate);
      final weekLocal = PlannerTimeZone.toPlannerLocal(weekStart);
      if (selectedLocal.difference(weekLocal).inDays.abs() > 6) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(
              selectedDate,
            );
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: AppThemeTokens.of(context).canvas,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _buildHeader(context, weekStart, selectedDate, days),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final rulerWidth = TimelineHourGrid.measuredRulerWidth(
                    context,
                    days.first,
                    textScale: scale,
                  );
                  final layout = WeekViewportLayout.forWidth(
                    constraints.maxWidth,
                    textScale: scale,
                    rulerWidth: rulerWidth,
                  );
                  final selectedIndex = _selectedDayIndex(
                    weekStart,
                    selectedDate,
                  );
                  final selectedPage = selectedIndex ~/ layout.daysPerPage;
                  _ensurePageController(selectedPage, layout.daysPerPage);
                  final gridHeight =
                      days
                              .map((day) => PlannerDayAxis(day).durationMinutes)
                              .reduce(math.max) *
                          AppConstants.pixelsPerMinute +
                      AppSpacing.huge;
                  final pageCount = (days.length / layout.daysPerPage).ceil();
                  return PageView.builder(
                    key: const ValueKey('week-pages'),
                    controller: _pageController,
                    itemCount: pageCount,
                    onPageChanged: (page) {
                      final first = page * layout.daysPerPage;
                      if (first < days.length &&
                          !isSameDay(selectedDate, days[first])) {
                        _selectDate(days[first], navigate: false);
                      }
                    },
                    itemBuilder: (context, page) {
                      final first = page * layout.daysPerPage;
                      final pageDays = days.sublist(
                        first,
                        math.min(first + layout.daysPerPage, days.length),
                      );
                      return _WeekPage(
                        key: ValueKey('week-page-$page-${layout.daysPerPage}'),
                        days: pageDays,
                        pageCapacity: layout.daysPerPage,
                        columnWidth: layout.columnWidthFor(
                          constraints.maxWidth,
                        ),
                        rulerWidth: layout.rulerWidth,
                        gridMinutes: gridMinutes,
                        gridHeight: gridHeight,
                        selectedDate: selectedDate,
                        now: now,
                        onSelectDate: (date) => _selectDate(date),
                        onHeaderTap: (date) {
                          _selectDate(date, navigate: false);
                          context.go('/day');
                        },
                        onTaskTap: (task, date) {
                          ref.read(selectedDateProvider.notifier).state = date;
                          ref.read(selectedTaskIdProvider.notifier).state =
                              task.id;
                          ref.read(taskEditorOpenProvider.notifier).state =
                              true;
                          context.go('/day');
                        },
                        scrollController: _scrollControllerFor(page),
                        onScroll: _recordScroll,
                        onReady: () => _positionPage(page, pageDays),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DateTime weekStart,
    DateTime selectedDate,
    List<DateTime> days,
  ) {
    final tokens = AppThemeTokens.of(context);
    final offset = _selectedDayIndex(weekStart, selectedDate);
    return Container(
      color: tokens.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                onPressed: () => _navigateWeek(-1),
              ),
              Text(
                '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d, yyyy').format(addDays(weekStart, 6))}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                key: const ValueKey('weekview-next'),
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _navigateWeek(1),
              ),
              OutlinedButton(
                key: const ValueKey('weekview-this-week'),
                onPressed: _goToToday,
                child: const Text('This Week'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('week-scroll-to-now'),
                onPressed: _scrollToNow,
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('Now'),
              ),
              SegmentedButton<String>(
                key: const ValueKey('day-week-switcher'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Day')),
                  ButtonSegment(value: 'week', label: Text('Week')),
                ],
                selected: const {'week'},
                onSelectionChanged: (selection) {
                  if (selection.contains('day')) context.go('/day');
                },
              ),
              const GlobalSearchAction(),
              const SyncStatusAction(),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            key: const ValueKey('week-date-selector'),
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var index = 0; index < days.length; index++)
                ChoiceChip(
                  key: ValueKey(
                    'week-day-selector-${isoDateString(days[index])}',
                  ),
                  selected: index == offset,
                  label: Text(DateFormat('EEE d').format(days[index])),
                  onSelected: (_) => _selectDate(days[index]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekPage extends StatelessWidget {
  final List<DateTime> days;
  final int pageCapacity;
  final double columnWidth;
  final double rulerWidth;
  final int gridMinutes;
  final double gridHeight;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onHeaderTap;
  final void Function(Task task, DateTime date) onTaskTap;
  final ScrollController scrollController;
  final ValueChanged<double> onScroll;
  final VoidCallback onReady;

  const _WeekPage({
    super.key,
    required this.days,
    required this.pageCapacity,
    required this.columnWidth,
    required this.rulerWidth,
    required this.gridMinutes,
    required this.gridHeight,
    required this.selectedDate,
    required this.now,
    required this.onSelectDate,
    required this.onHeaderTap,
    required this.onTaskTap,
    required this.scrollController,
    required this.onScroll,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final firstAxis = PlannerDayAxis(days.first);
    final tokens = AppThemeTokens.of(context);
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: rulerWidth,
                child: Container(
                  color: tokens.surface,
                  alignment: Alignment.center,
                  child: Text(
                    'TIME',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: tokens.textMuted, letterSpacing: 1.2),
                  ),
                ),
              ),
              for (final date in days)
                SizedBox(
                  width: columnWidth,
                  child: _WeekHeaderCell(
                    key: ValueKey('week-header-${isoDateString(date)}'),
                    date: date,
                    selected: isSameDay(date, selectedDate),
                    onTap: () => onHeaderTap(date),
                  ),
                ),
              if (days.length < pageCapacity)
                for (var i = days.length; i < pageCapacity; i++)
                  SizedBox(width: columnWidth, child: const SizedBox()),
            ],
          ),
        ),
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          bottom: 0,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              onScroll(notification.metrics.pixels);
              return false;
            },
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: gridHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: rulerWidth,
                          child: TimelineHourGrid(
                            date: days.first,
                            gridMinutes: gridMinutes,
                            rulerWidth: rulerWidth,
                            showRuler: true,
                          ),
                        ),
                        for (var index = 0; index < days.length; index++)
                          SizedBox(
                            width: columnWidth,
                            child: _WeekDayGrid(
                              key: ValueKey(
                                'week-day-grid-${isoDateString(days[index])}',
                              ),
                              date: days[index],
                              columnWidth: columnWidth,
                              rulerWidth: rulerWidth,
                              showInternalRuler:
                                  index > 0 &&
                                  !TimelineHourGrid.equivalentMarkers(
                                    firstAxis,
                                    PlannerDayAxis(days[index]),
                                  ),
                              gridMinutes: gridMinutes,
                              onTaskTap: onTaskTap,
                              onReady: onReady,
                            ),
                          ),
                        if (days.length < pageCapacity)
                          for (var i = days.length; i < pageCapacity; i++)
                            SizedBox(width: columnWidth),
                      ],
                    ),
                    if (days.any((date) => isSameDay(date, now)))
                      CurrentTimeIndicator(
                        key: ValueKey(
                          'week-current-time-${isoDateString(now)}',
                        ),
                        pixelsPerMinute: AppConstants.pixelsPerMinute,
                        day: days.firstWhere((date) => isSameDay(date, now)),
                        now: now,
                        left: rulerWidth,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekHeaderCell extends ConsumerWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  const _WeekHeaderCell({
    super.key,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(activeDayTasksForDateProvider(date));
    final tasks = tasksAsync.value ?? const <Task>[];
    final completed = tasks
        .where((task) => task.status.dbValue == 'completed')
        .length;
    final tokens = AppThemeTokens.of(context);
    final isToday = isSameDay(date, DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: selected ? tokens.selected : tokens.surface,
        border: Border(
          bottom: BorderSide(
            color: isToday ? AppColors.primary : tokens.outline,
            width: isToday ? 2 : 1,
          ),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('week-column-${isoDateString(date)}'),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      Text(
                        DateFormat('EEE d').format(date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (tasksAsync.hasValue && tasks.isNotEmpty)
                        Text(
                          '$completed/${tasks.length}',
                          key: ValueKey('day-count-${isoDateString(date)}'),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      if (isToday)
                        const Icon(
                          Icons.today,
                          key: ValueKey('week-today-marker'),
                          size: 14,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 30,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DayContextAction(
                key: ValueKey('week-context-${isoDateString(date)}'),
                date: date,
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayGrid extends ConsumerWidget {
  final DateTime date;
  final double columnWidth;
  final double rulerWidth;
  final bool showInternalRuler;
  final int gridMinutes;
  final void Function(Task task, DateTime date) onTaskTap;
  final VoidCallback onReady;

  const _WeekDayGrid({
    super.key,
    required this.date,
    required this.columnWidth,
    required this.rulerWidth,
    required this.showInternalRuler,
    required this.gridMinutes,
    required this.onTaskTap,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialization = ref.watch(dayMaterializationProvider(date));
    final tasksAsync = ref.watch(activeDayTasksForDateProvider(date));
    final categoriesAsync = ref.watch(categoriesProvider);
    final internalRuler = showInternalRuler ? rulerWidth : 0.0;
    final available = math.max(1, columnWidth - internalRuler).toDouble();
    if (materialization.hasError ||
        tasksAsync.hasError ||
        categoriesAsync.hasError) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
      return SizedBox(
        key: ValueKey('week-column-${isoDateString(date)}'),
        child: ErrorPanel(
          compact: true,
          message: friendlyErrorMessage(
            materialization.error ?? tasksAsync.error ?? categoriesAsync.error!,
          ),
        ),
      );
    }
    if (!materialization.hasValue ||
        !tasksAsync.hasValue ||
        !categoriesAsync.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
      return const Center(child: CircularProgressIndicator());
    }
    final tasks = tasksAsync.requireValue;
    final categories = categoriesAsync.requireValue;
    final geometries = TimelineGeometry.layoutForDay(tasks: tasks, date: date);
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
    return Stack(
      key: ValueKey('week-grid-${isoDateString(date)}'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: TimelineHourGrid(
            date: date,
            gridMinutes: gridMinutes,
            rulerWidth: internalRuler,
            showRuler: showInternalRuler,
          ),
        ),
        for (final geometry in geometries)
          _buildBlock(
            context,
            geometry,
            categoriesById[geometry.task.categoryId],
            available,
            onTaskTap,
            tasks,
          ),
      ],
    );
  }

  Widget _buildBlock(
    BuildContext context,
    TimelineTaskGeometry geometry,
    Category? category,
    double availableWidth,
    void Function(Task task, DateTime date) onTaskTap,
    List<Task> allTasks,
  ) {
    final laneWidth = availableWidth / geometry.laneCount;
    final dense =
        geometry.hasOverlap &&
        laneWidth < 84 * MediaQuery.textScalerOf(context).scale(1);
    final left =
        (showInternalRuler ? rulerWidth : 0) +
        geometry.laneIndex * laneWidth +
        2;
    final width = math.max(2, laneWidth - 4).toDouble();
    final taskBlock = Semantics(
      label: dense
          ? '${geometry.task.title}, ${geometry.componentTaskIds.length} overlapping tasks'
          : null,
      child: TaskBlockWidget(
        task: geometry.task,
        geometry: geometry,
        category: category,
        compact: true,
        selected: false,
        hasOverlap: geometry.hasOverlap,
        onTap: () => onTaskTap(geometry.task, date),
      ),
    );
    final child = dense && geometry.laneIndex == 0
        ? Stack(
            fit: StackFit.expand,
            children: [
              taskBlock,
              TimelineOverlapAction(
                geometry: geometry,
                tasks: allTasks,
                date: date,
                onOpen: (task) => onTaskTap(task, date),
              ),
            ],
          )
        : taskBlock;
    return Positioned(
      key: ValueKey('week-block-${geometry.task.id}'),
      top: geometry.topPx + 1,
      left: left,
      width: width,
      height: math.max(1, geometry.heightPx - 2).toDouble(),
      child: child,
    );
  }
}
