import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/duration_utils.dart';

/// Translucent preview of a task block shown at the live drop position
/// during a drag (architecture.md §8 — ghost preview). Purely presentational;
/// positioned in pixels by the parent.
class GhostPreview extends StatelessWidget {
  final String title;
  final double topPx;
  final double heightPx;
  final double left;
  final double right;
  final Color accentColor;
  final int durationMinutes;

  const GhostPreview({
    super.key,
    required this.title,
    required this.topPx,
    required this.heightPx,
    required this.left,
    required this.right,
    required this.accentColor,
    required this.durationMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topPx,
      left: left,
      right: right,
      height: heightPx.clamp(24.0, double.infinity),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.55,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariantDark.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 10),
              ],
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Flexible(
                  child: Text(
                    Duration(minutes: durationMinutes).shortLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
