abstract final class AppConstants {
  static const int defaultGridMinutes = 60;
  static const List<int> gridOptions = [15, 30, 60];
  static const int maxCascadeDepth = 10;
  static const double hourRowHeight = 64.0;
  static const double hourLabelWidth = 56.0;
  static const double desktopBreakpoint = 900;
  static const Duration quickCreateDefaultDuration = Duration(hours: 1);

  /// Height of the drag handle strip on the bottom edge of a block.
  static const double resizeHandleHeight = 10.0;

  /// Horizontal offset applied per overlapping block for the overlap
  /// indicator.
  static const double overlapOffsetPerIndex = 14.0;

  /// Maximum vertical movement (logical px) before a mobile long-press is
  /// treated as a drag instead of a context-menu tap.
  static const double longPressMenuSlopPx = 8.0;
}
