import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';

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
            elevation: 2,
            borderRadius: BorderRadius.circular(
              AppThemeTokens.of(context).radiusSmall,
            ),
            color: AppThemeTokens.of(context).surfaceRaised,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.add_task,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('quick-create-input'),
                      controller: _controller,
                      autofocus: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: const InputDecoration(
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
                  IconButton(
                    tooltip: 'Cancel quick create',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onCancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
