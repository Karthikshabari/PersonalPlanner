import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether Command, not Control, is the primary shortcut modifier.
bool get usesCommandModifier => defaultTargetPlatform == TargetPlatform.macOS;

/// Ctrl+[trigger], or Command+[trigger] on macOS.
SingleActivator primaryShortcut(
  LogicalKeyboardKey trigger, {
  bool shift = false,
}) => SingleActivator(
  trigger,
  control: !usesCommandModifier,
  meta: usesCommandModifier,
  shift: shift,
);
