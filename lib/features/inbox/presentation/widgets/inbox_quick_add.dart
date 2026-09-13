import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: InboxCaptureEditor(
          onSubmit: (content, dueDate) =>
              ref.read(inboxRepositoryProvider).addToInbox(
                    content,
                    dueDate: dueDate,
                  ),
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
      onSubmit: (content, dueDate) => ref
          .read(inboxRepositoryProvider)
          .addToInbox(content, dueDate: dueDate),
    );
  }
}
