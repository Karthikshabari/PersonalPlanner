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
    final capacity = ((width - ruler) / minimum).floor();
    if (width >= 1200 && capacity >= 7) return 7;
    return capacity.clamp(1, 3);
  }

  double columnWidthFor(double width) {
    final available = (width - rulerWidth).clamp(0.0, double.infinity);
    // Capacity uses minimumDayWidth as a content preference. At the smallest
    // phone widths there is no room for that preference plus the ruler, so a
    // single page column must fit the actual viewport rather than overflow it.
    return available / daysPerPage;
  }

  List<List<T>> pagesOf<T>(List<T> values) {
    final pages = <List<T>>[];
    for (var offset = 0; offset < values.length; offset += daysPerPage) {
      final end = (offset + daysPerPage).clamp(0, values.length);
      pages.add(List<T>.unmodifiable(values.sublist(offset, end)));
    }
    return List<List<T>>.unmodifiable(pages);
  }
}
