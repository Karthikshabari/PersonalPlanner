import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Gesture wrapper around a task block that initiates move-drags.
///
/// A mouse or trackpad moves a block immediately: a vertical drag recognizer
/// starts after the framework's normal movement slop. On Android and iOS a
/// finger (or stylus) needs intent first. A swipe that starts on a block must
/// scroll the day, so a move starts only after a press-and-hold of
/// [touchHoldDuration]; once the hold is recognised the finger moves the
/// block and the scroll view no longer competes. A hold released without
/// moving opens the context menu, as a long press always did. A mouse on an
/// Android tablet keeps the immediate drag.
///
/// [onDragUpdate] reports the total vertical delta in logical pixels since
/// the drag began.
class DraggableTaskBlock extends StatefulWidget {
  /// How long a finger must rest on a block before a move can start.
  static const touchHoldDuration = Duration(milliseconds: 300);

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
  static const _pointerKinds = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  static bool get _isTouchPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _dragActivated = false;
  bool _holdMoved = false;
  double _accumulatedDy = 0;

  void _reset() {
    _dragActivated = false;
    _holdMoved = false;
    _accumulatedDy = 0;
  }

  void _dragStart() {
    _reset();
    widget.onDragStart();
    _dragActivated = true;
  }

  void _dragUpdate(double totalDy) {
    if (!_dragActivated) return;
    _accumulatedDy = totalDy;
    widget.onDragUpdate(_accumulatedDy);
  }

  void _dragEnd() {
    final wasActive = _dragActivated;
    _reset();
    if (wasActive) widget.onDragEnd();
  }

  void _dragCancel() {
    final wasActive = _dragActivated;
    _reset();
    if (wasActive) widget.onDragCancel();
  }

  void _holdEnd(Offset globalPosition) {
    // No movement since the hold was recognised: nothing to move, so keep the
    // long-press context action.
    if (!_holdMoved) {
      _dragCancel();
      widget.onContextMenuRequested(globalPosition);
      return;
    }
    _dragEnd();
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
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          VerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                VerticalDragGestureRecognizer
              >(
                () => VerticalDragGestureRecognizer(
                  // On touch platforms a finger uses the hold below.
                  supportedDevices: _isTouchPlatform ? _pointerKinds : null,
                ),
                (recognizer) {
                  recognizer
                    ..onStart = (_) {
                      _dragStart();
                    }
                    ..onUpdate = (details) {
                      _dragUpdate(_accumulatedDy + details.delta.dy);
                    }
                    ..onEnd = (_) {
                      _dragEnd();
                    }
                    ..onCancel = _dragCancel;
                },
              ),
          if (_isTouchPlatform)
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: DraggableTaskBlock.touchHoldDuration,
                    supportedDevices: PointerDeviceKind.values
                        .toSet()
                        .difference(_pointerKinds),
                  ),
                  (recognizer) {
                    recognizer
                      ..onLongPressStart = (_) {
                        _dragStart();
                      }
                      ..onLongPressMoveUpdate = (details) {
                        if (details.offsetFromOrigin.distance > kTouchSlop) {
                          _holdMoved = true;
                        }
                        _dragUpdate(details.offsetFromOrigin.dy);
                      }
                      ..onLongPressEnd = (details) {
                        _holdEnd(details.globalPosition);
                      }
                      ..onLongPressCancel = _dragCancel;
                  },
                ),
        },
        child: widget.child,
      ),
    );
  }
}
