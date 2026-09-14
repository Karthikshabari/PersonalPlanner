import 'package:flutter/material.dart';

/// Small, self-contained motion wrapper for timeline blocks.
///
/// New blocks enter from the side, removed blocks fade out, and an active
/// drag gets a subtle scale and shadow lift without changing its layout slot.
class TaskBlockMotion extends StatefulWidget {
  final Widget child;
  final bool isDragging;
  final bool isRemoving;
  final VoidCallback? onRemoved;

  const TaskBlockMotion({
    super.key,
    required this.child,
    this.isDragging = false,
    this.isRemoving = false,
    this.onRemoved,
  });

  @override
  State<TaskBlockMotion> createState() => _TaskBlockMotionState();
}

class _TaskBlockMotionState extends State<TaskBlockMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _removalReported = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.isRemoving ? 1 : 0,
    );
    if (widget.isRemoving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reverse());
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant TaskBlockMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRemoving && !oldWidget.isRemoving) {
      _removalReported = false;
      _controller.value = 1;
      _reverse();
    } else if (!widget.isRemoving && oldWidget.isRemoving) {
      _controller.forward();
    }
  }

  void _reverse() {
    if (!mounted || _removalReported) return;
    _controller.reverse().whenComplete(() {
      if (!mounted || _removalReported) return;
      _removalReported = true;
      widget.onRemoved?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.easeOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset((1 - value) * -12, 0),
          child: Opacity(
            opacity: value,
            child: AnimatedScale(
              scale: widget.isDragging ? 1.03 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: widget.isDragging
                      ? [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.shadow
                                .withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
