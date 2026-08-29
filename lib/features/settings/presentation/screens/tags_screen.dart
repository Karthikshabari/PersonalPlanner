import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/tag.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../task_editor/providers/tag_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags'),
        actions: const [SyncStatusAction()],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add-tag'),
        onPressed: () => _showTagDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorPanel(message: friendlyErrorMessage(error)),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final tag = items[index];
            return Card(
              child: ListTile(
                key: ValueKey('tag-row-${tag.name}'),
                leading: const Icon(Icons.sell_outlined),
                title: Text(tag.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('edit-tag-${tag.name}'),
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showTagDialog(context, ref, tag),
                    ),
                    IconButton(
                      key: ValueKey('delete-tag-${tag.name}'),
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteTag(context, ref, tag),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static Future<void> _showTagDialog(
    BuildContext context,
    WidgetRef ref, [
    Tag? existing,
  ]) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'New tag' : 'Rename tag'),
        content: TextField(
          key: const ValueKey('tag-name-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('save-tag'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final repo = ref.read(tagRepositoryProvider);
              if (existing == null) {
                await repo.insertTag(
                  Tag(
                    id: '',
                    name: name,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                );
              } else {
                await repo.updateTag(existing.copyWith(name: name));
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  static Future<void> _deleteTag(
    BuildContext context,
    WidgetRef ref,
    Tag tag,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text('Delete "${tag.name}" from all tasks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-tag'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(tagRepositoryProvider).deleteTag(tag.id);
    }
  }
}
