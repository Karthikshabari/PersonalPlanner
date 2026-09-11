import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/priority.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/recurring_rule.dart';
import '../../../../core/models/task.dart';
import '../../../../core/constants/app_constants.dart';
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
import '../../../timeline/domain/conflict_resolver.dart';
import '../../../timeline/domain/scheduling_conflict_service.dart';
import '../../../timeline/presentation/widgets/conflict_resolution_dialog.dart';
import '../../../../core/models/task_template.dart';
import '../../providers/tag_providers.dart';
import '../../providers/task_editor_action_provider.dart';
import '../../domain/task_editor_save_command.dart';
import '../../domain/task_editor_draft.dart';
import '../../../timer/presentation/widgets/timer_controls.dart';
import '../../../timer/providers/timer_providers.dart';
import '../widgets/category_dropdown.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/save_as_template_dialog.dart';
import '../widgets/subtask_editor.dart';
import '../widgets/tag_picker.dart';
import '../widgets/use_template_dropdown.dart';

enum TaskEditorPresentation { desktopPanel, bottomSheet }

class TaskEditorPanel extends ConsumerStatefulWidget {
  final TaskEditorPresentation presentation;

  /// Parent-owned close action. For a bottom sheet this callback is
  /// responsible for dismissing the sheet; without it the panel pops its
  /// own modal route.
  final VoidCallback? onClose;

  const TaskEditorPanel({
    super.key,
    this.presentation = TaskEditorPresentation.desktopPanel,
    this.onClose,
  });

