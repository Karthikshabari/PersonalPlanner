import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/layout/breakpoints.dart';
import '../../../../../core/layout/size_class_scope.dart';
import '../../../../../core/models/enums/task_status.dart';
import '../../../../../core/models/inbox_item.dart';
import '../../../../../core/models/task.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_theme_tokens.dart';
import '../../../../../core/utils/clock_format.dart';
import '../../../../../core/utils/date_utils.dart';
import '../../../../../core/providers/database_provider.dart';
import '../../../../../core/utils/planner_time_zone.dart';
import '../../../../../core/widgets/error_panel.dart';
import '../../../../inbox/presentation/widgets/inbox_quick_add.dart';
import '../../../../inbox/providers/inbox_provider.dart';
import '../../../../review/presentation/widgets/review_snack_bar.dart';
import '../../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../../providers/day_view_controller.dart';
import '../../providers/grid_settings_provider.dart';
import '../../providers/selected_date_provider.dart';
import '../../providers/selected_task_provider.dart';
import '../../providers/undo_stack_provider.dart';
import '../day_style.dart';
import 'move_to_today_slot.dart';
import 'overdue_age.dart';

/// Width from which a row shows its actions without hover or focus.
const _alwaysVisibleActionsWidth = 520.0;
const _minRowHeight = 56.0;
const _overflowWidth = 48.0;

/// The snack bar with Undo that follows Done, Skip and Move, captured before
/// the first `await`: the row that started the action leaves the tree as soon
/// as the stream drops its task, so neither its `context` nor its `ref` may
/// be used afterwards.
class AttentionFeedback {
  AttentionFeedback._(this._context, this._undo);

  /// [anchor] is a context that outlives the row (the compact sheet passes
  /// its own, so the bar shows above the sheet); without one the root
  /// navigator's context is used.
  factory AttentionFeedback.capture(
    BuildContext context,
    WidgetRef ref, {
    BuildContext? anchor,
  }) => AttentionFeedback._(
    anchor ?? Navigator.of(context, rootNavigator: true).context,
    ref.read(undoStackProvider.notifier),
  );

  final BuildContext _context;
  final UndoStackNotifier _undo;

  void show(String message, {bool withUndo = true}) {
    if (!_context.mounted) return;
    showReviewSnackBar(
      _context,
      message,
      actionLabel: withUndo ? 'Undo' : null,
      onAction: withUndo ? () => unawaited(_runUndo()) : null,
    );
  }

  Future<void> _runUndo() async {
    try {
      await _undo.undo();
    } on Object catch (error) {
      show(friendlyErrorMessage(error), withUndo: false);
    }
  }
}

/// One row of the Day "Needs attention" list: an overdue task (Done, Move to
/// today, Pick a new time, Skip; swipe right/left for the first two) or an
/// explicit Inbox capture due today (Schedule, Edit, Open Inbox; no swipe).
class DayAttentionRow extends ConsumerStatefulWidget {
  const DayAttentionRow({
    super.key,
    required this.item,
    required this.showDragHandle,
    this.feedbackContext,
  });

  final InboxItem item;

  /// A 6-dot handle at the row start is the only part that drags the item to
  /// the timeline. Hidden where the list covers the timeline (compact sheet).
  final bool showDragHandle;

  /// See [AttentionFeedback.capture].
  final BuildContext? feedbackContext;

  @override
  ConsumerState<DayAttentionRow> createState() => _DayAttentionRowState();
}

class _DayAttentionRowState extends ConsumerState<DayAttentionRow> {
  final MenuController _menu = MenuController();
  bool _hovered = false;
  bool _focused = false;

  InboxItem get _item => widget.item;
  Task get _task => widget.item.task;

  DateTime _now() =>
      ref.read(inboxClockProvider).value ?? ref.read(inboxNowFactoryProvider)();

  AttentionFeedback _feedback() =>
      AttentionFeedback.capture(context, ref, anchor: widget.feedbackContext);

  // ---- actions -----------------------------------------------------------

