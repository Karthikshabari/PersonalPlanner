import 'package:flutter/material.dart';

import '../../../../core/models/task.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../domain/conflict_resolver.dart';

/// Modal dialog offering the four conflict resolution options:
/// Shift All Following / Shift Only Overlapping / Keep Overlap / Cancel.
///
/// Returns the chosen strategy, or null when the user cancels/discards.
Future<ConflictResolution?> showConflictResolutionDialog(
  BuildContext context, {
  required Task droppedTask,
  required List<Task> conflicts,
}) {
  return showDialog<ConflictResolution>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: AppThemeTokens.of(context).warning,
      ),
      title: const Text('Resolve conflict'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48)
            .clamp(280.0, 380.0)
            .toDouble(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  const TextSpan(text: '"'),
                  TextSpan(
                    text: droppedTask.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '" overlaps '),
                  TextSpan(
                    text: conflicts.length == 1
                        ? '"${conflicts.first.title}"'
                        : '${conflicts.length} blocks',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: '. How should the schedule be adjusted?',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final conflict in conflicts.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• ${conflict.title} — '
                  '${_durationLabel(conflict)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (conflicts.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• and ${conflicts.length - 3} more…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const ValueKey('conflict-shift-all'),
              onPressed: () =>
                  Navigator.of(context)
                      .pop(ConflictResolution.shiftAllFollowing),
              child: const Text('Shift All Following'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              key: const ValueKey('conflict-shift-overlapping'),
              onPressed: () =>
                  Navigator.of(context)
                      .pop(ConflictResolution.shiftOnlyOverlapping),
              child: const Text('Shift Only Overlapping'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              key: const ValueKey('conflict-keep-overlap'),
              onPressed: () =>
                  Navigator.of(context).pop(ConflictResolution.keepOverlap),
              child: const Text('Keep Overlap'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const ValueKey('conflict-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    ),
  );
}

String _durationLabel(Task task) {
  final duration = task.scheduledDuration;
  return duration == null ? '' : duration.shortLabel;
}
