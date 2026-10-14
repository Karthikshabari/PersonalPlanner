import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import 'inbox_capture_editor.dart';
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
  // Read before the dialog opens: the opening widget can be rebuilt away
  // while the dialog is up, and its ref would then throw.
  final repository = ref.read(inboxRepositoryProvider);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: InboxCaptureEditor(
          onSubmit: (content, _) => repository.addToInbox(content),
          onCommitted: () => Navigator.of(dialogContext).pop(),
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

/// Edits the text of an Inbox idea. The legacy due date, if any, is kept as it
/// is; the editor has no date control.
Future<void> showInboxEditDialog(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required String initialContent,
}) async {
  final repository = ref.read(taskRepositoryProvider);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: InboxCaptureEditor(
          title: 'Edit Inbox capture',
          initialContent: initialContent,
          onSubmit: (content, _) async {
            final snapshot = await repository.getTaskWithRevision(taskId);
            final current = snapshot?.$1;
            final revision = snapshot?.$2;
            if (current == null || revision == null || !current.isInbox) {
              throw StateError(
                'This Inbox capture changed or was scheduled elsewhere; reload and try again.',
              );
            }
            await repository.updateTask(
              current.copyWith(description: content, inboxContentVersion: 1),
              expectedRevision: revision,
            );
          },
          onCommitted: () => Navigator.of(dialogContext).pop(),
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

class _InboxQuickAddState extends ConsumerState<InboxQuickAdd> {
  @override
  Widget build(BuildContext context) {
    return InboxCaptureEditor(
      compact: true,
      clearOnSuccess: true,
      onSubmit: (content, _) =>
          ref.read(inboxRepositoryProvider).addToInbox(content),
    );
  }
}