  Future<void> _setStatus(TaskStatus status, String message) async {
    final feedback = _feedback();
    try {
      await TimelineActions.setStatus(ref, _task, status);
      feedback.show(message);
    } on Object catch (error) {
      feedback.show(friendlyErrorMessage(error), withUndo: false);
    }
  }

  Future<void> _done() => _setStatus(TaskStatus.completed, 'Marked done');

  Future<void> _skip() => _setStatus(TaskStatus.skipped, 'Skipped');

  /// The slot [moveToTodaySlot] picks, from the blocks already on today's
  /// plan.
  Future<TodaySlot?> _suggestedSlot() async {
    final now = _now();
    final repository = ref.read(taskRepositoryProvider);
    final grid =
        ref.read(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;
    final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(now);
    final today = await repository.getScheduledTasksBetween(dayStart, dayEnd);
    return moveToTodaySlot(_task, now, grid, today);
  }

  Future<void> _moveToToday() async {
    final feedback = _feedback();
    try {
      final slot = await _suggestedSlot();
      if (!mounted) return;
      if (slot == null) {
        feedback.show(
          'No room left today. Use Pick a new time.',
          withUndo: false,
        );
        return;
      }
      final moved = await TimelineActions.scheduleInboxItem(
        context,
        ref,
        _item,
        slot.start,
        slot.end,
      );
      if (moved) feedback.show('Moved to ${formatClock24(slot.start)}');
    } on Object catch (error) {
      feedback.show(friendlyErrorMessage(error), withUndo: false);
    }
  }

  /// Opens the shared scheduling form (it has the date and time controls),
  /// starting at the slot "Move to today" would use.
  Future<void> _pickTime() async {
    final feedback = _feedback();
    final slot = await _suggestedSlot();
    if (!mounted) return;
    final start = slot?.start ?? _task.startTime ?? _now();
    final end =
        slot?.end ??
        start.add(Duration(minutes: _task.scheduledDuration?.inMinutes ?? 60));
    final scheduled = await TimelineActions.showInboxSchedulingForm(
      context,
      ref,
      _item,
      start,
      end,
    );
    if (scheduled) {
      feedback.show(_item.isOverdue ? 'Rescheduled' : 'Scheduled');
    }
  }

  Future<void> _edit() async {
    if (!_item.isOverdue) {
      await showInboxEditDialog(
        context,
        ref,
        taskId: _task.id,
        initialContent: _task.description ?? '',
      );
      return;
    }
    final selected = ref.read(selectedTaskIdProvider.notifier);
    selected.state = _task.id;
    if (!Breakpoints.hasSidePanel(DaySizeClass.of(context))) {
      await TaskEditorPanel.showAsBottomSheet(context);
      selected.state = null;
      return;
    }
    // Selection alone never opens the side-panel editor: show the task's day
    // and open it, as Search does for a result.
    final start = _task.startTime;
    if (start != null) {
      ref.read(selectedDateProvider.notifier).state = startOfDay(start);
    }
    ref.read(taskEditorOpenProvider.notifier).state = true;
  }

  Future<void> _delete() =>
      TimelineActions.deleteWithConfirmation(context, ref, _task);

  void _openInbox() {
    final router = GoRouter.of(context);
    // Leave the compact sheet first so it does not stay over the Inbox.
    if (ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
    router.go('/inbox');
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final overdue = _item.isOverdue;
    final now =
        ref.watch(inboxClockProvider.select((clock) => clock.value)) ??
        ref.read(inboxNowFactoryProvider)();
    final instant = overdue ? overdueInstant(_task) : null;
    final age = instant == null ? '' : formatOverdueAge(instant, now);
    final exact = overdue ? formatOverdueExact(_task) : '';
    final title = _item.displayPreview;

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final inline = constraints.maxWidth >= _alwaysVisibleActionsWidth;
        final actionsShown = inline || _hovered || _focused;
        final actions = _actions();
        final content = Row(
          children: [
            if (widget.showDragHandle) _dragHandle(tokens, title),
            _leadingIcon(tokens, overdue),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              // The row's own label already says all of this.
              child: ExcludeSemantics(
                child: _titleColumn(
                  context,
                  title: title,
                  subtitle: overdue ? age : 'Due today',
                  exact: exact,
                ),
              ),
            ),
            if (inline) ...actions,
            _overflowMenu(title),
          ],
        );
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: inline
                ? content
                : Stack(
                    alignment: AlignmentDirectional.centerEnd,
                    children: [
                      content,
                      Positioned.directional(
                        textDirection: Directionality.of(context),
                        end: _overflowWidth,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  (constraints.maxWidth -
                                          2 * AppSpacing.md -
                                          _overflowWidth)
                                      .clamp(0.0, double.infinity),
                            ),
                            child: _hoverActions(
                              tokens,
                              actions,
                              shown: actionsShown,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: _hovered
            ? Color.alphaBlend(
                DayStyle.hoverFill(context),
                tokens.surfaceRaised,
              )
            : tokens.surfaceRaised,
        border: Border(
          bottom: BorderSide(color: tokens.outline.withValues(alpha: 0.5)),
        ),
      ),
      child: row,
    );

    body = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: _menu.open,
          child: body,
        ),
      ),
    );

