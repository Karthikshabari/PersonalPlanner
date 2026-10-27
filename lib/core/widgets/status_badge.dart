import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  static Color colorFor(AppThemeTokens tokens, TaskStatus status) =>
      switch (status) {
        TaskStatus.completed => tokens.success,
        TaskStatus.skipped => tokens.offline,
        TaskStatus.cancelled => tokens.textMuted,
        TaskStatus.rescheduled => tokens.warning,
        TaskStatus.inProgress => tokens.pending,
        TaskStatus.planned => tokens.info,
      };

  static IconData iconFor(TaskStatus status) => switch (status) {
    TaskStatus.planned => Icons.radio_button_unchecked,
    TaskStatus.inProgress => Icons.play_arrow,
    TaskStatus.completed => Icons.check_circle,
    TaskStatus.skipped => Icons.skip_next,
    TaskStatus.cancelled => Icons.cancel_outlined,
    TaskStatus.rescheduled => Icons.schedule,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final color = colorFor(tokens, status);
    final badge = Semantics(
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
              Icon(iconFor(status), size: 12, color: color),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // The status colour stays on the border and icon; text in
                  // it fails 4.5:1 over its own tint in the light theme.
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return onTap == null ? badge : MinTapTarget(child: badge);
  }
}

/// Keeps [child]'s size and look but lets taps within [size] dp of its centre
/// reach it. The extra area is limited by the ancestors' own bounds: a parent
/// never passes a tap outside its box down to its children.
class MinTapTarget extends SingleChildRenderObjectWidget {
  final double size;

  const MinTapTarget({super.key, this.size = 48, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinTapTarget(size);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMinTapTarget).minSize = size;
  }
}

class _RenderMinTapTarget extends RenderProxyBox {
  double minSize;

  _RenderMinTapTarget(this.minSize);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final slackX = ((minSize - size.width) / 2).clamp(0.0, double.infinity);
    final slackY = ((minSize - size.height) / 2).clamp(0.0, double.infinity);
    if (position.dx < -slackX ||
        position.dx >= size.width + slackX ||
        position.dy < -slackY ||
        position.dy >= size.height + slackY) {
      return false;
    }
    // Hand the child the nearest point inside it, so its own bounds check
    // and gesture handling work unchanged.
    return super.hitTest(
      result,
      position: Offset(
        position.dx.clamp(0.0, size.width - 0.01),
        position.dy.clamp(0.0, size.height - 0.01),
      ),
    );
  }
}
