import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Gesture wrapper around a task block that initiates move-drags.
///
/// A normal vertical drag recognizer is used on every platform. Flutter's
/// gesture arena therefore makes a tap, double tap, vertical drag and the
/// surrounding scroll view mutually exclusive using the framework's normal
/// movement slop. Touch users do not have to wait for a long press to move a
/// task; a stationary long press remains available for the context menu.
///
/// [onDragUpdate] reports the total vertical delta in logical pixels since
/// the drag began.
class DraggableTaskBlock extends StatefulWidget {
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final ValueChanged<Offset> onContextMenuRequested;
  final Widget child;

  const DraggableTaskBlock({
    super.key,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onContextMenuRequested,
    required this.child,
  });

  @override
  State<DraggableTaskBlock> createState() => _DraggableTaskBlockState();
}

class _DraggableTaskBlockState extends State<DraggableTaskBlock> {
  static bool get _isTouchPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _dragActivated = false;
  double _accumulatedDy = 0;

  void _reset() {
    _dragActivated = false;
    _accumulatedDy = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // The positioned block owns its complete rectangle, including empty
      // space below short content in multi-hour/cross-day tasks. Deferring to
      // descendants lets those blank areas fall through to the timeline's
      // scroll gesture instead of starting a task interaction.
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: _isTouchPlatform
          ? null
          : (details) => widget.onContextMenuRequested(details.globalPosition),
      onVerticalDragStart: (_) {
        _reset();
        widget.onDragStart();
        _dragActivated = true;
      },
      onVerticalDragUpdate: (details) {
        if (!_dragActivated) return;
        _accumulatedDy += details.delta.dy;
        widget.onDragUpdate(_accumulatedDy);
      },
      onVerticalDragEnd: (_) {
        final wasActive = _dragActivated;
        _reset();
        if (wasActive) widget.onDragEnd();
      },
      onVerticalDragCancel: () {
        final wasActive = _dragActivated;
        _reset();
        if (wasActive) widget.onDragCancel();
      },
      // A stationary touch long-press keeps the existing context action.
      onLongPressStart: _isTouchPlatform
          ? (details) => widget.onContextMenuRequested(details.globalPosition)
          : null,
      child: widget.child,
    );
  }
}
