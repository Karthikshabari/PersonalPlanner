import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

/// Gesture wrapper around a task block that initiates move-drags.
///
/// * Desktop: click + drag (vertical drag recognizer).
/// * Touch platforms: long-press + drag; releasing a long-press without
///   meaningful movement requests the context menu instead.
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

  void _maybeActivate() {
    if (_dragActivated) return;
    if (_accumulatedDy.abs() > AppConstants.longPressMenuSlopPx) {
      _dragActivated = true;
      widget.onDragStart();
    }
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
      // Desktop: immediate click + drag.
      onVerticalDragStart: _isTouchPlatform
          ? null
          : (_) {
              _reset();
              widget.onDragStart();
              _dragActivated = true;
            },
      onVerticalDragUpdate: _isTouchPlatform
          ? null
          : (details) {
              if (!_dragActivated) return;
              _accumulatedDy += details.delta.dy;
              widget.onDragUpdate(_accumulatedDy);
            },
      onVerticalDragEnd: _isTouchPlatform
          ? null
          : (_) {
              final wasActive = _dragActivated;
              _reset();
              if (wasActive) widget.onDragEnd();
            },
      onVerticalDragCancel: _isTouchPlatform
          ? null
          : () {
              final wasActive = _dragActivated;
              _reset();
              if (wasActive) widget.onDragCancel();
            },
      // Touch: long-press + drag; plain long-press opens the context menu.
      onLongPressStart: _isTouchPlatform
          ? (LongPressStartDetails details) => _reset()
          : null,
      onLongPressMoveUpdate: _isTouchPlatform
          ? (LongPressMoveUpdateDetails details) {
              _accumulatedDy = details.offsetFromOrigin.dy;
              _maybeActivate();
              if (_dragActivated) widget.onDragUpdate(_accumulatedDy);
            }
          : null,
      onLongPressEnd: _isTouchPlatform
          ? (LongPressEndDetails details) {
              if (_dragActivated) {
                widget.onDragEnd();
              } else {
                widget.onContextMenuRequested(details.globalPosition);
              }
              _reset();
            }
          : null,
      onLongPressCancel: _isTouchPlatform
          ? () {
              if (_dragActivated) widget.onDragCancel();
              _reset();
            }
          : null,
      child: widget.child,
    );
  }
}