    body = Semantics(
      container: true,
      label: overdue ? '$title, overdue, missed $exact' : '$title, due today',
      customSemanticsActions: {
        for (final action in _semanticsActions())
          CustomSemanticsAction(label: action.label): action.run,
      },
      child: body,
    );

    if (!overdue) return body;
    return Dismissible(
      key: ValueKey('day-attention-swipe-${_task.id}'),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      background: _SwipeBackground(
        color: tokens.success,
        icon: Icons.check,
        label: 'Done',
        alignment: AlignmentDirectional.centerStart,
      ),
      secondaryBackground: _SwipeBackground(
        color: tokens.info,
        icon: Icons.today,
        label: 'Move to today',
        alignment: AlignmentDirectional.centerEnd,
      ),
      // The action runs here and the row is never "dismissed": it leaves the
      // tree when the stream drops the task. Returning true first would leave
      // a dismissed Dismissible in the tree.
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _done();
        } else {
          await _moveToToday();
        }
        return false;
      },
      child: body,
    );
  }

  List<({String label, VoidCallback run})> _semanticsActions() =>
      _item.isOverdue
      ? [
          (label: 'Done', run: () => unawaited(_done())),
          (label: 'Move to today', run: () => unawaited(_moveToToday())),
          (label: 'Pick a new time', run: () => unawaited(_pickTime())),
          (label: 'Skip', run: () => unawaited(_skip())),
        ]
      : [
          (label: 'Schedule', run: () => unawaited(_pickTime())),
          (label: 'Edit', run: () => unawaited(_edit())),
          (label: 'Open Inbox', run: _openInbox),
        ];

  Widget _leadingIcon(AppThemeTokens tokens, bool overdue) {
    final color = overdue ? tokens.warning : tokens.info;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DayStyle.small(context)),
      ),
      child: Icon(
        overdue ? Icons.history : Icons.inbox_outlined,
        size: 18,
        color: color,
      ),
    );
  }

  Widget _titleColumn(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String exact,
  }) {
    final secondary = Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DayStyle.secondary(context),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DayStyle.rowTitle(context)
              .copyWith(color: AppThemeTokens.of(context).textPrimary),
        ),
        if (exact.isEmpty)
          secondary
        else
          Tooltip(message: exact, excludeFromSemantics: true, child: secondary),
      ],
    );
  }

  /// The drag source. Only the handle drags, so swiping the row and
  /// scrolling the list never start a drag.
  Widget _dragHandle(AppThemeTokens tokens, String title) {
    return ExcludeSemantics(
      child: Draggable<InboxItem>(
        data: _item,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(DayStyle.small(context)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border.all(color: tokens.warning),
                borderRadius: BorderRadius.circular(DayStyle.small(context)),
              ),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DayStyle.secondary(context)
                    .copyWith(color: tokens.textPrimary),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox(
            key: ValueKey('day-attention-handle-${_task.id}'),
            width: 24,
            height: 40,
            child: Icon(
              Icons.drag_indicator,
              size: 20,
              color: tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  /// The icon buttons of the row; the caller decides whether they sit in the
  /// row or float over its right end.
  List<Widget> _actions() {
    final id = _task.id;
    Widget button(
      String key,
      IconData icon,
      String tooltip,
      VoidCallback run,
    ) => IconButton(
      key: ValueKey('day-attention-$key-$id'),
      tooltip: tooltip,
      icon: Icon(icon, semanticLabel: tooltip, size: 20),
      style: IconButton.styleFrom(minimumSize: DayStyle.minTarget),
      onPressed: run,
    );
    if (_item.isOverdue) {
      return [
        button('done', Icons.check, 'Done', () => unawaited(_done())),
        button(
          'move',
          Icons.today,
          'Move to today',
          () => unawaited(_moveToToday()),
        ),
        button(
          'pick',
          Icons.schedule,
          'Pick a new time',
          () => unawaited(_pickTime()),
        ),
        button('skip', Icons.redo, 'Skip', () => unawaited(_skip())),
      ];
    }
    return [
      button(
        'schedule',
        Icons.event_available_outlined,
        'Schedule',
        () => unawaited(_pickTime()),
      ),
      button('edit', Icons.edit_outlined, 'Edit', () => unawaited(_edit())),
      button('open-inbox', Icons.inbox_outlined, 'Open Inbox', _openInbox),
    ];
  }

  /// Actions that appear on hover or focus, floating over the row's right
  /// end. The fade is on this small group only; it is zero with reduced
  /// motion. Hidden actions ignore the pointer so a tap on touch never hits
  /// one, but they stay focusable so Tab reaches (and reveals) them.
  Widget _hoverActions(
    AppThemeTokens tokens,
    List<Widget> actions, {
    required bool shown,
  }) {
    return AnimatedOpacity(
      key: ValueKey('day-attention-actions-${_task.id}'),
      opacity: shown ? 1 : 0,
      duration: DayStyle.quick(context),
      curve: DayStyle.curve,
      child: IgnorePointer(
        ignoring: !shown,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(DayStyle.small(context)),
              border: Border.all(color: tokens.outline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
      ),
    );
  }

  Widget _overflowMenu(String title) {
    final overdue = _item.isOverdue;
    MenuItemButton entry(String label, IconData icon, VoidCallback run) =>
        MenuItemButton(
          leadingIcon: Icon(icon, size: 18),
          onPressed: run,
          child: Text(label),
        );
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        if (overdue) ...[
          entry('Done', Icons.check, () => unawaited(_done())),
          entry('Move to today', Icons.today, () => unawaited(_moveToToday())),
          entry(
            'Pick a new time',
            Icons.schedule,
            () => unawaited(_pickTime()),
          ),
          entry('Skip', Icons.redo, () => unawaited(_skip())),
        ] else
          entry(
            'Schedule',
            Icons.event_available_outlined,
            () => unawaited(_pickTime()),
          ),
        entry('Edit', Icons.edit_outlined, () => unawaited(_edit())),
        if (!overdue) entry('Open Inbox', Icons.inbox_outlined, _openInbox),
        entry('Delete', Icons.delete_outline, () => unawaited(_delete())),
      ],
      builder: (context, controller, child) => IconButton(
        key: ValueKey('day-attention-menu-${_task.id}'),
        tooltip: 'Task actions',
        icon: const Icon(
          Icons.more_vert,
          semanticLabel: 'Task actions',
          size: 20,
        ),
        style: IconButton.styleFrom(minimumSize: DayStyle.minTarget),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// What a swipe reveals: a tint, an icon and a label.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final IconData icon;
  final String label;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      color: color.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: DayStyle.section(context)
                .copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
