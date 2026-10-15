import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/layout/size_class_scope.dart';
import '../../../../core/models/day_context.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../day_context/presentation/day_context_editor.dart';
import '../../../day_context/providers/day_context_providers.dart';
import '../../../review/presentation/widgets/weekly_review_style.dart';
import '../../../review/providers/review_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/snap_to_grid.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/grid_settings_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../providers/timeline_action_provider.dart';
import 'day_layout.dart';
import 'day_style.dart';

/// Minutes since midnight where "New task" starts: the selected task's start,
/// else now (when the viewed day is today), else 09:00, snapped to the grid.
/// Same rule as the N shortcut (`KeyboardShortcutHandler._newTask`).
int newTaskSlotMinutes({
  required int gridMinutes,
  required DateTime selectedDate,
  required DateTime now,
  DateTime? selectedTaskStart,
}) {
  final raw = selectedTaskStart != null
      ? minutesSinceMidnight(selectedTaskStart)
      : isSameDay(selectedDate, now)
      ? minutesSinceMidnight(now)
      : 9 * Duration.minutesPerHour;
  return snapSlotStart(raw, gridMinutes);
}

/// Asks the timeline to open quick create at the slot the N shortcut would
/// use. Shared by the header button and the compact FAB.
void requestNewTask(WidgetRef ref) {
  final grid =
      ref.read(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;
  final selectedId = ref.read(selectedTaskIdProvider);
  Task? selected;
  if (selectedId != null) {
    for (final task in ref.read(dayTasksProvider).value ?? const <Task>[]) {
      if (task.id == selectedId && task.deletedAt == null) selected = task;
    }
  }
  ref.read(timelineQuickCreateSlotProvider.notifier).state = newTaskSlotMinutes(
    gridMinutes: grid,
    selectedDate: ref.read(selectedDateProvider),
    now: ref.read(insightsNowFactoryProvider)(),
    selectedTaskStart: selected?.startTime,
  );
}

IconData dayContextIcon(DayContextKind? kind) => switch (kind) {
  DayContextKind.travel => Icons.luggage_outlined,
  DayContextKind.holiday => Icons.celebration_outlined,
  DayContextKind.leave => Icons.event_busy_outlined,
  DayContextKind.office => Icons.business_outlined,
  DayContextKind.custom => Icons.label_outline,
  null => Icons.add_circle_outline,
};

/// The Day header. Compact windows get a top bar with the Day/Week switch on
/// a second row; medium and wider get one 64 dp row whose content is capped
/// at [DayLayout.contentMaxWidth] so the actions stay next to the title.
class DayHeaderBar extends ConsumerWidget {
  const DayHeaderBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = DaySizeClass.of(context);
    final tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.outline)),
      ),
      child: sizeClass.isCompact
          ? const _CompactTopBar()
          : _WideHeader(sizeClass: sizeClass),
    );
  }
}

ButtonStyle _iconButtonStyle(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(DayStyle.minTarget),
  side: DayStyle.focusBorder(context),
);

/// Tooltip text with the shortcut appended. The hint is shown only at medium
/// and up and only where the shortcut handler is active (the same platform
/// check as `KeyboardShortcutHandler._isDesktop`, which ignores Android and
/// iOS), so a hint never advertises a key that does nothing.
String _tip(WindowSizeClass sizeClass, String label, String key) {
  final shortcutsActive =
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;
  return !sizeClass.isCompact && shortcutsActive ? '$label ($key)' : label;
}

Future<void> _pickDate(
  BuildContext context,
  WidgetRef ref,
  DateTime selected,
) async {
  final local = PlannerTimeZone.toPlannerLocal(selected);
  final picked = await showDatePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDate: PlannerTimeZone.calendarDate(
      local.year,
      local.month,
      local.day,
    ),
  );
  if (picked == null) return;
  ref.read(selectedDateProvider.notifier).state = startOfDay(
    PlannerTimeZone.calendarDate(picked.year, picked.month, picked.day),
  );
}

