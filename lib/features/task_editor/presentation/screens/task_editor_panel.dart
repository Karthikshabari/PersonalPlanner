import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/priority.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/recurring_rule.dart';
import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../recurring/domain/recurrence_aggregate_command.dart';
import '../../../recurring/domain/rrule_utils.dart';
import '../../../recurring/presentation/widgets/recurrence_scope_dialog.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../timeline/presentation/providers/day_tasks_provider.dart';
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../../timeline/presentation/providers/undo_stack_provider.dart';
import '../../../../core/models/task_template.dart';
import '../../providers/tag_providers.dart';
import '../../providers/task_editor_action_provider.dart';
import '../../domain/task_editor_save_command.dart';
import '../../../timer/presentation/widgets/timer_controls.dart';
import '../../../timer/providers/timer_providers.dart';
import '../widgets/category_dropdown.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/save_as_template_dialog.dart';
import '../widgets/subtask_editor.dart';
import '../widgets/tag_picker.dart';
import '../widgets/use_template_dropdown.dart';

class TaskEditorPanel extends ConsumerStatefulWidget {
  const TaskEditorPanel({super.key});

  static Future<void> showAsBottomSheet(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 8,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // AnimatedPadding deflates the constraints by the IME inset. Use
            // that post-inset height instead of adding an inset around a
            // 90%-of-full-screen child, which can request more space than the
            // visible keyboard viewport on short phones.
            final maxHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height * .9;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: const SizedBox(
                width: double.infinity,
                child: TaskEditorPanel(),
              ),
            );
          },
        ),
      ),
    ).whenComplete(() {
      container.read(selectedTaskIdProvider.notifier).state = null;
    });
  }

  @override
  ConsumerState<TaskEditorPanel> createState() => _TaskEditorPanelState();
}

