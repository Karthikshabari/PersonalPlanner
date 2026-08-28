import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/inbox_item.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../../../timeline/presentation/providers/day_view_controller.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../providers/inbox_provider.dart';
import '../widgets/overdue_badge.dart';

/// A draggable row in the inbox list (desktop strip / mobile tab).
/// Explicit items schedule themselves when dropped on the timeline;
/// overdue items reschedule (linked copy), per Flows 5 & 6.
class InboxTaskTile extends ConsumerWidget {
  final InboxItem item;

  const InboxTaskTile({super.key, required this.item});

  void _skip(BuildContext context, WidgetRef ref) {
    final task = item.task;
    ref
        .read(inboxRepositoryProvider)
        .scheduleStatus(task.id, TaskStatus.skipped);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    ref.read(selectedTaskIdProvider.notifier).state = item.task.id;
    if (!isDesktopWidth(MediaQuery.sizeOf(context).width)) {
      await TaskEditorPanel.showAsBottomSheet(context);
      if (context.mounted) {
        ref.read(selectedTaskIdProvider.notifier).state = null;
      }
    }
  }

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final initialDate = item.task.startTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: DateTime(initialDate.year, initialDate.month, initialDate.day),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: item.task.startTime == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(item.task.startTime!),
    );
    if (time == null || !context.mounted) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final duration = item.task.scheduledDuration?.inMinutes ?? 60;
    final end = start.add(Duration(minutes: duration));
    if (!isSameDay(start, end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task must end before midnight')),
      );
      return;
    }
    final scheduled = await TimelineActions.scheduleInboxItem(
      context,
      ref,
      item,
      start,
      end,
    );
    if (scheduled && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(item.isOverdue ? 'Rescheduled' : 'Scheduled')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = item.task;
    final tile = ListTile(
      key: ValueKey('inbox-item-${task.id}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        item.isOverdue ? Icons.history : Icons.inbox_outlined,
        size: 18,
        color: item.isOverdue ? AppColors.warning : AppColors.textSecondaryDark,
      ),
      title: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: item.isOverdue
            ? Align(alignment: Alignment.centerLeft, child: OverdueBadge(item: item))
            : null,
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('inbox-menu-${task.id}'),
        icon: const Icon(Icons.more_vert, size: 16),
        onSelected: (value) {
          if (value == 'skip') _skip(context, ref);
          if (value == 'edit') _edit(context, ref);
          if (value == 'schedule') _schedule(context, ref);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'schedule',
            child: Text(item.isOverdue ? 'Reschedule' : 'Schedule'),
          ),
          if (item.isOverdue)
            const PopupMenuItem(value: 'skip', child: Text('Mark as Skipped')),
        ],
      ),
    );

    return Draggable<InboxItem>(
      data: item,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            border: Border.all(color: AppColors.warning),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(task.title,
              style: const TextStyle(fontSize: 12)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}
