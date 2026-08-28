import 'package:flutter/material.dart';

/// Which scope of a recurring series an action applies to.
enum RecurrenceScope { thisOccurrence, allFuture }

/// "This occurrence only" / "This and all future"-style chooser shown when
/// editing or deleting a task generated from a recurring rule
/// (planner.md Chunk 4 #7/#8). Returns `null` when cancelled.
Future<RecurrenceScope?> showRecurrenceScopeDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String thisOccurrenceLabel,
  required String allFutureLabel,
}) {
  return showDialog<RecurrenceScope>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('scope-this-occurrence'),
          onPressed: () =>
              Navigator.of(context).pop(RecurrenceScope.thisOccurrence),
          child: Text(thisOccurrenceLabel),
        ),
        FilledButton(
          key: const ValueKey('scope-all-future'),
          onPressed: () => Navigator.of(context).pop(RecurrenceScope.allFuture),
          child: Text(allFutureLabel),
        ),
      ],
    ),
  );
}
