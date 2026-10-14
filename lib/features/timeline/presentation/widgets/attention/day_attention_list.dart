import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/models/inbox_item.dart';
import '../../../../../core/providers/database_provider.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_theme_tokens.dart';
import '../../../../../core/utils/clock_format.dart';
import '../../../../../core/utils/planner_time_zone.dart';
import '../../../../../core/widgets/confirm_dialog.dart';
import '../../../../../core/widgets/error_panel.dart';
import '../../../../inbox/providers/inbox_provider.dart';
import '../../../domain/commands/batch_command.dart';
import '../../../../inbox/domain/inbox_commands.dart';
import '../../providers/grid_settings_provider.dart';
import '../../providers/undo_stack_provider.dart';
import '../day_style.dart';
import 'attention_groups.dart';
import 'day_attention_row.dart';
import 'move_to_today_slot.dart';

/// "Needs attention": a header (title, count, "Move all to today") and the
/// items in groups (Due today, Earlier, Yesterday, Today), each group a lazy
/// [SliverList] under a small heading.
///
/// Used by the compact sheet, the medium strip and the side panel. With a
/// [controller] (the sheet's) the header is the first sliver so dragging it
/// moves the sheet; otherwise it stays pinned above the scrolling list.
class DayAttentionList extends ConsumerWidget {
  const DayAttentionList({
    super.key,
    required this.items,
    required this.showDragHandle,
    this.showTitle = true,
    this.controller,
    this.scrollKey,
    this.leading,
    this.feedbackContext,
  });

  final List<InboxItem> items;

  /// Whether rows show the 6-dot handle that drags onto the timeline.
  final bool showDragHandle;

  /// False when the host (the strip) already has its own title line; the
  /// header then only holds "Move all to today".
  final bool showTitle;

  /// The compact sheet's scroll controller; puts the header inside the scroll
  /// view.
  final ScrollController? controller;

  /// Key of the scroll view.
  final Key? scrollKey;

  /// Shown above the header, inside the scroll view (the sheet's grab bar).
  final Widget? leading;

  /// See [AttentionFeedback.capture].
  final BuildContext? feedbackContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now =
        ref.watch(inboxClockProvider.select((clock) => clock.value)) ??
        ref.read(inboxNowFactoryProvider)();
    final groups = groupAttention(items, now);
    final overdue = [
      for (final group in groups)
        if (group.kind != AttentionGroupKind.dueToday) ...group.items,
    ];
    final header = _Header(
      count: items.length,
      showTitle: showTitle,
      onMoveAll: overdue.length >= 2
          ? () => unawaited(_moveAll(context, ref, overdue))
          : null,
    );
    final insideScroll = controller != null;
    final scroll = CustomScrollView(
      key: scrollKey,
      controller: controller,
      physics: insideScroll ? const AlwaysScrollableScrollPhysics() : null,
      slivers: [
        if (insideScroll) ...[
          if (leading != null) SliverToBoxAdapter(child: leading),
          SliverToBoxAdapter(child: header),
        ],
        for (final group in groups) ...[
          SliverToBoxAdapter(child: _GroupHeader(group: group)),
          SliverList.builder(
            itemCount: group.items.length,
            itemBuilder: (context, index) {
              final item = group.items[index];
              return DayAttentionRow(
                key: ValueKey('day-attention-${item.task.id}'),
                item: item,
                showDragHandle: showDragHandle,
                feedbackContext: feedbackContext,
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      ],
    );
    if (insideScroll) return scroll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: scroll),
      ],
    );
  }

  /// Moves every overdue task to today in one undo step: oldest first, each
  /// at the next free grid slot after the previous one, durations kept. The
  /// slots are free, so there is no per-task conflict dialog. Tasks that no
  /// longer fit before midnight stay overdue (the dialog says how many fit).
  Future<void> _moveAll(
    BuildContext context,
    WidgetRef ref,
    List<InboxItem> overdue,
  ) async {
    // Everything the steps after an await need is read now.
    final feedback = AttentionFeedback.capture(
      context,
      ref,
      anchor: feedbackContext,
    );
    final tasks = ref.read(taskRepositoryProvider);
    final inbox = ref.read(inboxRepositoryProvider);
    final database = ref.read(appDatabaseProvider);
    final undo = ref.read(undoStackProvider.notifier);
    final grid =
        ref.read(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;

    Future<List<PlacedMove>> plan() async {
      final now =
          ref.read(inboxClockProvider).value ??
          ref.read(inboxNowFactoryProvider)();
      final (dayStart, dayEnd) = PlannerTimeZone.dayBounds(now);
      final today = await tasks.getScheduledTasksBetween(dayStart, dayEnd);
      return placeAllToday(
        [for (final item in overdue) item.task],
        now,
        grid,
        today,
      );
    }

    try {
      final preview = await plan();
      if (!context.mounted) return;
      if (preview.isEmpty) {
        feedback.show('No room left today.', withUndo: false);
        return;
      }
      final total = overdue.length;
      final fit = preview.length;
      final rule =
          'Oldest first, one after another from '
          '${formatClock24(preview.first.slot.start)}, each keeping its length.';
      final confirmed = await showConfirmDialog(
        context,
        title: fit == total
            ? 'Move $total overdue tasks to today?'
            : 'Move $fit of $total overdue tasks to today?',
        message: fit == total
            ? rule
            : '$rule Only $fit fit before midnight; the other '
                  '${total - fit} stay overdue.',
        confirmLabel: 'Move to today',
        destructive: false,
      );
      if (!confirmed || !context.mounted) return;

      // The plan is made again so it is based on today's blocks and the
      // clock as they are now, not as they were when the dialog opened.
      final placed = await plan();
      if (placed.isEmpty) {
        feedback.show('No room left today.', withUndo: false);
        return;
      }
      final batch = BatchCommand([
        for (final move in placed)
          RescheduleOverdueCommand(
            repository: inbox,
            originalId: move.task.id,
            start: move.slot.start,
            end: move.slot.end,
          ),
      ], database: database);
      await undo.execute(batch);
      feedback.show('Moved ${placed.length} to today');
    } on Object catch (error) {
      feedback.show(friendlyErrorMessage(error), withUndo: false);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.showTitle,
    required this.onMoveAll,
  });

  final int count;
  final bool showTitle;
  final VoidCallback? onMoveAll;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final moveAll = onMoveAll == null
        ? null
        : TextButton(
            key: const ValueKey('day-attention-move-all'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onMoveAll,
            child: const Text('Move all to today'),
          );
    if (!showTitle) {
      if (moveAll == null) return const SizedBox.shrink();
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: moveAll,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: tokens.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'Needs attention',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DayStyle.section(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  key: const ValueKey('day-attention-count'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(DayStyle.pill),
                  ),
                  child: Text(
                    '$count',
                    style: DayStyle.secondary(context).copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            ?moveAll,
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final AttentionGroup group;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Text(
          '${group.label} · ${group.items.length}',
          key: ValueKey('day-attention-group-${group.kind.name}'),
          style: DayStyle.section(context)
              .copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}
