import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';

/// The Weekly Review's own visual constants, built from the existing theme
/// tokens so they follow the dark and the light theme. Nothing here changes a
/// global token or what the Daily review and Overview get.
abstract final class WeeklyStyle {
  // Spacing scale: 4, 8, 12, 16, 24.
  static const double space1 = AppSpacing.xs;
  static const double space2 = AppSpacing.sm;
  static const double space3 = AppSpacing.md;
  static const double space4 = AppSpacing.lg;
  static const double space6 = AppSpacing.xxl;

  /// Gap between a card title and its content.
  static const double titleGap = space2;

  /// Gap between cards, horizontally and vertically.
  static const double cardGap = space3;

  // Radius scale: card (AppThemeTokens.radiusMedium), inset, pill.
  static double insetRadius(BuildContext context) =>
      AppThemeTokens.of(context).radiusSmall;
  static const double pillRadius = 999;

  // Motion: press, hover and selection are short; content changes a bit
  // longer. All ease-out, all skipped with reduced motion.
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration content = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeOut;

  static Duration quickFor(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : quick;

  static Duration contentFor(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : content;

  /// Press feedback scale, and the selected rating tile's scale.
  static const double pressedScale = 0.97;
  static const double selectedScale = 1.04;

  /// A tonal step away from the card colour for tiles, chips, fields and pills
  /// inside a card: lighter on the dark card, darker on the light one. It is
  /// derived from the tokens, so it works in both themes.
  static Color inset(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Color.alphaBlend(
      tokens.textPrimary.withValues(alpha: 0.06),
      tokens.surface,
    );
  }

  /// A tonal fill for a hovered inset element.
  static Color insetHover(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Color.alphaBlend(
      tokens.textPrimary.withValues(alpha: 0.12),
      tokens.surface,
    );
  }

  /// Filled, border-less text field decoration with an accent ring on focus.
  static InputDecoration fieldDecoration(
    BuildContext context, {
    String? hintText,
    String? errorText,
    bool isDense = false,
    Color? fill,
  }) {
    final tokens = AppThemeTokens.of(context);
    final radius = BorderRadius.circular(insetRadius(context));
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: width == 0
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );
    return InputDecoration(
      isDense: isDense,
      hintText: hintText,
      errorText: errorText,
      filled: true,
      fillColor: fill ?? inset(context),
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      disabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(tokens.focus, 2),
    );
  }
}

/// Scales its child down a little while a pointer is pressed on it. A
/// transform only (no layer); [selectedScale] enlarges it when [selected].
class WeeklyPressScale extends StatefulWidget {
  const WeeklyPressScale({
    super.key,
    required this.child,
    this.selected = false,
    this.selectedScale = 1.0,
  });

  final Widget child;
  final bool selected;
  final double selectedScale;

  @override
  State<WeeklyPressScale> createState() => _WeeklyPressScaleState();
}

class _WeeklyPressScaleState extends State<WeeklyPressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed
        ? WeeklyStyle.pressedScale
        : widget.selected
        ? widget.selectedScale
        : 1.0;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: scale,
        duration: WeeklyStyle.quickFor(context),
        curve: WeeklyStyle.curve,
        child: widget.child,
      ),
    );
  }
}

/// "Show all N" / "Show less" under a long list. Local UI state is kept by the
/// caller; this is only the button (48 dp target, focus ring, tonal hover).
class WeeklyShowAllButton extends StatelessWidget {
  const WeeklyShowAllButton({
    super.key,
    required this.expanded,
    required this.total,
    required this.onPressed,
  });

  final bool expanded;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        expanded: expanded,
        label: expanded ? 'Show fewer rows' : 'Show all $total rows',
        excludeSemantics: true,
        child: TextButton(
          style:
              TextButton.styleFrom(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
                alignment: Alignment.centerLeft,
              ).copyWith(
                side: WidgetStateBorderSide.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? BorderSide(color: tokens.focus, width: 2)
                      : BorderSide.none,
                ),
              ),
          onPressed: onPressed,
          child: Text(expanded ? 'Show less' : 'Show all $total'),
        ),
      ),
    );
  }
}
