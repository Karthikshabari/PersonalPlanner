import 'package:flutter/material.dart';

/// Shows a brief toast-style snackbar (used for undo/redo feedback etc.).
void showAppToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
}
