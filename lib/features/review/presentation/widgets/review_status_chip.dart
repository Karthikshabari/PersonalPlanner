import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_mood.dart';
import 'dashed_outline.dart';
import 'review_theme.dart';

/// Reviewed / not reviewed indicator for a day. Never uses the error or
/// warning colour: an unreviewed day is not a failure.
class ReviewStatusChip extends StatelessWidget {
  const ReviewStatusChip({
    super.key,
    required this.reviewed,
    required this.mood,
    required this.onPressed,
  });

  final bool reviewed;
  final int? mood;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final success = ReviewColors.of(context).success;
    final label = !reviewed
        ? 'Not reviewed'
        : (mood == null ? 'Reviewed' : 'Reviewed · ${reviewMoodLabel(mood!)}');
    final labelStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(fontWeight: FontWeight.w600);

    final Widget content;
    final Widget decorated;
    if (!reviewed) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.textMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: labelStyle?.copyWith(color: tokens.textMuted)),
        ],
      );
      decorated = CustomPaint(
        painter: DashedOutlinePainter(color: tokens.outline, circle: false),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: tokens.surface,
            shape: const StadiumBorder(),
          ),
          child: _padded(content),
        ),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 14, color: success),
          const SizedBox(width: 6),
          Text(label, style: labelStyle?.copyWith(color: success)),
        ],
      );
      decorated = DecoratedBox(
        decoration: ShapeDecoration(
          color: Color.alphaBlend(
            success.withValues(alpha: 0.12),
            tokens.surface,
          ),
          shape: StadiumBorder(
            side: BorderSide(
              color: Color.alphaBlend(
                success.withValues(alpha: 0.5),
                tokens.outline,
              ),
            ),
          ),
        ),
        child: _padded(content),
      );
    }

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: decorated,
        ),
      ),
    );
  }

  Widget _padded(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 32),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      child: Center(widthFactor: 1, child: child),
    ),
  );
}
