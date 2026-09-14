import 'package:flutter/material.dart';

/// Converts infrastructure failures into a safe, actionable message. Raw
/// exceptions may contain SQL, URLs, account identifiers, or auth details and
/// are intentionally never shown in the UI.
String friendlyErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('checksum')) {
    return 'This backup is damaged or was changed. Choose another file.';
  }
  if (message.contains('backup') ||
      message.contains('json') ||
      message.contains('schema')) {
    return 'The backup file is invalid or from an unsupported version.';
  }
  if (message.contains('foreign key') || message.contains('integrity')) {
    return 'The operation failed an integrity check. No partial changes were saved.';
  }
  if (message.contains('secure') || message.contains('keyring')) {
    return 'Secure session storage is unavailable. Retry to restore your account.';
  }
  if (message.contains('auth') ||
      message.contains('session') ||
      message.contains('sign in')) {
    return 'Your session is unavailable. Sign in again and retry.';
  }
  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('offline')) {
    return 'The network is unavailable. Your local changes are safe; retry later.';
  }
  return 'Something went wrong. Your local data was not discarded; please retry.';
}

class ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  const ErrorPanel({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: color)),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class AppErrorBoundary extends StatelessWidget {
  final Widget child;

  const AppErrorBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
