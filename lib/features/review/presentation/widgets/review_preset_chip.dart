import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import 'dashed_outline.dart';
import 'weekly_review_style.dart';

/// The 2 dp focus ring for chips and buttons: the focus token while the
/// control has keyboard focus, no border otherwise.
WidgetStateBorderSide reviewFocusRing(AppThemeTokens tokens) =>
    WidgetStateBorderSide.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: tokens.focus, width: 2);
      }
      return BorderSide.none;
    });

/// A quick-reason chip: the same tonal chip as Weekly's feeling words (inset
/// fill, lighter on hover, focus ring, 48 dp target, press scale), filling its
/// grid cell with a one-line, centred, ellipsized label and a tooltip.
class ReviewPresetChip extends StatelessWidget {
  const ReviewPresetChip({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: WeeklyPressScale(
        child: ActionChip(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          side: reviewFocusRing(tokens),
          color: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? WeeklyStyle.insetHover(context)
                : WeeklyStyle.inset(context),
          ),
          label: SizedBox(
            width: double.infinity,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// "+ Save as preset": the last cell of the chip grid, a ghost chip with a
/// dashed hairline outline and accent text.
class ReviewGhostChip extends StatelessWidget {
  const ReviewGhostChip({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  /// Same height as the filled chips (a chip's 32 dp body plus its padding).
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(WeeklyStyle.insetRadius(context));
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: WeeklyPressScale(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(
                foregroundPainter: DashedOutlinePainter(
                  color: tokens.outlineStrong,
                  radius: WeeklyStyle.insetRadius(context),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    hoverColor: WeeklyStyle.inset(context),
                    focusColor: tokens.focus.withValues(alpha: 0.2),
                    onTap: onPressed,
                    child: Center(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: accent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
