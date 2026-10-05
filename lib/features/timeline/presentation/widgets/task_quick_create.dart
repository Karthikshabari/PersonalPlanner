import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/task_time_metrics.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../domain/scheduled_task_draft.dart';
import 'schedule_fields.dart';

/// Compact scheduled-task form used by toolbar, shortcut and empty-slot
/// creation. The form owns its draft until the async callback confirms a
/// committed row, which keeps validation/conflict/database failures editable.
class TaskQuickCreate extends StatefulWidget {
  final String taskId;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String initialTitle;
  final String initialDescription;
  final String heading;
  final String? infoText;
  final bool conversionMode;
  final Future<bool> Function(ScheduledTaskDraft draft) onSubmit;
  final VoidCallback onCancel;

  const TaskQuickCreate({
    super.key,
    required this.taskId,
    required this.initialStart,
    required this.initialEnd,
    this.initialTitle = '',
    this.initialDescription = '',
    this.heading = 'Create scheduled task',
    this.infoText,
    this.conversionMode = false,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<TaskQuickCreate> createState() => _TaskQuickCreateState();
}

class _TaskQuickCreateState extends State<TaskQuickCreate> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime? _start;
  late DateTime? _end;
  bool _saving = false;
  // Each message is rendered exactly once, next to what it is about: the
  // title field, the schedule fields, or (for save failures) the form.
  String? _titleError;
  String? _scheduleError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  ScheduledTaskDraft get _draft => ScheduledTaskDraft(
    id: widget.taskId,
    title: _titleController.text,
    description: _descriptionController.text,
    start: _start,
    end: _end,
  );

  void _cancel() {
    if (_saving) return;
    widget.onCancel();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final draft = _draft;
    final titleError = draft.titleError;
    final scheduleError = draft.scheduleError;
    setState(() {
      _titleError = titleError;
      _scheduleError = scheduleError;
      _error = null;
    });
    if (titleError != null || scheduleError != null) return;
    setState(() => _saving = true);
    try {
      final committed = await widget.onSubmit(draft);
      if (!mounted) return;
      if (committed) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Our own ArgumentError/StateError messages are written for the user;
  /// anything else (Drift, SQLite, platform) may dump whole rows, so it is
  /// mapped to a safe message.
  String _friendlyError(Object error) {
    if (error is ArgumentError) return '${error.message}';
    if (error is StateError) return error.message;
    return friendlyErrorMessage(error);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final planned = TaskTimeMetrics.plannedMinutes(_start, _end);
    return PopScope<void>(
      canPop: !_saving,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
        },
        child: FocusTraversalGroup(
          child: Material(
            color: tokens.surfaceRaised,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.add_task,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            widget.heading,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel quick create',
                          onPressed: _saving ? null : widget.onCancel,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (widget.infoText != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.infoText!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey('quick-create-input'),
                      controller: _titleController,
                      autofocus: true,
                      enabled: !_saving,
                      // Counter only: a pasted over-long title stays visible
                      // and Save explains the limit instead of truncating.
                      maxLength: AppConstants.maxTaskTitleLength,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        helperText: widget.conversionMode
                            ? 'Choose a title for this scheduled task'
                            : null,
                        errorText: _titleError,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey('quick-create-description'),
                      controller: _descriptionController,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ScheduleFields(
                      start: _start,
                      end: _end,
                      enabled: !_saving,
                      errorText: _scheduleError,
                      onStartChanged: (value) => setState(() => _start = value),
                      onEndChanged: (value) => setState(() => _end = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      planned == null
                          ? 'Not scheduled'
                          : 'Planned: $planned min',
                      key: const ValueKey('quick-create-planned-duration'),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: tokens.textMuted),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        key: const ValueKey('quick-create-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving ? null : widget.onCancel,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          key: const ValueKey('quick-create-submit'),
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
