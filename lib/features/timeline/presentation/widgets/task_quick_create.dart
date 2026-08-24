import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class TaskQuickCreate extends StatelessWidget {
  final int slotMinutes;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const TaskQuickCreate({
    super.key,
    required this.slotMinutes,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return Positioned(
      left: 64,
      right: 12,
      top: slotMinutes.toDouble(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onCancel,
        },
        child: TapRegion(
          onTapOutside: (_) => onCancel(),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surfaceVariantDark,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Task title…',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                ),
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) onSubmit(trimmed);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
