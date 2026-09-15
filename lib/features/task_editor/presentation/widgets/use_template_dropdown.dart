import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/task_template.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../templates/providers/template_providers.dart';

/// "Use template" dropdown in the task editor (planner.md Chunk 4 #12):
/// selecting a template pre-fills title, description, duration and category.
class UseTemplateDropdown extends ConsumerWidget {
  final ValueChanged<TaskTemplate> onSelected;

  const UseTemplateDropdown({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);
    return AsyncValueView(
      value: templatesAsync,
      onRetry: () => ref.invalidate(templatesProvider),
      builder: (templates) {
        if (templates.isEmpty) return const SizedBox.shrink();
        return DropdownButtonFormField<String>(
          key: const ValueKey('use-template-dropdown'),
          initialValue: null,
          decoration: const InputDecoration(labelText: 'Use template'),
          isExpanded: true,
          items: [
            for (final t in templates)
              DropdownMenuItem(value: t.id, child: Text(t.name)),
          ],
          onChanged: (id) {
            if (id == null) return;
            for (final t in templates) {
              if (t.id == id) {
                onSelected(t);
                break;
              }
            }
          },
        );
      },
    );
  }
}
