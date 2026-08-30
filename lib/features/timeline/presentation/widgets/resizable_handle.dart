import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme_tokens.dart';

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

  static bool get isTouchPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static const double touchTargetHeight = 48;

  @override
  State<ResizableHandle> createState() => _ResizableHandleState();
}

class _ResizableHandleState extends State<ResizableHandle> {
  bool _active = false;
  double _accumulatedDy = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return GestureDetector(
      key: const ValueKey('resize-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: ResizableHandle.isTouchPlatform
          ? null
          : (_) {
              if (_active) return;
              _active = true;
              _accumulatedDy = 0;
              widget.onResizeStart();
            },
      onVerticalDragUpdate: ResizableHandle.isTouchPlatform
          ? null
          : (details) {
              if (!_active) return;
              _accumulatedDy += details.delta.dy;
              widget.onResizeUpdate(_accumulatedDy);
            },
      onVerticalDragEnd: ResizableHandle.isTouchPlatform
          ? null
          : (_) {
              if (!_active) return;
              _active = false;
              widget.onResizeEnd();
            },
      onVerticalDragCancel: ResizableHandle.isTouchPlatform
          ? null
          : () {
              if (!_active) return;
              _active = false;
              widget.onResizeCancel();
            },
      onLongPressStart: ResizableHandle.isTouchPlatform
          ? (details) {
              if (_active) return;
              _active = true;
              _accumulatedDy = 0;
              widget.onResizeStart();
            }
          : null,
      onLongPressMoveUpdate: ResizableHandle.isTouchPlatform
          ? (details) {
              if (!_active) return;
              _accumulatedDy = details.offsetFromOrigin.dy;
              widget.onResizeUpdate(_accumulatedDy);
            }
          : null,
      onLongPressEnd: ResizableHandle.isTouchPlatform
          ? (details) {
              if (_active) {
                _active = false;
                widget.onResizeEnd();
              }
            }
          : null,
      onLongPressCancel: ResizableHandle.isTouchPlatform
          ? () {
              if (_active) {
                _active = false;
                widget.onResizeCancel();
              }
            }
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Semantics(
          label: 'Resize task',
          button: true,
          child: SizedBox(
            height: ResizableHandle.isTouchPlatform
                ? ResizableHandle.touchTargetHeight
                : AppConstants.resizeHandleHeight.toDouble(),
            width: double.infinity,
            child: Center(
              child: Container(
                width: 28,
                height: 3,
                decoration: BoxDecoration(
                  color: tokens.focus.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
