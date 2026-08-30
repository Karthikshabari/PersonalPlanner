import 'package:flutter/material.dart';

import '../models/enums/task_status.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_tokens.dart';

class StatusBadge extends StatelessWidget {
  final TaskStatus status;
  final VoidCallback? onTap;

  const StatusBadge({super.key, required this.status, this.onTap});

  static TaskStatus nextStatus(TaskStatus current) => switch (current) {
    TaskStatus.planned => TaskStatus.inProgress,
    TaskStatus.inProgress => TaskStatus.completed,
    _ => current,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final color = switch (status) {
      TaskStatus.completed => tokens.success,
      TaskStatus.skipped => tokens.offline,
      TaskStatus.cancelled => tokens.textMuted,
      TaskStatus.rescheduled => tokens.warning,
      TaskStatus.inProgress => tokens.pending,
      TaskStatus.planned => tokens.info,
    };
    return Semantics(
      button: onTap != null,
      label: 'Status: ${status.label}',
      hint: onTap == null ? null : 'Change status',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(status), size: 10, color: color),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(TaskStatus status) => switch (status) {
    TaskStatus.planned => Icons.radio_button_unchecked,
    TaskStatus.inProgress => Icons.play_arrow,
    TaskStatus.completed => Icons.check_circle,
    TaskStatus.skipped => Icons.skip_next,
    TaskStatus.cancelled => Icons.cancel_outlined,
    TaskStatus.rescheduled => Icons.schedule,
  };
}
