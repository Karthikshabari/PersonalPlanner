import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/layout/breakpoints.dart';

void main() {
  const c = WindowSizeClass.compact;
  const m = WindowSizeClass.medium;
  const e = WindowSizeClass.expanded;
  const l = WindowSizeClass.large;

  test('width boundaries map to the right size class', () {
    final cases = <double, WindowSizeClass>{
      0: c,
      359: c,
      599: c,
      599.9: c,
      600: m,
      839: m,
      840: e,
      1199: e,
      1200: l,
      3840: l,
    };
    cases.forEach((width, expected) {
      expect(Breakpoints.of(width), expected, reason: 'width $width');
    });
  });

  test('helpers per class', () {
    expect(
      [for (final s in WindowSizeClass.values) Breakpoints.isCompact(s)],
      [true, false, false, false],
    );
    expect(
      [for (final s in WindowSizeClass.values) Breakpoints.hasRail(s)],
      [false, true, true, true],
    );
    expect(
      [for (final s in WindowSizeClass.values) Breakpoints.hasSidePanel(s)],
      [false, false, true, true],
    );
    expect(
      [for (final s in WindowSizeClass.values) Breakpoints.railExtended(s)],
      [false, false, false, true],
    );
  });

  test('extension matches the static helpers', () {
    for (final s in WindowSizeClass.values) {
      expect(s.isCompact, Breakpoints.isCompact(s));
      expect(s.hasRail, Breakpoints.hasRail(s));
      expect(s.hasSidePanel, Breakpoints.hasSidePanel(s));
      expect(s.railExtended, Breakpoints.railExtended(s));
    }
  });
}
