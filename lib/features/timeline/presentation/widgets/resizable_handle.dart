import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

/// Bottom-edge drag handle for resizing a task block. Uses vertical drag on
/// desktop (click + drag) and long-press + drag on touch platforms.
///
/// [onResizeUpdate] reports the total vertical delta in logical pixels since
/// the resize began.
class ResizableHandle extends StatefulWidget {
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResizeUpdate;
  final VoidCallback onResizeEnd;
  final VoidCallback onResizeCancel;

  const ResizableHandle({
    super.key,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onResizeCancel,
  });

  @override
  State<ResizableHandle> createState() => _ResizableHandleState();
}

class _ResizableHandleState extends State<ResizableHandle> {
  static bool get _isTouchPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _active = false;
  double _accumulatedDy = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('resize-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _isTouchPlatform
          ? null
          : (_) {
              if (_active) return;
              _active = true;
              _accumulatedDy = 0;
              widget.onResizeStart();
            },
      onVerticalDragUpdate: _isTouchPlatform
          ? null
          : (details) {
              if (!_active) return;
              _accumulatedDy += details.delta.dy;
              widget.onResizeUpdate(_accumulatedDy);
            },
      onVerticalDragEnd: _isTouchPlatform
          ? null
          : (_) {
              if (!_active) return;
              _active = false;
              widget.onResizeEnd();
            },
      onVerticalDragCancel: _isTouchPlatform
          ? null
          : () {
              if (!_active) return;
              _active = false;
              widget.onResizeCancel();
            },
      onLongPressStart: _isTouchPlatform
          ? (details) {
              if (_active) return;
              _active = true;
              _accumulatedDy = 0;
              widget.onResizeStart();
            }
          : null,
      onLongPressMoveUpdate: _isTouchPlatform
          ? (details) {
              if (!_active) return;
              _accumulatedDy = details.offsetFromOrigin.dy;
              widget.onResizeUpdate(_accumulatedDy);
            }
          : null,
      onLongPressEnd:
          _isTouchPlatform ? (details) { if (_active) { _active = false; widget.onResizeEnd(); } } : null,
      onLongPressCancel: _isTouchPlatform
          ? () {
              if (_active) {
                _active = false;
                widget.onResizeCancel();
              }
            }
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: SizedBox(
          height: AppConstants.resizeHandleHeight.toDouble(),
          width: double.infinity,
          child: Center(
            child: Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
