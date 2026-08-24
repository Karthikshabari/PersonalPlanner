import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/widgets/app_toast.dart';
import '../providers/day_view_controller.dart';
import '../providers/selected_task_provider.dart';

/// Right-click (desktop) / long-press (mobile) context menu for a task block:
/// Edit, Duplicate, Delete, Change Status (submenu).
Future<void> showTaskContextMenu(
  BuildContext context,
  WidgetRef ref,
  Task task,
  Offset globalPosition,
) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    items: const [
      PopupMenuItem(value: 'edit', height: 40, child: Text('Edit')),
      PopupMenuItem(value: 'duplicate', height: 40, child: Text('Duplicate')),
      PopupMenuItem(
          value: 'delete', height: 40, child: Text('Delete')),
      PopupMenuItem(
          value: 'status',
          height: 40,
          child: Text('Change Status ›')),
    ],
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'edit':
      ref.read(selectedTaskIdProvider.notifier).state = task.id;
      break;
    case 'duplicate':
      await TimelineActions.duplicateTask(context, ref, task);
      break;
    case 'delete':
      await TimelineActions.deleteWithConfirmation(context, ref, task);
      break;
    case 'status':
      final status = await _showStatusSubmenu(context, globalPosition);
      if (status != null) {
        await TimelineActions.setStatus(ref, task, status);
        if (!context.mounted) return;
        showAppToast(context, 'Status: ${status.label}');
      }
      break;
  }
}

Future<TaskStatus?> _showStatusSubmenu(
  BuildContext context,
  Offset globalPosition,
) {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<TaskStatus>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx + 120,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx - 120,
      overlay.size.height - globalPosition.dy,
    ),
    items: [
      for (final status in TaskStatus.values)
        PopupMenuItem(
          value: status,
          height: 36,
          child: Text(status.label),
        ),
    ],
  );
}
