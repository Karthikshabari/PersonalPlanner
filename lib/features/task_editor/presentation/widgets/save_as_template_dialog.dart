import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task.dart';
import '../../../../core/models/task_template.dart';
import '../../../../core/utils/uuid.dart';
import '../../../templates/providers/template_providers.dart';
import '../../providers/tag_providers.dart';

/// "Save as template" (planner.md Chunk 4 #13): asks for a name and creates
/// a template from the current task's fields.
Future<void> saveAsTemplate(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  Set<String>? tagIds,
}) async {
  final nameController = TextEditingController(text: task.title);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save as template'),
      content: TextField(
        key: const ValueKey('template-name-field'),
        controller: nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Template name'),
        onSubmitted: (value) =>
            Navigator.of(context).pop(value.trim().isEmpty ? null : value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('template-save-confirm'),
          onPressed: () {
            final value = nameController.text.trim();
            Navigator.of(context).pop(value.isEmpty ? null : value);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (name == null) return;

  final duration = task.estimatedDurationMin ??
      task.scheduledDuration?.inMinutes ??
      60;
  var effectiveTagIds = tagIds?.toList() ?? <String>[];
  if (tagIds == null) {
    try {
      final tags = await ref.read(tagRepositoryProvider).getTagsForTask(task.id);
      effectiveTagIds = tags.map((t) => t.id).toList();
    } catch (_) {}
  }

  await ref.read(templateRepositoryProvider).insertTemplate(TaskTemplate(
        id: generateUuidV7(),
        name: name,
        description: task.description,
        durationMin: duration,
        categoryId: task.categoryId,
        priority: task.priority.dbValue,
        tags: effectiveTagIds,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}
