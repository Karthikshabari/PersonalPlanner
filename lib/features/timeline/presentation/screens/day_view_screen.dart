import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/task.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/overlap_flags_provider.dart';
import '../providers/selected_task_provider.dart';
import '../providers/day_view_controller.dart';
import '../providers/undo_stack_provider.dart';
import '../widgets/day_header.dart';
import '../widgets/timeline_widget.dart';

class DayViewScreen extends ConsumerWidget {
  const DayViewScreen({super.key});

  static bool _isEditingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.widget is EditableText;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            () => _undo(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true):
            () => _redo(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyD): () =>
            _duplicateSelected(context, ref),
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _deleteSelected(context, ref),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _deleteSelected(context, ref),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop =
                constraints.maxWidth >= AppConstants.desktopBreakpoint;
            if (isDesktop) {
              return const Column(
                children: [
                  DayHeader(),
                  Divider(height: 1),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: TimelineWidget()),
                        VerticalDivider(width: 1),
                        SizedBox(
                          width: 340,
                          child: TaskEditorPanel(),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                const DayHeader(),
                const Divider(height: 1),
                Expanded(
                  child: TimelineWidget(
                    onTaskTap: (_) =>
                        TaskEditorPanel.showAsBottomSheet(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Task? _selectedTask(WidgetRef ref) {
    final id = ref.read(selectedTaskIdProvider);
    if (id == null) return null;
    final tasks = ref.read(dayTasksProvider).value ?? const <Task>[];
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _undo(BuildContext context, WidgetRef ref) {
    if (_isEditingText()) return;
    // Stale keep-overlap flags must not survive history changes.
    ref.read(keepOverlapIdsProvider.notifier).state = const <String>{};
    ref.read(undoStackProvider.notifier).undo().then((description) {
      if (description != null && context.mounted) {
        showAppToast(context, 'Undo: $description');
      }
    });
  }

  void _redo(BuildContext context, WidgetRef ref) {
    if (_isEditingText()) return;
    ref.read(keepOverlapIdsProvider.notifier).state = const <String>{};
    ref.read(undoStackProvider.notifier).redo().then((description) {
      if (description != null && context.mounted) {
        showAppToast(context, 'Redo: $description');
      }
    });
  }

  void _duplicateSelected(BuildContext context, WidgetRef ref) {
    if (_isEditingText()) return;
    final task = _selectedTask(ref);
    if (task == null) return;
    TimelineActions.duplicateTask(context, ref, task);
  }

  void _deleteSelected(BuildContext context, WidgetRef ref) {
    if (_isEditingText()) return;
    final task = _selectedTask(ref);
    if (task == null) return;
    TimelineActions.deleteWithConfirmation(context, ref, task);
  }
}
