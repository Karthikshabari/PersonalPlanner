import 'package:flutter/material.dart';

/// The editor's "Discard unsaved changes?" prompt. True only when the user
/// chose Discard; Keep editing, Esc and a barrier tap all mean false.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Discard unsaved changes?'),
      content: const Text('Your edits will be lost if you close the editor.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard == true;
}
