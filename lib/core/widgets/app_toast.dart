import 'package:flutter/material.dart';

/// Shows a brief toast-style snackbar (used for undo/redo feedback etc.).
/// With [actionLabel] it also offers one action (such as Undo) and stays a
/// little longer, so a thumb has time to reach it.
void showAppToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: actionLabel == null ? 2 : 4),
        persist: false,
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
