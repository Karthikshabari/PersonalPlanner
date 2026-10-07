import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:personal_planner/core/theme/app_spacing.dart';

enum PlanChangeDecision { preserve, replace }

class PlanChangeDialogResult {
  const PlanChangeDialogResult(this.decision, this.reason);

  final PlanChangeDecision decision;
  final String? reason;
}

/// Deliberate acknowledgement before a persisted scheduled plan changes name.
/// Returning null is cancellation: the surrounding editor must not write any
/// task, recurrence or scheduling mutation.
Future<PlanChangeDialogResult?> showPlanChangeDialog(
  BuildContext context, {
  required String previousTitle,
  required String nextTitle,
  required bool allFuture,
}) => showDialog<PlanChangeDialogResult>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _PlanChangeDialog(
    previousTitle: previousTitle,
    nextTitle: nextTitle,
    allFuture: allFuture,
  ),
);

class _PlanChangeDialog extends StatefulWidget {
  const _PlanChangeDialog({
    required this.previousTitle,
    required this.nextTitle,
    required this.allFuture,
  });

  final String previousTitle;
  final String nextTitle;
  final bool allFuture;

  @override
  State<_PlanChangeDialog> createState() => _PlanChangeDialogState();
}

class _PlanChangeDialogState extends State<_PlanChangeDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Title changed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.allFuture ? 'This and all future unfinished occurrences' : 'This scheduled task'} '
            'will change from “${widget.previousTitle}” to “${widget.nextTitle}”.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            key: const ValueKey('plan-change-reason'),
            controller: _reason,
            maxLines: 1,
            inputFormatters: [LengthLimitingTextInputFormatter(140)],
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              helperText: 'Saved with the plan change.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('plan-change-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('plan-change-replace'),
          onPressed: () => Navigator.of(
            context,
          ).pop(const PlanChangeDialogResult(PlanChangeDecision.replace, null)),
          child: const Text('Replace normally'),
        ),
        FilledButton(
          key: const ValueKey('plan-change-preserve'),
          onPressed: () {
            final reason = _reason.text.trim();
            Navigator.of(context).pop(
              PlanChangeDialogResult(
                PlanChangeDecision.preserve,
                reason.isEmpty ? null : reason,
              ),
            );
          },
          child: const Text('Preserve as plan change'),
        ),
      ],
    );
  }
}