void _setToday(WidgetRef ref) {
  ref.read(selectedDateProvider.notifier).state = startOfDay(
    ref.read(insightsNowFactoryProvider)(),
  );
}

void _step(WidgetRef ref, DateTime selected, int days) {
  ref.read(selectedDateProvider.notifier).state = addDays(selected, days);
}

class _DaySwitcher extends ConsumerWidget {
  const _DaySwitcher({required this.expand, required this.sizeClass});

  /// Fill the available width (compact second row).
  final bool expand;
  final WindowSizeClass sizeClass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    return SegmentedButton<String>(
      key: const ValueKey('day-week-switcher'),
      showSelectedIcon: false,
      expandedInsets: expand ? EdgeInsets.zero : null,
      style: ButtonStyle(
        side: DayStyle.focusBorder(
          context,
          rest: BorderSide(color: tokens.outlineStrong),
        ),
      ),
      segments: [
        ButtonSegment(
          value: 'day',
          label: const Text('Day'),
          tooltip: _tip(sizeClass, 'Toggle Day/Week', 'W'),
        ),
        ButtonSegment(
          value: 'week',
          label: const Text('Week'),
          tooltip: _tip(sizeClass, 'Toggle Day/Week', 'W'),
        ),
      ],
      selected: const {'day'},
      onSelectionChanged: (selection) {
        if (!selection.contains('week')) return;
        ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(
          ref.read(selectedDateProvider),
        );
        context.go('/week');
      },
    );
  }
}

class _TodayButton extends ConsumerWidget {
  const _TodayButton({
    required this.selected,
    this.padding,
    this.iconOnly = false,
  });

  final DateTime selected;
  final EdgeInsetsGeometry? padding;

  /// A 48x48 icon button instead of the text button; the compact top bar uses
  /// it when the date has no room left at a large text size.
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = isSameDay(selected, ref.read(insightsNowFactoryProvider)());
    final tokens = AppThemeTokens.of(context);
    if (iconOnly) {
      return IconButton(
        key: const ValueKey('day-today'),
        tooltip: 'Today',
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(DayStyle.minTarget),
          side: DayStyle.focusBorder(
            context,
            rest: BorderSide(color: tokens.outlineStrong),
          ),
        ),
        icon: const Icon(Icons.today_outlined, semanticLabel: 'Today'),
        onPressed: isToday ? null : () => _setToday(ref),
      );
    }
    return OutlinedButton(
      key: const ValueKey('day-today'),
      style: ButtonStyle(
        padding: padding == null ? null : WidgetStatePropertyAll(padding),
        side: DayStyle.focusBorder(
          context,
          rest: BorderSide(color: tokens.outlineStrong),
        ),
      ),
      onPressed: isToday ? null : () => _setToday(ref),
      child: const Text('Today'),
    );
  }
}

