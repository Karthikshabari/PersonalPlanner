import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// Provides the current [WindowSizeClass] to descendants.
///
/// Dependents rebuild only when the class changes, so resizing inside one
/// class rebuilds nothing that reads it through [of].
class DaySizeClass extends InheritedWidget {
  const DaySizeClass({
    super.key,
    required this.sizeClass,
    required super.child,
  });

  final WindowSizeClass sizeClass;

  /// The nearest scope's class. Without a scope it falls back to the window
  /// width, so widgets also work in isolated widget tests.
  static WindowSizeClass of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DaySizeClass>();
    return scope?.sizeClass ?? Breakpoints.of(MediaQuery.sizeOf(context).width);
  }

  @override
  bool updateShouldNotify(DaySizeClass old) => old.sizeClass != sizeClass;
}
