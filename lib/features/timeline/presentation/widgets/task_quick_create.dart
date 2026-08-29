import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';

class TaskQuickCreate extends StatefulWidget {
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
  State<TaskQuickCreate> createState() => _TaskQuickCreateState();
}

class _TaskQuickCreateState extends State<TaskQuickCreate> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 64,
      right: 12,
      top: widget.slotMinutes.toDouble(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        },
        child: TapRegion(
          onTapOutside: (_) => widget.onCancel(),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: TextField(
                key: const ValueKey('quick-create-input'),
                controller: _controller,
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
                  if (trimmed.isNotEmpty) widget.onSubmit(trimmed);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
