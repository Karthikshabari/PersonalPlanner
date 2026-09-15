import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (name.isEmpty) {
      setState(() => _error = 'Template name must not be blank.');
      return;
    }
    final parsedDuration = int.tryParse(_durationController.text.trim());
    if (parsedDuration == null || parsedDuration <= 0) {
      setState(() => _error = 'Duration must be a positive whole number.');
      return;
    }
    final duration = parsedDuration.clamp(1, 10000);
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
                decoration: const InputDecoration(labelText: 'Name'),
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
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes)',
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
