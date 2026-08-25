import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/task.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../inbox/presentation/widgets/inbox_sidebar.dart';
import '../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../providers/day_tasks_provider.dart';
import '../providers/overlap_flags_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../providers/day_view_controller.dart';
import '../../../recurring/providers/recurring_providers.dart';
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
    // Materialize recurring rules for the viewed date (Chunk 4 #3). Watching
    // the provider keeps the work alive and re-runs when the date changes.
    final selectedDate = ref.watch(selectedDateProvider);
    ref.watch(dayMaterializationProvider(selectedDate));
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
        // Chunk 5 navigation shortcuts: W toggles Day ↔ Week, Ctrl+R opens
        // the Daily Review for today.
        const SingleActivator(LogicalKeyboardKey.keyW): () =>
            _toggleWeekView(context),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            _openDailyReview(context),
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
                  InboxSidebar(),
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

  void _toggleWeekView(BuildContext context) {
    if (_isEditingText()) return;
    GoRouter.of(context).go('/week');
  }

  void _openDailyReview(BuildContext context) {
    if (_isEditingText()) return;
    GoRouter.of(context).go('/review');
  }
}
