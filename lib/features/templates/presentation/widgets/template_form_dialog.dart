import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/task_template.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/utils/uuid.dart';
import '../../../categories/providers/category_providers.dart';
import '../../providers/template_providers.dart';

/// Create/edit form for a template (planner.md Chunk 4 #11). Returns the
/// saved template, or `null` when cancelled. Pass [existing] to edit.
Future<TaskTemplate?> showTemplateFormDialog(
  BuildContext context,
  WidgetRef ref, {
  TaskTemplate? existing,
}) {
  return showDialog<TaskTemplate>(
    context: context,
    builder: (_) => _TemplateFormDialog(existing: existing),
  );
}

class _TemplateFormDialog extends ConsumerStatefulWidget {
  final TaskTemplate? existing;

  const _TemplateFormDialog({this.existing});

  @override
  ConsumerState<_TemplateFormDialog> createState() =>
      _TemplateFormDialogState();
}

class _TemplateFormDialogState extends ConsumerState<_TemplateFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _durationController;
  String? _categoryId;
  bool _saving = false;
  String? _error;
  String? _nameError;
  String? _durationError;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nameController = TextEditingController(text: t?.name ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _durationController = TextEditingController(
      text: t?.durationMin.toString() ?? '60',
    );
    _categoryId = t?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final parsedDuration = int.tryParse(_durationController.text.trim());
    final nameError = name.isEmpty
        ? 'Template name must not be blank.'
        : name.length > AppConstants.maxTemplateNameLength
        ? 'Name must be ${AppConstants.maxTemplateNameLength} '
              'characters or fewer'
        : null;
    final durationError = parsedDuration == null || parsedDuration <= 0
        ? 'Duration must be a positive whole number.'
        : parsedDuration > AppConstants.maxTemplateDurationMinutes
        ? 'Duration must be ${AppConstants.maxTemplateDurationMinutes} '
              'minutes (24 hours) or less'
        : null;
    if (nameError != null || durationError != null) {
      setState(() {
        _nameError = nameError;
        _durationError = durationError;
      });
      return;
    }
    final duration = parsedDuration!;
    final now = DateTime.now();
    final template =
        (widget.existing ??
                TaskTemplate(
                  id: generateUuidV7(),
                  name: name,
                  durationMin: duration,
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              name: name,
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              durationMin: duration,
              categoryId: _categoryId,
            );
    final repo = ref.read(templateRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
      _nameError = null;
      _durationError = null;
    });
    try {
      if (widget.existing == null) {
        await repo.insertTemplate(template);
      } else {
        await repo.updateTemplate(template);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(template);
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48)
        .clamp(280.0, 380.0)
        .toDouble();
    return AlertDialog(
      icon: Icon(
        Icons.bookmark_border,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(widget.existing == null ? 'New template' : 'Edit template'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('template-form-name'),
                controller: _nameController,
                autofocus: true,
                onSubmitted: (_) => _save(),
                maxLength: AppConstants.maxTemplateNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_durationError != null) {
                    setState(() => _durationError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Duration (minutes)',
                  errorText: _durationError,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ErrorPanel(message: _error!, compact: true),
              if (categoriesAsync.hasError)
                ErrorPanel(
                  message: friendlyErrorMessage(categoriesAsync.error!),
                  onRetry: () => ref.invalidate(categoriesProvider),
                  compact: true,
                )
              else if (!categoriesAsync.hasValue)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final c in categoriesAsync.requireValue)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (c) => setState(() => _categoryId = c),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('template-form-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