class _TaskEditorPanelState extends ConsumerState<TaskEditorPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late final TextEditingController _estimatedController;
  late final TextEditingController _actualController;

  String? _editingTaskId;
  Task? _originalTask;
  Set<String>? _originalTagIds;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _scheduleDirty = false;
  String? _categoryId;
  Priority _priority = Priority.none;
  TaskStatus _status = TaskStatus.planned;
  Set<String>? _stagedTagIds;
  bool _saving = false;
  String? _errorMessage;
  Task? _activeTask;

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
    _actualController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _estimatedController.dispose();
    _actualController.dispose();
    super.dispose();
  }

  void _syncFromTask(Task? task, {bool force = false}) {
    final id = task?.id;
    if (!force && _editingTaskId == id) return;
    _editingTaskId = id;
    _originalTask = task;
    _originalTagIds = null;
    _titleController.text = task?.title ?? '';
    _descriptionController.text = task?.description ?? '';
    _notesController.text = task?.notes ?? '';
    _estimatedController.text = task?.estimatedDurationMin?.toString() ?? '';
    _actualController.text = task?.actualDurationMin?.toString() ?? '';
    _categoryId = task?.categoryId;
    _priority = task?.priority ?? Priority.none;
    _status = task?.status ?? TaskStatus.planned;
    _stagedTagIds = null;
    final start = task?.startTime;
    final end = task?.endTime;
    _startTime = start == null
        ? null
        : TimeOfDay.fromDateTime(PlannerTimeZone.toPlannerLocal(start));
    _endTime = end == null
        ? null
        : TimeOfDay.fromDateTime(PlannerTimeZone.toPlannerLocal(end));
    _scheduleDirty = false;
    _originalRuleId = task?.recurringRuleId;
    _customConfig = null;
    _loadedPreset = null;
    // Tasks without a rule are "Never"; for recurring tasks the preset is
    // resolved once the rule loads (see build).
    _repeat = task?.recurringRuleId == null ? RepeatPreset.never : null;
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  bool _sameIds(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  bool get _hasDraftChanges {
    final original = _originalTask;
    if (original == null) return false;
    if (_titleController.text.trim() != original.title ||
        _descriptionController.text.trim() != (original.description ?? '') ||
        _notesController.text.trim() != (original.notes ?? '') ||
        _estimatedController.text.trim() !=
            (original.estimatedDurationMin?.toString() ?? '') ||
        _actualController.text.trim() !=
            (original.actualDurationMin?.toString() ?? '') ||
        _categoryId != original.categoryId ||
        _priority != original.priority ||
        _status != original.status ||
        _scheduleDirty) {
      return true;
    }
    if (_stagedTagIds != null &&
        _originalTagIds != null &&
        !_sameIds(_stagedTagIds!, _originalTagIds!)) {
      return true;
    }
    if (_originalRuleId == null) {
      return _repeat != null && _repeat != RepeatPreset.never;
    }
    return _repeat != null &&
        _loadedPreset != null &&
        (_repeat != _loadedPreset ||
            (_repeat == RepeatPreset.custom && _customConfig != null));
  }

  void _closeImmediately() {
    ref.read(selectedTaskIdProvider.notifier).state = null;
    if (MediaQuery.sizeOf(context).width < 900 &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_hasDraftChanges) {
      _closeImmediately();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your edits will be lost if you close the editor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _closeImmediately();
  }

  Future<_ExternalMergeChoice?> _showExternalConflictDialog(
    List<String> fields,
  ) {
    return showDialog<_ExternalMergeChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Task changed elsewhere'),
        content: Text(
          'These fields changed both here and elsewhere: ${fields.join(', ')}.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('reload-task'),
            onPressed: () =>
                Navigator.of(context).pop(_ExternalMergeChoice.reload),
            child: const Text('Reload'),
          ),
          FilledButton(
            key: const ValueKey('keep-my-task'),
            onPressed: () =>
                Navigator.of(context).pop(_ExternalMergeChoice.keepMine),
            child: const Text('Keep Mine'),
          ),
        ],
      ),
    );
  }

  int get _effectiveDurationMinutes {
    if (!_scheduleDirty) {
      final persisted = _originalTask?.scheduledDuration;
      if (persisted != null) {
        return persisted.inMinutes.clamp(1, 10000);
      }
    }
    if (_startTime != null && _endTime != null) {
      var minutes =
          _endTime!.hour * 60 +
          _endTime!.minute -
          (_startTime!.hour * 60 + _startTime!.minute);
      if (minutes <= 0) minutes += Duration.minutesPerDay;
      return minutes;
    }
    return (int.tryParse(_estimatedController.text.trim()) ?? 60).clamp(
      1,
      10000,
    );
  }

  SaveAsTemplateDraft? _currentTemplateDraft(Task task, Set<String> tagIds) {
    final title = _titleController.text.trim();
    final estimatedText = _estimatedController.text.trim();
    final estimated = int.tryParse(estimatedText);
    if (title.isEmpty) {
      _showValidationError('Title must not be blank');
      return null;
    }
    if (estimatedText.isNotEmpty && estimated == null) {
      _showValidationError('Estimated duration must be a whole number');
      return null;
    }
    if (estimated != null && estimated <= 0) {
      _showValidationError('Estimated duration must be positive');
      return null;
    }
    if (_startTime != null &&
        _endTime != null &&
        _effectiveDurationMinutes <= 0) {
      _showValidationError('End time must be later than start time');
      return null;
    }
    final description = _descriptionController.text.trim();
    return SaveAsTemplateDraft(
      suggestedName: title,
      description: description.isEmpty ? null : description,
      durationMin: estimated ?? _effectiveDurationMinutes,
      categoryId: _categoryId,
      priority: _priority.dbValue,
      tagIds: Set.unmodifiable(tagIds),
      sourceTaskId: task.id,
    );
  }

  Future<void> _saveCurrentDraftAsTemplate(
    Task task,
    Set<String> tagIds,
  ) async {
    final draft = _currentTemplateDraft(task, tagIds);
    if (draft == null || !mounted) return;
    try {
      await saveAsTemplate(context, ref, draft);
    } catch (error) {
      if (mounted) _showValidationError(friendlyErrorMessage(error));
    }
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

  Future<void> _save(Task task, {bool close = false}) async {
    if (_saving) return;
    try {
      await _saveImpl(task, close: close);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = friendlyErrorMessage(error);
      });
      _showValidationError(friendlyErrorMessage(error));
    }
  }

  Future<void> _saveImpl(Task task, {bool close = false}) async {
    if (_saving) return;
    final viewedDate = ref.read(selectedDateProvider);
    final date = task.startTime ?? viewedDate;
    final localDate = PlannerTimeZone.toPlannerLocal(date);
    // TimeOfDay is only a display/editor control. Until the user touches a
    // schedule button, retain the persisted instants verbatim so multi-day
    // intervals and seconds cannot be shortened by a title-only save.
    final start = !_scheduleDirty
        ? task.startTime
        : _startTime == null
        ? null
        : PlannerTimeZone.calendarDate(
            localDate.year,
            localDate.month,
            localDate.day,
            hour: _startTime!.hour,
            minute: _startTime!.minute,
          );
    var end = !_scheduleDirty
        ? task.endTime
        : _endTime == null
        ? null
        : PlannerTimeZone.calendarDate(
            localDate.year,
            localDate.month,
            localDate.day,
            hour: _endTime!.hour,
            minute: _endTime!.minute,
          );
    if (start != null && end != null && !end.isAfter(start)) {
      final endLocal = PlannerTimeZone.toPlannerLocal(end);
      end = PlannerTimeZone.calendarDate(
        endLocal.year,
        endLocal.month,
        endLocal.day + 1,
        hour: _endTime!.hour,
        minute: _endTime!.minute,
      );
    }
    final estimatedText = _estimatedController.text.trim();
    final actualText = _actualController.text.trim();
    final estimated = int.tryParse(estimatedText);
    final actual = int.tryParse(actualText);
    if (_titleController.text.trim().isEmpty) {
      _showValidationError('Title must not be blank');
      return;
    }
    if (estimatedText.isNotEmpty && estimated == null) {
      _showValidationError('Estimated duration must be a whole number');
      return;
    }
    if (estimated != null && estimated <= 0) {
      _showValidationError('Estimated duration must be positive');
      return;
    }
    if (actualText.isNotEmpty && actual == null) {
      _showValidationError('Actual duration must be a whole number');
      return;
    }
    if (actual != null && actual < 0) {
      _showValidationError('Actual duration must not be negative');
      return;
    }
    if (start != null && end != null && !end.isAfter(start)) {
      _showValidationError('End time must be later than start time');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

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
      if (scope == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }

    final stagedTagIds =
        _stagedTagIds ??
        (await ref.read(tagRepositoryProvider).getTagsForTask(task.id))
            .map((tag) => tag.id)
            .toSet();

    // Read the current row immediately before writing. The editor keeps the
    // original snapshot from when it opened, so changes made elsewhere can
    // be merged field-by-field instead of silently being overwritten.
    final latest = await ref.read(taskRepositoryProvider).getTaskById(task.id);
    if (latest == null || latest.deletedAt != null) {
      throw StateError('Task ${task.id} is no longer available');
    }
    final original = _originalTask ?? task;
    final latestTagIds =
        (await ref.read(tagRepositoryProvider).getTagsForTask(task.id))
            .map((tag) => tag.id)
            .toSet();
    final originalTagIds = _originalTagIds ?? stagedTagIds;
    final normalizedDescription = _descriptionController.text.trim();
    final normalizedNotes = _notesController.text.trim();
    final actualDirty =
        _actualController.text.trim() !=
        (original.actualDurationMin?.toString() ?? '');
    final localDraft = task.copyWith(
      title: _titleController.text.trim(),
      description: normalizedDescription.isEmpty ? null : normalizedDescription,
      notes: normalizedNotes.isEmpty ? null : normalizedNotes,
      categoryId: _categoryId,
      priority: _priority,
      status: _status,
      startTime: start,
      endTime: end,
      estimatedDurationMin: estimated,
      actualDurationMin: actualDirty
          ? (actual ?? task.actualDurationMin)
          : null,
    );

    bool changed<T>(T local, T baseline) => local != baseline;
    final conflicts = <String>[];
    void checkConflict<T>(String label, T local, T baseline, T remote) {
      if (changed(local, baseline) &&
          changed(remote, baseline) &&
          local != remote) {
        conflicts.add(label);
      }
    }

    checkConflict('Title', localDraft.title, original.title, latest.title);
    checkConflict(
      'Description',
      localDraft.description,
      original.description,
      latest.description,
    );
    checkConflict('Notes', localDraft.notes, original.notes, latest.notes);
    checkConflict(
      'Category',
      localDraft.categoryId,
      original.categoryId,
      latest.categoryId,
    );
    checkConflict(
      'Priority',
      localDraft.priority,
      original.priority,
      latest.priority,
    );
    checkConflict('Status', localDraft.status, original.status, latest.status);
    checkConflict(
      'Start time',
      localDraft.startTime,
      original.startTime,
      latest.startTime,
    );
    checkConflict(
      'End time',
      localDraft.endTime,
      original.endTime,
      latest.endTime,
    );
    checkConflict(
      'Estimated duration',
      localDraft.estimatedDurationMin,
      original.estimatedDurationMin,
      latest.estimatedDurationMin,
    );
    if (actualDirty) {
      checkConflict(
        'Actual duration',
        actual,
        original.actualDurationMin,
        latest.actualDurationMin,
      );
    }
    final tagsDirty = !_sameIds(stagedTagIds, originalTagIds);
    if (tagsDirty && !_sameIds(latestTagIds, originalTagIds)) {
      conflicts.add('Tags');
    }

    if (conflicts.isNotEmpty) {
      final choice = await _showExternalConflictDialog(conflicts);
      if (choice == _ExternalMergeChoice.reload) {
        _syncFromTask(latest, force: true);
        if (mounted) {
          setState(() {
            _originalTagIds = latestTagIds;
            _stagedTagIds = latestTagIds;
            _saving = false;
          });
        }
        return;
      }
      if (choice != _ExternalMergeChoice.keepMine) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }

    final editedTask = latest.copyWith(
      title: changed(localDraft.title, original.title)
          ? localDraft.title
          : latest.title,
      description: changed(localDraft.description, original.description)
          ? localDraft.description
          : latest.description,
      notes: changed(localDraft.notes, original.notes)
          ? localDraft.notes
          : latest.notes,
      categoryId: changed(localDraft.categoryId, original.categoryId)
          ? localDraft.categoryId
          : latest.categoryId,
      priority: changed(localDraft.priority, original.priority)
          ? localDraft.priority
          : latest.priority,
      status: changed(localDraft.status, original.status)
          ? localDraft.status
          : latest.status,
      startTime: changed(localDraft.startTime, original.startTime)
          ? localDraft.startTime
          : latest.startTime,
      endTime: changed(localDraft.endTime, original.endTime)
          ? localDraft.endTime
          : latest.endTime,
      estimatedDurationMin:
          changed(
            localDraft.estimatedDurationMin,
            original.estimatedDurationMin,
          )
          ? localDraft.estimatedDurationMin
          : latest.estimatedDurationMin,
      actualDurationMin: actualDirty
          ? (actual ?? latest.actualDurationMin)
          : latest.actualDurationMin,
    );
    final tagsToSave = tagsDirty ? stagedTagIds : latestTagIds;

    if (editedTask.status != latest.status &&
        !latest.status.allowedTransitions.contains(editedTask.status)) {
      throw StateError(
        'Cannot change ${latest.status.label} to ${editedTask.status.label}',
      );
    }

    final wantsDetach = _repeat == RepeatPreset.never;

    if (hadRule) {
      final ruleId = _originalRuleId!;
      final boundary = startOfDay(task.startTime ?? viewedDate);
      final selectionChanged =
          _repeat != null &&
          (_loadedPreset == null ||
              _repeat != _loadedPreset ||
              (_repeat == RepeatPreset.custom && _customConfig != null));
      final command = RecurrenceAggregateCommand(
        database: ref.read(appDatabaseProvider),
        ruleId: ruleId,
        description: scope == RecurrenceScope.allFuture
            ? 'Update future recurring tasks'
            : 'Update recurring occurrence',
        mutation: () async {
          final liveRule = await rulesRepo.getRuleById(ruleId);
          if (liveRule == null) {
            throw StateError('Recurring rule $ruleId not found');
          }
          if (scope == RecurrenceScope.allFuture) {
            if (wantsDetach) {
              await rulesRepo.setEndDate(ruleId, addDays(boundary, -1));
              await rulesRepo.deactivateRule(ruleId);
              await ref
                  .read(recurrenceServiceProvider)
                  .deleteMaterializedFuture(
                    ruleId,
                    boundary,
                    keepTaskId: task.id,
                  );
            } else {
              final updatedRule = liveRule.copyWith(
                rrule: selectionChanged
                    ? (_resolveRrule(start ?? liveRule.startDate) ??
                          liveRule.rrule)
                    : liveRule.rrule,
                taskTitle: editedTask.title,
                taskDescription: editedTask.description == ''
                    ? null
                    : editedTask.description,
                durationMin: _effectiveDurationMinutes,
                categoryId: _categoryId,
                priority: _priority.dbValue,
                tags: tagsToSave.toList(),
                startTimeOfDay: _startTime == null
                    ? liveRule.startTimeOfDay
                    : _formatTimeOfDay(_startTime!),
              );
              await rulesRepo.updateRule(updatedRule);
              await ref
                  .read(recurrenceServiceProvider)
                  .reconcileMaterializedFuture(updatedRule, boundary);
            }
          } else if (wantsDetach) {
            await rulesRepo.addException(ruleId, boundary);
          }

          await ref
              .read(taskRepositoryProvider)
              .updateTask(
                editedTask.copyWith(
                  recurringRuleId:
                      scope == RecurrenceScope.allFuture && wantsDetach
                      ? null
                      : (wantsDetach && scope == RecurrenceScope.thisOccurrence
                            ? null
                            : ruleId),
                ),
              );
          if (actualDirty && actual != null) {
            await ref
                .read(timerServiceProvider)
                .setManualActual(task.id, actual);
          }
          await ref
              .read(tagRepositoryProvider)
              .replaceTagsForTask(task.id, tagsToSave);
        },
      );
      await ref.read(undoStackProvider.notifier).execute(command);
      ref.invalidate(recurringRuleProvider(ruleId));
    } else if (!hadRule && _repeat != null && _repeat != RepeatPreset.never) {
      // Attach a brand-new rule to this previously one-off task.
      final anchorDate = start ?? DateTime.now();
      final rruleString = _resolveRrule(anchorDate)!;
      await TaskEditorSaveCommand(
        ref.read(appDatabaseProvider),
      ).execute(() async {
        final rule = await rulesRepo.createRule(
          RecurringRule(
            id: '',
            rrule: rruleString,
            taskTitle: editedTask.title,
            taskDescription: editedTask.description == ''
                ? null
                : editedTask.description,
            durationMin: _effectiveDurationMinutes,
            categoryId: _categoryId,
            priority: _priority.dbValue,
            tags: stagedTagIds.toList(),
            startTimeOfDay: _startTime == null
                ? '09:00'
                : _formatTimeOfDay(_startTime!),
            startDate: startOfDay(anchorDate),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await ref
            .read(taskRepositoryProvider)
            .updateTask(editedTask.copyWith(recurringRuleId: rule.id));
        if (actualDirty && actual != null) {
          await ref.read(timerServiceProvider).setManualActual(task.id, actual);
        }
        await ref
            .read(tagRepositoryProvider)
            .replaceTagsForTask(task.id, tagsToSave);
      });
    } else {
      await TaskEditorSaveCommand(
        ref.read(appDatabaseProvider),
      ).execute(() async {
        await ref
            .read(taskRepositoryProvider)
            .updateTask(editedTask.copyWith(recurringRuleId: null));
        if (actualDirty && actual != null) {
          await ref.read(timerServiceProvider).setManualActual(task.id, actual);
        }
        await ref
            .read(tagRepositoryProvider)
            .replaceTagsForTask(task.id, tagsToSave);
      });
    }

    final saved = await ref.read(taskRepositoryProvider).getTaskById(task.id);
    if (saved == null) throw StateError('Task ${task.id} not found after save');

    // Re-materialize the viewed day so new/changed rules show up instantly.
    ref.invalidate(dayMaterializationProvider(viewedDate));

    if (!mounted) return;
    setState(() {
      _originalRuleId = saved.recurringRuleId;
      _originalTask = saved;
      _originalTagIds = tagsToSave;
      _stagedTagIds = tagsToSave;
      _saving = false;
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Task saved')));
    if (close && mounted) {
      ref.read(selectedTaskIdProvider.notifier).state = null;
      if (MediaQuery.sizeOf(context).width < 900 &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showValidationError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyTemplate(TaskTemplate template, Task task) async {
    setState(() {
      _titleController.text = template.name;
      _descriptionController.text = template.description ?? '';
      _estimatedController.text = template.durationMin.toString();
      _categoryId = template.categoryId;
      _priority = Priority.fromDb(template.priority);
      _stagedTagIds = template.tags.toSet();
      if (_startTime != null) {
        _scheduleDirty = true;
        final totalMinutes =
            _startTime!.hour * 60 + _startTime!.minute + template.durationMin;
        _endTime = TimeOfDay(
          hour: (totalMinutes ~/ 60) % 24,
          minute: totalMinutes % 60,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(taskEditorSaveRequestProvider, (previous, next) {
      if (previous == next || _activeTask == null) return;
      unawaited(_save(_activeTask!, close: true));
    });
    final taskId = ref.watch(selectedTaskIdProvider);
    final tasksAsync = ref.watch(dayTasksProvider);
    final selectedTaskAsync = taskId == null
        ? const AsyncValue<Task?>.data(null)
        : ref.watch(selectedTaskByIdProvider(taskId));

    if (taskId != null && tasksAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(tasksAsync.error!),
        onRetry: () {
          ref.invalidate(dayTasksProvider);
          ref.invalidate(selectedTaskByIdProvider(taskId));
        },
      );
    }
    if (taskId != null && selectedTaskAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(selectedTaskAsync.error!),
        onRetry: () => ref.invalidate(selectedTaskByIdProvider(taskId)),
      );
    }
    if (taskId != null && !tasksAsync.hasValue && !selectedTaskAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    if (taskId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 28,
                color: AppThemeTokens.of(context).textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Select a task to edit',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Choose a block from the timeline or Inbox.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    Task? task;
    for (final t in tasksAsync.value ?? const <Task>[]) {
      if (t.id == taskId) {
        task = t;
        break;
      }
    }
    task ??= selectedTaskAsync.value;
    _activeTask = task;
    _syncFromTask(task);

    if (task == null) {
      return const ErrorPanel(
        message: 'The selected task is no longer available.',
      );
    }
    final selectedTaskId = task.id;

    final taskTagsAsync = ref.watch(tagsForTaskProvider(selectedTaskId));
    final persistedTagIds =
        taskTagsAsync.value?.map((tag) => tag.id).toSet() ??
        _stagedTagIds ??
        <String>{};
    if (_stagedTagIds == null && taskTagsAsync.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stagedTagIds == null) {
          setState(() {
            _originalTagIds ??= persistedTagIds;
            _stagedTagIds = persistedTagIds;
          });
        }
      });
    }

    // Resolve the attached rule (if any) to display its preset.
    RecurringRule? rule;
    AsyncValue<RecurringRule?>? ruleAsync;
    if (_originalRuleId != null) {
      final loadedRuleAsync = ref.watch(
        recurringRuleProvider(_originalRuleId!),
      );
      ruleAsync = loadedRuleAsync;
      rule = loadedRuleAsync.value;
      if (_repeat == null && loadedRuleAsync.hasValue) {
        final loadedRule = loadedRuleAsync.value;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _originalRuleId != null) {
            setState(() {
              _loadedPreset = loadedRule == null
                  ? RepeatPreset.never
                  : RruleUtils.detectPreset(loadedRule.rrule);
              _repeat = _loadedPreset;
            });
          }
        });
      }
    }

    final anchorDate = startOfDay(
      task.startTime ?? ref.watch(selectedDateProvider),
    );

    final tokens = AppThemeTokens.of(context);
    return PopScope<void>(
      canPop: !_hasDraftChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: ColoredBox(
        color: tokens.surfaceSubtle,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.selected,
                        borderRadius: BorderRadius.circular(tokens.radiusSmall),
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 19,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppSectionHeader(
                        title: 'Edit Task',
                        subtitle: 'Keep the plan clear and actionable',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close editor',
                      icon: const Icon(Icons.close),
                      onPressed: _requestClose,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Task details',
                  icon: Icons.subject_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_errorMessage != null)
                  ErrorPanel(message: _errorMessage!, compact: true),
                if (taskTagsAsync.hasError)
                  ErrorPanel(
                    message: friendlyErrorMessage(taskTagsAsync.error!),
                    onRetry: () =>
                        ref.invalidate(tagsForTaskProvider(selectedTaskId)),
                    compact: true,
                  ),
                if (!taskTagsAsync.hasValue && _stagedTagIds == null)
                  const Center(child: CircularProgressIndicator()),
                if (ruleAsync?.hasError ?? false)
                  ErrorPanel(
                    message: friendlyErrorMessage(ruleAsync!.error!),
                    onRetry: () =>
                        ref.invalidate(recurringRuleProvider(_originalRuleId!)),
                    compact: true,
                  ),
                if (ruleAsync != null && !ruleAsync.hasValue)
                  const Center(child: CircularProgressIndicator()),
                UseTemplateDropdown(
                  onSelected: (t) => _applyTemplate(t, task!),
                ),
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
                const AppSectionHeader(
                  title: 'Schedule and status',
                  icon: Icons.schedule_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                CategoryDropdown(
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
                    for (final s in {
                      _status,
                      ...(_originalTask?.status.allowedTransitions ??
                          const <TaskStatus>[]),
                    })
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: _status == TaskStatus.rescheduled
                      ? null
                      : (s) =>
                            setState(() => _status = s ?? TaskStatus.planned),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(
                          _startTime == null
                              ? 'Start'
                              : _startTime!.format(context),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _startTime ??
                                const TimeOfDay(hour: 9, minute: 0),
                          );
                          if (picked != null) {
                            setState(() {
                              _startTime = picked;
                              _scheduleDirty = true;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_filled, size: 16),
                        label: Text(
                          _endTime == null ? 'End' : _endTime!.format(context),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _endTime ??
                                const TimeOfDay(hour: 10, minute: 0),
                          );
                          if (picked != null) {
                            setState(() {
                              _endTime = picked;
                              _scheduleDirty = true;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const AppSectionHeader(
                  title: 'Time tracking',
                  icon: Icons.timer_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _estimatedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Estimated duration (minutes)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey('actual-duration-field'),
                  controller: _actualController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Actual duration (minutes)',
                    helperText: 'Auto-tracked by the timer; editable',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const SizedBox(height: AppSpacing.lg),
                AppSurface(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TimerControls(task: task),
                ),
                const SizedBox(height: AppSpacing.md),
                if (ruleAsync == null || ruleAsync.hasValue)
                  AppSurface(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: RecurrencePicker(
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
                  ),
                const SizedBox(height: AppSpacing.md),
                const AppSectionHeader(
                  title: 'Notes and context',
                  icon: Icons.notes_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Subtasks',
                  icon: Icons.checklist_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Subtask checks and additions save immediately.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppSurface(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SubtaskEditor(taskId: task.id),
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Tags',
                  icon: Icons.sell_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Tag selection is saved with the task; new tag names are created immediately.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppSurface(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TagPicker(
                    taskId: task.id,
                    selectedIds: _stagedTagIds ?? persistedTagIds,
                    onChanged: (ids) => setState(() => _stagedTagIds = ids),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const ValueKey('save-task-button'),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                  onPressed: _saving ? null : () => _save(task!),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('save-as-template-button'),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save as template'),
                  onPressed: _saving
                      ? null
                      : () => _saveCurrentDraftAsTemplate(
                          task!,
                          _stagedTagIds ?? persistedTagIds,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ExternalMergeChoice { reload, keepMine }
