import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../providers/inbox_provider.dart';

/// Type a title, press Enter → inbox item created (planner.md Chunk 3 #13).
class InboxQuickAdd extends ConsumerStatefulWidget {
  const InboxQuickAdd({super.key});

  @override
  ConsumerState<InboxQuickAdd> createState() => _InboxQuickAddState();
}

Future<void> showInboxQuickAddDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController();
  final title = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add to Inbox'),
      content: TextField(
        key: const ValueKey('inbox-shortcut-input'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Capture an idea…'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('inbox-shortcut-submit'),
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (title != null && title.trim().isNotEmpty) {
    await ref.read(inboxRepositoryProvider).addToInbox(title.trim());
  }
}

class _InboxQuickAddState extends ConsumerState<InboxQuickAdd> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await ref.read(inboxRepositoryProvider).addToInbox(trimmed);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: TextField(
        key: const ValueKey('inbox-quick-add'),
        controller: _controller,
        decoration: const InputDecoration(
          hintText: 'Capture an idea…',
          prefixIcon: Icon(Icons.add),
        ),
        onSubmitted: _add,
      ),
    );
  }
}
