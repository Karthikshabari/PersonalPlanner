import 'package:flutter/material.dart';

/// Floating review feedback: bottom centre, 4 s, at most 480 dp wide on
/// large screens. `persist: false` keeps auto-dismiss when an action is set
/// (D27).
void showReviewSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 600;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: wide ? 480 : null,
        duration: const Duration(seconds: 4),
        persist: false,
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
