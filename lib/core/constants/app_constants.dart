abstract final class AppConstants {
  static const int defaultGridMinutes = 60;
  static const List<int> gridOptions = [15, 30, 60];
  static const int maxCascadeDepth = 10;
  static const double hourRowHeight = 64.0;
  static const double pixelsPerMinute = hourRowHeight / 60.0;
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

  /// Upper bound of `tasks.title` (Drift `withLength(max: 500)`, counted in
  /// UTF-16 code units like Dart's `String.length`).
  static const int maxTaskTitleLength = 500;

  /// User-facing message for a title over [maxTaskTitleLength].
  static const String taskTitleTooLongMessage =
      'Title must be $maxTaskTitleLength characters or fewer';

  /// Upper bound of `categories.name` (Drift `withLength(max: 100)`).
  static const int maxCategoryNameLength = 100;
}
