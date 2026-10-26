import 'package:flutter/material.dart';

import '../../features/settings/data/backup_format.dart';

/// Converts infrastructure failures into a safe, actionable message. Raw
/// exceptions may contain SQL, URLs, account identifiers, or auth details and
/// are intentionally never shown in the UI.
String friendlyErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (error is BackupValidationException) {
    return message.contains('checksum')
        ? 'This backup is damaged or was changed. Choose another file.'
        : 'The backup file is invalid or from an unsupported version.';
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

final _frameworkRef = RegExp(r'\bref\b', caseSensitive: false);

/// The message of an error our own code threw for the user (an
/// [ArgumentError] or [StateError] with a written message); anything else,
/// including a Riverpod "Using ref ... unmounted" [StateError], goes through
/// [friendlyErrorMessage].
String userFacingErrorMessage(Object error) {
  final message = switch (error) {
    ArgumentError(:final message) => '$message',
    StateError(:final message) => message,
    _ => null,
  };
  if (message == null || _frameworkRef.hasMatch(message)) {
    return friendlyErrorMessage(error);
  }
  return message;
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
