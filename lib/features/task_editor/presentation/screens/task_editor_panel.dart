import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/category.dart';
import '../../../../core/models/enums/priority.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/recurring_rule.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../recurring/domain/rrule_utils.dart';
import '../../../recurring/presentation/widgets/recurrence_scope_dialog.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../timeline/presentation/providers/day_tasks_provider.dart';
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../../../core/models/task_template.dart';
import '../../providers/tag_providers.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/save_as_template_dialog.dart';
import '../widgets/subtask_editor.dart';
import '../widgets/tag_picker.dart';
import '../widgets/use_template_dropdown.dart';

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

  // Recurrence staging (Chunk 4). `_repeat == null` means "unchanged or
  // still loading" — never persisted as-is. `_loadedPreset` is what the
  // attached rule currently looks like, so "all future" saves can tell a
  // deliberate pattern change from an untouched picker.
  String? _originalRuleId;
  RepeatPreset? _repeat;
  RepeatPreset? _loadedPreset;
  CustomRecurrenceConfig? _customConfig;

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
    _estimatedController.text = task?.estimatedDurationMin?.toString() ?? '';
    _categoryId = task?.categoryId;
    _priority = task?.priority ?? Priority.none;
    _status = task?.status ?? TaskStatus.planned;
    final start = task?.startTime;
    final end = task?.endTime;
    _startTime = start == null ? null : TimeOfDay.fromDateTime(start);
    _endTime = end == null ? null : TimeOfDay.fromDateTime(end);
    _originalRuleId = task?.recurringRuleId;
    _customConfig = null;
    _loadedPreset = null;
    // Tasks without a rule are "Never"; for recurring tasks the preset is
    // resolved once the rule loads (see build).
    _repeat = task?.recurringRuleId == null ? RepeatPreset.never : null;
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  int get _effectiveDurationMinutes {
    if (_startTime != null && _endTime != null) {
      var minutes = _endTime!.hour * 60 +
          _endTime!.minute -
          (_startTime!.hour * 60 + _startTime!.minute);
      if (minutes <= 0) minutes += 24 * 60;
      return minutes;
    }
    return (int.tryParse(_estimatedController.text.trim()) ?? 60).clamp(1, 10000);
  }

  /// RRULE string implied by the current picker selection, or `null` when
  /// nothing repeat-worthy is selected.
  String? _resolveRrule(DateTime anchorDate) {
    final preset = _repeat;
    if (preset == null || preset == RepeatPreset.never) return null;
    if (preset == RepeatPreset.custom) {
      if (_customConfig == null) return null;
      return RruleUtils.configToRrule(_customConfig!, anchorDate);
    }
    return RruleUtils.presetToRrule(preset, anchorDate);
  }

  Future<void> _save(Task task) async {
    final viewedDate = ref.read(selectedDateProvider);
    final date = task.startTime ?? DateTime.now();
    final start = _startTime == null
        ? null
        : DateTime(
            date.year, date.month, date.day, _startTime!.hour, _startTime!.minute);
    final end = _endTime == null
        ? null
        : DateTime(date.year, date.month, date.day, _endTime!.hour, _endTime!.minute);
    final estimated = int.tryParse(_estimatedController.text.trim());

    // --- Recurring scope handling (planner.md Chunk 4 #7/#8) ---
    final rulesRepo = ref.read(recurringRepositoryProvider);
    final hadRule = _originalRuleId != null;
    RecurrenceScope? scope;
    if (hadRule) {
      scope = await showRecurrenceScopeDialog(
        context,
        title: 'Recurring task',
        message:
            'This task belongs to a recurring series.\nApply your changes to:',
        thisOccurrenceLabel: 'This occurrence only',
        allFutureLabel: 'This and all future',
      );
      if (scope == null) return; // cancelled
    }

    final editedTask = task.copyWith(
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
    );

    var ruleIdForTask = _originalRuleId;
    final wantsDetach = _repeat == RepeatPreset.never;

    if (scope == RecurrenceScope.allFuture) {
      if (wantsDetach) {
        // "Never" + all future: end the whole series (history stays intact).
        await rulesRepo.deactivateRule(_originalRuleId!);
      } else {
        // Update the rule's template fields so future materializations
        // inherit the changes. The rrule is only rewritten when the picker
        // selection actually differs from the rule's current pattern —
        // regenerating from an arbitrary instance's date could otherwise
        // shift weekly/monthly anchors.
        final rule = await rulesRepo.getRuleById(_originalRuleId!);
        if (rule != null) {
          final tags =
              await ref.read(tagRepositoryProvider).getTagsForTask(task.id);
          final selectionChanged = _repeat != null &&
              (_loadedPreset == null || _repeat != _loadedPreset ||
                  (_repeat == RepeatPreset.custom && _customConfig != null));
          await rulesRepo.updateRule(rule.copyWith(
            rrule: selectionChanged
                ? (_resolveRrule(start ?? rule.startDate) ?? rule.rrule)
                : rule.rrule,
            taskTitle: editedTask.title,
            taskDescription:
                editedTask.description == '' ? null : editedTask.description,
            durationMin: _effectiveDurationMinutes,
            categoryId: _categoryId,
            priority: _priority.dbValue,
            tags: tags.map((t) => t.id).toList(),
            startTimeOfDay: _startTime == null
                ? rule.startTimeOfDay
                : _formatTimeOfDay(_startTime!),
          ));
          // Drop the cached copy so other instances of this series resolve
          // their preset from the updated pattern.
          ref.invalidate(recurringRuleProvider(_originalRuleId!));
        }
      }
    } else if (!hadRule &&
        _repeat != null &&
        _repeat != RepeatPreset.never) {
      // Attach a brand-new rule to this previously one-off task.
      final anchorDate = start ?? DateTime.now();
      final tags = await ref.read(tagRepositoryProvider).getTagsForTask(task.id);
      final rruleString = _resolveRrule(anchorDate)!;
      final rule = await rulesRepo.createRule(RecurringRule(
        id: '',
        rrule: rruleString,
        taskTitle: editedTask.title,
        taskDescription:
            editedTask.description == '' ? null : editedTask.description,
        durationMin: _effectiveDurationMinutes,
        categoryId: _categoryId,
        priority: _priority.dbValue,
        tags: tags.map((t) => t.id).toList(),
        startTimeOfDay:
            _startTime == null ? '09:00' : _formatTimeOfDay(_startTime!),
        startDate: startOfDay(anchorDate),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      ruleIdForTask = rule.id;
    } else if (scope == RecurrenceScope.thisOccurrence && wantsDetach) {
      // "Never" + this occurrence only: detach just this task.
      ruleIdForTask = null;
    }

    final saved = await ref
        .read(taskRepositoryProvider)
        .updateTask(editedTask.copyWith(recurringRuleId: ruleIdForTask));

    // Re-materialize the viewed day so new/changed rules show up instantly.
    ref.invalidate(dayMaterializationProvider(viewedDate));

    if (!mounted) return;
    setState(() {
      _originalRuleId = saved.recurringRuleId;
      if (saved.recurringRuleId == null) {
        _repeat = RepeatPreset.never;
        _customConfig = null;
        _loadedPreset = null;
      } else if (scope == RecurrenceScope.thisOccurrence) {
        // Staged repeat changes were discarded — re-resolve from the rule.
        _repeat = null;
        _customConfig = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task saved')),
    );
  }

  Future<void> _applyTemplate(TaskTemplate template, Task task) async {
    setState(() {
      _titleController.text = template.name;
      _descriptionController.text = template.description ?? '';
      _estimatedController.text = template.durationMin.toString();
      _categoryId = template.categoryId;
      _priority = Priority.fromDb(template.priority);
      if (_startTime != null) {
        _endTime = TimeOfDay.fromDateTime(
            DateTime(0, 1, 1, _startTime!.hour, _startTime!.minute)
                .add(Duration(minutes: template.durationMin)));
      }
    });
    final tagRepo = ref.read(tagRepositoryProvider);
    for (final tagId in template.tags) {
      await tagRepo.addTagToTask(task.id, tagId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskId = ref.watch(selectedTaskIdProvider);
    final tasksAsync = ref.watch(dayTasksProvider);

    Task? task;
    if (taskId != null) {
      final tasks = tasksAsync.maybeWhen(
          data: (t) => t, orElse: () => const <Task>[]);
      for (final t in tasks) {
        if (t.id == taskId) {
          task = t;
          break;
        }
      }
    }
    _syncFromTask(task);

    if (task == null) return const SizedBox.shrink();

    // Resolve the attached rule (if any) to display its preset.
    RecurringRule? rule;
    if (_originalRuleId != null) {
      final ruleAsync = ref.watch(recurringRuleProvider(_originalRuleId!));
      rule = ruleAsync.value;
      if (_repeat == null && ruleAsync.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _originalRuleId != null) {
            setState(() {
              _loadedPreset = ruleAsync.value == null
                  ? RepeatPreset.never
                  : RruleUtils.detectPreset(ruleAsync.value!.rrule);
              _repeat = _loadedPreset;
            });
          }
        });
      }
    }

    final anchorDate = startOfDay(task.startTime ?? ref.watch(selectedDateProvider));

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
                  onPressed: () =>
                      ref.read(selectedTaskIdProvider.notifier).state = null,
                ),
              ],
            ),
            UseTemplateDropdown(onSelected: (t) => _applyTemplate(t, task!)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
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
              onChanged: (p) => setState(() => _priority = p ?? Priority.none),
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
              onChanged: (s) => setState(() => _status = s ?? TaskStatus.planned),
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
            RecurrencePicker(
              selection: _repeat ?? RepeatPreset.never,
              anchorDate: anchorDate,
              existingRrule: rule?.rrule,
              customConfig: _customConfig,
              onChanged: (preset) => setState(() {
                _repeat = preset;
                if (preset != RepeatPreset.custom) _customConfig = null;
              }),
              onCustomConfirmed: (config) => setState(() {
                _customConfig = config;
                _repeat = RepeatPreset.custom;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Subtasks', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SubtaskEditor(taskId: task.id),
            const SizedBox(height: AppSpacing.lg),
            Text('Tags', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            TagPicker(taskId: task.id),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const ValueKey('save-task-button'),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
              onPressed: () => _save(task!),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('save-as-template-button'),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Save as template'),
              onPressed: () => saveAsTemplate(context, ref, task!),
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
