import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/category.dart';
import '../../../../core/models/enums/priority.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../timeline/presentation/providers/day_tasks_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';

class TaskEditorPanel extends ConsumerStatefulWidget {
  final bool useDialogSizing;

  const TaskEditorPanel({super.key, this.useDialogSizing = false});

  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: SizedBox(
          height: 560,
          child: TaskEditorPanel(),
        ),
      ),
    );
  }

  @override
  ConsumerState<TaskEditorPanel> createState() => _TaskEditorPanelState();
}

class _TaskEditorPanelState extends ConsumerState<TaskEditorPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late final TextEditingController _estimatedController;

  String? _editingTaskId;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _categoryId;
  Priority _priority = Priority.none;
  TaskStatus _status = TaskStatus.planned;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _notesController = TextEditingController();
    _estimatedController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _estimatedController.dispose();
    super.dispose();
  }

  void _syncFromTask(Task? task) {
    final id = task?.id;
    if (_editingTaskId == id) return;
    _editingTaskId = id;
    _titleController.text = task?.title ?? '';
    _descriptionController.text = task?.description ?? '';
    _notesController.text = task?.notes ?? '';
    _estimatedController.text =
        task?.estimatedDurationMin?.toString() ?? '';
    _categoryId = task?.categoryId;
    _priority = task?.priority ?? Priority.none;
    _status = task?.status ?? TaskStatus.planned;
    final start = task?.startTime;
    final end = task?.endTime;
    _startTime =
        start == null ? null : TimeOfDay.fromDateTime(start);
    _endTime = end == null ? null : TimeOfDay.fromDateTime(end);
  }

  Future<void> _save(Task task) async {
    final date = task.startTime ?? DateTime.now();
    final start = _startTime == null
        ? null
        : DateTime(
            date.year, date.month, date.day, _startTime!.hour, _startTime!.minute);
    final end = _endTime == null
        ? null
        : DateTime(date.year, date.month, date.day, _endTime!.hour,
            _endTime!.minute);
    final estimated = int.tryParse(_estimatedController.text.trim());
    await ref.read(taskRepositoryProvider).updateTask(task.copyWith(
          title: _titleController.text.trim().isEmpty
              ? task.title
              : _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          notes: _notesController.text.trim(),
          categoryId: _categoryId,
          priority: _priority,
          status: _status,
          startTime: start,
          endTime: end,
          estimatedDurationMin: estimated,
        ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskId = ref.watch(selectedTaskIdProvider);
    final tasksAsync = ref.watch(dayTasksProvider);

    Task? task;
    if (taskId != null) {
      final tasks =
          tasksAsync.maybeWhen(data: (t) => t, orElse: () => const <Task>[]);
      for (final t in tasks) {
        if (t.id == taskId) {
          task = t;
          break;
        }
      }
    }
    _syncFromTask(task);

    if (task == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Task',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => ref
                      .read(selectedTaskIdProvider.notifier)
                      .state = null,
                ),
              ],
            ),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              decoration:
                  const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            _CategoryDropdown(
              value: _categoryId,
              onChanged: (c) => setState(() => _categoryId = c),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<Priority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              isExpanded: true,
              items: [
                for (final p in Priority.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (p) =>
                  setState(() => _priority = p ?? Priority.none),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<TaskStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              isExpanded: true,
              items: [
                for (final s in TaskStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) =>
                  setState(() => _status = s ?? TaskStatus.planned),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(_startTime == null
                        ? 'Start'
                        : _startTime!.format(context)),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _startTime ??
                            const TimeOfDay(hour: 9, minute: 0),
                      );
                      if (picked != null) {
                        setState(() => _startTime = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time_filled, size: 16),
                    label: Text(_endTime == null
                        ? 'End'
                        : _endTime!.format(context)),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _endTime ??
                            const TimeOfDay(hour: 10, minute: 0),
                      );
                      if (picked != null) {
                        setState(() => _endTime = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _estimatedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Estimated duration (minutes)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
              onPressed: () => _save(task!),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDropdown extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.maybeWhen(
        data: (c) => c, orElse: () => const <Category>[]);
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        for (final c in categories)
          DropdownMenuItem(
            value: c.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(int.parse(c.colorHex.replaceFirst('#', '0xFF'))),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(c.name),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
