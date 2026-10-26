import 'dart:math' as math;

import '../constants/app_constants.dart';

bool isDesktopWidth(double width) => width >= AppConstants.desktopBreakpoint;

/// Content-driven layout metrics for the seven-day timeline.
///
/// The shell keeps its existing navigation breakpoint; this class only
/// decides how many of the seven date columns can be shown in the available
/// Week body.  It deliberately uses content minima so text scaling and a
/// narrow intermediate window cannot squeeze a column into an unusable width.
class WeekViewportLayout {
  static const double defaultMinimumDayWidth = 160;
  static const double defaultRulerWidth = 56;

  final int daysPerPage;
  final double minimumDayWidth;
  final double rulerWidth;

  const WeekViewportLayout({
    required this.daysPerPage,
    required this.minimumDayWidth,
    required this.rulerWidth,
  });

  factory WeekViewportLayout.forWidth(
    double width, {
    double textScale = 1,
    double? rulerWidth,
  }) {
    final scale = textScale < 1 ? 1.0 : textScale;
    final minimum = defaultMinimumDayWidth * scale;
    final ruler = rulerWidth ?? defaultRulerWidth * scale;
    return WeekViewportLayout(
      daysPerPage: capacityFor(width, textScale: scale, rulerWidth: ruler),
      minimumDayWidth: minimum,
      rulerWidth: ruler,
    );
  }

  /// Number of consecutive date columns shown in one horizontal page.
  static int capacityFor(
    double width, {
    double textScale = 1,
    double? rulerWidth,
  }) {
    final scale = textScale < 1 ? 1.0 : textScale;
    if (width < 600) return 1;
    final minimum = defaultMinimumDayWidth * scale;
    final ruler = rulerWidth ?? defaultRulerWidth * scale;
    return ((width - ruler) / minimum).floor().clamp(1, 7);
  }

  double columnWidthFor(double width) {
    final available = (width - rulerWidth).clamp(0.0, double.infinity);
    // Capacity uses minimumDayWidth as a content preference. At the smallest
    // phone widths there is no room for that preference plus the ruler, so a
    // single page column must fit the actual viewport rather than overflow it.
    return available / daysPerPage;
  }

  /// Number of horizontal pages needed for [count] consecutive days.
  int pageCountFor(int count) => (count / daysPerPage).ceil();

  /// Index of the first day on [page]. The last page is pulled back so it
  /// shows [daysPerPage] days (for example Friday to Sunday) instead of a
  /// lone Sunday beside blank columns.
  int firstDayOfPage(int page, int count) =>
      math.min(page * daysPerPage, math.max(0, count - daysPerPage));

  List<List<T>> pagesOf<T>(List<T> values) {
    return List<List<T>>.unmodifiable([
      for (var page = 0; page < pageCountFor(values.length); page++)
        List<T>.unmodifiable(
          values.skip(firstDayOfPage(page, values.length)).take(daysPerPage),
        ),
    ]);
  }
}
