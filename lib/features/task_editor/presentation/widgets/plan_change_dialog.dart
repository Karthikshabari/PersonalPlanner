import 'package:flutter/material.dart';

enum PlanChangeDecision { preserve, replace }

/// Deliberate acknowledgement before a persisted scheduled plan changes name.
/// Returning null is cancellation: the surrounding editor must not write any
/// task, recurrence or scheduling mutation.
Future<PlanChangeDecision?> showPlanChangeDialog(
  BuildContext context, {
  required String previousTitle,
  required String nextTitle,
  required bool allFuture,
}) => showDialog<PlanChangeDecision>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    title: const Text('Title changed'),
    content: Text(
      '${allFuture ? 'This and all future unfinished occurrences' : 'This scheduled task'} '
      'will change from “$previousTitle” to “$nextTitle”.',
    ),
    actions: [
      TextButton(
        key: const ValueKey('plan-change-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const ValueKey('plan-change-replace'),
        onPressed: () => Navigator.of(context).pop(PlanChangeDecision.replace),
        child: const Text('Replace normally'),
      ),
      FilledButton(
        key: const ValueKey('plan-change-preserve'),
        onPressed: () => Navigator.of(context).pop(PlanChangeDecision.preserve),
        child: const Text('Preserve as plan change'),
      ),
    ],
  ),
);
