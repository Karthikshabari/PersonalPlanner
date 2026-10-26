import 'package:flutter/material.dart';

import '../controllers/provisioning_ui_controller.dart';

/// Asks before clearing the cloud setup on this device. Returns true only when
/// the user pressed "Start over" (or "Use offline-only mode" when
/// [offlineOnly] is set, which clears the same setup but says what the user
/// chose).
Future<bool> showCloudSetupResetDialog(
  BuildContext context, {
  bool offlineOnly = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('cloud-reset-dialog'),
      title: Text(
        offlineOnly ? cloudUseOfflineDialogTitle : cloudSetupResetDialogTitle,
      ),
      content: SingleChildScrollView(
        child: Text(
          offlineOnly ? cloudUseOfflineDialogBody : cloudSetupResetDialogBody,
        ),
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
          child: Text(
            offlineOnly
                ? cloudUseOfflineDialogConfirmLabel
                : cloudSetupResetDialogConfirmLabel,
          ),
        ),
      ],
    ),
  );
  return result == true;
}