  static Future<void> showAsBottomSheet(
    BuildContext context, {
    VoidCallback? onClose,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
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
              child: SizedBox(
                width: double.infinity,
                child: TaskEditorPanel(
                  presentation: TaskEditorPresentation.bottomSheet,
                  onClose: onClose,
                ),
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
  Task? _conflictBaselineTask;
  TaskEditorBaseline? _baseline;
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
  bool _synchronizingControllers = false;

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
    for (final controller in [
      _titleController,
      _descriptionController,
      _notesController,
      _estimatedController,
      _actualController,
    ]) {
      controller.addListener(_onEditorControllerChanged);
    }
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

  void _onEditorControllerChanged() {
    if (_synchronizingControllers || !mounted) return;
    // PopScope must be rebuilt as soon as a text field changes; relying on a
    // later provider rebuild leaves Android Back/barrier dismissal with a
    // stale clean-state decision.
    setState(() {});
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  bool _sameTimeOfDay(TimeOfDay? left, TimeOfDay? right) =>
      left?.hour == right?.hour && left?.minute == right?.minute;

  bool get _scheduleInputsChanged {
    final task = _baseline?.task ?? _originalTask;
    if (task == null) return false;
    final originalStart = task.startTime == null
        ? null
        : TimeOfDay.fromDateTime(
            PlannerTimeZone.toPlannerLocal(task.startTime!),
          );
    final originalEnd = task.endTime == null
        ? null
        : TimeOfDay.fromDateTime(PlannerTimeZone.toPlannerLocal(task.endTime!));
    return !_sameTimeOfDay(_startTime, originalStart) ||
        !_sameTimeOfDay(_endTime, originalEnd);
  }

  bool _taskFieldsChangedAgainst(Task baseline) =>
      TaskEditorBaseline.normalizeTitle(_titleController.text) !=
          TaskEditorBaseline.normalizeTitle(baseline.title) ||
      TaskEditorBaseline.normalizeDescription(_descriptionController.text) !=
          baseline.description ||
      TaskEditorBaseline.normalizeNotes(_notesController.text) !=
          TaskEditorBaseline.normalizeNotes(baseline.notes ?? '') ||
      _estimatedController.text.trim() !=
          (baseline.estimatedDurationMin?.toString() ?? '') ||
      _actualController.text.trim() !=
          (baseline.actualDurationMin?.toString() ?? '') ||
      _categoryId != baseline.categoryId ||
      _priority != baseline.priority ||
      _status != baseline.status ||
      _scheduleInputsChanged;

  void _rebaseUntouchedFields(Task latest) {
    final previous = _baseline?.task;
    if (previous == null) return;
    final titleDirty =
        TaskEditorBaseline.normalizeTitle(_titleController.text) !=
        TaskEditorBaseline.normalizeTitle(previous.title);
    final descriptionDirty =
        TaskEditorBaseline.normalizeDescription(_descriptionController.text) !=
        previous.description;
    final notesDirty =
        TaskEditorBaseline.normalizeNotes(_notesController.text) !=
        TaskEditorBaseline.normalizeNotes(previous.notes ?? '');
    final estimatedDirty =
        _estimatedController.text.trim() !=
        (previous.estimatedDurationMin?.toString() ?? '');
    final actualDirty =
        _actualController.text.trim() !=
        (previous.actualDurationMin?.toString() ?? '');
    final categoryDirty = _categoryId != previous.categoryId;
    final priorityDirty = _priority != previous.priority;
    final statusDirty = _status != previous.status;
    final scheduleDirty = _scheduleInputsChanged;
    final conflictBaseline = _conflictBaselineTask ?? previous;

    _synchronizingControllers = true;
    if (!titleDirty) _setControllerText(_titleController, latest.title);
    if (!descriptionDirty) {
      _setControllerText(_descriptionController, latest.description ?? '');
    }
    if (!notesDirty) _setControllerText(_notesController, latest.notes ?? '');
    if (!estimatedDirty) {
      _setControllerText(
        _estimatedController,
        latest.estimatedDurationMin?.toString() ?? '',
      );
    }
    if (!actualDirty) {
      _setControllerText(
        _actualController,
        latest.actualDurationMin?.toString() ?? '',
      );
    }
    if (!categoryDirty) _categoryId = latest.categoryId;
    if (!priorityDirty) _priority = latest.priority;
    if (!statusDirty) _status = latest.status;
    if (!scheduleDirty) {
      _startTime = latest.startTime == null
          ? null
          : TimeOfDay.fromDateTime(
              PlannerTimeZone.toPlannerLocal(latest.startTime!),
            );
      _endTime = latest.endTime == null
          ? null
          : TimeOfDay.fromDateTime(
              PlannerTimeZone.toPlannerLocal(latest.endTime!),
            );
    }
    _synchronizingControllers = false;
    _conflictBaselineTask = conflictBaseline.copyWith(
      title: titleDirty ? conflictBaseline.title : latest.title,
      description: descriptionDirty
          ? conflictBaseline.description
          : latest.description,
      notes: notesDirty ? conflictBaseline.notes : latest.notes,
      categoryId: categoryDirty
          ? conflictBaseline.categoryId
          : latest.categoryId,
      priority: priorityDirty ? conflictBaseline.priority : latest.priority,
      status: statusDirty ? conflictBaseline.status : latest.status,
      startTime: scheduleDirty ? conflictBaseline.startTime : latest.startTime,
      endTime: scheduleDirty ? conflictBaseline.endTime : latest.endTime,
      estimatedDurationMin: estimatedDirty
          ? conflictBaseline.estimatedDurationMin
          : latest.estimatedDurationMin,
      actualDurationMin: actualDirty
          ? conflictBaseline.actualDurationMin
          : latest.actualDurationMin,
    );
    _originalTask = latest;
    _baseline = TaskEditorBaseline(
      task: latest,
      tagIds: _originalTagIds ?? _baseline!.tagIds,
      recurrenceSignature: _baseline!.recurrenceSignature,
    );
  }

  void _syncFromTask(Task? task, {bool force = false}) {
    final id = task?.id;
    if (!force && _editingTaskId == id) {
      final baseline = _baseline;
      if (task == null ||
          baseline == null ||
          baseline.hasSameTaskValues(task)) {
        return;
      }
      _rebaseUntouchedFields(task);
      return;
    }
    _synchronizingControllers = true;
    _editingTaskId = id;
    _originalTask = task;
    _conflictBaselineTask = task;
    _baseline = task == null
        ? null
        : TaskEditorBaseline(task: task, tagIds: const <String>{});
    _originalTagIds = null;
    _setControllerText(_titleController, task?.title ?? '');
    _setControllerText(_descriptionController, task?.description ?? '');
    _setControllerText(_notesController, task?.notes ?? '');
    _setControllerText(
      _estimatedController,
      task?.estimatedDurationMin?.toString() ?? '',
    );
    _setControllerText(
      _actualController,
      task?.actualDurationMin?.toString() ?? '',
    );
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
    _synchronizingControllers = false;
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  bool _sameIds(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  bool get _hasDraftChanges {
    final original = _baseline?.task ?? _originalTask;
    if (original == null) return false;
    if (_taskFieldsChangedAgainst(original)) {
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
    // Desktop keeps this panel mounted while the selected task changes. Clear
    // the draft before clearing selection so reopening the same task cannot
    // reuse discarded (or already-closed) controller values.
    _syncFromTask(null, force: true);
    _activeTask = null;
    ref.read(selectedTaskIdProvider.notifier).state = null;
    final callback = widget.onClose;
    if (callback != null) {
      callback();
    } else if (widget.presentation == TaskEditorPresentation.bottomSheet &&
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

  Future<TaskEditorPersistedState> _readPersistedState(String taskId) async {
    final repository = ref.read(taskRepositoryProvider);
    final saved = await repository.getTaskById(taskId);
    if (saved == null) {
      throw StateError('Task $taskId not found after save');
    }
    final tagIds =
        (await ref.read(tagRepositoryProvider).getTagsForTask(taskId))
            .map((tag) => tag.id)
            .toSet();
    return TaskEditorPersistedState(task: saved, tagIds: tagIds);
  }

  void _acceptPersistedState(TaskEditorPersistedState persisted) {
    _syncFromTask(persisted.task, force: true);
    _originalTagIds = persisted.tagIds;
    _stagedTagIds = persisted.tagIds;
    _baseline = TaskEditorBaseline(
      task: persisted.task,
      tagIds: persisted.tagIds,
      recurrenceSignature: persisted.recurrenceSignature,
    );
    _errorMessage = null;
  }

  Future<void> _saveImpl(Task task, {bool close = false}) async {
    if (_saving) return;
    // A schedule control is a projection of the persisted instant. Recompute
    // this flag from the snapshot instead of treating any picker interaction
    // as a permanent dirty marker, so changing a time and changing it back is
    // a clean editor.
    _scheduleDirty = _scheduleInputsChanged;
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
    TaskEditorPersistedState? persistedState;
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
    final latestSnapshot = await ref
        .read(taskRepositoryProvider)
        .getTaskWithRevision(task.id);
    final latest = latestSnapshot?.$1;
    final latestRevision = latestSnapshot?.$2;
    if (latest == null || latest.deletedAt != null || latestRevision == null) {
      throw StateError('Task ${task.id} is no longer available');
    }
    final conflictBaseline = _conflictBaselineTask ?? _originalTask ?? task;
    final mergeBaseline = _baseline?.task ?? conflictBaseline;
    final latestTagIds =
        (await ref.read(tagRepositoryProvider).getTagsForTask(task.id))
            .map((tag) => tag.id)
            .toSet();
    final originalTagIds = _originalTagIds ?? stagedTagIds;
    final normalizedDescription = _descriptionController.text;
    final normalizedNotes = _notesController.text.trim();
    final actualDirty =
        _actualController.text.trim() !=
        (mergeBaseline.actualDurationMin?.toString() ?? '');
    final draft = TaskEditorDraft(
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
      actualDurationDirty: actualDirty,
    );

    final conflicts = draft.conflictingFields(conflictBaseline, latest);
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

    final editedTask = draft.mergeOnto(mergeBaseline, latest);
    final tagsToSave = tagsDirty ? stagedTagIds : latestTagIds;

    // Scheduling edits use the same fresh full-interval candidate set and
    // resolution choices as drag, resize, keyboard and Inbox scheduling.
    // Keep the plan outside the persistence branches so recurrence and
    // ordinary saves apply the selected shifts inside their transaction.
    var schedulePlan = const ResolutionPlan();
    var scheduleCandidates = const <Task>[];
    final scheduleChanged =
        editedTask.startTime != latest.startTime ||
        editedTask.endTime != latest.endTime;
    if (scheduleChanged &&
        editedTask.startTime != null &&
        editedTask.endTime != null) {
      final repository = ref.read(taskRepositoryProvider);
      scheduleCandidates = await SchedulingConflictService.loadCandidates(
        repository,
        editedTask,
        anchorDate: viewedDate,
      );
      final scheduleConflicts = SchedulingConflictService.conflicts(
        editedTask,
        scheduleCandidates,
      );
      if (scheduleConflicts.isNotEmpty) {
        if (!mounted) return;
        final choice = await showConflictResolutionDialog(
          context,
          droppedTask: editedTask,
          conflicts: scheduleConflicts,
        );
        if (choice == null) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        schedulePlan = SchedulingConflictService.plan(
          proposed: editedTask,
          candidates: scheduleCandidates,
          resolution: choice,
          maxCascadeDepth: AppConstants.maxCascadeDepth,
        );
      }
    }

    Future<void> applySchedulePlan() async {
      if (schedulePlan.shifts.isEmpty) return;
      final repository = ref.read(taskRepositoryProvider);
      final originals = {
        for (final candidate in scheduleCandidates) candidate.id: candidate,
      };
      for (final shift in schedulePlan.shifts) {
        final expected = originals[shift.taskId];
        if (expected == null) continue;
        final currentSnapshot = await repository.getTaskWithRevision(
          shift.taskId,
        );
        final current = currentSnapshot?.$1;
        final revision = currentSnapshot?.$2;
        if (current == null || revision == null) {
          throw StateError(
            'A conflicting task was removed while the schedule dialog was open.',
          );
        }
        if (current.startTime != expected.startTime ||
            current.endTime != expected.endTime) {
          throw StateError(
            'A conflicting task changed while the schedule dialog was open; reload and try again.',
          );
        }
        await repository.updateTask(
          current.copyWith(startTime: shift.newStart, endTime: shift.newEnd),
          expectedRevision: revision,
        );
      }
    }

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
        extraTaskIds: schedulePlan.shifts.map((shift) => shift.taskId).toSet(),
        mutation: () async {
          await applySchedulePlan();
          int? taskRevisionForWrite = latestRevision;
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
              // Reconciliation updates every future materialized instance,
              // including the one currently open in the editor. Refresh its
              // revision before the editor's final write so the optimistic
              // guard does not reject our own atomic series update.
              final refreshed = await ref
                  .read(taskRepositoryProvider)
                  .getTaskWithRevision(task.id);
              taskRevisionForWrite = refreshed?.$2;
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
                expectedRevision: taskRevisionForWrite,
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
      persistedState = await _readPersistedState(task.id);
    } else if (!hadRule && _repeat != null && _repeat != RepeatPreset.never) {
      // Attach a brand-new rule to this previously one-off task.
      final anchorDate = start ?? DateTime.now();
      final rruleString = _resolveRrule(anchorDate)!;
      persistedState =
          await TaskEditorSaveCommand(ref.read(appDatabaseProvider))
              .execute(() async {
                await applySchedulePlan();
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
                    .updateTask(
                      editedTask.copyWith(recurringRuleId: rule.id),
                      expectedRevision: latestRevision,
                    );
                if (actualDirty && actual != null) {
                  await ref
                      .read(timerServiceProvider)
                      .setManualActual(task.id, actual);
                }
                await ref
                    .read(tagRepositoryProvider)
                    .replaceTagsForTask(task.id, tagsToSave);
                return _readPersistedState(task.id);
              });
    } else {
      persistedState =
          await TaskEditorSaveCommand(ref.read(appDatabaseProvider))
              .execute(() async {
                await applySchedulePlan();
                await ref
                    .read(taskRepositoryProvider)
                    .updateTask(
                      editedTask.copyWith(recurringRuleId: null),
                      expectedRevision: latestRevision,
                    );
                if (actualDirty && actual != null) {
                  await ref
                      .read(timerServiceProvider)
                      .setManualActual(task.id, actual);
                }
                await ref
                    .read(tagRepositoryProvider)
                    .replaceTagsForTask(task.id, tagsToSave);
                return _readPersistedState(task.id);
              });
    }

    final persisted = persistedState ?? await _readPersistedState(task.id);

    // Re-materialize the viewed day so new/changed rules show up instantly.
    ref.invalidate(dayMaterializationProvider(viewedDate));

    if (!mounted) return;
    _acceptPersistedState(persisted);
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Task saved')));
    if (close && mounted) {
      _closeImmediately();
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

  Widget _persistentHeader(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final task = _activeTask;
    return Material(
      color: tokens.surfaceSubtle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
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
                const Expanded(
                  child: AppSectionHeader(
                    title: 'Edit Task',
                    subtitle: 'Keep the plan clear and actionable',
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Close editor',
                  child: IconButton(
                    tooltip: 'Close editor',
                    icon: const Icon(Icons.close),
                    onPressed: _requestClose,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: const ValueKey('save-task-button'),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
                onPressed: _saving || task == null ? null : () => _save(task),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorFrame(BuildContext context, Widget body) {
    final tokens = AppThemeTokens.of(context);
    return PopScope<void>(
      canPop: !_hasDraftChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: ColoredBox(
        color: tokens.surfaceSubtle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _persistentHeader(context),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
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
      return _editorFrame(
        context,
        Center(
          child: ErrorPanel(
            message: friendlyErrorMessage(tasksAsync.error!),
            onRetry: () {
              ref.invalidate(dayTasksProvider);
              ref.invalidate(selectedTaskByIdProvider(taskId));
            },
          ),
        ),
      );
    }
    if (taskId != null && selectedTaskAsync.hasError) {
      return _editorFrame(
        context,
        Center(
          child: ErrorPanel(
            message: friendlyErrorMessage(selectedTaskAsync.error!),
            onRetry: () => ref.invalidate(selectedTaskByIdProvider(taskId)),
          ),
        ),
      );
    }
    if (taskId != null && !tasksAsync.hasValue && !selectedTaskAsync.hasValue) {
      return _editorFrame(
        context,
        const Center(child: CircularProgressIndicator()),
      );
    }

    if (taskId == null) {
      return _editorFrame(
        context,
        Center(
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
    // A task update can briefly invalidate the day stream before the
    // selected-task query publishes its replacement row. Keep the mounted
    // editor alive during that transient gap so a successful Save cannot
    // remove its controls or lose focus; an explicit null query result still
    // represents a genuinely deleted/missing task.
    if (task == null &&
        !selectedTaskAsync.hasValue &&
        _activeTask?.id == taskId) {
      task = _activeTask;
    }
    _activeTask = task;
    _syncFromTask(task);

    if (task == null) {
      return _editorFrame(
        context,
        const Center(
          child: ErrorPanel(
            message: 'The selected task is no longer available.',
          ),
        ),
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
    return _editorFrame(
      context,
      IgnorePointer(
        ignoring: _saving,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              _scheduleDirty = _scheduleInputsChanged;
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
                              _scheduleDirty = _scheduleInputsChanged;
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