/// A pill showing the day's context; tapping it edits the context. Renders
/// nothing when the day has none (the overflow menu adds one).
class _DayContextChip extends ConsumerWidget {
  const _DayContextChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(dayContextForDateProvider(date)).value;
    if (current == null) return const SizedBox.shrink();
    final tokens = AppThemeTokens.of(context);
    final label = 'Day context: ${current.displayLabel}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          key: ValueKey('day-context-action-${isoDateString(date)}'),
          borderRadius: BorderRadius.circular(DayStyle.small(context)),
          onTap: () => showDayContextEditor(
            context,
            date: isoDateString(date),
            initial: current,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(DayStyle.small(context)),
                border: Border.all(color: tokens.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      dayContextIcon(current.kind),
                      size: 16,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        current.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DayStyle.secondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Day context..." always; "Previous day" and "Next day" on compact, where
/// stepping is otherwise only the swipe.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.date, required this.includeStepping});

  final DateTime date;
  final bool includeStepping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(dayContextForDateProvider(date)).value;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('day-overflow-context'),
          leadingIcon: Icon(dayContextIcon(current?.kind)),
          onPressed: () => showDayContextEditor(
            context,
            date: isoDateString(date),
            initial: current,
          ),
          child: Text(current == null ? 'Day context…' : 'Edit day context…'),
        ),
        if (includeStepping) ...[
          MenuItemButton(
            key: const ValueKey('day-overflow-previous'),
            leadingIcon: const Icon(Icons.chevron_left),
            onPressed: () => _step(ref, date, -1),
            child: const Text('Previous day'),
          ),
          MenuItemButton(
            key: const ValueKey('day-overflow-next'),
            leadingIcon: const Icon(Icons.chevron_right),
            onPressed: () => _step(ref, date, 1),
            child: const Text('Next day'),
          ),
        ],
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('day-overflow'),
        tooltip: 'More actions',
        style: _iconButtonStyle(context),
        icon: const Icon(Icons.more_vert, semanticLabel: 'More actions'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

const double _dateButtonPadding = AppSpacing.sm;

/// Width of a 48 dp touch target (`DayStyle.minTarget`).
const double _targetExtent = 48;

/// What the compact top bar shows for the date and for Today, decided by
/// measuring the real text (style and the user's text scale) against the room
/// the row leaves: "EEE, MMM d", then "MMM d", then "MMM d" with Today as an
/// icon.
class _CompactDateFit {
  const _CompactDateFit(this.label, {required this.todayAsIcon});

  final String label;
  final bool todayAsIcon;

  /// Search, sync status and the overflow menu, each a 48 dp target.
  static const double _trailingWidth = 3 * _targetExtent;

  /// Slack for rounding between the painter and the laid-out button.
  static const double _slack = 4;

  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static _CompactDateFit resolve(
    BuildContext context,
    DateTime selected,
    double rowWidth,
  ) {
    final style = DayStyle.dateTitle(context);
    final long = DateFormat('EEE, MMM d').format(selected);
    final short = DateFormat('MMM d').format(selected);
    double needed(String text) =>
        _textWidth(context, text, style) + 2 * _dateButtonPadding + _slack;
    final room = rowWidth - _trailingWidth;
    final todayText =
        _textWidth(
          context,
          'Today',
          Theme.of(context).textTheme.labelLarge ?? const TextStyle(),
        ) +
        2 * AppSpacing.md;
    final todayWidth = todayText < _targetExtent ? _targetExtent : todayText;
    if (needed(long) <= room - todayWidth) {
      return _CompactDateFit(long, todayAsIcon: false);
    }
    if (needed(short) <= room - todayWidth) {
      return _CompactDateFit(short, todayAsIcon: false);
    }
    return _CompactDateFit(short, todayAsIcon: true);
  }
}

class _CompactTopBar extends ConsumerWidget {
  const _CompactTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDateProvider);
    final tokens = AppThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fit = _CompactDateFit.resolve(
                  context,
                  selected,
                  constraints.maxWidth,
                );
                return Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const ValueKey('day-date-button'),
                          style: TextButton.styleFrom(
                            foregroundColor: tokens.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: _dateButtonPadding,
                            ),
                          ).copyWith(side: DayStyle.focusBorder(context)),
                          onPressed: () => _pickDate(context, ref, selected),
                          child: Text(
                            fit.label,
                            semanticsLabel: DateFormat('EEEE, MMMM d, y')
                                .format(selected),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DayStyle.dateTitle(context),
                          ),
                        ),
                      ),
                    ),
                    _TodayButton(
                      selected: selected,
                      iconOnly: fit.todayAsIcon,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                    const GlobalSearchAction(),
                    const SyncStatusAction(),
                    _OverflowMenu(date: selected, includeStepping: true),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _DayContextChip(date: selected),
          ),
        ),
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: _DaySwitcher(
              expand: true,
              sizeClass: DaySizeClass.of(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _WideHeader extends ConsumerWidget {
  const _WideHeader({required this.sizeClass});

  final WindowSizeClass sizeClass;

  /// Header widths (at text scale 1, growing with the scale) the controls
  /// need: below [_singleRowWidth] they wrap to two rows; below
  /// [_labelledNewTaskWidth] "New task" keeps only its icon.
  static double _singleRowWidth(double scale, {required bool withChip}) =>
      480 + 220 * scale + (withChip ? 170 : 0);
  static double _labelledNewTaskWidth(double scale) => 520 + 270 * scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDateProvider);
    final tokens = AppThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Only medium shows the context chip in the header; with it the single
    // row needs more room, so it wraps to two rows sooner.
    final hasChip =
        sizeClass == WindowSizeClass.medium &&
        ref.watch(dayContextForDateProvider(selected)).value != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DayLayout.contentMaxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final singleRow =
                constraints.maxWidth >=
                _singleRowWidth(textScale, withChip: hasChip);
            final labelled =
                constraints.maxWidth >= _labelledNewTaskWidth(textScale);
            final previous = IconButton(
              key: const ValueKey('day-previous'),
              tooltip: _tip(sizeClass, 'Previous day', '←'),
              style: _iconButtonStyle(context),
              icon: const Icon(
                Icons.chevron_left,
                semanticLabel: 'Previous day',
              ),
              onPressed: () => _step(ref, selected, -1),
            );
            final date = TextButton(
              key: const ValueKey('day-date-button'),
              style: TextButton.styleFrom(
                foregroundColor: tokens.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ).copyWith(side: DayStyle.focusBorder(context)),
              onPressed: () => _pickDate(context, ref, selected),
              child: Text(
                DateFormat('EEE, MMM d, yyyy').format(selected),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DayStyle.dateTitle(context),
              ),
            );
            final next = IconButton(
              key: const ValueKey('day-next'),
              tooltip: _tip(sizeClass, 'Next day', '→'),
              style: _iconButtonStyle(context),
              icon: const Icon(Icons.chevron_right, semanticLabel: 'Next day'),
              onPressed: () => _step(ref, selected, 1),
            );
            final chip = sizeClass == WindowSizeClass.medium
                ? Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: _DayContextChip(date: selected),
                    ),
                  )
                : null;
            final today = Tooltip(
              message: _tip(sizeClass, 'Today', 'T'),
              child: _TodayButton(selected: selected),
            );
            final switcher = _DaySwitcher(expand: false, sizeClass: sizeClass);
            final newTaskStyle = ButtonStyle(
              side: DayStyle.focusBorder(context),
            );
            final newTask = Tooltip(
              message: _tip(sizeClass, 'New task', 'N'),
              child: WeeklyPressScale(
                child: labelled
                    ? FilledButton.icon(
                        key: const ValueKey('day-new-task'),
                        style: newTaskStyle,
                        onPressed: () => requestNewTask(ref),
                        icon: const Icon(Icons.add),
                        label: const Text('New task'),
                      )
                    : FilledButton(
                        key: const ValueKey('day-new-task'),
                        style: newTaskStyle,
                        onPressed: () => requestNewTask(ref),
                        child: const Icon(Icons.add),
                      ),
              ),
            );
            final sync = <Widget>[
              const SizedBox(width: AppSpacing.xs),
              const SyncStatusAction(),
              _OverflowMenu(date: selected, includeStepping: false),
            ];
            // The left group takes the free width; the title is its only
            // flexible part, so it is never squeezed by a spacer.
            Widget left(List<Widget> controls) => Expanded(
              child: Row(
                children: [
                  previous,
                  Flexible(child: date),
                  next,
                  ...controls,
                ],
              ),
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: singleRow
                  ? SizedBox(
                      height: 64,
                      child: Row(
                        children: [
                          left([
                            ?chip,
                            const SizedBox(width: AppSpacing.sm),
                            today,
                            const SizedBox(width: AppSpacing.sm),
                            switcher,
                          ]),
                          newTask,
                          ...sync,
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              left([?chip]),
                              ...sync,
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              today,
                              const SizedBox(width: AppSpacing.sm),
                              switcher,
                              const Spacer(),
                              newTask,
                            ],
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}
