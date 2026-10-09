import 'dart:math' as math;

import '../../../../core/theme/app_spacing.dart';

/// Page metrics shared by the Daily review (and matching Weekly's): one
/// centred column at most [maxContentWidth] wide, two columns once that
/// column is at least [wideBreakpoint] wide.
abstract final class ReviewLayout {
  static const double maxContentWidth = 1000;
  static const double wideBreakpoint = 760;

  /// Side gutter (and top / bottom padding) of the scrolling page.
  static const double pagePadding = AppSpacing.lg;

  /// Gap between cards, horizontally and vertically.
  static const double cardGap = AppSpacing.md;

  /// Whether a page [screenWidth] dp wide gets the two-column layout. The same
  /// rule as the Weekly review: the content column, not the window, decides.
  static bool isWide(double screenWidth) =>
      math.min(screenWidth - 2 * pagePadding, maxContentWidth) >=
      wideBreakpoint;
}
