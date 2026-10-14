import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../../review/presentation/widgets/weekly_review_style.dart';

/// The Day screen's visual constants, built only from [AppThemeTokens] and the
/// active theme so the dark and the light theme both work. Nothing on Day
/// goes below 12sp.
abstract final class DayStyle {
  // Radii: small (chips, rows, inputs), medium (cards, banner, strip, panel
  // cards, task blocks), pill. Nothing else.
  static double small(BuildContext context) =>
      AppThemeTokens.of(context).radiusSmall;
  static double medium(BuildContext context) =>
      AppThemeTokens.of(context).radiusMedium;
  static const double pill = 999;

  // Text styles. Colours come from the theme text styles and the tokens.

  /// Date title: 20 / w600.
  static TextStyle dateTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!
          .copyWith(fontSize: 20, fontWeight: FontWeight.w600);

  /// Section heading: 14 / w600.
  static TextStyle section(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!
          .copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  /// Row title: 14 / w500.
  static TextStyle rowTitle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!
          .copyWith(fontSize: 14, fontWeight: FontWeight.w500);

  /// Secondary text: 12 in `textSecondary` at full alpha (the theme's
  /// bodySmall is 85% alpha, which is not inherited here).
  static TextStyle secondary(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(fontSize: 12, color: AppThemeTokens.of(context).textSecondary);

  /// Hour ruler: 12 with tabular figures.
  static TextStyle ruler(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(
        fontSize: 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // Interaction.
  static Color hoverFill(BuildContext context) =>
      AppThemeTokens.of(context).hover;

  /// 2px `tokens.focus` border when focused, none otherwise.
  static WidgetStateBorderSide focusBorder(BuildContext context) {
    final focus = AppThemeTokens.of(context).focus;
    return WidgetStateBorderSide.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: focus, width: 2)
          : BorderSide.none,
    );
  }

  /// Minimum touch target.
  static const Size minTarget = Size(48, 48);

  // Motion: 140 ms and 200 ms, ease-out, zero with reduced motion.
  static Duration quick(BuildContext context) => WeeklyStyle.quickFor(context);
  static Duration content(BuildContext context) =>
      WeeklyStyle.contentFor(context);
  static const Curve curve = WeeklyStyle.curve;
}
