/// Window width, never platform.
///
/// The size class of a window decides the layout. Platform checks stay for
/// input only (touch handles, shortcuts).
library;

enum WindowSizeClass { compact, medium, expanded, large }

abstract final class Breakpoints {
  /// Medium starts here; below it is compact.
  static const double medium = 600;

  /// Expanded starts here; 600-839 is medium.
  static const double expanded = 840;

  /// Large starts here; 840-1199 is expanded.
  static const double large = 1200;

  static WindowSizeClass of(double windowWidth) {
    if (windowWidth >= large) return WindowSizeClass.large;
    if (windowWidth >= expanded) return WindowSizeClass.expanded;
    if (windowWidth >= medium) return WindowSizeClass.medium;
    return WindowSizeClass.compact;
  }

  static bool isCompact(WindowSizeClass sizeClass) =>
      sizeClass == WindowSizeClass.compact;

  /// A navigation rail instead of a bottom bar: medium and up.
  static bool hasRail(WindowSizeClass sizeClass) =>
      sizeClass != WindowSizeClass.compact;

  /// Room for a side panel next to the timeline: expanded and up.
  static bool hasSidePanel(WindowSizeClass sizeClass) =>
      sizeClass == WindowSizeClass.expanded ||
      sizeClass == WindowSizeClass.large;

  /// A labelled (extended) rail: large only.
  static bool railExtended(WindowSizeClass sizeClass) =>
      sizeClass == WindowSizeClass.large;
}

extension WindowSizeClassX on WindowSizeClass {
  bool get isCompact => Breakpoints.isCompact(this);
  bool get hasRail => Breakpoints.hasRail(this);
  bool get hasSidePanel => Breakpoints.hasSidePanel(this);
  bool get railExtended => Breakpoints.railExtended(this);
}
