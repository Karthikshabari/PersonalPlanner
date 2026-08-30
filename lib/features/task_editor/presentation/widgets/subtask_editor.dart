import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/subtask.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../data/subtask_repository.dart';
import '../../providers/subtask_providers.dart';

/// Inline subtask checklist inside the task editor panel (planner.md Chunk 3 #4):
/// checkboxes toggle completion, Enter adds a new subtask, drag handles
/// reorder, X deletes.
class SubtaskEditor extends ConsumerStatefulWidget {
  final String taskId;

  const SubtaskEditor({super.key, required this.taskId});

  @override
  ConsumerState<SubtaskEditor> createState() => _SubtaskEditorState();
}

class _SubtaskEditorState extends ConsumerState<SubtaskEditor> {
  final _newSubtaskController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newSubtaskController.dispose();
    super.dispose();
  }

  SubtaskRepository get _repo => ref.read(subtaskRepositoryProvider);

  Future<void> _runMutation(Future<void> Function() mutation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await mutation();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || _busy) return;
    await _runMutation(() async {
      await _repo.insertSubtask(
        Subtask(
          id: '',
          taskId: widget.taskId,
          title: trimmed,
          sortOrder: 1 << 20,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      _newSubtaskController.clear();
    });
  }

  Future<void> _onReorder(
    List<Subtask> subtasks,
    int oldIndex,
    int newIndex,
  ) async {
    if (_busy) return;
    await _runMutation(() async {
      final ids = subtasks.map((s) => s.id).toList();
      final moved = ids.removeAt(oldIndex);
      ids.insert(newIndex, moved);
      await _repo.reorderSubtasks(widget.taskId, ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtasksAsync = ref.watch(subtasksForTaskProvider(widget.taskId));
    return subtasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorPanel(
        message: friendlyErrorMessage(e),
        onRetry: () => ref.invalidate(subtasksForTaskProvider(widget.taskId)),
        compact: true,
      ),
      data: (subtasks) {
        final input = TextField(
          key: const ValueKey('subtask-input'),
          controller: _newSubtaskController,
          decoration: const InputDecoration(labelText: 'Add subtask'),
          onSubmitted: _add,
          enabled: !_busy,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ErrorPanel(message: _error!, compact: true),
            if (subtasks.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: subtasks.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _onReorder(subtasks, oldIndex, newIndex),
                proxyDecorator: (child, index, animation) => ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.04).animate(animation),
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final subtask = subtasks[index];
                  return ListTile(
                    key: ValueKey('subtask-${subtask.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      key: ValueKey('subtask-check-${subtask.id}'),
                      value: subtask.isCompleted,
                      onChanged: _busy
                          ? null
                          : (_) => _runMutation(
                              () => _repo.toggleSubtask(subtask.id),
                            ),
                    ),
                    title: Text(
                      subtask.title,
                      style: TextStyle(
                        fontSize: 13,
                        decoration: subtask.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            Icons.drag_handle,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          key: ValueKey('subtask-delete-${subtask.id}'),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: _busy
                              ? null
                              : () => _runMutation(
                                  () => _repo.deleteSubtask(subtask.id),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            input,
          ],
        );
      },
    );
  }
}
