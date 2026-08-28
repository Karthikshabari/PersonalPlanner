import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums/priority.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../categories/providers/category_providers.dart';
import '../../providers/template_providers.dart';
import '../widgets/template_form_dialog.dart';

/// Settings → Task Templates (planner.md Chunk 4 #11): list, create, edit
/// and delete templates.
class TaskTemplatesScreen extends ConsumerWidget {
  const TaskTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final templates = templatesAsync.maybeWhen(
        data: (t) => t, orElse: () => const []);
    final categories = categoriesAsync.maybeWhen(
        data: (c) => c, orElse: () => const []);

    return Scaffold(
      appBar: AppBar(title: const Text('Task Templates')),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add-template-fab'),
        onPressed: () => showTemplateFormDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: templates.isEmpty
          ? const Center(
              child: Text('No templates yet.\nCreate one with + or save a '
                  'task as template from the editor.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                final category = categories
                    .where((c) => c.id == template.categoryId)
                    .firstOrNull;
                return Card(
                  key: ValueKey('template-card-${template.id}'),
                  child: ListTile(
                    leading: category == null
                        ? const Icon(Icons.bookmark_border_outlined)
                        : Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Color(int.parse(
                                  category.colorHex.replaceFirst('#', '0xFF'))),
                              shape: BoxShape.circle,
                            ),
                          ),
                    title: Text(template.name),
                    subtitle: Text(
                      '${template.durationMin} min'
                      '${category == null ? '' : ' · ${category.name}'}'
                      ' · ${Priority.fromDb(template.priority).label}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () =>
                              showTemplateFormDialog(context, ref,
                                  existing: template),
                        ),
                        IconButton(
                          key: ValueKey('delete-template-${template.id}'),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () async {
                            final confirmed = await showConfirmDialog(
                              context,
                              title: 'Delete template?',
                              message:
                                  '"${template.name}" will be removed. Tasks '
                                  'already created from it are not affected.',
                              confirmLabel: 'Delete',
                            );
                            if (confirmed) {
                              await ref
                                  .read(templateRepositoryProvider)
                                  .deleteTemplate(template.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
