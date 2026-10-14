/// Day screen layout constants (logical pixels unless noted).
abstract final class DayLayout {
  /// Widest the timeline column grows.
  static const double timelineMaxWidth = 840;

  /// Widest the whole Day content grows.
  static const double contentMaxWidth = 1400;

  /// Side panel width at the expanded and large size classes.
  static const double panelWidthExpanded = 320;
  static const double panelWidthLarge = 360;

  /// Largest share of the window height the attention strip may take.
  static const double stripMaxHeightFraction = 0.35;

  /// Window heights below this collapse the rail.
  static const double railCollapseHeight = 560;

  /// Minutes before now the timeline scrolls to on open.
  static const int nowScrollLeadMinutes = 90;
}
