import 'package:flutter/material.dart';

import '../controllers/provisioning_ui_controller.dart';

/// Asks before clearing the cloud setup on this device. Returns true only when
/// the user pressed "Start over".
Future<bool> showCloudSetupResetDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('cloud-reset-dialog'),
      title: const Text(cloudSetupResetDialogTitle),
      content: const SingleChildScrollView(
        child: Text(cloudSetupResetDialogBody),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cloud-reset-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(cloudSetupResetDialogKeepLabel),
        ),
        FilledButton(
          key: const ValueKey('cloud-reset-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(cloudSetupResetDialogConfirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}
