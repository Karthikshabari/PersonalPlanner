import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/models/task_template.dart';
import '../../../../core/utils/uuid.dart';
import '../../../templates/providers/template_providers.dart';
import '../../providers/tag_providers.dart';

@immutable
class SaveAsTemplateDraft {
  final String suggestedName;
  final String? description;
  final int durationMin;
  final String? categoryId;
  final int priority;
  final Set<String>? tagIds;
  final String? sourceTaskId;

  const SaveAsTemplateDraft({
    required this.suggestedName,
    required this.description,
    required this.durationMin,
    required this.categoryId,
    required this.priority,
    required this.tagIds,
    this.sourceTaskId,
  });

  factory SaveAsTemplateDraft.fromPersistedTask(Task task) {
    return SaveAsTemplateDraft(
      suggestedName: task.title,
      description: task.description,
      durationMin:
          task.estimatedDurationMin ?? task.scheduledDuration?.inMinutes ?? 60,
      categoryId: task.categoryId,
      priority: task.priority.dbValue,
      tagIds: null,
      sourceTaskId: task.id,
    );
  }
}

/// "Save as template" (planner.md Chunk 4 #13): asks for a name and creates
/// a template from either the current editor draft or a persisted task.
Future<void> saveAsTemplate(
  BuildContext context,
  WidgetRef ref,
  SaveAsTemplateDraft draft,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) =>
        _SaveAsTemplateDialog(initialName: draft.suggestedName),
  );
  if (name == null) return;

  var effectiveTagIds = draft.tagIds?.toList() ?? <String>[];
  if (draft.tagIds == null && draft.sourceTaskId != null) {
    final tags = await ref
        .read(tagRepositoryProvider)
        .getTagsForTask(draft.sourceTaskId!);
    effectiveTagIds = tags.map((t) => t.id).toList();
  }

  await ref
      .read(templateRepositoryProvider)
      .insertTemplate(
        TaskTemplate(
          id: generateUuidV7(),
          name: name,
          description: draft.description,
          durationMin: draft.durationMin,
          categoryId: draft.categoryId,
          priority: draft.priority,
          tags: effectiveTagIds,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
}

class _SaveAsTemplateDialog extends StatefulWidget {
  final String initialName;

  const _SaveAsTemplateDialog({required this.initialName});

  @override
  State<_SaveAsTemplateDialog> createState() => _SaveAsTemplateDialogState();
}

class _SaveAsTemplateDialogState extends State<_SaveAsTemplateDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _nameController.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as template'),
      content: TextField(
        key: const ValueKey('template-name-field'),
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Template name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('template-save-confirm'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
